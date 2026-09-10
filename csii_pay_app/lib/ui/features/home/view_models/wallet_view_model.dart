import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:csii_pay_app/data/repositories/wallet_repository.dart';
import 'package:csii_pay_app/data/services/node_api_service.dart';
import 'package:csii_pay_app/data/services/marketplace_service.dart';
import 'package:csii_pay_app/domain/models/user_profile.dart';
import 'package:csii_pay_app/domain/models/transaction_item.dart';

enum AppState { connecting, authRequired, pinRequired, authenticated }

class QuickSwapPreview {
  final double payAmount;
  final double receivedAmount;
  final double averageRate;
  final double bestRate;
  final double totalAvailableLiquidity;
  final int ordersCount;
  final bool hasSufficientLiquidity;

  const QuickSwapPreview({
    required this.payAmount,
    required this.receivedAmount,
    required this.averageRate,
    required this.bestRate,
    required this.totalAvailableLiquidity,
    required this.ordersCount,
    required this.hasSufficientLiquidity,
  });
}

class WalletViewModel extends ChangeNotifier {
  final WalletRepository _repo;
  Timer? _refreshTimer;
  Timer? _pingTimer;

  AppState _appState = AppState.connecting;
  bool _isLoading = false;
  String? _error;
  NodeStatus? _nodeStatus;
  List<Order> _orders = [];
  List<Block> _recentBlocks = [];
  List<Block> _allBlocks = [];
  List<TransactionItem> _transactions = [];
  bool _isLoadingTransactions = false;

  WalletViewModel(this._repo);

  AppState get appState => _appState;
  bool get isLoading => _isLoading;
  String? get error => _error;
  NodeStatus? get nodeStatus => _nodeStatus;
  AccountInfo? get account => _repo.cachedAccount;
  UserProfile? get currentProfile => _repo.currentProfile;
  String? get currentAccountId => _repo.cachedAccount?.accountId;
  List<Order> get orders => _orders;
  List<Order> get openOrders => _orders.where((o) => o.status == 'OPEN').toList();
  List<Block> get recentBlocks => _recentBlocks;
  List<Block> get allBlocks => _allBlocks;
  List<TransactionItem> get transactions => _transactions;
  bool get isLoadingTransactions => _isLoadingTransactions;
  String get nodeUrl => _repo.nodeUrl;
  MarketplaceService get marketplaceService => _repo.marketplaceService;
  List<Map<String, dynamic>> _myGroups = [];
  List<Map<String, dynamic>> get myGroups => _myGroups;

  // Convenience aliases
  String? get accountId => _repo.cachedAccount?.accountId;
  double get cspBalance => _repo.cachedAccount?.balances.csp ?? 0.0;
  double get bdpBalance => _repo.cachedAccount?.balances.bdp ?? 0.0;
  double get frozenBdp => _repo.cachedAccount?.frozenBalances.bdp ?? 0.0;
  double get frozenCsp => _repo.cachedAccount?.frozenBalances.csp ?? 0.0;
  bool get isVerified => _repo.cachedAccount?.isVerified ?? false;
  String get verificationStatus =>
      _repo.cachedAccount?.verificationStatus ?? (_repo.cachedAccount?.isVerified == true ? 'VERIFIED' : 'PENDING');
  NodeApiService get api => _repo.api;

  Future<void> loadMyGroups() async {
    final acc = currentAccountId;
    if (acc == null) return;
    final r = await api.getMyGroups(acc);
    if (r.success && r.data != null) {
      _myGroups = List<Map<String, dynamic>>.from(r.data!);
      notifyListeners();
    }
  }

  Future<String?> getNickname(String username) => _repo.getNickname(username);
  Future<UserProfile?> getUserProfile(String username) => _repo.getUserProfile(username);
  Future<ApiResult<AccountInfo>> inspectAccount(String accountId) =>
      _repo.getAccountDetails(accountId);

  Future<void> setNodeUrl(String url) async {
    await _repo.setNodeUrl(url);
  }

  void clearError() {
    _error = null;
    notifyListeners();
  }

  Future<bool> hasAppPin() => WalletRepository.hasAppPin();

  Future<void> setAppPin(String pin) async {
    await WalletRepository.setAppPin(pin);
    notifyListeners();
  }

  Future<void> removeAppPin() async {
    await WalletRepository.removeAppPin();
    notifyListeners();
  }

  Future<bool> unlockWithPin(String pin) async {
    final saved = await WalletRepository.getAppPin();
    if (saved == pin.trim()) {
      _appState = AppState.authenticated;
      _startTimers();
      await _loadAll();
      notifyListeners();
      return true;
    }
    return false;
  }

