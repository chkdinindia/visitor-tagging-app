/// Central configuration for the Visitor Tagging app.
///
/// All API endpoints live here so the backend contract can be changed
/// without touching the rest of the code. See API_CONTRACT.md.
class AppConfig {
  AppConfig._();

  /// Base URL of the visitor tagging API (no trailing slash).
  static const String baseUrl = 'https://api.chkdin.com/visitor-tagging';

  /// GET  {baseUrl}{eventPath}?event_id=123456
  /// Validates the event and returns the full QR code database.
  static const String eventPath = '/event';

  /// GET  {baseUrl}{syncPath}?event_id=123456&since=2026-11-14T09:30:00.000Z
  /// Returns QR codes that were added or whose category changed since `since`.
  static const String syncPath = '/sync';

  /// POST {baseUrl}{tagPath}
  /// Sends a guest QR + printed card QR pair to the server.
  static const String tagPath = '/tag';

  /// Extra headers sent with every request (for example an API key).
  static const Map<String, String> extraHeaders = <String, String>{};

  /// How often the app pulls changes and uploads pending tags.
  static const Duration syncInterval = Duration(minutes: 2);

  /// Network timeout for a single request. The first download can be large.
  static const Duration requestTimeout = Duration(seconds: 60);

  /// Number of digits in an Event ID.
  static const int eventIdLength = 6;

  /// If false, a guest QR that is not in the local database is rejected.
  static const bool allowUnknownGuest = false;

  /// If true, a QR that exists in the guest database cannot be used as a card.
  /// This prevents accidentally pairing two guests together.
  static const bool rejectGuestQrAsCard = true;

  /// Event ID that runs the app offline with sample data, for testing the
  /// scanner and UI before the APIs are ready. Guest QRs: DEMO-0001 … DEMO-0200.
  static const String demoEventId = '000000';

  /// Ignore the same code if it is scanned again within this window.
  static const Duration duplicateScanWindow = Duration(milliseconds: 1200);
}
