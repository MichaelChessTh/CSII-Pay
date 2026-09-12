import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:csii_pay_app/data/repositories/wallet_repository.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('WalletRepository credentials persistence and clearance', () async {
    expect(await WalletRepository.hasSavedCredentials(), isFalse);

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('account_id', 'alice');
    await prefs.setString('refresh_token', 'rt.example.token');
    await prefs.setString('saved_password', 'legacy-plaintext');

    expect(await WalletRepository.hasSavedCredentials(), isTrue);
    expect(await WalletRepository.getSavedAccountId(), 'alice');
    expect(await WalletRepository.getSavedRefreshToken(), 'rt.example.token');

    await WalletRepository.clearSavedCredentials();
    expect(await WalletRepository.hasSavedCredentials(), isFalse);
    expect(await WalletRepository.getSavedAccountId(), isNull);
    expect(await WalletRepository.getSavedRefreshToken(), isNull);
    expect(prefs.getString('saved_password'), isNull, reason: 'legacy plaintext password must be purged');
  });

  test('WalletRepository PIN management', () async {
    expect(await WalletRepository.hasAppPin(), isFalse);
    expect(await WalletRepository.getAppPin(), isNull);

    await WalletRepository.setAppPin('1234');
    expect(await WalletRepository.hasAppPin(), isTrue);
    expect(await WalletRepository.getAppPin(), '1234');

    await WalletRepository.removeAppPin();
    expect(await WalletRepository.hasAppPin(), isFalse);
    expect(await WalletRepository.getAppPin(), isNull);
  });

  test('PIN failure counter counts down to a wipe', () async {
    for (var expected = WalletRepository.maxPinAttempts - 1; expected >= 1; expected--) {
      expect(await WalletRepository.recordPinFailure(), expected);
    }
    expect(await WalletRepository.recordPinFailure(), 0);
    await WalletRepository.resetPinFailures();
    expect(await WalletRepository.recordPinFailure(), WalletRepository.maxPinAttempts - 1);
  });
}
