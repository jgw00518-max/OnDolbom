import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ondolbom/model/auth/signup_api.dart';
import 'package:ondolbom/model/auth/login_preferences.dart';
import 'package:ondolbom/view/auth/login_view.dart';
import 'package:ondolbom/view/auth/signup_view.dart';
import 'package:ondolbom/vm/auth/auth_vm.dart';
import 'package:ondolbom/vm/auth/signup_vm.dart';
import 'login_preferences_test.dart' show MemoryPreferences;
import 'widget_test.dart' show FakeAuth;

void main() {
  test('이메일 확인 전 가입 차단, 증명 전달 후 가입·로그인 순서 보장', () async {
    final auth = FakeAuth();
    final sent = <http.Request>[];
    final api = SignupApi(
      'http://localhost',
      MockClient((request) async {
        sent.add(request);
        if (request.url.path.endsWith('confirm')) expect(auth.email, isNull);
        return http.Response(
          jsonEncode(switch (request.url.path.split('/').last) {
            'request' => {'request_id': 'id'},
            'verify' => {'verification_token': 'signup-token'},
            _ => {'created': true},
          }),
          200,
        );
      }),
    );
    final container = ProviderContainer(
      overrides: [
        signupApiProvider.overrideWithValue(api),
        firebaseAuthProvider.overrideWithValue(auth),
        loginPreferencesProvider.overrideWithValue(MemoryPreferences()),
      ],
    );
    addTearDown(container.dispose);
    final subscription = container.listen(signupVmProvider, (_, _) {});
    addTearDown(subscription.close);
    final vm = container.read(signupVmProvider.notifier);
    await vm.complete('password', 'password');
    expect(sent, isEmpty);
    expect(auth.registrations, 0);
    await vm.send(' FAMILY@example.com ');
    expect(jsonDecode(sent.first.body)['email'], 'family@example.com');
    await vm.send('family@example.com');
    expect(sent.length, 1);
    await vm.verify('123456');
    await vm.complete('password', 'different');
    expect(sent.length, 2);
    await vm.complete('password', 'password');
    expect(jsonDecode(sent.last.body)['verification_token'], 'signup-token');
    expect(auth.email, 'family@example.com');
    // Firebase 직접 가입을 사용하지 않아 UI를 우회한 미인증 생성 경로를 없앤다.
    expect(auth.registrations, 0);
    expect(container.read(signupVmProvider).hasError, false);
  });

  test('서버 가입 실패 시 Firebase 로그인하지 않는다', () async {
    final auth = FakeAuth();
    final api = SignupApi(
      'http://localhost',
      MockClient((_) async => http.Response('private details', 400)),
    );
    final container = ProviderContainer(
      overrides: [
        signupApiProvider.overrideWithValue(api),
        firebaseAuthProvider.overrideWithValue(auth),
        loginPreferencesProvider.overrideWithValue(MemoryPreferences()),
      ],
    );
    addTearDown(container.dispose);
    await container
        .read(authVmProvider.notifier)
        .signUp(
          'family@example.com',
          'password',
          requestId: 'id',
          verificationToken: 'proof',
        );
    expect(auth.email, isNull);
    expect(
      authErrorMessage(container.read(authVmProvider).error!),
      isNot(contains('private details')),
    );
  });

  test('중복 요청과 화면 폐기 후 늦은 응답을 막는다', () async {
    final pending = Completer<http.Response>();
    var calls = 0;
    final api = SignupApi(
      'http://localhost',
      MockClient((_) {
        calls++;
        return pending.future;
      }),
    );
    final container = ProviderContainer(
      overrides: [signupApiProvider.overrideWithValue(api)],
    );
    container.listen(signupVmProvider, (_, _) {});
    final vm = container.read(signupVmProvider.notifier);
    final first = vm.send('family@example.com');
    await vm.send('family@example.com');
    await Future<void>.delayed(Duration.zero);
    expect(calls, 1);
    container.dispose();
    pending.complete(http.Response('{"request_id":"id"}', 200));
    await first;
  });

  testWidgets('가입 화면 진입과 이메일→코드→비밀번호 입력을 연결한다', (tester) async {
    final api = SignupApi(
      'http://localhost',
      MockClient(
        (request) async => http.Response(
          jsonEncode(
            request.url.path.endsWith('request')
                ? {'request_id': 'id'}
                : {'verification_token': 'proof'},
          ),
          200,
        ),
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          signupApiProvider.overrideWithValue(api),
          loginPreferencesProvider.overrideWithValue(MemoryPreferences()),
        ],
        child: const MaterialApp(home: LoginView()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('이메일로 회원가입'));
    await tester.tap(find.text('이메일로 회원가입'));
    await tester.pumpAndSettle();
    expect(find.byType(SignupView), findsOneWidget);
    expect(find.text('이메일로 가입'), findsNothing);
    await tester.enterText(
      find.byType(TextFormField).last,
      'family@example.com',
    );
    await tester.tap(find.text('인증번호 전송'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, '인증번호 확인'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField).last, '123456');
    await tester.tap(find.widgetWithText(FilledButton, '인증번호 확인'));
    await tester.pumpAndSettle();
    expect(find.text('이메일로 가입'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });
}
