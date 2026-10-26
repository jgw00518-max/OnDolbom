import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondolbom/vm/auth/auth_vm.dart';
import 'package:ondolbom/model/auth/login_preferences.dart';

import 'login_preferences_test.dart' show MemoryPreferences;
import 'widget_test.dart' show FakeAuth;

class SessionAuth extends FakeAuth {
  final initial = Completer<User?>();
  @override
  Stream<User?> authStateChanges() => Stream.fromFuture(initial.future);
}

void main() {
  test('자동 로그인 미선택이면 Firebase 복원 완료 후에 세션을 종료한다', () async {
    final auth = SessionAuth();
    final restored = restoreLoginSession(auth, MemoryPreferences());
    await Future<void>.delayed(Duration.zero);
    expect(auth.logouts, 0);
    auth.initial.complete(null);
    await restored;
    expect(auth.logouts, 1);
  });

  test('자동 로그인 선택 시에는 SDK의 복원 세션을 유지한다', () async {
    final auth = SessionAuth()..initial.complete(null);
    await restoreLoginSession(auth, MemoryPreferences()..autoLogin = true);
    expect(auth.logouts, 0);
  });

  test('로그인 성공 시 옵션을 저장하고 실패 시에는 자동 로그인을 허용하지 않는다', () async {
    final auth = FakeAuth();
    final preferences = MemoryPreferences();
    final container = ProviderContainer(
      overrides: [
        firebaseAuthProvider.overrideWithValue(auth),
        loginPreferencesProvider.overrideWithValue(preferences),
      ],
    );
    addTearDown(container.dispose);
    final vm = container.read(authVmProvider.notifier);
    await vm.signIn('user@example.com', 'password', autoLogin: true);
    expect(preferences.autoLogin, isTrue);
    // 명시적인 로그아웃은 옵션과 무관하게 SDK 세션을 종료한다.
    await vm.signOut();
    expect(auth.logouts, 1);
    auth.failure = FirebaseAuthException(code: 'invalid-credential');
    await vm.signIn('wrong@example.com', 'password', autoLogin: true);
    expect(preferences.autoLogin, isFalse);
    auth.failure = null;
    await vm.signIn('user@example.com', 'password', autoLogin: false);
    expect(preferences.autoLogin, isFalse);
  });
}
