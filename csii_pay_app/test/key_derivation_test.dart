import 'package:flutter_test/flutter_test.dart';
import 'package:csii_pay_app/data/services/crypto_service.dart';

void main() {
  test('deriveAccountKeypair matches the node implementation (node.py derive_account_keypair)', () {
    // Vector produced by: derive_account_keypair("correct horse battery", "0123456789abcdef0123456789abcdef")
    final kp = deriveAccountKeypair('correct horse battery', '0123456789abcdef0123456789abcdef');
    expect(kp.privateKeyHex, '6c503829f0509c70a05dce94712b3ab61e1a19f4b67fbafca5e21eb308e44078');
    expect(kp.publicKeyHex,
        '169ecef4dc037d3474e033defee8e94afd6ae6cbc2756944a6bccaf4d2b5b531d3ea4ee7f98bf486b82c4fa8c8861cbf44b25d6d7b4c0340fe4b54b6715ae1ce');
  });

  test('pbkdf2Sha256 matches RFC 6070-style vector for HMAC-SHA256', () {
    // PBKDF2-HMAC-SHA256("password", "salt", 1, 32) = 120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b
    final dk = pbkdf2Sha256('password'.codeUnits, 'salt'.codeUnits, 1, 32);
    final hex = dk.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    expect(hex, '120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b');
  });
}
