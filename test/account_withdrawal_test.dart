import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ondolbom/model/auth/login_preferences.dart';
import 'package:ondolbom/view/auth/account_withdrawal_button.dart';
import 'package:ondolbom/vm/auth/account_withdrawal_vm.dart';
import 'package:ondolbom/vm/auth/auth_vm.dart';
import 'package:ondolbom/vm/auth/user_profile_vm.dart';
import 'login_preferences_test.dart' show MemoryPreferences;

class WithdrawalUser extends Fake implements User {
  @override
  String get uid => 'uid';
  @override
  Future<String?> getIdToken([bool forceRefresh = false]) async => 'token';
}

class WithdrawalAuth extends Fake implements FirebaseAuth {
  int signouts = 0;
  @override
  User? get currentUser => WithdrawalUser();
  @override
  Future<void> signOut() async {
    signouts++;
  }
}

void main() {
  for (final code in [200, 409, 503]) {
    test('탈퇴 응답 $code 성공 후에만 세션과 저장 아이디를 정리한다', () async {
      final auth = WithdrawalAuth();
      final prefs = MemoryPreferences()
        ..email = 'saved@example.com'
        ..autoLogin = true;
      var cleanup = 0;
      final client = MockClient((request) async {
        expect(request.method, 'DELETE');
        expect(request.url.path, '/auth/account');
        expect(request.headers['Authorization'], 'Bearer token');
        return http.Response(
          jsonEncode({'detail': 'withdrawal blocked'}),
          code,
        );
      });
      final container = ProviderContainer(
        overrides: [
          firebaseAuthProvider.overrideWithValue(auth),
          authHttpClientProvider.overrideWithValue(client),
          loginPreferencesProvider.overrideWithValue(prefs),
          beforeSignOutProvider.overrideWithValue(() async {
            cleanup++;
          }),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(client.close);
      final sub = container.listen(accountWithdrawalProvider, (_, _) {});
      addTearDown(sub.close);
      expect(
        await container.read(accountWithdrawalProvider.notifier).withdraw(),
        code == 200,
      );
      expect(auth.signouts, code == 200 ? 1 : 0);
      expect(cleanup, code == 200 ? 1 : 0);
      expect(prefs.email, code == 200 ? null : 'saved@example.com');
      expect(prefs.autoLogin, code != 200);
    });
  }
  testWidgets('회원 탈퇴 취소는 API를 호출하지 않는다', (tester) async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return http.Response('{}', 200);
    });
    addTearDown(client.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authHttpClientProvider.overrideWithValue(client)],
        child: const MaterialApp(
          home: Scaffold(body: AccountWithdrawalButton()),
        ),
      ),
    );
    await tester.tap(find.text('회원 탈퇴'));
    await tester.pumpAndSettle();
    expect(find.text('회원 탈퇴하시겠어요?'), findsOneWidget);
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(calls, 0);
  });
}
