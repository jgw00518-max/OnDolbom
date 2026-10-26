import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondolbom/model/auth/login_preferences.dart';
import 'package:ondolbom/view/auth/login_view.dart';
import 'package:ondolbom/vm/auth/auth_vm.dart';

import 'widget_test.dart' show FakeAuth;

class MemoryPreferences extends LoginPreferences {
  bool autoLogin = false;
  @override
  Future<bool> readAutoLogin() async => autoLogin;
  @override
  Future<void> saveAutoLogin(bool enabled) async => autoLogin = enabled;
  String? email;
  Completer<String?>? pending;
  @override
  Future<String?> readEmail() async =>
      pending == null ? email : pending!.future;
  @override
  Future<void> saveEmail(String value) async => email = value.trim();
  @override
  Future<void> clearEmail() async => email = null;
}

void main() {
  test('실패한 이메일은 저장하지 않고 성공한 이메일만 보관하며 로그아웃에도 유지한다', () async {
    final preferences = MemoryPreferences()..email = 'old@example.com';
    final auth = FakeAuth()
      ..failure = FirebaseAuthException(code: 'invalid-credential');
    final container = ProviderContainer(
      overrides: [
        loginPreferencesProvider.overrideWithValue(preferences),
        firebaseAuthProvider.overrideWithValue(auth),
      ],
    );
    addTearDown(container.dispose);
    final vm = container.read(authVmProvider.notifier);
    await vm.signIn('wrong@example.com', 'password', rememberEmail: true);
    expect(preferences.email, 'old@example.com');
    auth.failure = null;
    await vm.signIn(' new@example.com ', 'password', rememberEmail: true);
    expect(preferences.email, 'new@example.com');
    await vm.signOut();
    expect(preferences.email, 'new@example.com');
    await vm.signIn('other@example.com', 'password', rememberEmail: false);
    expect(preferences.email, isNull);
  });

  testWidgets('저장 이메일을 복원하고 해제하면 삭제하며 다음 로그인 화면에는 남기지 않는다', (tester) async {
    final preferences = MemoryPreferences()..email = 'saved@example.com';
    Widget app() => ProviderScope(
      overrides: [loginPreferencesProvider.overrideWithValue(preferences)],
      child: const MaterialApp(home: LoginView()),
    );
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextFormField>(find.byType(TextFormField).first)
          .controller!
          .text,
      'saved@example.com',
    );
    expect(
      tester
          .widget<TextFormField>(find.byType(TextFormField).at(1))
          .controller!
          .text,
      isEmpty,
    );
    expect(
      tester
          .widget<Checkbox>(find.byType(Checkbox).first)
          .value,
      isTrue,
    );
    await tester.tap(find.text('아이디 저장'));
    await tester.pumpAndSettle();
    expect(preferences.email, isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(app());
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextFormField>(find.byType(TextFormField).first)
          .controller!
          .text,
      isEmpty,
    );
  });

  testWidgets('저장값 복원 중 입력을 막고 화면 종료 후 늦은 응답도 안전하게 처리한다', (tester) async {
    final preferences = MemoryPreferences()..pending = Completer<String?>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [loginPreferencesProvider.overrideWithValue(preferences)],
        child: const MaterialApp(home: LoginView()),
      ),
    );
    expect(
      tester.widget<TextFormField>(find.byType(TextFormField).first).enabled,
      isFalse,
    );
    await tester.pumpWidget(const SizedBox());
    preferences.pending!.complete('saved@example.com');
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
