import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ondolbom/model/auth/password_reset_api.dart';
import 'package:ondolbom/view/auth/password_reset_view.dart';
import 'package:ondolbom/vm/auth/password_reset_vm.dart';

void main() {
  for (final width in [320.0, 1100.0]) {
    testWidgets('재설정 디자인은 ${width.toInt()}px 화면에서도 같은 버튼 색상을 사용한다', (
      tester,
    ) async {
      tester.view.physicalSize = Size(width, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: PasswordResetView())),
      );
      await tester.pumpAndSettle();
      expect(find.text('STEP 1 OF 3'), findsOneWidget);
      final style = tester
          .widget<FilledButton>(find.byType(FilledButton))
          .style!;
      expect(style.backgroundColor!.resolve({}), const Color(0xFFF6B08A));
      expect(style.foregroundColor!.resolve({}), const Color(0xFF3E3A39));
      if (width > 760) expect(find.text('RESET PASSWORD'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });
  }
  test('단계별 증명 전달과 비밀번호 확인, 완료 상태를 검증한다', () async {
    final sent = <Map<String, dynamic>>[];
    final api = PasswordResetApi(
      'http://localhost',
      MockClient((request) async {
        sent.add(jsonDecode(request.body) as Map<String, dynamic>);
        return http.Response(
          jsonEncode(switch (request.url.path.split('/').last) {
            'request' => {'request_id': 'request-id'},
            'verify' => {'reset_token': 'one-use-token'},
            _ => {'changed': true},
          }),
          200,
        );
      }),
    );
    final container = ProviderContainer(
      overrides: [passwordResetApiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);
    final sub = container.listen(passwordResetProvider, (_, _) {});
    addTearDown(sub.close);
    final vm = container.read(passwordResetProvider.notifier);
    await vm.send(' family@example.com ');
    expect(sent.first['email'], 'family@example.com');
    await vm.send('family@example.com');
    expect(sent.length, 1);
    await vm.verify('123456');
    expect(sent.last['request_id'], 'request-id');
    await vm.confirm('new-password', 'different');
    expect(sent.length, 2);
    await vm.confirm('new-password', 'new-password');
    expect(sent.last['reset_token'], 'one-use-token');
    expect(
      container.read(passwordResetProvider).requireValue,
      PasswordResetStep.done,
    );
  });

  test('중복 요청과 화면 폐기 뒤 늦은 응답을 처리한다', () async {
    final pending = Completer<http.Response>();
    var calls = 0;
    final api = PasswordResetApi(
      'http://localhost',
      MockClient((_) {
        calls++;
        return pending.future;
      }),
    );
    final container = ProviderContainer(
      overrides: [passwordResetApiProvider.overrideWithValue(api)],
    );
    container.listen(passwordResetProvider, (_, _) {});
    final vm = container.read(passwordResetProvider.notifier);
    final first = vm.send('family@example.com');
    await vm.send('family@example.com');
    await Future<void>.delayed(Duration.zero);
    expect(calls, 1);
    container.dispose();
    pending.complete(http.Response('{"request_id":"request-id"}', 200));
    await first;
  });

  testWidgets('이메일→코드→비밀번호 화면과 확인 입력을 연결한다', (tester) async {
    final api = PasswordResetApi(
      'http://localhost',
      MockClient(
        (request) async => http.Response(
          jsonEncode(
            request.url.path.endsWith('request')
                ? {'request_id': 'id'}
                : request.url.path.endsWith('verify')
                ? {'reset_token': 'token'}
                : {'changed': true},
          ),
          200,
        ),
      ),
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [passwordResetApiProvider.overrideWithValue(api)],
        child: const MaterialApp(home: PasswordResetView()),
      ),
    );
    await tester.tap(find.text('인증번호 전송'));
    await tester.pump();
    expect(find.text('이메일 형식을 확인해 주세요.'), findsOneWidget);
    await tester.enterText(find.byType(TextFormField), 'family@example.com');
    await tester.tap(find.text('인증번호 전송'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).last, '123456');
    await tester.tap(find.widgetWithText(FilledButton, '인증번호 확인'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, 'new-password');
    await tester.enterText(find.byType(TextFormField).last, 'new-password');
    await tester.tap(find.text('비밀번호 재설정'));
    await tester.pumpAndSettle();
    expect(find.text('로그인으로 돌아가기'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    expect(tester.takeException(), isNull);
  });

  test('서버 오류의 비밀 원문을 노출하지 않는다', () async {
    final api = PasswordResetApi(
      'http://localhost',
      MockClient((_) async => http.Response('private details', 503)),
    );
    await expectLater(
      api.post('request', {'email': 'family@example.com'}),
      throwsA(
        isA<PasswordResetFailure>().having(
          (e) => e.toString(),
          'message',
          isNot(contains('private details')),
        ),
      ),
    );
  });
}
