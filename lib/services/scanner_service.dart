import 'package:flutter/services.dart';

/// Receives barcodes from the handheld's built-in laser scanner when it is
/// configured in broadcast (intent) mode. See MainActivity.kt for the list of
/// supported vendor intents.
///
/// Scanners in keyboard / "key wedge" mode are handled by the hidden input
/// field on the scan screen instead.
class ScannerService {
  ScannerService._();

  static const EventChannel _channel = EventChannel('com.chkdin.visitor_tagging/scanner');

  static Stream<String> get broadcastScans => _channel
      .receiveBroadcastStream()
      .where((dynamic event) => event is String)
      .map((dynamic event) => (event as String).trim())
      .handleError((Object _) {});
}
