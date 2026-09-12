import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:cloud_firestore/cloud_firestore.dart' hide Order;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../services/node_api_service.dart';
import '../services/crypto_service.dart';
import '../services/user_profile_service.dart';
import '../services/marketplace_service.dart';
import '../../domain/models/user_profile.dart';
import '../../domain/models/transaction_item.dart';

class WalletRepository {
  final NodeApiService _api;
  final UserProfileService _profileService;
  final MarketplaceService _marketplaceService;
  static const _keyNodeUrl = 'node_url';
  static const _keyAccountId = 'account_id';
  static const _keyRefreshToken = 'refresh_token';
  static const _keyPrivKey = 'wallet_privkey';
  static const _keyAppPin = 'app_pin';
  static const _keyPinFailures = 'pin_failed_attempts';
  static const _legacyKeySavedPassword = 'saved_password';
  static const int maxPinAttempts = 5;

  AccountInfo? _cachedAccount;
  UserProfile? _currentProfile;
  BigInt? _privkey;

  WalletRepository(
    this._api, {
    UserProfileService? profileService,
    MarketplaceService? marketplaceService,
  })  : _profileService = profileService ?? _createProfileService(),
        _marketplaceService = marketplaceService ?? _createMarketplaceService(_api) {
    _api.onTokensChanged = _persistTokens;
  }

  static UserProfileService _createProfileService() {
    try {
      return UserProfileService(firestore: FirebaseFirestore.instance);
    } catch (_) {
      return UserProfileService(firestore: null);
    }
  }

  static MarketplaceService _createMarketplaceService(NodeApiService api) {
    try {
      return MarketplaceService(firestore: FirebaseFirestore.instance, nodeApi: api);
    } catch (_) {
      return MarketplaceService(firestore: null, nodeApi: api);
    }
  }

  String get nodeUrl => _api.nodeUrl;
  MarketplaceService get marketplaceService => _marketplaceService;
  UserProfileService get profileService => _profileService;
  NodeApiService get api => _api;

  AccountInfo? get cachedAccount => _cachedAccount;
  UserProfile? get currentProfile => _currentProfile;
  BigInt? get privkey => _privkey;

