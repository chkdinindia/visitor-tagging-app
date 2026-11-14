import 'package:flutter_test/flutter_test.dart';
import 'package:visitor_tagging/data/models.dart';

void main() {
  test('parses QR records with common key names', () {
    final a = QrRecord.fromApi(<String, dynamic>{'qr_code': 'ABC123', 'category_id': 4});
    final b = QrRecord.fromApi(<String, dynamic>{'qrcode': 'XYZ', 'categoryId': '7', 'category_name': 'VIP'});

    expect(a?.qrCode, 'ABC123');
    expect(a?.categoryId, '4');
    expect(b?.categoryLabel, 'VIP');
    expect(QrRecord.fromApi(<String, dynamic>{'category_id': 1}), isNull);
  });
}
