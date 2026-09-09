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
    await prefs.setString('saved_password', 'secret123');

    expect(await WalletRepository.hasSavedCredentials(), isTrue);
    expect(await WalletRepository.getSavedAccountId(), 'alice');
    expect(await WalletRepository.getSavedPassword(), 'secret123');

    await WalletRepository.clearSavedCredentials();
    expect(await WalletRepository.hasSavedCredentials(), isFalse);
    expect(await WalletRepository.getSavedAccountId(), isNull);
    expect(await WalletRepository.getSavedPassword(), isNull);
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
}