  Future<void> setNodeUrl(String url) async {
    _api.nodeUrl = url.trim().replaceAll(RegExp(r'/$'), '');
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyNodeUrl, _api.nodeUrl);
  }

  static Future<String?> getSavedNodeUrl() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyNodeUrl);
  }

  static Future<String?> getSavedAccountId() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyAccountId);
  }

  static Future<String?> getSavedRefreshToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyRefreshToken);
  }

  /// A resumable session needs an account id and a refresh token.
  /// The password itself is never written to disk.
  static Future<bool> hasSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final acc = prefs.getString(_keyAccountId);
    final rt = prefs.getString(_keyRefreshToken);
    return acc != null && acc.isNotEmpty && rt != null && rt.isNotEmpty;
  }

  static Future<void> clearSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyAccountId);
    await prefs.remove(_keyRefreshToken);
    await prefs.remove(_keyPrivKey);
    await prefs.remove(_keyPinFailures);
    // Earlier builds stored the password in plain text: make sure it is gone.
    await prefs.remove(_legacyKeySavedPassword);
  }

  /// Counts a wrong PIN. Returns attempts remaining; 0 means the session must be wiped.
  static Future<int> recordPinFailure() async {
    final prefs = await SharedPreferences.getInstance();
    final failures = (prefs.getInt(_keyPinFailures) ?? 0) + 1;
    await prefs.setInt(_keyPinFailures, failures);
    return (maxPinAttempts - failures).clamp(0, maxPinAttempts);
  }

  static Future<void> resetPinFailures() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyPinFailures);
  }

  Future<void> _persistTokens(AuthTokens? tokens) async {
    final prefs = await SharedPreferences.getInstance();
    if (tokens == null || tokens.refreshToken.isEmpty) {
      await prefs.remove(_keyRefreshToken);
    } else {
      await prefs.setString(_keyRefreshToken, tokens.refreshToken);
    }
  }

  Future<void> _persistIdentity(String accountId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyAccountId, accountId);
    await prefs.remove(_legacyKeySavedPassword);
    if (_privkey != null) {
      // Interim: the signing key lives in app preferences (never the password).
      // Moving it to the platform keystore (flutter_secure_storage) is the next step.
      await prefs.setString(_keyPrivKey, _privkey!.toRadixString(16).padLeft(64, '0'));
    }
  }

  /// Derives the signing key on-device; the node no longer returns private keys.
  void _deriveKey(String password, AccountInfo info) {
    final salt = info.salt;
    if (salt == null || salt.isEmpty) {
      _privkey = null;
      return;
    }
    final kp = deriveAccountKeypair(password, salt);
    final onChainKey = info.publicKey;
    if (onChainKey != null && onChainKey.isNotEmpty && onChainKey != kp.publicKeyHex) {
      debugPrint('[WalletRepository] Derived public key differs from the on-chain key for ${info.accountId}');
    }
    _privkey = kp.privateKey;
  }

  /// Cold start: resume with the stored refresh token instead of re-sending a password.
  Future<bool> restoreSession() async {
    final prefs = await SharedPreferences.getInstance();
    final accountId = prefs.getString(_keyAccountId);
    final refreshToken = prefs.getString(_keyRefreshToken);
    final privHex = prefs.getString(_keyPrivKey);
    if (accountId == null || accountId.isEmpty || refreshToken == null || refreshToken.isEmpty) {
      return false;
    }
    _api.refreshToken = refreshToken;
    if (!await _api.refreshSession()) {
      await clearSavedCredentials();
      return false;
    }
    final r = await _api.getAccount(accountId);
    if (!r.success || r.data == null) {
      return false;
    }
    _privkey = privHex != null ? BigInt.tryParse(privHex, radix: 16) : null;
    _cachedAccount = r.data;
    _currentProfile = await _profileService.getUserProfile(accountId);
    return true;
  }

  static Future<String?> getAppPin() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyAppPin);
  }

  static Future<bool> hasAppPin() async {
    final prefs = await SharedPreferences.getInstance();
    final pin = prefs.getString(_keyAppPin);
    return pin != null && pin.isNotEmpty;
  }

  static Future<void> setAppPin(String pin) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyAppPin, pin.trim());
  }

  static Future<void> removeAppPin() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyAppPin);
  }

  /// Fetches the dynamically published Cloudflare Gateway URL from Cloud Firestore
  Future<String?> fetchRemoteGatewayUrl() async {
    // If running in browser, the current serving origin is the gateway
    if (kIsWeb) {
      final origin = '${Uri.base.scheme}://${Uri.base.host}${Uri.base.hasPort ? ':${Uri.base.port}' : ''}';
      if (origin.startsWith('http')) {
        return origin;
      }
    }

    String? cloudUrl;
    String? lanUrl;

    // 1. Try Firestore SDK
    try {
      final doc = await FirebaseFirestore.instance
          .collection('network_config')
          .doc('gateway')
          .get();
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        final status = data['status']?.toString();
        if (status == 'online') {
          cloudUrl = data['url']?.toString();
          lanUrl = data['lan_url']?.toString();
        }
      }
    } catch (_) {}

    // 2. Try Firestore REST API fallback
    if (cloudUrl == null && lanUrl == null) {
      try {
        const restUrl =
            'https://firestore.googleapis.com/v1/projects/csii-pay/databases/(default)/documents/network_config/gateway';
        final res = await http.get(Uri.parse(restUrl)).timeout(const Duration(seconds: 4));
        if (res.statusCode == 200) {
          final data = jsonDecode(res.body) as Map<String, dynamic>;
          final fields = data['fields'] as Map<String, dynamic>?;
          final status = fields?['status']?['stringValue']?.toString();
          if (status == 'online') {
            cloudUrl = fields?['url']?['stringValue']?.toString();
            lanUrl = fields?['lan_url']?['stringValue']?.toString();
          }
        }
      } catch (_) {}
    }

    // 3. If on same Wi-Fi, test lan_url first for instant local latency
    if (lanUrl != null && lanUrl.startsWith('http')) {
      final cleanLan = lanUrl.trim().replaceAll(RegExp(r'/$'), '');
      try {
        final ping = await http.get(Uri.parse('$cleanLan/status')).timeout(const Duration(milliseconds: 1500));
        if (ping.statusCode == 200) {
          return cleanLan;
        }
      } catch (_) {}
    }

    if (cloudUrl != null && cloudUrl.startsWith('http')) {
      return cloudUrl.trim().replaceAll(RegExp(r'/$'), '');
    }

    return null;
  }

  Future<ApiResult<NodeStatus>> checkNode() => _api.getStatus();

  Future<ApiResult<AccountInfo>> login(String accountId, String password) async {
    final cleanId = accountId.trim().replaceFirst(RegExp(r'^@'), '');
    if (cleanId.isEmpty) {
      return const ApiResult.err('Please enter your account ID or username');
    }

    // 1. Try direct login with provided identifier
    var r = await _api.login(cleanId, password);
    var effectiveAccountId = cleanId;

    // 2. If direct login fails, try resolving cleanId as Student ID or Nickname
    if (!r.success) {
      final resolved = await _profileService.findUsernameByStudentIdOrNickname(cleanId);
      if (resolved != null && resolved.toLowerCase() != cleanId.toLowerCase()) {
        final retry = await _api.login(resolved, password);
        if (retry.success) {
          r = retry;
          effectiveAccountId = resolved;
        }
      }
    }

    // 3. If still failing and cleanId has uppercase letters, try lowercase
    if (!r.success && cleanId != cleanId.toLowerCase()) {
      final retry = await _api.login(cleanId.toLowerCase(), password);
      if (retry.success) {
        r = retry;
        effectiveAccountId = cleanId.toLowerCase();
      }
    }

    if (r.success && r.data != null) {
      final finalAccountId = (r.data!.accountId.isNotEmpty) ? r.data!.accountId : effectiveAccountId;
      _cachedAccount = r.data;
      _deriveKey(password, r.data!);
      await WalletRepository.resetPinFailures();
      await _persistIdentity(finalAccountId);

      // Load or build user profile
      final existingProfile = await _profileService.getUserProfile(finalAccountId);
      if (existingProfile != null) {
        _currentProfile = existingProfile;
      } else {
        _currentProfile = UserProfile(
          username: finalAccountId,
          studentId: finalAccountId == '6958082456' ? '6958082456' : 'N/A',
          fullName: finalAccountId == '6958082456' ? 'Genesis Node Operator' : finalAccountId,
          nickname: finalAccountId == '6958082456' ? 'Genesis Operator' : finalAccountId,
          publicKey: r.data!.publicKey ?? '',
          createdAt: DateTime.now(),
        );
        // Persist profile to Firestore so peers can immediately resolve nickname
        await _profileService.saveUserProfile(_currentProfile!);
      }
    }
    return r;
  }

  Future<ApiResult<AccountInfo>> register(String accountId, String password) async {
    final cleanId = accountId.trim().replaceFirst(RegExp(r'^@'), '');
    final r = await _api.register(cleanId, password);
    if (r.success && r.data != null) {
      _cachedAccount = r.data;
      _deriveKey(password, r.data!);
      await _persistIdentity(cleanId);
    }
    return r;
  }

  Future<ApiResult<AccountInfo>> registerWithProfile({
    required String studentId,
    required String fullName,
    required String nickname,
    required String username,
    required String password,
  }) async {
    final cleanUsername = username.trim().replaceFirst(RegExp(r'^@'), '');
    final cleanStudentId = studentId.trim();

    // 1. Verify username uniqueness in Cloud Firestore
    final available = await _profileService.isUsernameAvailable(cleanUsername);
    if (!available) {
      return const ApiResult.err('Username is already taken in the system.');
    }

    // 2. Register account on blockchain node
    final r = await _api.register(cleanUsername, password, studentId: cleanStudentId);
    if (!r.success || r.data == null) {
      return r;
    }

    _cachedAccount = r.data;
    _deriveKey(password, r.data!);
    await _persistIdentity(cleanUsername);

    // 3. Store profile in Firestore (excluding password)
    final profile = UserProfile(
      username: cleanUsername,
      studentId: cleanStudentId,
      fullName: fullName.trim(),
      nickname: nickname.trim(),
      publicKey: r.data!.publicKey ?? '',
      createdAt: DateTime.now(),
    );
    await _profileService.saveUserProfile(profile);
    _currentProfile = profile;

    return r;
  }

  Future<String?> getNickname(String username) => _profileService.getNickname(username);
  Future<UserProfile?> getUserProfile(String username) => _profileService.getUserProfile(username);

  Future<ApiResult<AccountInfo>> refreshAccount() async {
    final accId = _cachedAccount?.accountId;
    if (accId == null) return const ApiResult.err('Not logged in');
    final r = await _api.getAccount(accId);
    if (r.success && r.data != null) {
      // Retain the privateKey from memory session
      _cachedAccount = AccountInfo(
        accountId: r.data!.accountId,
        balances: r.data!.balances,
        frozenBalances: r.data!.frozenBalances,
        isVerified: r.data!.isVerified,
        verificationStatus: r.data!.verificationStatus,
        nonce: r.data!.nonce,
        salt: r.data!.salt,
        publicKey: r.data!.publicKey,
        privateKey: _privkey?.toRadixString(16).padLeft(64, '0'),
      );
    }
    return r;
  }

  void _signTx(Map<String, dynamic> tx) {
    if (_privkey != null) {
      tx['signature'] = signTransactionPayload(tx, _privkey!);
    } else {
      tx['signature'] = 'DIRECT';
    }
  }

  Future<ApiResult<bool>> transfer({
    required String recipient,
    required String token,
    required double amount,
  }) async {
    final acc = _cachedAccount;
    if (acc == null) return const ApiResult.err('Not logged in');
    await refreshAccount();
    final activeAcc = _cachedAccount ?? acc;
    final tx = {
      'tx_id': generateTxId('TX_${activeAcc.accountId}'),
      'sender': activeAcc.accountId,
      'action': 'TRANSFER',
      'payload': {
        'recipient': recipient,
        'token': token,
        'amount': amount,
      },
      'nonce': activeAcc.nonce,
      'timestamp': DateTime.now().millisecondsSinceEpoch / 1000.0,
      'signature': '',
    };
    _signTx(tx);
    final r = await _api.submitTx(tx);
    if (r.success) {
      await refreshAccount();
    }
    return r;
  }

  Future<ApiResult<bool>> createOrder({
    required String offerToken,
    required double offerAmount,
    required String requestToken,
    required double requestAmount,
    required bool allowPartial,
  }) async {
    final acc = _cachedAccount;
    if (acc == null) return const ApiResult.err('Not logged in');
    await refreshAccount();
    final activeAcc = _cachedAccount ?? acc;
    final orderId = generateTxId('ORD_${activeAcc.accountId}').substring(0, 16);
    final tx = {
      'tx_id': generateTxId('TX_ORD_CREATE_$orderId'),
      'sender': activeAcc.accountId,
      'action': 'ORDER_CREATE',
      'payload': {
        'order_id': orderId,
        'offer_token': offerToken,
        'offer_amount': offerAmount,
        'request_token': requestToken,
        'request_amount': requestAmount,
        'allow_partial': allowPartial,
      },
      'nonce': activeAcc.nonce,
      'timestamp': DateTime.now().millisecondsSinceEpoch / 1000.0,
      'signature': '',
    };
    _signTx(tx);
    final r = await _api.submitTx(tx);
    if (r.success) await refreshAccount();
    return r;
  }

  Future<ApiResult<bool>> fulfillOrder(String orderId, {double? fillAmount}) async {
    final acc = _cachedAccount;
    if (acc == null) return const ApiResult.err('Not logged in');
    await refreshAccount();
    final activeAcc = _cachedAccount ?? acc;
    final payload = <String, dynamic>{'order_id': orderId};
    if (fillAmount != null) payload['fill_amount'] = fillAmount;
    final tx = {
      'tx_id': generateTxId('TX_ORD_FULFILL_$orderId'),
      'sender': activeAcc.accountId,
      'action': 'ORDER_FULFILL',
      'payload': payload,
      'nonce': activeAcc.nonce,
      'timestamp': DateTime.now().millisecondsSinceEpoch / 1000.0,
      'signature': '',
    };
    _signTx(tx);
    final r = await _api.submitTx(tx);
    if (r.success) await refreshAccount();
    return r;
  }

  Future<ApiResult<bool>> cancelOrder(String orderId) async {
    final acc = _cachedAccount;
    if (acc == null) return const ApiResult.err('Not logged in');
    await refreshAccount();
    final activeAcc = _cachedAccount ?? acc;
    final tx = {
      'tx_id': generateTxId('TX_ORD_CANCEL_$orderId'),
      'sender': activeAcc.accountId,
      'action': 'ORDER_CANCEL',
      'payload': {'order_id': orderId},
      'nonce': activeAcc.nonce,
      'timestamp': DateTime.now().millisecondsSinceEpoch / 1000.0,
      'signature': '',
    };
    _signTx(tx);
    final r = await _api.submitTx(tx);
    if (r.success) await refreshAccount();
    return r;
  }

  Future<ApiResult<List<Order>>> getOrders() => _api.getOrders();

  Future<ApiResult<List<Block>>> getChain() => _api.getChain();

  Future<ApiResult<NodeStatus>> getStatus() => _api.getStatus();

  Future<ApiResult<AccountInfo>> getAccountDetails(String accountId) =>
      _api.getAccount(accountId);

  Future<ApiResult<List<TransactionItem>>> getTransactionHistory({
    int limit = 20,
    int offset = 0,
  }) async {
    final accId = _cachedAccount?.accountId;
    if (accId == null) return const ApiResult.err('Not logged in');
    final r = await _api.getTransactions(accId, limit: limit, offset: offset);
    if (r.success && r.data != null) {
      final list = r.data!.map((j) => TransactionItem.fromJson(j)).toList();
      return ApiResult.ok(list);
    }
    return ApiResult.err(r.error ?? 'Failed to load transaction history');
  }

  Future<void> ping() async {
    if (_cachedAccount != null && _api.hasSession) {
      await _api.ping();
    }
  }

  Future<void> logout({bool clearSaved = false}) async {
    _cachedAccount = null;
    _privkey = null;
    // Revoke on the node and forget the refresh token: a signed-out device must not resume silently.
    await _api.logout();
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyRefreshToken);
    await prefs.remove(_keyPrivKey);
    if (clearSaved) {
      await clearSavedCredentials();
    }
  }
}
