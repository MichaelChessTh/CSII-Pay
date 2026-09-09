import 'package:flutter_test/flutter_test.dart';
import 'package:csii_pay_app/domain/crypto_utils.dart';

void main() {
  test('Fee calculation test', () {
    expect(calculateFee('BDP', 100), 1.0);
    expect(calculateFee('CSP', 100), 0.0);
    expect(calculateFee('CSP', 200), 2.0);
    expect(calculateFee('CSP', 600), 12.0);
  });

  test('QR Payload encode and decode test', () {
    const payload = QrPayload(
      accountId: '6958082456',
      amount: 50.0,
      token: 'CSP',
      note: 'Coffee',
    );
    final jsonStr = payload.toJsonString();
    final parsed = QrPayload.tryParse(jsonStr);
    expect(parsed, isNotNull);
    expect(parsed!.accountId, '6958082456');
    expect(parsed.amount, 50.0);
    expect(parsed.token, 'CSP');
    expect(parsed.note, 'Coffee');
  });
}
