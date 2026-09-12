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
  final int nextLotteryBlock;
  final int blocksUntilLottery;

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
    this.nextLotteryBlock = 10,
    this.blocksUntilLottery = 10,
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
        nextLotteryBlock: j['next_lottery_block'] ?? 10,
        blocksUntilLottery: j['blocks_until_lottery'] ?? 10,
      );
}

class ActivityBreakdownItem {
  final double val;
  final double pts;
  final double weightPct;
  final int jobsCount;

  const ActivityBreakdownItem({
    required this.val,
    required this.pts,
    required this.weightPct,
    this.jobsCount = 0,
  });

  factory ActivityBreakdownItem.fromJson(Map<String, dynamic> j) =>
      ActivityBreakdownItem(
        val: (j['val'] as num? ?? 0).toDouble(),
        pts: (j['pts'] as num? ?? 0).toDouble(),
        weightPct: (j['weight_pct'] as num? ?? 0).toDouble(),
        jobsCount: (j['jobs_count'] as num? ?? 0).toInt(),
      );
}

class ActivityBreakdown {
  final ActivityBreakdownItem monthlyActivity;
  final ActivityBreakdownItem monthlyCommissions;
  final ActivityBreakdownItem allTimeActivity;
  final ActivityBreakdownItem allTimeCommissions;
  final ActivityBreakdownItem jobsComplexity;

  const ActivityBreakdown({
    required this.monthlyActivity,
    required this.monthlyCommissions,
    required this.allTimeActivity,
    required this.allTimeCommissions,
    required this.jobsComplexity,
  });

  factory ActivityBreakdown.fromJson(Map<String, dynamic> j) =>
      ActivityBreakdown(
        monthlyActivity:
            ActivityBreakdownItem.fromJson(j['monthly_activity'] ?? {}),
        monthlyCommissions:
            ActivityBreakdownItem.fromJson(j['monthly_commissions'] ?? {}),
        allTimeActivity:
            ActivityBreakdownItem.fromJson(j['all_time_activity'] ?? {}),
        allTimeCommissions:
            ActivityBreakdownItem.fromJson(j['all_time_commissions'] ?? {}),
        jobsComplexity:
            ActivityBreakdownItem.fromJson(j['jobs_complexity'] ?? {}),
      );
}

class StudentTier {
  final String name;
  final String badge;
  final String colorHex;
  final int rankLevel;
  final String? nextTier;
  final double nextThreshold;
  final double pointsToNext;
  final double progressPct;

  const StudentTier({
    required this.name,
    required this.badge,
    required this.colorHex,
    required this.rankLevel,
    this.nextTier,
    required this.nextThreshold,
    required this.pointsToNext,
    required this.progressPct,
  });

  factory StudentTier.fromJson(Map<String, dynamic> j) => StudentTier(
        name: j['name'] ?? 'Bronze Scholar',
        badge: j['badge'] ?? '🥉 Bronze Scholar',
        colorHex: j['color'] ?? '#CD7F32',
        rankLevel: (j['rank_level'] as num? ?? 1).toInt(),
        nextTier: j['next_tier'],
        nextThreshold: (j['next_threshold'] as num? ?? 100.0).toDouble(),
        pointsToNext: (j['points_to_next'] as num? ?? 0.0).toDouble(),
        progressPct: (j['progress_pct'] as num? ?? 0.0).toDouble(),
      );
}

class StudentDiversity {
  final double multiplier;
  final bool hasTransfers;
  final bool hasJobs;
  final bool hasExchange;
  final bool hasGroup;

  const StudentDiversity({
    required this.multiplier,
    required this.hasTransfers,
    required this.hasJobs,
    required this.hasExchange,
    required this.hasGroup,
  });

