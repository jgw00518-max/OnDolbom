import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ondolbom/model/invites/family_invite.dart';
import 'package:ondolbom/vm/auth/auth_vm.dart';
import 'package:ondolbom/vm/invites/invite_vm.dart';
import 'notifications_vm_test.dart' show NotificationTestAuth;

void main() {
  test('재요청은 인증과 원본 ID만 보내고 SMTP 실패를 성공 발송으로 표시하지 않는다', () async {
    for (final sent in [true, false]) {
      final client = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/invites/expired-id/resend');
        expect(request.headers['Authorization'], 'Bearer test-token');
        expect(request.body, isEmpty);
        return http.Response(
          jsonEncode({'invite_id': 'new-id', 'email_sent': sent}),
          201,
        );
      });
      final container = ProviderContainer(
        overrides: [
          firebaseAuthProvider.overrideWithValue(NotificationTestAuth()),
          inviteHttpClientProvider.overrideWithValue(client),
        ],
      );
      expect(
        await container.read(inviteVmProvider).resendInvite('expired-id'),
        sent,
      );
      container.dispose();
      client.close();
    }
  });

  test('초대 만료 시각과 서버 권한을 읽고 구버전 응답은 재요청을 숨긴다', () {
    final json = <String, dynamic>{
      'invite_id': 'old',
      'family_room_id': 'room',
      'invite_email': 'family@example.com',
      'invite_at': '2026-10-01T10:00:00',
      'invite_status': '만료',
      'care_recipient_name': '가족',
    };
    expect(FamilyInvite.fromJson(json).canResend, isFalse);
    final invite = FamilyInvite.fromJson({
      ...json,
      'can_resend': 1,
      'expires_at': '2026-10-08T10:00:00',
    });
    expect(invite.canResend, isTrue);
    expect(invite.expiresAt, DateTime(2026, 10, 8, 10));
  });
}