  Future<void> init() async {
    _setLoading(true);
    _error = null;

    // 1. Attempt connection to primary/saved node URL
    var r = await _repo.checkNode();
    if (!r.success) {
      // 2. Automatic fallback to Cloudflare Gateway if off-campus/mobile
      final gatewayUrl = await _repo.fetchRemoteGatewayUrl();
      if (gatewayUrl != null && gatewayUrl.isNotEmpty && gatewayUrl != _repo.nodeUrl) {
        await _repo.setNodeUrl(gatewayUrl);
        r = await _repo.checkNode();
      }
    }

    if (r.success) {
      _nodeStatus = r.data;

      // 3. Check for saved credentials for seamless auto-login
      final hasCreds = await WalletRepository.hasSavedCredentials();
      if (hasCreds) {
        final savedAcc = await WalletRepository.getSavedAccountId();
        final savedPwd = await WalletRepository.getSavedPassword();
        if (savedAcc != null && savedPwd != null) {
          final loginRes = await _repo.login(savedAcc, savedPwd);
          if (loginRes.success) {
            final pinConfigured = await WalletRepository.hasAppPin();
            if (pinConfigured) {
              _appState = AppState.pinRequired;
            } else {
              _appState = AppState.authenticated;
              _startTimers();
              await _loadAll();
            }
            _setLoading(false);
            return;
          }
        }
      }

      _appState = AppState.authRequired;
    } else {
      _error = 'Cannot connect to node: ${r.error}';
      _appState = AppState.connecting;
    }
    _setLoading(false);
  }

  Future<bool> connectToCloudGateway() async {
    _setLoading(true);
    _error = null;
    final gatewayUrl = await _repo.fetchRemoteGatewayUrl();
    if (gatewayUrl == null || gatewayUrl.isEmpty) {
      _error = 'No active Cloudflare Gateway found in cloud configuration.';
      _setLoading(false);
      notifyListeners();
      return false;
    }
    await setNodeUrl(gatewayUrl);
    final r = await _repo.checkNode();
    if (r.success) {
      _nodeStatus = r.data;
      _appState = AppState.authRequired;
      _setLoading(false);
      return true;
    } else {
      _error = 'Cloudflare Gateway unreachable: ${r.error}';
      _setLoading(false);
      notifyListeners();
      return false;
    }
  }

  Future<bool> login(String accountId, String password) async {
    _setLoading(true);
    _error = null;
    final r = await _repo.login(accountId, password);
    if (r.success) {
      _appState = AppState.authenticated;
      _startTimers();
      await _loadAll();
    } else {
      _error = r.error ?? 'Login failed';
    }
    _setLoading(false);
    return r.success;
  }

  Future<bool> register(String accountId, String password) async {
    _setLoading(true);
    _error = null;
    final r = await _repo.register(accountId, password);
    if (r.success) {
      _appState = AppState.authenticated;
      _startTimers();
      await _loadAll();
    } else {
      _error = r.error ?? 'Registration failed';
    }
    _setLoading(false);
    return r.success;
  }

  Future<bool> registerWithProfile({
    required String studentId,
    required String fullName,
    required String nickname,
    required String username,
    required String password,
  }) async {
    _setLoading(true);
    _error = null;
    final r = await _repo.registerWithProfile(
      studentId: studentId,
      fullName: fullName,
      nickname: nickname,
      username: username,
      password: password,
    );
    if (r.success) {
      _appState = AppState.authenticated;
      _startTimers();
      await _loadAll();
    } else {
      _error = r.error ?? 'Registration failed';
    }
    _setLoading(false);
    return r.success;
  }

  Future<void> refresh() async {
    await _loadAll();
  }

  Future<void> _loadAll() async {
    // Quick essentials load first
    await Future.wait([
      _refreshAccount(),
      _refreshOrders(),
      _refreshNodeStatus(),
      _refreshBlocks(),
    ]);
    // Dynamically load transactions in background so it doesn't block initial load
    unawaited(refreshTransactions(silent: true));
  }

  Future<void> _refreshAccount() async {
    await _repo.refreshAccount();
    await loadMyGroups();
    notifyListeners();
  }

  Future<void> _refreshOrders() async {
    final r = await _repo.getOrders();
    if (r.success) {
      _orders = r.data!;
      notifyListeners();
    }
  }

  Future<void> refreshOrdersSilently() async {
    final r = await _repo.getOrders();
    if (r.success) {
      _orders = r.data!;
      notifyListeners();
    }
  }

