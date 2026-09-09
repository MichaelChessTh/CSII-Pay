import 'package:flutter_test/flutter_test.dart';
import 'package:csii_pay_app/domain/models/user_profile.dart';

void main() {
  group('UserProfile Model', () {
    test('serialization and deserialization works correctly', () {
      final now = DateTime.now();
      final profile = UserProfile(
        username: 'student42',
        studentId: '64010042',
        fullName: 'Alice Wonder',
        nickname: 'Alice',
        publicKey: '04abcdef1234567890',
        createdAt: now,
      );

      final json = profile.toJson();
      expect(json['username'], 'student42');
      expect(json['studentId'], '64010042');
      expect(json['fullName'], 'Alice Wonder');
      expect(json['nickname'], 'Alice');
      expect(json['publicKey'], '04abcdef1234567890');
      expect(json.containsKey('password'), isFalse); // Passwords must NEVER be stored

      final reconstructed = UserProfile.fromJson(json);
      expect(reconstructed.username, profile.username);
      expect(reconstructed.studentId, profile.studentId);
      expect(reconstructed.fullName, profile.fullName);
      expect(reconstructed.nickname, profile.nickname);
      expect(reconstructed.publicKey, profile.publicKey);
    });
  });
}
