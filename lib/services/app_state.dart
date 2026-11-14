import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../data/api_client.dart';
import '../data/local_db.dart';
import '../data/models.dart';

/// Holds the session, runs the 2-minute sync loop and manages the tag queue.
class AppState extends ChangeNotifier {
  AppState({LocalDb? db, ApiClient? api})
      : _db = db ?? LocalDb(),
        _api = api ?? ApiClient();

  static const _kEventId = 'event_id';
  static const _kEventName = 'event_name';
  static const _kCategoryId = 'category_id';
  static const _kCategoryName = 'category_name';
  static const _kLastSync = 'last_sync_utc';
  static const _kDeviceId = 'device_id';
  static const _kBaseUrl = 'base_url';

  final LocalDb _db;
  final ApiClient _api;
  late SharedPreferences _prefs;

  Timer? _timer;
  bool _flushing = false;

  // Session
  String? eventId;
  String eventName = '';
  String categoryId = '';
  String categoryName = '';
  String deviceId = '';

  // Sync status
  DateTime? lastSyncUtc;
  DateTime? lastAttemptUtc;
  bool? online;
  bool syncing = false;
  String? lastError;
  int lastChangeCount = 0;

  // Counters
  int totalCodes = 0;
  int pendingCount = 0;
  int syncedCount = 0;
  int rejectedCount = 0;
  List<TagRecord> recentTags = const <TagRecord>[];

  bool get isLoggedIn => eventId != null;
  bool get isDemo => eventId == AppConfig.demoEventId;
  int get taggedCount => pendingCount + syncedCount;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    await _db.open();

    ApiClient.baseUrl = _prefs.getString(_kBaseUrl) ?? AppConfig.defaultBaseUrl;
    deviceId = _prefs.getString(_kDeviceId) ?? _generateDeviceId();
    await _prefs.setString(_kDeviceId, deviceId);

    eventId = _prefs.getString(_kEventId);
    eventName = _prefs.getString(_kEventName) ?? '';
    categoryId = _prefs.getString(_kCategoryId) ?? '';
    categoryName = _prefs.getString(_kCategoryName) ?? '';
    final savedSync = _prefs.getString(_kLastSync);
    lastSyncUtc = savedSync == null ? null : DateTime.tryParse(savedSync)?.toUtc();

