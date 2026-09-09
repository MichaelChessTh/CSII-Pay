import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:csii_pay_app/domain/models/marketplace_application.dart';
import 'package:csii_pay_app/data/services/node_api_service.dart';

class MarketplaceService {
  final FirebaseFirestore _firestore;
  final NodeApiService _nodeApi;
  static const String _restBaseUrl =
      'https://firestore.googleapis.com/v1/projects/csii-pay/databases/(default)/documents/marketplace_applications';

  MarketplaceService({
    FirebaseFirestore? firestore,
    required NodeApiService nodeApi,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _nodeApi = nodeApi;

  CollectionReference<Map<String, dynamic>> get _jobsRef =>
      _firestore.collection('marketplace_applications');

  /// Generate cryptographically secure 6-digit numeric code
  static String generateSecretCode() {
    final rnd = Random.secure();
    final code = 100000 + rnd.nextInt(900000);
    return code.toString();
  }

  /// Compute SHA-256 hex string of code
  static String hashSecretCode(String code) {
    return sha256.convert(utf8.encode(code.trim())).toString();
  }

  /// Cache secret code locally for creator review
  Future<void> _cacheLocalSecret(String jobId, String secretCode) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('mkt_secret_$jobId', secretCode);
    } catch (e) {
      debugPrint('[MarketplaceService] SharedPreferences cache error: $e');
    }
  }

