import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;
import 'package:csii_pay_app/domain/models/user_profile.dart';

class UserProfileService {
  final FirebaseFirestore _firestore;
  static const String _restBaseUrl =
      'https://firestore.googleapis.com/v1/projects/csii-pay/databases/(default)/documents/users';

  final Map<String, String?> _nicknameCache = {
    '6958082456': 'Genesis Operator',
  };

  UserProfileService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _usersRef =>
      _firestore.collection('users');

  /// Check if username is already taken in Cloud Firestore
  Future<bool> isUsernameAvailable(String username) async {
    final cleanUsername = username.trim().toLowerCase();
    if (cleanUsername.isEmpty) return false;
    if (cleanUsername == '6958082456') return false;

    try {
      final doc = await _usersRef.doc(cleanUsername).get();
      if (doc.exists) return false;

      final query = await _usersRef
          .where('username', isEqualTo: username.trim())
          .limit(1)
          .get();
      return query.docs.isEmpty;
    } catch (e) {
      debugPrint('[UserProfileService] SDK isUsernameAvailable failed ($e), falling back to REST');
      return await _checkAvailabilityViaRest(cleanUsername);
    }
  }

  Future<bool> _checkAvailabilityViaRest(String cleanUsername) async {
    try {
      final res = await http.get(Uri.parse('$_restBaseUrl/$cleanUsername'));
      if (res.statusCode == 404) {
        return true; // Not found means username is available
      }
      if (res.statusCode == 200) {
        return false; // Found means already taken
      }
      return true;
    } catch (e) {
      debugPrint('[UserProfileService] REST availability check error: $e');
      return true;
    }
  }

  /// Save new user profile in Cloud Firestore under document ID = username
  Future<bool> saveUserProfile(UserProfile profile) async {
    final docId = profile.username.trim().toLowerCase();
    bool saved = false;

    try {
      await _usersRef.doc(docId).set(profile.toFirestore(), SetOptions(merge: true));
      saved = true;
      debugPrint('[UserProfileService] Saved profile via SDK for @$docId');
    } catch (e) {
      debugPrint('[UserProfileService] SDK save failed ($e), falling back to REST');
      saved = await _saveProfileViaRest(profile);
    }

    if (saved || true) {
      _nicknameCache[docId] = profile.nickname;
      _nicknameCache[profile.username.trim()] = profile.nickname;
    }
    return saved;
  }

  Future<bool> _saveProfileViaRest(UserProfile profile) async {
    final docId = profile.username.trim().toLowerCase();
    try {
      final body = jsonEncode({
        'fields': {
          'username': {'stringValue': profile.username.trim()},
          'nickname': {'stringValue': profile.nickname.trim()},
          'studentId': {'stringValue': profile.studentId.trim()},
          'fullName': {'stringValue': profile.fullName.trim()},
          'publicKey': {'stringValue': profile.publicKey.trim()},
          'createdAt': {
            'timestampValue': profile.createdAt.toUtc().toIso8601String()
          },
        }
      });
      final res = await http.patch(
        Uri.parse('$_restBaseUrl/$docId'),
        headers: {'Content-Type': 'application/json'},
        body: body,
      );
      if (res.statusCode >= 200 && res.statusCode < 300) {
        debugPrint('[UserProfileService] Successfully saved profile via REST for @$docId');
        return true;
      } else {
        debugPrint('[UserProfileService] REST save failed with code ${res.statusCode}: ${res.body}');
        return false;
      }
    } catch (e) {
      debugPrint('[UserProfileService] REST save exception: $e');
      return false;
    }
  }

  /// Get user profile by username
  Future<UserProfile?> getUserProfile(String username) async {
    final cleanUsername = username.trim().toLowerCase();
    if (cleanUsername.isEmpty) return null;

    if (cleanUsername == '6958082456') {
      return UserProfile(
        username: '6958082456',
        studentId: 'GENESIS-001',
        fullName: 'Genesis Authority',
        nickname: 'Genesis Operator',
        publicKey: '',
        createdAt: DateTime(2026, 1, 1),
      );
    }

    try {
      final doc = await _usersRef.doc(cleanUsername).get();
      if (doc.exists) {
        final profile = UserProfile.fromFirestore(doc);
        _nicknameCache[cleanUsername] = profile.nickname;
        _nicknameCache[username.trim()] = profile.nickname;
        return profile;
      }

      // Try case-insensitive query if doc was stored under different case
      final query = await _usersRef
          .where('username', isEqualTo: username.trim())
          .limit(1)
          .get();
      if (query.docs.isNotEmpty) {
        final profile = UserProfile.fromFirestore(query.docs.first);
        _nicknameCache[cleanUsername] = profile.nickname;
        _nicknameCache[username.trim()] = profile.nickname;
        return profile;
      }
    } catch (e) {
      debugPrint('[UserProfileService] SDK get profile error ($e), trying REST fallback');
    }

    // Direct REST Fallback (immune to SDK client offline state on web)
    final restProfile = await _fetchProfileViaRest(cleanUsername);
    if (restProfile != null) {
      _nicknameCache[cleanUsername] = restProfile.nickname;
      _nicknameCache[username.trim()] = restProfile.nickname;
      return restProfile;
    }

    return null;
  }

  Future<UserProfile?> _fetchProfileViaRest(String cleanUsername) async {
    try {
      final res = await http.get(Uri.parse('$_restBaseUrl/$cleanUsername'));
      if (res.statusCode == 200) {
        final data = jsonDecode(res.body) as Map<String, dynamic>;
        final fields = data['fields'] as Map<String, dynamic>?;
        if (fields != null) {
          final profile = UserProfile(
            username: fields['username']?['stringValue'] ?? cleanUsername,
            studentId: fields['studentId']?['stringValue'] ?? '',
            fullName: fields['fullName']?['stringValue'] ?? '',
            nickname: fields['nickname']?['stringValue'] ?? cleanUsername,
            publicKey: fields['publicKey']?['stringValue'] ?? '',
            createdAt: DateTime.tryParse(
                    fields['createdAt']?['timestampValue'] ?? '') ??
                DateTime.now(),
          );
          debugPrint('[UserProfileService] Resolved profile via REST: ${profile.nickname} (@${profile.username})');
          return profile;
        }
      }
    } catch (e) {
      debugPrint('[UserProfileService] REST get profile error: $e');
    }
    return null;
  }

  /// Quick lookup for recipient nickname with local memory caching
  Future<String?> getNickname(String username) async {
    final trimmed = username.trim();
    if (trimmed.isEmpty) return null;

    final lower = trimmed.toLowerCase();
    if (_nicknameCache.containsKey(lower) && _nicknameCache[lower] != null) {
      return _nicknameCache[lower];
    }
    if (_nicknameCache.containsKey(trimmed) && _nicknameCache[trimmed] != null) {
      return _nicknameCache[trimmed];
    }

    final profile = await getUserProfile(trimmed);
    if (profile != null && profile.nickname.isNotEmpty) {
      _nicknameCache[lower] = profile.nickname;
      _nicknameCache[trimmed] = profile.nickname;
      return profile.nickname;
    }
    return null;
  }
}