    await _refreshCounts();
    if (isLoggedIn) {
      _startTimer();
      unawaited(syncNow());
    }
  }

  // ---------------------------------------------------------------------------
  // Session
  // ---------------------------------------------------------------------------

  /// Categories the operator can choose for [id].
  Future<List<TaggingCategory>> fetchCategories(String id) async {
    if (id == AppConfig.demoEventId) return AppConfig.demoCategories;
    return _api.fetchCategories(id);
  }

  /// Validates the event, downloads the full QR database and stores the
  /// current UTC time as the sync checkpoint.
  Future<void> login(
    String id,
    TaggingCategory category, {
    void Function(String status)? onStatus,
  }) async {
    final startedAtUtc = DateTime.now().toUtc();
    onStatus?.call('Downloading ${category.name}…');
    final snapshot = id == AppConfig.demoEventId
        ? _demoSnapshot(category)
        : await _api.fetchEvent(id, categoryId: category.id);

    onStatus?.call('Saving ${snapshot.records.length} QR codes…');
    await _db.replaceAllCodes(snapshot.records);

    eventId = id;
    eventName = snapshot.eventName.isEmpty ? 'Event $id' : snapshot.eventName;
    lastSyncUtc = snapshot.serverTimeUtc ?? startedAtUtc;
    lastAttemptUtc = startedAtUtc;
    lastChangeCount = snapshot.records.length;
    online = true;
    lastError = null;

    await _prefs.setString(_kEventId, id);
    await _prefs.setString(_kEventName, eventName);
    categoryId = category.id;
    categoryName = category.name;
    await _prefs.setString(_kCategoryId, categoryId);
    await _prefs.setString(_kCategoryName, categoryName);
    await _prefs.setString(_kLastSync, lastSyncUtc!.toIso8601String());

    await _refreshCounts();
    _startTimer();
    notifyListeners();
  }

  Future<void> logout() async {
    _timer?.cancel();
    _timer = null;
    await _db.clearAll();
    await _prefs.remove(_kEventId);
    await _prefs.remove(_kEventName);
    await _prefs.remove(_kCategoryId);
    await _prefs.remove(_kCategoryName);
    await _prefs.remove(_kLastSync);

    eventId = null;
    eventName = '';
    categoryId = '';
    categoryName = '';
    lastSyncUtc = null;
    lastAttemptUtc = null;
    lastError = null;
    online = null;
    lastChangeCount = 0;
    await _refreshCounts();
    notifyListeners();
  }

  String get baseUrl => ApiClient.baseUrl;

  Future<void> setBaseUrl(String url) async {
    var value = url.trim();
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    if (value.isEmpty) value = AppConfig.defaultBaseUrl;
    ApiClient.baseUrl = value;
    await _prefs.setString(_kBaseUrl, value);
    notifyListeners();
  }

  void onAppResumed() {
    if (isLoggedIn) unawaited(syncNow());
  }

  // ---------------------------------------------------------------------------
  // Sync
  // ---------------------------------------------------------------------------

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(AppConfig.syncInterval, (_) => syncNow());
  }

  /// Pulls changed / new QR codes since the last checkpoint, then uploads
  /// any pending tags.
  Future<void> syncNow() async {
    final id = eventId;
    if (id == null || syncing) return;
    if (isDemo) {
      online = true;
      lastAttemptUtc = DateTime.now().toUtc();
      lastSyncUtc = lastAttemptUtc;
      await flushQueue();
      return;
    }

    syncing = true;
    notifyListeners();

    final startedAtUtc = DateTime.now().toUtc();
    lastAttemptUtc = startedAtUtc;
    try {
      final since = lastSyncUtc ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true);
      final snapshot = await _api.fetchChanges(id, since);
      if (eventId != id) return; // Logged out while the request was running.

      // Sync returns changes for every category. Keep rows in the selected
      // category; remove rows that moved to another category.
      final keep = <QrRecord>[];
      final remove = <String>[...snapshot.deletedCodes];
      for (final record in snapshot.records) {
        if (record.categoryId == categoryId) {
          keep.add(record);
        } else {
          remove.add(record.qrCode);
        }
      }
      await _db.upsertCodes(keep);
      await _db.deleteCodes(remove);

      lastSyncUtc = snapshot.serverTimeUtc ?? startedAtUtc;
      lastChangeCount = keep.length;
      await _prefs.setString(_kLastSync, lastSyncUtc!.toIso8601String());
      online = true;
      lastError = null;
    } on ApiException catch (e) {
      online = !e.isNetwork;
      lastError = e.message;
    } catch (e) {
      online = false;
      lastError = e.toString();
    } finally {
      syncing = false;
      await _refreshCounts();
      notifyListeners();
    }

    await flushQueue();
  }

  /// Uploads pending tags in order. Stops at the first network error and
  /// tries again on the next sync cycle.
  Future<void> flushQueue() async {
    final id = eventId;
    if (id == null || _flushing) return;
    _flushing = true;
    try {
      while (true) {
        final batch = await _db.pendingTags(limit: 20);
        if (batch.isEmpty) break;
        for (final tag in batch) {
          try {
            if (id != AppConfig.demoEventId) {
              await _api.submitTag(tag, eventId: id, deviceId: deviceId);
            }
            await _db.markSynced(tag.id!);
            online = true;
          } on ApiException catch (e) {
            if (e.isNetwork || e.isRetryable) {
              online = !e.isNetwork;
              lastError = e.message;
              await _db.recordFailedAttempt(tag.id!, e.message);
              return;
            }
            await _db.markRejected(tag.id!, e.message);
          } catch (e) {
            await _db.recordFailedAttempt(tag.id!, e.toString());
            return;
          }
        }
        await _refreshCounts();
        notifyListeners();
      }
    } finally {
      _flushing = false;
      await _refreshCounts();
      notifyListeners();
    }
  }

  Future<void> retryRejected() async {
    await _db.requeueRejected();
    await _refreshCounts();
    notifyListeners();
    await flushQueue();
  }

  // ---------------------------------------------------------------------------
  // Scanning
  // ---------------------------------------------------------------------------

  Future<QrRecord?> findGuest(String code) => _db.findCode(code);

  Future<TagRecord?> tagForGuest(String guestQr) => _db.tagForGuest(guestQr);

  Future<TagRecord?> tagForCard(String cardQr) => _db.tagForCard(cardQr);

  /// Saves the pair locally and uploads it right away if online.
  Future<void> saveTag(QrRecord guest, String cardQr) async {
    await _db.insertTag(TagRecord(
      guestQr: guest.qrCode,
      cardQr: cardQr,
      categoryId: guest.categoryId,
      categoryName: guest.categoryName,
      scannedAtUtc: DateTime.now().toUtc(),
    ));
    await _refreshCounts();
    notifyListeners();
    unawaited(flushQueue());
  }

  // ---------------------------------------------------------------------------

  Future<void> _refreshCounts() async {
    totalCodes = await _db.countCodes();
    pendingCount = await _db.countTags(TagSyncStatus.pending);
    syncedCount = await _db.countTags(TagSyncStatus.synced);
    rejectedCount = await _db.countTags(TagSyncStatus.rejected);
    recentTags = await _db.recentTags(limit: 15);
  }

  EventSnapshot _demoSnapshot(TaggingCategory category) {
    return EventSnapshot(
      eventName: 'Demo Event',
      records: List<QrRecord>.generate(200, (i) {
        return QrRecord(
          qrCode: 'DEMO-${(i + 1).toString().padLeft(4, '0')}',
          categoryId: category.id,
          categoryName: category.name,
        );
      }),
      deletedCodes: const <String>[],
    );
  }

  String _generateDeviceId() {
    final random = Random.secure();
    return List<String>.generate(12, (_) => random.nextInt(16).toRadixString(16)).join();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}
