import 'package:cloud_firestore/cloud_firestore.dart';

class UserProfile {
  final String username;
  final String studentId;
  final String fullName;
  final String nickname;
  final String publicKey;
  final DateTime createdAt;

  const UserProfile({
    required this.username,
    required this.studentId,
    required this.fullName,
    required this.nickname,
    this.publicKey = '',
    required this.createdAt,
  });

  factory UserProfile.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};
    DateTime created;
    final rawCreated = data['createdAt'];
    if (rawCreated is Timestamp) {
      created = rawCreated.toDate();
    } else if (rawCreated is String) {
      created = DateTime.tryParse(rawCreated) ?? DateTime.now();
    } else {
      created = DateTime.now();
    }

    return UserProfile(
      username: (data['username'] as String?) ?? doc.id,
      studentId: (data['studentId'] as String?) ?? '',
      fullName: (data['fullName'] as String?) ?? '',
      nickname: (data['nickname'] as String?) ?? '',
      publicKey: (data['publicKey'] as String?) ?? '',
      createdAt: created,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'username': username,
      'studentId': studentId,
      'fullName': fullName,
      'nickname': nickname,
      'publicKey': publicKey,
      'createdAt': Timestamp.fromDate(createdAt),
    };
  }

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      username: (json['username'] as String?) ?? '',
      studentId: (json['studentId'] as String?) ?? '',
      fullName: (json['fullName'] as String?) ?? '',
      nickname: (json['nickname'] as String?) ?? '',
      publicKey: (json['publicKey'] as String?) ?? '',
      createdAt: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString()) ?? DateTime.now()
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'username': username,
      'studentId': studentId,
      'fullName': fullName,
      'nickname': nickname,
      'publicKey': publicKey,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  UserProfile copyWith({
    String? username,
    String? studentId,
    String? fullName,
    String? nickname,
    String? publicKey,
    DateTime? createdAt,
  }) {
    return UserProfile(
      username: username ?? this.username,
      studentId: studentId ?? this.studentId,
      fullName: fullName ?? this.fullName,
      nickname: nickname ?? this.nickname,
      publicKey: publicKey ?? this.publicKey,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
