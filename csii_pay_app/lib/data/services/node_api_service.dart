import 'dart:convert';
import 'package:http/http.dart' as http;

class NodeStatus {
  final String nodeId;
  final String operatorAccount;
  final String host;
  final int port;
  final int blockHeight;
  final String latestBlockHash;
  final int peersCount;
  final int mempoolSize;
  final int activeUsersCount;
  final String consensus;

  const NodeStatus({
    required this.nodeId,
    required this.operatorAccount,
    required this.host,
    required this.port,
    required this.blockHeight,
    required this.latestBlockHash,
    required this.peersCount,
    required this.mempoolSize,
    required this.activeUsersCount,
    required this.consensus,
  });

  factory NodeStatus.fromJson(Map<String, dynamic> j) => NodeStatus(
        nodeId: j['node_id'] ?? '',
        operatorAccount: j['operator_account'] ?? '',
        host: j['host'] ?? '',
        port: j['port'] ?? 8000,
        blockHeight: j['block_height'] ?? 0,
        latestBlockHash: j['latest_block_hash'] ?? '',
        peersCount: j['peers_count'] ?? 0,
        mempoolSize: j['mempool_size'] ?? 0,
        activeUsersCount: j['active_users_count'] ?? 0,
        consensus: j['consensus'] ?? '',
      );
}

class WalletBalance {
  final double csp;
  final double bdp;
  const WalletBalance({required this.csp, required this.bdp});

  factory WalletBalance.fromJson(Map<String, dynamic> j) => WalletBalance(
        csp: (j['CSP'] as num? ?? 0).toDouble(),
        bdp: (j['BDP'] as num? ?? 0).toDouble(),
      );
}

class AccountInfo {
  final String accountId;
  final WalletBalance balances;
  final WalletBalance frozenBalances;
  final bool isVerified;
  final String verificationStatus;
  final int nonce;
  final String? salt;
  final String? publicKey;
  final String? privateKey;

  const AccountInfo({
    required this.accountId,
    required this.balances,
    this.frozenBalances = const WalletBalance(csp: 0, bdp: 0),
    this.isVerified = false,
    this.verificationStatus = 'PENDING',
    required this.nonce,
    this.salt,
    this.publicKey,
    this.privateKey,
  });

  factory AccountInfo.fromJson(Map<String, dynamic> j) => AccountInfo(
        accountId: j['account_id'] ?? '',
        balances: WalletBalance.fromJson(j['balances'] ?? {}),
        frozenBalances: WalletBalance.fromJson(j['frozen_balances'] ?? {}),
        isVerified: j['is_verified'] ?? false,
        verificationStatus: j['verification_status'] ?? (j['is_verified'] == true ? 'VERIFIED' : 'PENDING'),
        nonce: j['nonce'] ?? 0,
        salt: j['salt'] as String?,
        publicKey: j['public_key'] as String?,
        privateKey: j['private_key'] as String?,
      );
}

class Order {
  final String id;
  final String maker;
  final String offerToken;
  final double offerAmount;
  final String requestToken;
  final double requestAmount;
  final String status;
  final bool allowPartial;
  final double createdAt;

  const Order({
    required this.id,
    required this.maker,
    required this.offerToken,
    required this.offerAmount,
    required this.requestToken,
    required this.requestAmount,
    required this.status,
    required this.allowPartial,
    required this.createdAt,
  });

  factory Order.fromJson(Map<String, dynamic> j) => Order(
        id: j['id'] ?? '',
        maker: j['maker'] ?? '',
        offerToken: j['offer_token'] ?? '',
        offerAmount: (j['offer_amount'] as num? ?? 0).toDouble(),
        requestToken: j['request_token'] ?? '',
        requestAmount: (j['request_amount'] as num? ?? 0).toDouble(),
        status: j['status'] ?? '',
        allowPartial: j['allow_partial'] ?? true,
        createdAt: (j['created_at'] as num? ?? 0).toDouble(),
      );

  double get rate => requestAmount > 0 ? offerAmount / requestAmount : 0;
}

class Block {
  final int index;
  final String hash;
  final String prevHash;
  final double timestamp;
  final String validator;
  final String stateHash;
  final List<Map<String, dynamic>> transactions;

  const Block({
    required this.index,
    required this.hash,
    required this.prevHash,
    required this.timestamp,
    required this.validator,
    required this.stateHash,
    required this.transactions,
  });

