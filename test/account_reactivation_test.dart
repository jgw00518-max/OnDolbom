import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ondolbom/model/auth/app_user.dart';
import 'package:ondolbom/view/auth/account_reactivation_view.dart';
import 'package:ondolbom/view/home.dart';
import 'package:ondolbom/vm/auth/auth_vm.dart';
import 'package:ondolbom/vm/auth/user_profile_vm.dart';
import 'vm/notifications_vm_test.dart' show NotificationTestAuth;

void main() {
  test('비활성 프로필 403을 재활성화 화면용 상태로 구분한다', () async {
    final client = MockClient(
      (_) async => http.Response(
        jsonEncode({
          'detail': {
            'code': 'account_inactive',
            'can_reactivate': true,
            'reactivation_until': '2026-11-29 12:00:00',
          },
        }),
        403,
      ),
    );
    final container = ProviderContainer(
      overrides: [
        firebaseAuthProvider.overrideWithValue(NotificationTestAuth()),
        authUserProvider.overrideWith(
          (ref) => Stream.value(const AppUser(uid: 'verified')),
        ),
        authHttpClientProvider.overrideWithValue(client),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(client.close);
    final subscription = container.listen(userProfileProvider, (_, _) {});
    addTearDown(subscription.close);
    await expectLater(
      container.read(userProfileProvider.future),
      throwsA(
        isA<AccountInactiveException>().having(
          (e) => e.canReactivate,
          'can reactivate',
          true,
        ),
      ),
    );
  });
  testWidgets('비활성 계정은 공간 목록 대신 재활성화 화면을 표시한다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          userProfileProvider.overrideWith(
            (ref) async =>
                throw const AccountInactiveException('2026-11-29', true),
          ),
        ],
        child: const MaterialApp(home: Home()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('비활성 계정'), findsOneWidget);
    expect(find.text('계정 활성화'), findsOneWidget);
    expect(find.text('어느 가족과 함께할까요?'), findsNothing);
  });
  testWidgets('30일 경과 계정은 활성화 버튼을 제공하지 않는다', (tester) async {
    await tester.pumpWidget(
      const ProviderScope(
        child: MaterialApp(
          home: AccountReactivationView(
            account: AccountInactiveException('2026-10-01', false),
          ),
        ),
      ),
    );
    expect(find.text('계정 활성화'), findsNothing);
    expect(find.text('재활성화 기간이 지났어요'), findsOneWidget);
  });
  testWidgets('활성화 버튼은 본인 토큰으로 복구 API를 요청한다', (tester) async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      expect(request.method, 'POST');
      expect(request.url.path, '/auth/account/reactivate');
      expect(request.headers['Authorization'], 'Bearer test-token');
      return http.Response('{}', 200);
    });
    addTearDown(client.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          firebaseAuthProvider.overrideWithValue(NotificationTestAuth()),
          authHttpClientProvider.overrideWithValue(client),
        ],
        child: const MaterialApp(
          home: AccountReactivationView(
            account: AccountInactiveException('2026-11-29', true),
          ),
        ),
      ),
    );
    await tester.tap(find.text('계정 활성화'));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(tester.takeException(), isNull);
  });
}
