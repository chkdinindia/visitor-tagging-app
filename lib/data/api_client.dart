import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import '../config/app_config.dart';
import 'models.dart';

class ApiException implements Exception {
  const ApiException(this.message, {this.isNetwork = false});

  final String message;

  /// True when the request did not reach the server or the server had a
  /// temporary failure. Network errors are retried; other errors are not.
  final bool isNetwork;

  @override
  String toString() => message;
}

/// Result of the full download or a delta sync.
class EventSnapshot {
  const EventSnapshot({
    required this.eventName,
    required this.records,
    required this.deletedCodes,
    this.serverTimeUtc,
  });

  final String eventName;
  final List<QrRecord> records;
  final List<String> deletedCodes;
  final DateTime? serverTimeUtc;
}

class ApiClient {
  ApiClient({http.Client? client}) : _http = client ?? http.Client();

  final http.Client _http;

  Map<String, String> get _headers => <String, String>{
        'Accept': 'application/json',
        ...AppConfig.extraHeaders,
      };

  Uri _uri(String path, Map<String, String> query) =>
      Uri.parse('${AppConfig.baseUrl}$path').replace(queryParameters: query);

  /// Validates the event and downloads the full QR database.
  Future<EventSnapshot> fetchEvent(String eventId) async {
    final body = await _send(() => _http.get(
          _uri(AppConfig.eventPath, <String, String>{'event_id': eventId}),
          headers: _headers,
        ));
    return _parseSnapshot(body);
  }

  /// Downloads QR codes added or changed after [sinceUtc].
  Future<EventSnapshot> fetchChanges(String eventId, DateTime sinceUtc) async {
    final body = await _send(() => _http.get(
          _uri(AppConfig.syncPath, <String, String>{
            'event_id': eventId,
            'since': sinceUtc.toUtc().toIso8601String(),
          }),
          headers: _headers,
        ));
    return _parseSnapshot(body);
  }

  /// Uploads one guest/card pair.
  Future<void> submitTag(
    TagRecord tag, {
    required String eventId,
    required String deviceId,
  }) async {
    await _send(() => _http.post(
          Uri.parse('${AppConfig.baseUrl}${AppConfig.tagPath}'),
          headers: <String, String>{..._headers, 'Content-Type': 'application/json'},
          body: jsonEncode(<String, Object?>{
            'event_id': eventId,
            'guest_qr': tag.guestQr,
            'card_qr': tag.cardQr,
            'category_id': tag.categoryId,
            'scanned_at': tag.scannedAtUtc.toUtc().toIso8601String(),
            'device_id': deviceId,
            'local_id': tag.id,
          }),
        ));
  }

  // ---------------------------------------------------------------------------

  Future<Map<String, dynamic>> _send(Future<http.Response> Function() request) async {
    http.Response response;
    try {
      response = await request().timeout(AppConfig.requestTimeout);
    } on TimeoutException {
      throw const ApiException('Request timed out', isNetwork: true);
    } on IOException {
      throw const ApiException('No internet connection', isNetwork: true);
    } on http.ClientException catch (e) {
      throw ApiException('Network error: ${e.message}', isNetwork: true);
    }

    if (response.statusCode >= 500) {
      throw ApiException('Server error (${response.statusCode})', isNetwork: true);
    }

    dynamic decoded;
    try {
      decoded = response.body.isEmpty ? <String, dynamic>{} : jsonDecode(response.body);
    } on FormatException {
      throw ApiException('Invalid response from server (${response.statusCode})');
    }

    final Map<String, dynamic> body = decoded is Map<String, dynamic>
        ? decoded
        : <String, dynamic>{'data': decoded};

    final message = pickString(body, const ['message', 'msg', 'error']);
    if (response.statusCode >= 400) {
      throw ApiException(message ?? 'Request failed (${response.statusCode})');
    }
    if (body['status'] == false || body['success'] == false) {
      throw ApiException(message ?? 'Request was rejected by the server');
    }
    return body;
  }

  EventSnapshot _parseSnapshot(Map<String, dynamic> body) {
    final dynamic data = body['data'];
    final Map<dynamic, dynamic> payload = data is Map ? data : body;

    final dynamic list = payload['qr_codes'] ??
        payload['records'] ??
        payload['items'] ??
        (payload['data'] is List ? payload['data'] : null) ??
        (data is List ? data : null);

    final records = <QrRecord>[];
    if (list is List) {
      for (final item in list) {
        final record = QrRecord.fromApi(item);
        if (record != null) records.add(record);
      }
    }

    final deleted = <String>[];
    final dynamic deletedRaw = payload['deleted'] ?? payload['deleted_qr_codes'];
    if (deletedRaw is List) {
      for (final item in deletedRaw) {
        final code = item is Map ? QrRecord.fromApi(item)?.qrCode : item?.toString();
        if (code != null && code.isNotEmpty) deleted.add(code);
      }
    }

    String eventName = '';
    final dynamic event = payload['event'] ?? body['event'];
    if (event is Map) {
      eventName = pickString(event, const ['name', 'event_name', 'title']) ?? '';
    }
    if (eventName.isEmpty) {
      eventName = pickString(payload, const ['event_name']) ??
          pickString(body, const ['event_name']) ??
          '';
    }

    return EventSnapshot(
      eventName: eventName,
      records: records,
      deletedCodes: deleted,
      serverTimeUtc: _parseTime(payload['server_time'] ?? body['server_time']),
    );
  }

  DateTime? _parseTime(dynamic value) {
    if (value == null) return null;
    if (value is num) {
      final n = value.toInt();
      final ms = n > 100000000000 ? n : n * 1000;
      return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true);
    }
    final text = value.toString().trim();
    if (text.isEmpty) return null;
    final numeric = int.tryParse(text);
    if (numeric != null) return _parseTime(numeric);
    // "2026-11-14 09:30:00" without zone is treated as UTC.
    final hasZone = text.endsWith('Z') || RegExp(r'[+-]\d{2}:?\d{2}$').hasMatch(text);
    final parsed = DateTime.tryParse(hasZone ? text : '${text.replaceFirst(' ', 'T')}Z');
    return parsed?.toUtc();
  }
}
