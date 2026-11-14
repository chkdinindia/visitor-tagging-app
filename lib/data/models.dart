/// A guest QR code with its category, as stored in the local database.
class QrRecord {
  const QrRecord({
    required this.qrCode,
    required this.categoryId,
    this.categoryName,
  });

  final String qrCode;
  final String categoryId;
  final String? categoryName;

  String get categoryLabel {
    final name = categoryName?.trim() ?? '';
    if (name.isNotEmpty) return name;
    if (categoryId.isEmpty) return 'No category';
    return 'Category $categoryId';
  }

  Map<String, Object?> toDb() => <String, Object?>{
        'qr_code': qrCode,
        'category_id': categoryId,
        'category_name': categoryName,
      };

  factory QrRecord.fromDb(Map<String, Object?> row) => QrRecord(
        qrCode: row['qr_code'] as String,
        categoryId: (row['category_id'] ?? '').toString(),
        categoryName: row['category_name'] as String?,
      );

  /// Parses one item from the API. Accepts a few common key spellings so the
  /// app keeps working if the backend uses slightly different names.
  static QrRecord? fromApi(dynamic json) {
    if (json is! Map) return null;
    final code = pickString(json, const ['qr_code', 'qrcode', 'qr', 'code', 'unique_id']);
    if (code == null || code.isEmpty) return null;
    final categoryId =
        pickString(json, const ['category_id', 'categoryId', 'cat_id', 'category']) ?? '';
    final categoryName =
        pickString(json, const ['category_name', 'categoryName', 'cat_name']);
    return QrRecord(qrCode: code, categoryId: categoryId, categoryName: categoryName);
  }
}

/// Returns the first non-null scalar value for the given keys, as a string.
String? pickString(Map<dynamic, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = json[key];
    if (value == null || value is Map || value is List) continue;
    return value.toString().trim();
  }
  return null;
}

enum TagSyncStatus { pending, synced, rejected }

/// A guest QR paired with a printed card QR.
class TagRecord {
  const TagRecord({
    this.id,
    required this.guestQr,
    required this.cardQr,
    required this.categoryId,
    this.categoryName,
    required this.scannedAtUtc,
    this.status = TagSyncStatus.pending,
    this.error,
  });

  final int? id;
  final String guestQr;
  final String cardQr;
  final String categoryId;
  final String? categoryName;
  final DateTime scannedAtUtc;
  final TagSyncStatus status;
  final String? error;

  Map<String, Object?> toDb() => <String, Object?>{
        if (id != null) 'id': id,
        'guest_qr': guestQr,
        'card_qr': cardQr,
        'category_id': categoryId,
        'category_name': categoryName,
        'scanned_at': scannedAtUtc.toUtc().toIso8601String(),
        'status': status.index,
        'error': error,
      };

  factory TagRecord.fromDb(Map<String, Object?> row) {
    final statusIndex = (row['status'] as int?) ?? 0;
    return TagRecord(
      id: row['id'] as int?,
      guestQr: row['guest_qr'] as String,
      cardQr: row['card_qr'] as String,
      categoryId: (row['category_id'] ?? '').toString(),
      categoryName: row['category_name'] as String?,
      scannedAtUtc: DateTime.tryParse(row['scanned_at'] as String? ?? '')?.toUtc() ??
          DateTime.now().toUtc(),
      status: TagSyncStatus.values[statusIndex.clamp(0, TagSyncStatus.values.length - 1)],
      error: row['error'] as String?,
    );
  }
}