  Future<String?> getCachedSecret(String jobId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString('mkt_secret_$jobId');
    } catch (_) {
      return null;
    }
  }

  /// Create marketplace job on blockchain escrow and mirror in Firestore
  Future<ApiResult<MarketplaceApplication>> createApplication({
    required String creatorAccountId,
    required String? creatorNickname,
    required String title,
    required String type,
    required String category,
    required String description,
    required String deadline,
    required int difficulty,
    required String lineId,
    required double wage,
    String wageToken = 'CSP',
    String? teamName,
  }) async {
    final secretCode = generateSecretCode();
    final secretHash = hashSecretCode(secretCode);
    final jobId = 'JOB_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(9999)}';

    final effectiveCreator = teamName ?? creatorAccountId;
    final effectiveNickname = teamName != null ? 'Team $teamName' : (creatorNickname ?? creatorAccountId);
    final effectiveType = teamName != null ? 'team application' : type;

    final payload = {
      'job_id': jobId,
      'creator': effectiveCreator,
      'creator_nickname': effectiveNickname,
      'title': title,
      'type': effectiveType,
      'category': category,
      'description': description,
      'deadline': deadline,
      'difficulty': difficulty,
      'line_id': lineId,
      'wage': wage,
      'wage_token': wageToken,
      'secret_hash': secretHash,
      if (teamName != null) 'team_name': teamName,
      if (teamName != null) 'author': creatorAccountId,
    };

    // 1. Submit to blockchain smart contract escrow
    final nodeRes = await _nodeApi.createMarketplaceJob(payload);
    if (!nodeRes.success) {
      return ApiResult.err(nodeRes.error ?? 'Blockchain smart contract failed');
    }

    await _cacheLocalSecret(jobId, secretCode);

    final app = MarketplaceApplication(
      id: jobId,
      title: title,
      type: effectiveType,
      category: category,
      description: description,
      deadline: deadline,
      difficulty: difficulty,
      lineId: lineId,
      wage: wage,
      wageToken: wageToken,
      creatorAccountId: effectiveCreator,
      creatorNickname: effectiveNickname,
      secretCode: secretCode,
      secretHash: secretHash,
      status: 'OPEN',
      createdAt: DateTime.now(),
    );

    // 2. Mirror in Firestore for fast multi-attribute search & cross-device sync
    try {
      await _jobsRef.doc(jobId).set(app.toJson(), SetOptions(merge: true));
    } catch (e) {
      debugPrint('[MarketplaceService] SDK firestore save error ($e), trying REST fallback');
      await _saveViaRest(app);
    }

    return ApiResult.ok(app);
  }

  Future<void> _saveViaRest(MarketplaceApplication app) async {
    try {
      final body = jsonEncode({
        'fields': {
          'id': {'stringValue': app.id},
          'title': {'stringValue': app.title},
          'type': {'stringValue': app.type},
          'category': {'stringValue': app.category},
          'description': {'stringValue': app.description},
          'deadline': {'stringValue': app.deadline},
          'difficulty': {'integerValue': app.difficulty.toString()},
          'line_id': {'stringValue': app.lineId},
          'wage': {'doubleValue': app.wage},
          'wage_token': {'stringValue': app.wageToken},
          'creator': {'stringValue': app.creatorAccountId},
          if (app.creatorNickname != null)
            'creator_nickname': {'stringValue': app.creatorNickname!},
          if (app.secretCode != null)
            'secret_code': {'stringValue': app.secretCode!},
          if (app.secretHash != null)
            'secret_hash': {'stringValue': app.secretHash!},
          'status': {'stringValue': app.status},
          'created_at': {'integerValue': (app.createdAt.millisecondsSinceEpoch ~/ 1000).toString()},
        }
      });
      await http.patch(
        Uri.parse('$_restBaseUrl/${app.id}'),
        headers: {'Content-Type': 'application/json'},
        body: body,
      );
    } catch (e) {
      debugPrint('[MarketplaceService] REST save failed: $e');
    }
  }

  /// Fetch applications with filtering
  Future<List<MarketplaceApplication>> fetchApplications({
    String? category,
    String? type,
    int? difficulty,
    String? creator,
    String? currentAccountId,
  }) async {
    List<MarketplaceApplication> list = [];

    // 1. Try blockchain node first
    try {
      final nodeRes = await _nodeApi.getMarketplaceJobs(
        category: category,
        type: type,
        difficulty: difficulty,
        creator: creator,
      );
      if (nodeRes.success && nodeRes.data != null && nodeRes.data!.isNotEmpty) {
        for (final item in nodeRes.data!) {
          final app = MarketplaceApplication.fromJson(item);
          list.add(app);
        }
      }
    } catch (e) {
      debugPrint('[MarketplaceService] Node fetch failed: $e');
    }

    // 2. If node list is empty or fallback needed, query Firestore
    if (list.isEmpty) {
      try {
        Query<Map<String, dynamic>> query = _jobsRef;
        if (category != null && category.isNotEmpty) {
          query = query.where('category', isEqualTo: category);
        }
        if (type != null && type.isNotEmpty) {
          query = query.where('type', isEqualTo: type);
        }
        if (difficulty != null) {
          query = query.where('difficulty', isEqualTo: difficulty);
        }
        if (creator != null && creator.isNotEmpty) {
          query = query.where('creator', isEqualTo: creator);
        }
        final snap = await query.get();
        list = snap.docs.map((d) => MarketplaceApplication.fromJson(d.data())).toList();
      } catch (e) {
        debugPrint('[MarketplaceService] Firestore query error: $e');
      }
    }

    // Inject cached secrets for current user's created jobs
    final enriched = <MarketplaceApplication>[];
    for (final app in list) {
      if (currentAccountId != null && app.creatorAccountId == currentAccountId && app.secretCode == null) {
        final cached = await getCachedSecret(app.id);
        if (cached != null) {
          enriched.add(app.copyWith(secretCode: cached));
          continue;
        }
      }
      enriched.add(app);
    }

    return enriched;
  }

  /// Claim job by entering secret code
  Future<ApiResult<Map<String, dynamic>>> claimApplication({
    required String accountId,
    required String jobId,
    required String secretCode,
  }) async {
    final res = await _nodeApi.claimMarketplaceJob(
      accountId: accountId,
      jobId: jobId,
      secretCode: secretCode,
    );

    if (res.success) {
      // Update firestore document status to COMPLETED
      try {
        await _jobsRef.doc(jobId).set({
          'status': 'COMPLETED',
          'worker': accountId,
        }, SetOptions(merge: true));
      } catch (_) {}
    }

    return res;
  }
}
