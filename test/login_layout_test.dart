import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondolbom/model/auth/login_preferences.dart';
import 'package:ondolbom/view/auth/login_view.dart';
import 'login_preferences_test.dart' show MemoryPreferences;

void main() {
  testWidgets('첨부 CSS의 모바일 배경·입력 높이·소셜 버튼 슬롯을 유지한다', (tester) async {
    tester.view.physicalSize = const Size(430, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          loginPreferencesProvider.overrideWithValue(MemoryPreferences()),
        ],
        child: const MaterialApp(home: LoginView()),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
      const Color(0xFFFFFAF7),
    );
    expect(
      tester.getSize(find.byType(TextFormField).first).height,
      closeTo(52, 1),
    );
    for (final label in ['Google로 계속하기', '카카오로 계속하기', '네이버로 계속하기']) {
      expect(tester.getSize(find.byTooltip(label)), const Size(48, 48));
    }
    final google = tester.getRect(find.byTooltip('Google로 계속하기'));
    final kakao = tester.getRect(find.byTooltip('카카오로 계속하기'));
    expect(kakao.left - google.right, 12);
    expect(find.text('G'), findsNothing);
    expect(find.text('N'), findsNothing);
  });

  testWidgets('넓은 화면에서는 안내 패널과 로그인 폼을 함께 표시한다', (tester) async {
    tester.view.physicalSize = const Size(1100, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          loginPreferencesProvider.overrideWithValue(MemoryPreferences()),
        ],
        child: const MaterialApp(home: LoginView()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('WELCOME BACK'), findsOneWidget);
    expect(find.text('SIGN IN'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('작은 화면·큰 글꼴·키보드에서도 로그인 요소가 잘리지 않는다', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          loginPreferencesProvider.overrideWithValue(MemoryPreferences()),
        ],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.4)),
            child: child!,
          ),
          home: const LoginView(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('SIGN IN'), findsOneWidget);
    expect(find.byTooltip('Google로 계속하기'), findsOneWidget);
    expect(find.byTooltip('카카오로 계속하기'), findsOneWidget);
    expect(find.byTooltip('네이버로 계속하기'), findsOneWidget);
    await tester.ensureVisible(find.text('이메일로 회원가입'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.byType(TextFormField).last);
    await tester.tap(find.byType(TextFormField).last);
    tester.view.viewInsets = const FakeViewPadding(bottom: 240);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