  factory Block.fromJson(Map<String, dynamic> j) => Block(
        index: j['index'] ?? 0,
        hash: j['hash'] ?? '',
        prevHash: j['prev_hash'] ?? '',
        timestamp: (j['timestamp'] as num? ?? 0).toDouble(),
        validator: j['validator'] ?? '',
        stateHash: j['state_hash'] ?? '',
        transactions: List<Map<String, dynamic>>.from(j['transactions'] ?? []),
      );
}

/// Result wrapper
class ApiResult<T> {
  final bool success;
  final T? data;
  final String? error;

  const ApiResult.ok(this.data)
      : success = true,
        error = null;

  const ApiResult.err(this.error)
      : success = false,
        data = null;
}

class NodeApiService {
  String nodeUrl;
  static const _timeout = Duration(seconds: 8);

  NodeApiService(this.nodeUrl);

  Uri _uri(String path) => Uri.parse('$nodeUrl$path');

  Map<String, String> get _headers => {
        'Content-Type': 'application/json',
        'User-Agent': 'CSII-Pay-Flutter',
      };

  Future<ApiResult<Map<String, dynamic>>> _get(String path) async {
    try {
      final resp = await http.get(_uri(path), headers: _headers).timeout(_timeout);
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        return ApiResult.ok(body);
      }
      return ApiResult.err(body['error']?.toString() ?? 'HTTP ${resp.statusCode}');
    } catch (e) {
      return ApiResult.err(e.toString());
    }
  }

  Future<ApiResult<Map<String, dynamic>>> _post(
      String path, Map<String, dynamic> body) async {
    try {
      final resp = await http
          .post(_uri(path), headers: _headers, body: jsonEncode(body))
          .timeout(_timeout);
      final respBody = jsonDecode(resp.body) as Map<String, dynamic>;
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        return ApiResult.ok(respBody);
      }
      return ApiResult.err(respBody['error']?.toString() ?? 'HTTP ${resp.statusCode}');
    } catch (e) {
      return ApiResult.err(e.toString());
    }
  }

  Future<ApiResult<NodeStatus>> getStatus() async {
    final r = await _get('/status');
    if (r.success) return ApiResult.ok(NodeStatus.fromJson(r.data!));
    return ApiResult.err(r.error);
  }

  Future<ApiResult<AccountInfo>> login(String accountId, String password) async {
    final r = await _post('/login', {'account_id': accountId, 'password': password});
    if (r.success && r.data!['success'] == true) {
      final acc = AccountInfo(
        accountId: accountId,
        balances: WalletBalance.fromJson(r.data!['balances'] ?? {}),
        frozenBalances: WalletBalance.fromJson(r.data!['frozen_balances'] ?? {}),
        isVerified: r.data!['is_verified'] ?? false,
        verificationStatus: r.data!['verification_status'] ?? (r.data!['is_verified'] == true ? 'VERIFIED' : 'PENDING'),
        nonce: r.data!['nonce'] ?? 0,
        salt: r.data!['salt'] as String?,
        publicKey: r.data!['public_key'] as String?,
      );
      return ApiResult.ok(acc);
    }
    return ApiResult.err(r.data?['error']?.toString() ?? r.error ?? 'Login failed');
  }

  Future<ApiResult<AccountInfo>> register(String accountId, String password) async {
    final r = await _post('/register', {'account_id': accountId, 'password': password});
    if (r.success && r.data!['success'] == true) {
      final acc = AccountInfo(
        accountId: accountId,
        balances: WalletBalance.fromJson(r.data!['balances'] ?? {}),
        frozenBalances: WalletBalance.fromJson(r.data!['frozen_balances'] ?? {}),
        isVerified: r.data!['is_verified'] ?? false,
        verificationStatus: r.data!['verification_status'] ?? (r.data!['is_verified'] == true ? 'VERIFIED' : 'PENDING'),
        nonce: r.data!['nonce'] ?? 0,
        salt: r.data!['salt'] as String?,
        publicKey: r.data!['public_key'] as String?,
      );
      return ApiResult.ok(acc);
    }
    return ApiResult.err(r.data?['error']?.toString() ?? r.error ?? 'Registration failed');
  }

  Future<ApiResult<AccountInfo>> getAccount(String accountId) async {
    final r = await _get('/account/$accountId');
    if (r.success) return ApiResult.ok(AccountInfo.fromJson(r.data!));
    return ApiResult.err(r.error);
  }

  Future<ApiResult<bool>> submitTx(Map<String, dynamic> tx) async {
    final r = await _post('/tx/submit', tx);
    if (r.success && r.data!['success'] == true) return const ApiResult.ok(true);
    return ApiResult.err(r.data?['error']?.toString() ?? r.error ?? 'Transaction failed');
  }

  Future<ApiResult<List<Order>>> getOrders() async {
    final r = await _get('/orders');
    if (r.success) {
      final list = (r.data!['orders'] as List? ?? [])
          .map((e) => Order.fromJson(e as Map<String, dynamic>))
          .toList();
      return ApiResult.ok(list);
    }
    return ApiResult.err(r.error);
  }

  Future<ApiResult<List<Block>>> getChain() async {
    final r = await _get('/chain');
    if (r.success) {
      final list = (r.data!['chain'] as List? ?? [])
          .map((e) => Block.fromJson(e as Map<String, dynamic>))
          .toList();
      return ApiResult.ok(list);
    }
    return ApiResult.err(r.error);
  }

  Future<ApiResult<bool>> ping(String accountId, String token) async {
    final r = await _post('/activity/ping', {'account_id': accountId, 'token': token});
    if (r.success) return const ApiResult.ok(true);
    return ApiResult.err(r.error);
  }

  Future<ApiResult<List<Map<String, dynamic>>>> getTransactions(
    String accountId, {
    int limit = 20,
    int offset = 0,
  }) async {
    final query = 'account=${Uri.encodeComponent(accountId)}&limit=$limit&offset=$offset';
    final r = await _get('/transactions?$query');
    if (r.success) {
      final list = (r.data!['transactions'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      return ApiResult.ok(list);
    }
    return ApiResult.err(r.error);
  }

  Future<ApiResult<List<Map<String, dynamic>>>> getMarketplaceJobs({
    String? category,
    String? type,
    int? difficulty,
    String? creator,
  }) async {
    final params = <String>[];
    if (category != null && category.isNotEmpty) {
      params.add('category=${Uri.encodeComponent(category)}');
    }
    if (type != null && type.isNotEmpty) {
      params.add('type=${Uri.encodeComponent(type)}');
    }
    if (difficulty != null) {
      params.add('difficulty=$difficulty');
    }
    if (creator != null && creator.isNotEmpty) {
      params.add('creator=${Uri.encodeComponent(creator)}');
    }
    final qs = params.isEmpty ? '' : '?${params.join('&')}';
    final r = await _get('/marketplace/jobs$qs');
    if (r.success) {
      final list = (r.data!['jobs'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      return ApiResult.ok(list);
    }
    return ApiResult.err(r.error);
  }

  Future<ApiResult<Map<String, dynamic>>> createMarketplaceJob(
      Map<String, dynamic> body) async {
    final r = await _post('/marketplace/create', body);
    if (r.success && r.data!['success'] == true) {
      return ApiResult.ok(r.data!);
    }
    return ApiResult.err(r.data?['error']?.toString() ?? r.error ?? 'Failed to create job');
  }

  Future<ApiResult<Map<String, dynamic>>> claimMarketplaceJob({
    required String accountId,
    required String jobId,
    required String secretCode,
  }) async {
    final r = await _post('/marketplace/claim', {
      'account_id': accountId,
      'job_id': jobId,
      'secret_code': secretCode,
    });
    if (r.success && r.data!['success'] == true) {
      return ApiResult.ok(r.data!);
    }
    return ApiResult.err(r.data?['error']?.toString() ?? r.error ?? 'Claim failed');
  }

  // ─────────────────────────── GROUPS ───────────────────────────

  Future<ApiResult<Map<String, dynamic>>> getMyGroupsData(String accountId) async {
    final r = await _get('/groups/member?account=${Uri.encodeComponent(accountId)}');
    if (r.success) return ApiResult.ok(r.data!);
    return ApiResult.err(r.error);
  }

  Future<ApiResult<Map<String, dynamic>>> getGroupInfo(String groupName) async {
    final r = await _get('/groups/info?name=${Uri.encodeComponent(groupName)}');
    if (r.success) return ApiResult.ok(r.data!['group'] as Map<String, dynamic>);
    return ApiResult.err(r.error);
  }

  Future<ApiResult<bool>> createGroup({
    required String accountId,
    required String groupName,
    required String description,
    double initialDeposit = 0.0,
    double? entranceFee,
  }) async {
    final r = await _post('/groups/create', {
      'account_id': accountId,
      'group_name': groupName,
      'description': description,
      'initial_deposit': initialDeposit,
      'entrance_fee': entranceFee ?? initialDeposit,
    });
    if (r.success && r.data!['success'] == true) return const ApiResult.ok(true);
    return ApiResult.err(r.data?['error']?.toString() ?? r.error ?? 'Failed to create team');
  }

  Future<ApiResult<bool>> leaveGroup({
    required String accountId,
    required String groupName,
  }) async {
    final r = await _post('/groups/leave', {
      'account_id': accountId,
      'group_name': groupName,
    });
    if (r.success && r.data!['success'] == true) return const ApiResult.ok(true);
    return ApiResult.err(r.data?['error']?.toString() ?? r.error ?? 'Failed to leave team');
  }

  Future<ApiResult<bool>> transferFromTeam({
    required String accountId,
    required String groupName,
    required String recipient,
    required double amount,
  }) async {
    final r = await _post('/groups/transfer', {
      'account_id': accountId,
      'group_name': groupName,
      'recipient': recipient,
      'amount': amount,
    });
    if (r.success && r.data!['success'] == true) return const ApiResult.ok(true);
    return ApiResult.err(r.data?['error']?.toString() ?? r.error ?? 'Team transfer failed');
  }

  Future<ApiResult<List<dynamic>>> getMyGroups(String accountId) async {
    final r = await _get('/groups/member?account=${Uri.encodeComponent(accountId)}');
    if (r.success && r.data != null) {
      final list = r.data!['my_groups'] as List<dynamic>? ?? [];
      return ApiResult.ok(list);
    }
    return ApiResult.err(r.error ?? 'Failed to load teams');
  }

  Future<ApiResult<bool>> inviteMember({
    required String accountId,
    required String groupName,
    required String invitee,
  }) async {
    final r = await _post('/groups/invite', {
      'account_id': accountId,
      'group_name': groupName,
      'invitee': invitee,
    });
    if (r.success && r.data!['success'] == true) return const ApiResult.ok(true);
    return ApiResult.err(r.data?['error']?.toString() ?? r.error ?? 'Failed to add member');
  }

  Future<ApiResult<bool>> joinGroup({
    required String accountId,
    required String groupName,
  }) async {
    final r = await _post('/groups/join', {
      'account_id': accountId,
      'group_name': groupName,
    });
    if (r.success && r.data!['success'] == true) return const ApiResult.ok(true);
    return ApiResult.err(r.data?['error']?.toString() ?? r.error ?? 'Failed to join group');
  }

  Future<ApiResult<bool>> createGroupPoll({
    required String accountId,
    required String groupName,
    required String pollType,
    required String title,
    required Map<String, dynamic> pollPayload,
  }) async {
    final r = await _post('/groups/poll/create', {
      'account_id': accountId,
      'group_name': groupName,
      'poll_type': pollType,
      'title': title,
      'poll_payload': pollPayload,
    });
    if (r.success && r.data!['success'] == true) return const ApiResult.ok(true);
    return ApiResult.err(r.data?['error']?.toString() ?? r.error ?? 'Failed to create poll');
  }

  Future<ApiResult<String>> voteGroupPoll({
    required String accountId,
    required String groupName,
    required String pollId,
    required bool vote,
  }) async {
    final r = await _post('/groups/poll/vote', {
      'account_id': accountId,
      'group_name': groupName,
      'poll_id': pollId,
      'vote': vote,
    });
    if (r.success && r.data!['success'] == true) {
      return ApiResult.ok(r.data!['poll_status']?.toString() ?? 'OPEN');
    }
    return ApiResult.err(r.data?['error']?.toString() ?? r.error ?? 'Failed to vote');
  }

  Future<ApiResult<bool>> executeGroupPoll({
    required String accountId,
    required String groupName,
    required String pollId,
  }) async {
    final r = await _post('/groups/poll/execute', {
      'account_id': accountId,
      'group_name': groupName,
      'poll_id': pollId,
    });
    if (r.success && r.data!['success'] == true) return const ApiResult.ok(true);
    return ApiResult.err(r.data?['error']?.toString() ?? r.error ?? 'Failed to execute poll');
  }

  Future<ApiResult<Map<String, dynamic>>> checkGroupAccount(String accountId) async {
    final r = await _get('/groups/info?name=${Uri.encodeComponent(accountId)}');
    if (r.success) return ApiResult.ok(r.data!['group'] as Map<String, dynamic>);
    return ApiResult.err(r.error);
  }
}