  factory StudentDiversity.fromJson(Map<String, dynamic> j) => StudentDiversity(
        multiplier: (j['multiplier'] as num? ?? 1.0).toDouble(),
        hasTransfers: j['has_transfers'] == true,
        hasJobs: j['has_jobs'] == true,
        hasExchange: j['has_exchange'] == true,
        hasGroup: j['has_group'] == true,
      );
}

class StudentLeaderboardEntry {
  final String accountId;
  final int rank;
  final double activityScore;
  final double tickets;
  final double winProbabilityPct;
  final int monthlyTxCount;
  final double monthlyFees;
  final int allTimeTxCount;
  final double allTimeFees;
  final int completedJobsCount;
  final int jobsScore;
  final ActivityBreakdown breakdown;
  final StudentTier? tier;
  final StudentDiversity? diversity;

  const StudentLeaderboardEntry({
    required this.accountId,
    required this.rank,
    required this.activityScore,
    required this.tickets,
    required this.winProbabilityPct,
    required this.monthlyTxCount,
    required this.monthlyFees,
    required this.allTimeTxCount,
    required this.allTimeFees,
    required this.completedJobsCount,
    required this.jobsScore,
    required this.breakdown,
    this.tier,
    this.diversity,
  });

  factory StudentLeaderboardEntry.fromJson(Map<String, dynamic> j) =>
      StudentLeaderboardEntry(
        accountId: j['account_id'] ?? '',
        rank: (j['rank'] as num? ?? 0).toInt(),
        activityScore: (j['activity_score'] as num? ?? 0).toDouble(),
        tickets: (j['tickets'] as num? ?? 1.0).toDouble(),
        winProbabilityPct: (j['win_probability_pct'] as num? ?? 0).toDouble(),
        monthlyTxCount: (j['monthly_tx_count'] as num? ?? 0).toInt(),
        monthlyFees: (j['monthly_fees'] as num? ?? 0).toDouble(),
        allTimeTxCount: (j['all_time_tx_count'] as num? ?? 0).toInt(),
        allTimeFees: (j['all_time_fees'] as num? ?? 0).toDouble(),
        completedJobsCount: (j['completed_jobs_count'] as num? ?? 0).toInt(),
        jobsScore: (j['jobs_score'] as num? ?? 0).toInt(),
        breakdown: ActivityBreakdown.fromJson(j['breakdown'] ?? {}),
        tier: j['tier'] != null ? StudentTier.fromJson(j['tier']) : null,
        diversity: j['diversity'] != null
            ? StudentDiversity.fromJson(j['diversity'])
            : null,
      );
}

class LotteryWinner {
  final int blockHeight;
  final String recipient;
  final double amount;
  final String token;
  final double timestamp;
  final double score;

  const LotteryWinner({
    required this.blockHeight,
    required this.recipient,
    required this.amount,
    required this.token,
    required this.timestamp,
    required this.score,
  });

  factory LotteryWinner.fromJson(Map<String, dynamic> j) => LotteryWinner(
        blockHeight: (j['block_height'] as num? ?? 0).toInt(),
        recipient: j['recipient'] ?? '',
        amount: (j['amount'] as num? ?? 0.1).toDouble(),
        token: j['token'] ?? 'BDP',
        timestamp: (j['timestamp'] as num? ?? 0).toDouble(),
        score: (j['score'] as num? ?? 0).toDouble(),
      );
}

class ActivityLeaderboardResponse {
  final List<StudentLeaderboardEntry> students;
  final double totalTickets;
  final List<LotteryWinner> recentLotteryWinners;
  final int nextLotteryBlock;
  final int blocksUntilLottery;
  final Map<String, dynamic> formulaWeights;

  const ActivityLeaderboardResponse({
    required this.students,
    required this.totalTickets,
    required this.recentLotteryWinners,
    required this.nextLotteryBlock,
    required this.blocksUntilLottery,
    required this.formulaWeights,
  });

