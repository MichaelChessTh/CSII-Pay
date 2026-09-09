import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:csii_pay_app/data/services/crypto_service.dart';

void main() {
  test('Dart Secp256k1 Schnorr signer produces 192-char signature', () {
    final privkey = BigInt.parse('34216482e93afe6c2a56921254f49e75048ce9890aa9600f7d206c4e92cf3136', radix: 16);
    final tx = {
      'action': 'TRANSFER',
      'sender': '6958082456',
      'nonce': 0,
      'timestamp': 1700000000.0,
      'payload': {'recipient': 'alice', 'token': 'CSP', 'amount': 10.0}
    };
    final canonical = computeCanonicalTxBytes(tx);
    expect(utf8.decode(canonical), '{"action":"TRANSFER","nonce":0,"payload":{"amount":10,"recipient":"alice","token":"CSP"},"sender":"6958082456","timestamp":1700000000}');
    final sig = signTransactionPayload(tx, privkey);
    expect(sig.length, 192);
  });

  test('Dart Secp256k1 canonical representation preserves decimal fractions', () {
    final tx = {
      'action': 'TRANSFER',
      'sender': '6958082456',
      'nonce': 1,
      'timestamp': 1725810000.5,
      'payload': {'recipient': 'bob', 'token': 'BDP', 'amount': 2.5}
    };
    final canonical = computeCanonicalTxBytes(tx);
    expect(utf8.decode(canonical), '{"action":"TRANSFER","nonce":1,"payload":{"amount":2.5,"recipient":"bob","token":"BDP"},"sender":"6958082456","timestamp":1725810000.5}');
  });
}
