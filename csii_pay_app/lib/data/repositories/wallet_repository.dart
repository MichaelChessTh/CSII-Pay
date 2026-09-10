import 'dart:async';
import 'dart:convert';
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
  static const _keySavedPassword = 'saved_password';
  static const _keyAppPin = 'app_pin';

  AccountInfo? _cachedAccount;
  UserProfile? _currentProfile;
  String? _authToken;
  BigInt? _privkey;

  WalletRepository(
    this._api, {
    UserProfileService? profileService,
    MarketplaceService? marketplaceService,
  })  : _profileService = profileService ?? UserProfileService(),
        _marketplaceService = marketplaceService ?? MarketplaceService(nodeApi: _api);

  String get nodeUrl => _api.nodeUrl;
  MarketplaceService get marketplaceService => _marketplaceService;
  UserProfileService get profileService => _profileService;
  NodeApiService get api => _api;

  AccountInfo? get cachedAccount => _cachedAccount;
  UserProfile? get currentProfile => _currentProfile;
  String? get authToken => _authToken;
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

  static Future<String?> getSavedPassword() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keySavedPassword);
  }

  static Future<bool> hasSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    final acc = prefs.getString(_keyAccountId);
    final pwd = prefs.getString(_keySavedPassword);
    return acc != null && acc.isNotEmpty && pwd != null && pwd.isNotEmpty;
  }

  static Future<void> clearSavedCredentials() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyAccountId);
    await prefs.remove(_keySavedPassword);
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
    // 1. Try Firestore SDK
    try {
      final doc = await FirebaseFirestore.instance
          .collection('network_config')
          .doc('gateway')
          .get();
      if (doc.exists && doc.data() != null) {
        final data = doc.data()!;
        final status = data['status']?.toString();
        final url = data['url']?.toString();
        if (status == 'online' && url != null && url.startsWith('http')) {
          return url.trim().replaceAll(RegExp(r'/$'), '');
        }
      }
    } catch (_) {}

    // 2. Try Firestore REST API fallback
    try {
      const restUrl =
          'https://firestore.googleapis.com/v1/projects/csii-pay/databases/(default)/documents/network_config/gateway';
      final res = await http.get(Uri.parse(restUrl)).timeout(const Duration(seconds: 4));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final fields = data['fields'] as Map<String, dynamic>?;
        final status = fields?['status']?['stringValue']?.toString();
        final url = fields?['url']?['stringValue']?.toString();
        if (status == 'online' && url != null && url.startsWith('http')) {
          return url.trim().replaceAll(RegExp(r'/$'), '');
        }
      }
    } catch (_) {}

    return null;
  }

  Future<ApiResult<NodeStatus>> checkNode() => _api.getStatus();

  Future<ApiResult<AccountInfo>> login(String accountId, String password) async {
    final r = await _api.login(accountId, password);
    if (r.success && r.data != null) {
      _cachedAccount = r.data;
      if (r.data!.privateKey != null) {
        _privkey = BigInt.tryParse(r.data!.privateKey!, radix: 16);
      }
      _authToken = _extractToken(r);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyAccountId, accountId);
      await prefs.setString(_keySavedPassword, password);

      // Load or build user profile
      final existingProfile = await _profileService.getUserProfile(accountId);
      if (existingProfile != null) {
        _currentProfile = existingProfile;
      } else {
        _currentProfile = UserProfile(
          username: accountId,
          studentId: accountId == '6958082456' ? '6958082456' : 'N/A',
          fullName: accountId == '6958082456' ? 'Genesis Node Operator' : accountId,
          nickname: accountId == '6958082456' ? 'Genesis Operator' : accountId,
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
    final r = await _api.register(accountId, password);
    if (r.success && r.data != null) {
      _cachedAccount = r.data;
      if (r.data!.privateKey != null) {
        _privkey = BigInt.tryParse(r.data!.privateKey!, radix: 16);
      }
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_keyAccountId, accountId);
      await prefs.setString(_keySavedPassword, password);
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
    final cleanUsername = username.trim();

    // 1. Verify username uniqueness in Cloud Firestore
    final available = await _profileService.isUsernameAvailable(cleanUsername);
    if (!available) {
      return const ApiResult.err('Username is already taken in the system.');
    }

    // 2. Register account on blockchain node
    final r = await _api.register(cleanUsername, password);
    if (!r.success || r.data == null) {
      return r;
    }

    _cachedAccount = r.data;
    if (r.data!.privateKey != null) {
      _privkey = BigInt.tryParse(r.data!.privateKey!, radix: 16);
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyAccountId, cleanUsername);
    await prefs.setString(_keySavedPassword, password);

    // 3. Store profile in Firestore (excluding password)
    final profile = UserProfile(
      username: cleanUsername,
      studentId: studentId.trim(),
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
    final tx = {
      'tx_id': generateTxId('TX_${acc.accountId}'),
      'sender': acc.accountId,
      'action': 'TRANSFER',
      'payload': {
        'recipient': recipient,
        'token': token,
        'amount': amount,
      },
      'nonce': _cachedAccount?.nonce ?? acc.nonce,
      'timestamp': DateTime.now().millisecondsSinceEpoch / 1000.0,
      'signature': '',
    };
    _signTx(tx);
    final r = await _api.submitTx(tx);
    if (r.success) {
      // Optimistically update nonce & refresh
      _cachedAccount = AccountInfo(
        accountId: acc.accountId,
        balances: acc.balances,
        frozenBalances: acc.frozenBalances,
        isVerified: acc.isVerified,
        verificationStatus: acc.verificationStatus,
        nonce: acc.nonce + 1,
        salt: acc.salt,
        publicKey: acc.publicKey,
        privateKey: acc.privateKey,
      );
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
    final orderId = generateTxId('ORD_${acc.accountId}').substring(0, 16);
    final tx = {
      'tx_id': generateTxId('TX_ORD_CREATE_$orderId'),
      'sender': acc.accountId,
      'action': 'ORDER_CREATE',
      'payload': {
        'order_id': orderId,
        'offer_token': offerToken,
        'offer_amount': offerAmount,
        'request_token': requestToken,
        'request_amount': requestAmount,
        'allow_partial': allowPartial,
      },
      'nonce': _cachedAccount?.nonce ?? acc.nonce,
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
    final payload = <String, dynamic>{'order_id': orderId};
    if (fillAmount != null) payload['fill_amount'] = fillAmount;
    final tx = {
      'tx_id': generateTxId('TX_ORD_FULFILL_$orderId'),
      'sender': acc.accountId,
      'action': 'ORDER_FULFILL',
      'payload': payload,
      'nonce': _cachedAccount?.nonce ?? acc.nonce,
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
    final tx = {
      'tx_id': generateTxId('TX_ORD_CANCEL_$orderId'),
      'sender': acc.accountId,
      'action': 'ORDER_CANCEL',
      'payload': {'order_id': orderId},
      'nonce': _cachedAccount?.nonce ?? acc.nonce,
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
    final acc = _cachedAccount;
    final token = _authToken;
    if (acc != null && token != null) {
      await _api.ping(acc.accountId, token);
    }
  }

  Future<void> logout({bool clearSaved = false}) async {
    _cachedAccount = null;
    _authToken = null;
    _privkey = null;
    if (clearSaved) {
      await clearSavedCredentials();
    }
  }

  String? _extractToken(ApiResult<dynamic> r) {
    return null;
  }
}