  factory ActivityLeaderboardResponse.fromJson(Map<String, dynamic> j) =>
      ActivityLeaderboardResponse(
        students: (j['students'] as List? ?? [])
            .map((e) =>
                StudentLeaderboardEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
        totalTickets: (j['total_tickets'] as num? ?? 0).toDouble(),
        recentLotteryWinners: (j['recent_lottery_winners'] as List? ?? [])
            .map((e) => LotteryWinner.fromJson(e as Map<String, dynamic>))
            .toList(),
        nextLotteryBlock: (j['next_lottery_block'] as num? ?? 10).toInt(),
        blocksUntilLottery: (j['blocks_until_lottery'] as num? ?? 10).toInt(),
        formulaWeights: (j['formula_weights'] as Map<String, dynamic>?) ?? {},
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
  final double activityScore;
  final int activityRank;
  final double lotteryTickets;
  final double winProbabilityPct;
  final ActivityBreakdown? activityBreakdown;

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
    this.activityScore = 0.0,
    this.activityRank = 0,
    this.lotteryTickets = 1.0,
    this.winProbabilityPct = 0.0,
    this.activityBreakdown,
  });

  factory AccountInfo.fromJson(Map<String, dynamic> j) => AccountInfo(
        accountId: j['account_id'] ?? '',
        balances: WalletBalance.fromJson(j['balances'] ?? {}),
        frozenBalances: WalletBalance.fromJson(j['frozen_balances'] ?? {}),
        isVerified: j['is_verified'] ?? false,
        verificationStatus: j['verification_status'] ??
            (j['is_verified'] == true ? 'VERIFIED' : 'PENDING'),
        nonce: j['nonce'] ?? 0,
        salt: j['salt'] as String?,
        publicKey: j['public_key'] as String?,
        privateKey: j['private_key'] as String?,
        activityScore: (j['activity_score'] as num? ?? 0.0).toDouble(),
        activityRank: (j['activity_rank'] as num? ?? 0).toInt(),
        lotteryTickets: (j['lottery_tickets'] as num? ?? 1.0).toDouble(),
        winProbabilityPct: (j['win_probability_pct'] as num? ?? 0.0).toDouble(),
        activityBreakdown: j['activity_breakdown'] != null
            ? ActivityBreakdown.fromJson(j['activity_breakdown'])
            : null,
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

/// Session tokens issued by the node. The access token is short-lived and sent
/// as a bearer header; the refresh token rotates on every use.
class AuthTokens {
  final String accessToken;
  final String refreshToken;
  const AuthTokens(this.accessToken, this.refreshToken);

  static AuthTokens? fromJson(Map<String, dynamic> j) {
    final access = j['access_token'] as String?;
    final refresh = j['refresh_token'] as String?;
    if (access == null || access.isEmpty) return null;
    return AuthTokens(access, refresh ?? '');
  }
}

class NodeApiService {
  String nodeUrl;
  static const _timeout = Duration(seconds: 8);

  String? accessToken;
  String? refreshToken;

  /// Invoked whenever the session changes (issued, rotated or cleared) so the
  /// owner can persist the refresh token.
  void Function(AuthTokens? tokens)? onTokensChanged;

  NodeApiService(this.nodeUrl);

  bool get hasSession => accessToken != null && accessToken!.isNotEmpty;

  Uri _uri(String path) => Uri.parse('$nodeUrl$path');

  Map<String, String> get _headers {
    final h = <String, String>{
      'Content-Type': 'application/json',
      'User-Agent': 'CSII-Pay-Flutter',
    };
    if (accessToken != null && accessToken!.isNotEmpty) {
      h['Authorization'] = 'Bearer $accessToken';
    }
    return h;
  }

  static bool _isAuthRoute(String path) =>
      path == '/login' || path == '/register' || path.startsWith('/auth/');

  void _captureTokens(Map<String, dynamic> j) {
    final t = AuthTokens.fromJson(j);
    if (t == null) return;
    accessToken = t.accessToken;
    if (t.refreshToken.isNotEmpty) refreshToken = t.refreshToken;
    onTokensChanged?.call(AuthTokens(accessToken!, refreshToken ?? ''));
  }

  void clearSession() {
    accessToken = null;
    refreshToken = null;
    onTokensChanged?.call(null);
  }

  /// Exchanges the refresh token for a new access/refresh pair.
  Future<bool> refreshSession() async {
    final rt = refreshToken;
    if (rt == null || rt.isEmpty) return false;
    final r = await _request('POST', '/auth/refresh', {'refresh_token': rt}, allowRefresh: false);
    if (r.success && r.data != null && r.data!['access_token'] != null) {
      _captureTokens(r.data!);
      return true;
    }
    clearSession();
    return false;
  }

  /// Revokes the current session on the node (best effort) and forgets it locally.
  Future<void> logout() async {
    if (hasSession) {
      await _request('POST', '/auth/logout', {'refresh_token': refreshToken ?? ''}, allowRefresh: false);
    }
    clearSession();
  }

  Future<ApiResult<Map<String, dynamic>>> _request(
    String method,
    String path,
    Map<String, dynamic>? body, {
    bool allowRefresh = true,
  }) async {
    try {
      final resp = method == 'GET'
          ? await http.get(_uri(path), headers: _headers).timeout(_timeout)
          : await http
              .post(_uri(path), headers: _headers, body: jsonEncode(body ?? const {}))
              .timeout(_timeout);

      // Access tokens last 15 minutes: on 401, rotate once and retry.
      if (resp.statusCode == 401 && allowRefresh && !_isAuthRoute(path) && refreshToken != null) {
        if (await refreshSession()) {
          return _request(method, path, body, allowRefresh: false);
        }
      }

      final respBody = jsonDecode(resp.body) as Map<String, dynamic>;
      if (resp.statusCode >= 200 && resp.statusCode < 300) {
        return ApiResult.ok(respBody);
      }
      return ApiResult.err(
          respBody['error']?.toString() ?? 'HTTP ${resp.statusCode}');
    } catch (e) {
      return ApiResult.err(e.toString());
    }
  }

  Future<ApiResult<Map<String, dynamic>>> _get(String path) =>
      _request('GET', path, null);

  Future<ApiResult<Map<String, dynamic>>> _post(
          String path, Map<String, dynamic> body) =>
      _request('POST', path, body);

  Future<ApiResult<NodeStatus>> getStatus() async {
    final r = await _get('/status');
    if (r.success) return ApiResult.ok(NodeStatus.fromJson(r.data!));
    return ApiResult.err(r.error);
  }

  Future<ApiResult<AccountInfo>> login(
      String accountId, String password) async {
    final cleanId = accountId.trim().replaceFirst(RegExp(r'^@'), '');
    final r =
        await _post('/login', {'account_id': cleanId, 'password': password});
    if (r.success && r.data!['success'] == true) {
      _captureTokens(r.data!);
      final actualAccountId = r.data!['account_id'] as String? ?? cleanId;
      final acc = AccountInfo(
        accountId: actualAccountId,
        balances: WalletBalance.fromJson(r.data!['balances'] ?? {}),
        frozenBalances:
            WalletBalance.fromJson(r.data!['frozen_balances'] ?? {}),
        isVerified: r.data!['is_verified'] ?? false,
        verificationStatus: r.data!['verification_status'] ??
            (r.data!['is_verified'] == true ? 'VERIFIED' : 'PENDING'),
        nonce: r.data!['nonce'] ?? 0,
        salt: r.data!['salt'] as String?,
        publicKey: r.data!['public_key'] as String?,
      );
      return ApiResult.ok(acc);
    }
    return ApiResult.err(
        r.data?['error']?.toString() ?? r.error ?? 'Login failed');
  }

  Future<ApiResult<AccountInfo>> register(
      String accountId, String password, {String? studentId}) async {
    final cleanId = accountId.trim().replaceFirst(RegExp(r'^@'), '');
    final Map<String, dynamic> body = {
      'account_id': cleanId,
      'password': password,
    };
    if (studentId != null && studentId.trim().isNotEmpty) {
      body['student_id'] = studentId.trim();
    }
    final r = await _post('/register', body);
    if (r.success && r.data!['success'] == true) {
      _captureTokens(r.data!);
      final actualAccountId = r.data!['account_id'] as String? ?? cleanId;
      final acc = AccountInfo(
        accountId: actualAccountId,
        balances: WalletBalance.fromJson(r.data!['balances'] ?? {}),
        frozenBalances:
            WalletBalance.fromJson(r.data!['frozen_balances'] ?? {}),
        isVerified: r.data!['is_verified'] ?? false,
        verificationStatus: r.data!['verification_status'] ??
            (r.data!['is_verified'] == true ? 'VERIFIED' : 'PENDING'),
        nonce: r.data!['nonce'] ?? 0,
        salt: r.data!['salt'] as String?,
        publicKey: r.data!['public_key'] as String?,
      );
      return ApiResult.ok(acc);
    }
    return ApiResult.err(
        r.data?['error']?.toString() ?? r.error ?? 'Registration failed');
  }

  Future<ApiResult<AccountInfo>> getAccount(String accountId) async {
    final r = await _get('/account/$accountId');
    if (r.success) return ApiResult.ok(AccountInfo.fromJson(r.data!));
    return ApiResult.err(r.error);
  }

  Future<ApiResult<bool>> submitTx(Map<String, dynamic> tx) async {
    final r = await _post('/tx/submit', tx);
    if (r.success && r.data!['success'] == true)
      return const ApiResult.ok(true);
    return ApiResult.err(
        r.data?['error']?.toString() ?? r.error ?? 'Transaction failed');
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

  /// Activity heartbeat. The account is taken from the bearer token server-side.
  Future<ApiResult<bool>> ping() async {
    if (!hasSession) return const ApiResult.err('Not signed in');
    final r = await _post('/activity/ping', const {});
    if (r.success) return const ApiResult.ok(true);
    return ApiResult.err(r.error);
  }

  Future<ApiResult<List<Map<String, dynamic>>>> getTransactions(
    String accountId, {
    int limit = 20,
    int offset = 0,
  }) async {
    final query =
        'account=${Uri.encodeComponent(accountId)}&limit=$limit&offset=$offset';
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
    String? viewer,
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
    if (viewer != null && viewer.isNotEmpty) {
      params.add('viewer=${Uri.encodeComponent(viewer)}');
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
    return ApiResult.err(
        r.data?['error']?.toString() ?? r.error ?? 'Failed to create job');
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
    return ApiResult.err(
        r.data?['error']?.toString() ?? r.error ?? 'Claim failed');
  }

  Future<ApiResult<Map<String, dynamic>>> cancelMarketplaceJob({
    required String accountId,
    required String jobId,
  }) async {
    final r = await _post('/marketplace/cancel', {
      'account_id': accountId,
      'job_id': jobId,
    });
    if (r.success && r.data!['success'] == true) {
      return ApiResult.ok(r.data!);
    }
    return ApiResult.err(
        r.data?['error']?.toString() ?? r.error ?? 'Cancel failed');
  }

  Future<ApiResult<List<Map<String, dynamic>>>> getMempool() async {
    final r = await _get('/mempool');
    if (r.success) {
      final list = (r.data!['mempool'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      return ApiResult.ok(list);
    }
    return ApiResult.err(r.error);
  }

  // ─────────────────────────── GROUPS ───────────────────────────

  Future<ApiResult<Map<String, dynamic>>> getMyGroupsData(
      String accountId) async {
    final r =
        await _get('/groups/member?account=${Uri.encodeComponent(accountId)}');
    if (r.success) return ApiResult.ok(r.data!);
    return ApiResult.err(r.error);
  }

  Future<ApiResult<Map<String, dynamic>>> getGroupInfo(String groupName) async {
    final r = await _get('/groups/info?name=${Uri.encodeComponent(groupName)}');
    if (r.success)
      return ApiResult.ok(r.data!['group'] as Map<String, dynamic>);
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
    if (r.success && r.data!['success'] == true)
      return const ApiResult.ok(true);
    return ApiResult.err(
        r.data?['error']?.toString() ?? r.error ?? 'Failed to create team');
  }

  Future<ApiResult<bool>> leaveGroup({
    required String accountId,
    required String groupName,
  }) async {
    final r = await _post('/groups/leave', {
      'account_id': accountId,
      'group_name': groupName,
    });
    if (r.success && r.data!['success'] == true)
      return const ApiResult.ok(true);
    return ApiResult.err(
        r.data?['error']?.toString() ?? r.error ?? 'Failed to leave team');
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
    if (r.success && r.data!['success'] == true)
      return const ApiResult.ok(true);
    return ApiResult.err(
        r.data?['error']?.toString() ?? r.error ?? 'Team transfer failed');
  }

  Future<ApiResult<List<dynamic>>> getMyGroups(String accountId) async {
    final r =
        await _get('/groups/member?account=${Uri.encodeComponent(accountId)}');
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
    if (r.success && r.data!['success'] == true)
      return const ApiResult.ok(true);
    return ApiResult.err(
        r.data?['error']?.toString() ?? r.error ?? 'Failed to add member');
  }

  Future<ApiResult<bool>> joinGroup({
    required String accountId,
    required String groupName,
  }) async {
    final r = await _post('/groups/join', {
      'account_id': accountId,
      'group_name': groupName,
    });
    if (r.success && r.data!['success'] == true)
      return const ApiResult.ok(true);
    return ApiResult.err(
        r.data?['error']?.toString() ?? r.error ?? 'Failed to join group');
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
    if (r.success && r.data!['success'] == true)
      return const ApiResult.ok(true);
    return ApiResult.err(
        r.data?['error']?.toString() ?? r.error ?? 'Failed to create poll');
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
    return ApiResult.err(
        r.data?['error']?.toString() ?? r.error ?? 'Failed to vote');
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
    if (r.success && r.data!['success'] == true)
      return const ApiResult.ok(true);
    return ApiResult.err(
        r.data?['error']?.toString() ?? r.error ?? 'Failed to execute poll');
  }

  Future<ApiResult<Map<String, dynamic>>> checkGroupAccount(
      String accountId) async {
    final r = await _get('/groups/info?name=${Uri.encodeComponent(accountId)}');
    if (r.success)
      return ApiResult.ok(r.data!['group'] as Map<String, dynamic>);
    return ApiResult.err(r.error);
  }

  Future<ApiResult<ActivityLeaderboardResponse>>
      getActivityLeaderboard() async {
    final r = await _get('/activity/leaderboard');
    if (r.success && r.data != null) {
      try {
        return ApiResult.ok(ActivityLeaderboardResponse.fromJson(r.data!));
      } catch (e) {
        return ApiResult.err('Failed to parse activity data: $e');
      }
    }
    return ApiResult.err(r.error ?? 'Failed to load activity leaderboard');
  }

  Future<ApiResult<StudentLeaderboardEntry>> getStudentActivityScore(
      String accountId) async {
    final r = await _get('/activity/account/${Uri.encodeComponent(accountId)}');
    if (r.success && r.data != null) {
      try {
        final stud = r.data!['student'] as Map<String, dynamic>?;
        if (stud != null) {
          return ApiResult.ok(StudentLeaderboardEntry.fromJson(stud));
        }
      } catch (e) {
        return ApiResult.err('Failed to parse student score: $e');
      }
    }
    return ApiResult.err(r.error ?? 'Failed to load student activity score');
  }
}
