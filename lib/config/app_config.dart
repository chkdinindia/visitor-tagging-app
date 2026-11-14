/// A guest category that can be tagged with printed cards.
class TaggingCategory {
  const TaggingCategory({required this.id, required this.name});

  /// Must match bts_qr_pool.category_id.
  final String id;
  final String name;
}

/// Central configuration for the Visitor Tagging app.
///
/// All API endpoints live here so the backend contract can be changed
/// without touching the rest of the code. See API_CONTRACT.md.
class AppConfig {
  AppConfig._();

  /// Default base URL of the visitor tagging API (no trailing slash).
  /// Can be changed on the device from the login screen (server icon).
  /// For CodeIgniter 3 this is "{site}/visitor_tagging"
  /// (or "{site}/index.php/visitor_tagging" if index.php is not removed).
  static const String defaultBaseUrl = 'https://studio.chkdin.com/visitor_tagging';

  /// GET  {baseUrl}{eventPath}?event_id=123456
  /// Validates the event and returns every QR in bts_qr_pool for that event.
  static const String eventPath = '/event';

  /// GET  {baseUrl}{syncPath}?event_id=123456&since=2026-11-14T09:30:00.000Z
  /// Returns rows whose changed_at (UTC) is on or after `since`.
  static const String syncPath = '/sync';

  /// POST {baseUrl}{tagPath}
  /// Sends a guest QR + printed card QR pair to the server.
  static const String tagPath = '/tag';

  /// Sent as the "X-Api-Key" header. Must match API_KEY in the CI3 controller.
  static const String apiKey = 'a2cba4859fe1d8124d73781060b802f311a7ab84';

  /// Headers sent with every request.
  static const Map<String, String> extraHeaders = <String, String>{'X-Api-Key': apiKey};

  /// How often the app pulls changes and uploads pending tags.
  static const Duration syncInterval = Duration(minutes: 2);

  /// Network timeout for a single request. The first download can be large.
  static const Duration requestTimeout = Duration(seconds: 60);

  /// Categories offered after login. Only the chosen category's QR codes are
  /// downloaded and kept in sync. Edit IDs and names to match bts_qr_pool.
  static const List<TaggingCategory> taggingCategories = <TaggingCategory>[
    TaggingCategory(id: '29', name: 'Association Partner'),
    TaggingCategory(id: '93', name: 'QUIZ - Day 3'),
    TaggingCategory(id: '0', name: 'Category 3 (set ID)'),
    TaggingCategory(id: '0', name: 'Category 4 (set ID)'),
  ];

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
