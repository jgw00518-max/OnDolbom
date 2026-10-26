import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondolbom/model/auth/google_login.dart';
import 'package:ondolbom/model/auth/login_preferences.dart';
import 'package:ondolbom/vm/auth/auth_vm.dart';

import 'login_preferences_test.dart' show MemoryPreferences;
import 'widget_test.dart' show FakeAuth;

class GoogleUser extends Fake implements User {
  @override
  String get email => 'google@example.com';
}

class GoogleResult extends Fake implements UserCredential {
  @override
  User get user => GoogleUser();
}

class GoogleAuth extends FakeAuth {
  int credentialCalls = 0;
  @override
  Future<UserCredential> signInWithCredential(AuthCredential credential) async {
    credentialCalls++;
    if (failure != null) throw failure!;
    return GoogleResult();
  }
}

void main() {
  test('Google 인증을 Firebase에 전달하고 자동 로그인·아이디 저장 옵션을 적용한다', () async {
    final auth = GoogleAuth();
    final preferences = MemoryPreferences();
    final container = ProviderContainer(
      overrides: [
        firebaseAuthProvider.overrideWithValue(auth),
        loginPreferencesProvider.overrideWithValue(preferences),
        googleCredentialProvider.overrideWithValue(
          () async => GoogleAuthProvider.credential(idToken: 'test'),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container
        .read(authVmProvider.notifier)
        .signInWithGoogle(autoLogin: true, rememberEmail: true);
    expect(auth.credentialCalls, 1);
    expect(preferences.autoLogin, isTrue);
    expect(preferences.email, 'google@example.com');
    expect(container.read(authVmProvider).hasError, isFalse);
  });

  test('계정 선택 취소는 인증 요청이나 오류 표시 없이 끝난다', () async {
    final auth = GoogleAuth();
    final preferences = MemoryPreferences()..email = 'old@example.com';
    final container = ProviderContainer(
      overrides: [
        firebaseAuthProvider.overrideWithValue(auth),
        loginPreferencesProvider.overrideWithValue(preferences),
        googleCredentialProvider.overrideWithValue(
          () async => throw GoogleLoginCancelled(),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container
        .read(authVmProvider.notifier)
        .signInWithGoogle(autoLogin: true, rememberEmail: true);
    expect(auth.credentialCalls, 0);
    expect(preferences.autoLogin, isFalse);
    expect(preferences.email, 'old@example.com');
    expect(container.read(authVmProvider).hasError, isFalse);
  });

  test('Firebase 인증 실패 시 이메일과 자동 로그인 성공 설정을 저장하지 않는다', () async {
    final auth = GoogleAuth()
      ..failure = FirebaseAuthException(
        code: 'account-exists-with-different-credential',
      );
    final preferences = MemoryPreferences()..email = 'old@example.com';
    final container = ProviderContainer(
      overrides: [
        firebaseAuthProvider.overrideWithValue(auth),
        loginPreferencesProvider.overrideWithValue(preferences),
        googleCredentialProvider.overrideWithValue(
          () async => GoogleAuthProvider.credential(idToken: 'test'),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container
        .read(authVmProvider.notifier)
        .signInWithGoogle(autoLogin: true, rememberEmail: true);
    expect(container.read(authVmProvider).hasError, isTrue);
    expect(preferences.email, 'old@example.com');
    expect(preferences.autoLogin, isFalse);
  });
}
