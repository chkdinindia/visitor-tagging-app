import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import 'models.dart';

/// SQLite storage for the guest QR database and the tag upload queue.
class LocalDb {
  Database? _database;

  Database get _db {
    final db = _database;
    if (db == null) throw StateError('LocalDb.open() has not been called');
    return db;
  }

  Future<void> open() async {
    final dir = await getDatabasesPath();
    _database = await openDatabase(
      p.join(dir, 'visitor_tagging.db'),
      version: 1,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE qr_codes (
            qr_code TEXT PRIMARY KEY,
            category_id TEXT NOT NULL,
            category_name TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE tags (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            guest_qr TEXT NOT NULL,
            card_qr TEXT NOT NULL,
            category_id TEXT,
            category_name TEXT,
            scanned_at TEXT NOT NULL,
            status INTEGER NOT NULL DEFAULT 0,
            error TEXT,
            attempts INTEGER NOT NULL DEFAULT 0
          )
        ''');
        await db.execute('CREATE INDEX idx_tags_card ON tags(card_qr)');
        await db.execute('CREATE INDEX idx_tags_guest ON tags(guest_qr)');
        await db.execute('CREATE INDEX idx_tags_status ON tags(status)');
      },
    );
  }

  // ---------------------------------------------------------------------------
  // QR codes
  // ---------------------------------------------------------------------------

  /// Replaces the whole QR database (used on first login).
  Future<void> replaceAllCodes(List<QrRecord> records) async {
    await _db.transaction((txn) async {
      await txn.delete('qr_codes');
      await _insertChunked(txn, records);
    });
  }

  /// Inserts new codes and updates changed ones.
  Future<void> upsertCodes(List<QrRecord> records) async {
    if (records.isEmpty) return;
    await _db.transaction((txn) => _insertChunked(txn, records));
  }

  Future<void> _insertChunked(Transaction txn, List<QrRecord> records) async {
    const chunkSize = 1000;
    for (var i = 0; i < records.length; i += chunkSize) {
      final batch = txn.batch();
      for (final record in records.skip(i).take(chunkSize)) {
        batch.insert('qr_codes', record.toDb(), conflictAlgorithm: ConflictAlgorithm.replace);
      }
      await batch.commit(noResult: true);
    }
  }

  Future<void> deleteCodes(List<String> codes) async {
    if (codes.isEmpty) return;
    await _db.transaction((txn) async {
      final batch = txn.batch();
      for (final code in codes) {
        batch.delete('qr_codes', where: 'qr_code = ?', whereArgs: <Object>[code]);
      }
      await batch.commit(noResult: true);
    });
  }

  Future<QrRecord?> findCode(String code) async {
    final rows = await _db.query(
      'qr_codes',
      where: 'qr_code = ?',
      whereArgs: <Object>[code],
      limit: 1,
    );
    return rows.isEmpty ? null : QrRecord.fromDb(rows.first);
  }

  Future<int> countCodes() async {
    return Sqflite.firstIntValue(await _db.rawQuery('SELECT COUNT(*) FROM qr_codes')) ?? 0;
  }

  // ---------------------------------------------------------------------------
  // Tags
  // ---------------------------------------------------------------------------

  Future<int> insertTag(TagRecord tag) => _db.insert('tags', tag.toDb());

  Future<int> countTags(TagSyncStatus status) async {
    return Sqflite.firstIntValue(await _db.rawQuery(
          'SELECT COUNT(*) FROM tags WHERE status = ?',
          <Object>[status.index],
        )) ??
        0;
  }

  Future<List<TagRecord>> pendingTags({int limit = 20}) async {
    final rows = await _db.query(
      'tags',
      where: 'status = ?',
      whereArgs: <Object>[TagSyncStatus.pending.index],
      orderBy: 'id ASC',
      limit: limit,
    );
    return rows.map(TagRecord.fromDb).toList();
  }

  Future<List<TagRecord>> recentTags({int limit = 20}) async {
    final rows = await _db.query('tags', orderBy: 'id DESC', limit: limit);
    return rows.map(TagRecord.fromDb).toList();
  }

  /// Latest active (not rejected) tag that used this printed card.
  Future<TagRecord?> tagForCard(String cardQr) => _latestTag('card_qr', cardQr);

  /// Latest active (not rejected) tag for this guest.
  Future<TagRecord?> tagForGuest(String guestQr) => _latestTag('guest_qr', guestQr);

  Future<TagRecord?> _latestTag(String column, String value) async {
    final rows = await _db.query(
      'tags',
      where: '$column = ? AND status != ?',
      whereArgs: <Object>[value, TagSyncStatus.rejected.index],
      orderBy: 'id DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : TagRecord.fromDb(rows.first);
  }

  Future<void> markSynced(int id) async {
    await _db.update(
      'tags',
      <String, Object?>{'status': TagSyncStatus.synced.index, 'error': null},
      where: 'id = ?',
      whereArgs: <Object>[id],
    );
  }

  Future<void> markRejected(int id, String error) async {
    await _db.update(
      'tags',
      <String, Object?>{'status': TagSyncStatus.rejected.index, 'error': error},
      where: 'id = ?',
      whereArgs: <Object>[id],
    );
  }

  Future<void> recordFailedAttempt(int id, String error) async {
    await _db.rawUpdate(
      'UPDATE tags SET attempts = attempts + 1, error = ? WHERE id = ?',
      <Object>[error, id],
    );
  }

  /// Moves rejected tags back to the upload queue.
  Future<int> requeueRejected() async {
    return _db.update(
      'tags',
      <String, Object?>{'status': TagSyncStatus.pending.index, 'error': null},
      where: 'status = ?',
      whereArgs: <Object>[TagSyncStatus.rejected.index],
    );
  }

  Future<void> clearAll() async {
    await _db.transaction((txn) async {
      await txn.delete('qr_codes');
      await txn.delete('tags');
    });
  }
}