  Future<void> refreshTransactions({bool silent = false}) async {
    if (!silent) {
      _isLoadingTransactions = true;
      notifyListeners();
    }
    try {
      final r = await _repo.getTransactionHistory(limit: 30, offset: 0);
      if (r.success && r.data != null) {
        _transactions = r.data!;
      }
    } catch (e) {
      debugPrint('[WalletViewModel] refreshTransactions error: $e');
    } finally {
      _isLoadingTransactions = false;
      notifyListeners();
    }
  }

  Future<void> _refreshNodeStatus() async {
    final r = await _repo.getStatus();
    if (r.success) {
      _nodeStatus = r.data;
      notifyListeners();
    }
  }

  Future<void> _refreshBlocks() async {
    final r = await _repo.getChain();
    if (r.success) {
      final chain = r.data!;
      _allBlocks = chain.reversed.toList();
      _recentBlocks = _allBlocks.take(10).toList();
      notifyListeners();
    }
  }

  Future<String?> transfer({
    required String recipient,
    required String token,
    required double amount,
    String? fromTeam,
  }) async {
    _setLoading(true);
    _error = null;
    if (fromTeam != null) {
      final r = await api.transferFromTeam(
        accountId: currentAccountId!,
        groupName: fromTeam,
        recipient: recipient,
        amount: amount,
      );
      _setLoading(false);
      if (r.success) {
        await _refreshAccount();
        return null;
      }
      _error = r.error ?? 'Team transfer failed';
      notifyListeners();
      return _error;
    } else {
      final r = await _repo.transfer(recipient: recipient, token: token, amount: amount);
      _setLoading(false);
      if (r.success) {
        await _refreshAccount();
        return null; // success
      }
      _error = r.error ?? 'Transfer failed';
      notifyListeners();
      return _error;
    }
  }

  Future<String?> createOrder({
    required String offerToken,
    required double offerAmount,
    required String requestToken,
    required double requestAmount,
    required bool allowPartial,
  }) async {
    _setLoading(true);
    final r = await _repo.createOrder(
      offerToken: offerToken,
      offerAmount: offerAmount,
      requestToken: requestToken,
      requestAmount: requestAmount,
      allowPartial: allowPartial,
    );
    _setLoading(false);
    if (r.success) {
      await _refreshOrders();
      return null;
    }
    return r.error ?? 'Order creation failed';
  }

  Future<String?> fulfillOrder(String orderId, {double? fillAmount}) async {
    _setLoading(true);
    final r = await _repo.fulfillOrder(orderId, fillAmount: fillAmount);
    _setLoading(false);
    if (r.success) {
      await _refreshOrders();
      await _refreshAccount();
      return null;
    }
    return r.error ?? 'Failed to fulfill order';
  }

  Future<String?> cancelOrder(String orderId) async {
    _setLoading(true);
    final r = await _repo.cancelOrder(orderId);
    _setLoading(false);
    if (r.success) {
      await _refreshOrders();
      await _refreshAccount();
      return null;
    }
    return r.error ?? 'Failed to cancel order';
  }

  /// Calculates depth, liquidity, and estimated payout for a quick swap
  QuickSwapPreview previewQuickSwap({
    required String buyToken,
    required double payAmount,
  }) {
    final payToken = buyToken == 'BDP' ? 'CSP' : 'BDP';
    final matching = openOrders.where((o) =>
        o.offerToken == buyToken &&
        o.requestToken == payToken &&
        o.maker != currentAccountId &&
        o.offerAmount > 0 &&
        o.requestAmount > 0).toList();

    double totalLiquidity = 0.0;
    for (final o in matching) {
      totalLiquidity += o.offerAmount;
    }

    if (matching.isEmpty) {
      return QuickSwapPreview(
        payAmount: payAmount,
        receivedAmount: 0.0,
        averageRate: 0.0,
        bestRate: 0.0,
        totalAvailableLiquidity: 0.0,
        ordersCount: 0,
        hasSufficientLiquidity: false,
      );
    }

    // Sort by best price ascending (payToken cost per 1 buyToken)
    matching.sort((a, b) {
      final rateA = a.requestAmount / a.offerAmount;
      final rateB = b.requestAmount / b.offerAmount;
      return rateA.compareTo(rateB);
    });

    final bestRate = matching.first.requestAmount / matching.first.offerAmount;

    if (payAmount <= 0) {
      return QuickSwapPreview(
        payAmount: 0.0,
        receivedAmount: 0.0,
        averageRate: bestRate,
        bestRate: bestRate,
        totalAvailableLiquidity: totalLiquidity,
        ordersCount: matching.length,
        hasSufficientLiquidity: true,
      );
    }

    double remainingPay = payAmount;
    double totalReceived = 0.0;
    int ordersUsed = 0;

    for (final order in matching) {
      if (remainingPay <= 0.000001) break;
      final orderCost = order.requestAmount;
      final unitRate = orderCost / order.offerAmount;

      if (remainingPay >= orderCost) {
        totalReceived += order.offerAmount;
        remainingPay -= orderCost;
        ordersUsed++;
      } else {
        if (order.allowPartial) {
          final partialBuy = remainingPay / unitRate;
          totalReceived += partialBuy;
          remainingPay = 0;
          ordersUsed++;
        }
      }
    }

    final double effectivePaid = payAmount - remainingPay;
    final double avgRate = totalReceived > 0 ? effectivePaid / totalReceived : bestRate;
    final bool hasSufficient = remainingPay <= 0.0001 && totalReceived > 0;

    return QuickSwapPreview(
      payAmount: payAmount,
      receivedAmount: totalReceived,
      averageRate: avgRate,
      bestRate: bestRate,
      totalAvailableLiquidity: totalLiquidity,
      ordersCount: ordersUsed,
      hasSufficientLiquidity: hasSufficient,
    );
  }

