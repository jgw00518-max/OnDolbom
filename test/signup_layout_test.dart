import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ondolbom/model/auth/signup_api.dart';
import 'package:ondolbom/view/auth/signup_view.dart';

void main() {
  testWidgets('작은 화면·큰 글꼴에서도 3단계 제목과 살구색 버튼을 표시한다', (tester) async {
    tester.view.physicalSize = const Size(320, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
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
        overrides: [signupApiProvider.overrideWithValue(api)],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!,
          ),
          home: const SignupView(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('STEP 1 OF 3'), findsOneWidget);
    expect(find.text('이메일로 시작하기'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byType(FilledButton))
          .style!
          .backgroundColor!
          .resolve({}),
      const Color(0xFFF6B08A),
    );
    await tester.enterText(
      find.byType(TextFormField).first,
      'family@example.com',
    );
    await tester.ensureVisible(find.widgetWithText(FilledButton, '인증번호 전송'));
    await tester.tap(find.widgetWithText(FilledButton, '인증번호 전송'));
    await tester.pumpAndSettle();
    expect(find.text('STEP 2 OF 3'), findsOneWidget);
    expect(
      tester.widget<TextFormField>(find.byType(TextFormField).first).enabled,
      false,
    );
    await tester.ensureVisible(find.byType(TextFormField).last);
    await tester.enterText(find.byType(TextFormField).last, '123456');
    await tester.ensureVisible(find.widgetWithText(FilledButton, '인증번호 확인'));
    await tester.tap(find.widgetWithText(FilledButton, '인증번호 확인'));
    await tester.pumpAndSettle();
    expect(find.text('STEP 3 OF 3'), findsOneWidget);
    expect(find.text('비밀번호 만들기'), findsOneWidget);
    final fields = tester
        .widgetList<TextFormField>(find.byType(TextFormField))
        .toList();
    // 목업의 8자 규칙으로 바뀌지 않았는지 기존 서비스 조건을 확인한다.
    expect(fields[1].validator!('123456'), isNull);
    expect(fields[1].validator!('12345'), isNotNull);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('넓은 화면에서 가입 안내 패널을 표시한다', (tester) async {
    tester.view.physicalSize = const Size(1100, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      const ProviderScope(child: MaterialApp(home: SignupView())),
    );
    await tester.pumpAndSettle();
    expect(find.text('JOIN US'), findsOneWidget);
    expect(find.text('STEP 1 OF 3'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