  /// Automatically distributes purchase across matching orders based on orderbook depth
  Future<String?> quickSwapBuy({
    required String buyToken,
    required double payAmount,
  }) async {
    if (payAmount <= 0) return 'Please enter a valid amount';
    final payToken = buyToken == 'BDP' ? 'CSP' : 'BDP';

    final matching = openOrders.where((o) =>
        o.offerToken == buyToken &&
        o.requestToken == payToken &&
        o.maker != currentAccountId &&
        o.offerAmount > 0 &&
        o.requestAmount > 0).toList();

    if (matching.isEmpty) {
      return 'No active sell orders found for $buyToken';
    }

    // Sort ascending by unit price (payToken / buyToken)
    matching.sort((a, b) {
      final rateA = a.requestAmount / a.offerAmount;
      final rateB = b.requestAmount / b.offerAmount;
      return rateA.compareTo(rateB);
    });

    double remainingPay = payAmount;
    final fills = <Map<String, dynamic>>[];

    for (final order in matching) {
      if (remainingPay <= 0.000001) break;
      final orderCost = order.requestAmount;
      final unitRate = orderCost / order.offerAmount;

      if (remainingPay >= orderCost) {
        fills.add({
          'orderId': order.id,
          'fillAmount': null, // full fill
          'cost': orderCost,
        });
        remainingPay -= orderCost;
      } else {
        if (order.allowPartial) {
          final partialBuy = remainingPay / unitRate;
          fills.add({
            'orderId': order.id,
            'fillAmount': partialBuy,
            'cost': remainingPay,
          });
          remainingPay = 0;
        }
      }
    }

    if (fills.isEmpty) {
      return 'Insufficient market liquidity to execute order';
    }

    _setLoading(true);
    try {
      for (final fill in fills) {
        final orderId = fill['orderId'] as String;
        final fillAmt = fill['fillAmount'] as double?;
        final r = await _repo.fulfillOrder(orderId, fillAmount: fillAmt);
        if (!r.success) {
          _setLoading(false);
          await _refreshOrders();
          await _refreshAccount();
          return r.error ?? 'Swap partially failed';
        }
      }
      _setLoading(false);
      await _refreshOrders();
      await _refreshAccount();
      return null;
    } catch (e) {
      _setLoading(false);
      await _refreshOrders();
      await _refreshAccount();
      return e.toString();
    }
  }

  Future<void> logout({bool clearSaved = true}) async {
    await _repo.logout(clearSaved: clearSaved);
    _appState = AppState.authRequired;
    _stopTimers();
    _orders = [];
    _recentBlocks = [];
    _allBlocks = [];
    _transactions = [];
    _myGroups = [];
    notifyListeners();
  }

  void _startTimers() {
    _refreshTimer?.cancel();
    _pingTimer?.cancel();
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) => _loadAll());
    _pingTimer = Timer.periodic(const Duration(seconds: 5), (_) => _repo.ping());
  }

  void _stopTimers() {
    _refreshTimer?.cancel();
    _pingTimer?.cancel();
  }

  void _setLoading(bool v) {
    _isLoading = v;
    notifyListeners();
  }

  @override
  void dispose() {
    _stopTimers();
    super.dispose();
  }
}
