import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ondolbom/model/auth/kakao_login.dart';
import 'package:ondolbom/model/auth/login_preferences.dart';
import 'package:ondolbom/vm/auth/auth_vm.dart';

import 'google_login_test.dart' show GoogleAuth, GoogleResult;
import 'login_preferences_test.dart' show MemoryPreferences;

class KakaoAuth extends GoogleAuth {
  String? customToken;
  @override
  Future<UserCredential> signInWithCustomToken(String token) async {
    customToken = token;
    return GoogleResult();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('브라우저 종료 후 복귀하면 대기를 해제하고 늦은 결과를 무시한다', (tester) async {
    final sdkResult = Completer<String>();
    final auth = KakaoAuth();
    var serverCalls = 0;
    final container = ProviderContainer(
      overrides: [
        firebaseAuthProvider.overrideWithValue(auth),
        loginPreferencesProvider.overrideWithValue(MemoryPreferences()),
        kakaoAccessTokenProvider.overrideWithValue(() => sdkResult.future),
        kakaoTokenExchangeProvider.overrideWithValue((_, _) async {
          serverCalls++;
          return 'must-not-login';
        }),
      ],
    );
    addTearDown(container.dispose);
    final operation = container
        .read(authVmProvider.notifier)
        .signInWithKakao(autoLogin: false, rememberEmail: false);
    await tester.pump();
    expect(container.read(authVmProvider).isLoading, isTrue);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 6));
    await operation;
    expect(container.read(authVmProvider).isLoading, isFalse);
    expect(container.read(authVmProvider).hasError, isFalse);
    sdkResult.complete('late-token');
    await tester.pump();
    expect(serverCalls, 0);
    expect(auth.customToken, isNull);
  });

  testWidgets('앱 복귀 직후 정상 SDK 결과는 취소하지 않는다', (tester) async {
    final sdk = Completer<String>();
    final operation = waitForKakaoLogin(() => sdk.future);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    sdk.complete('valid-token');
    await tester.pump();
    expect(await operation, 'valid-token');
    await tester.pump(const Duration(seconds: 6));
    expect(tester.takeException(), isNull);
  });

  testWidgets('복귀 이벤트도 결과도 없으면 제한 시간 후 대기를 종료한다', (tester) async {
    final sdk = Completer<String>();
    final operation = waitForKakaoLogin(
      () => sdk.future,
      timeout: const Duration(seconds: 2),
    );
    final assertion = expectLater(operation, throwsA(isA<KakaoLoginFailure>()));
    await tester.pump(const Duration(seconds: 3));
    await assertion;
    sdk.complete('late');
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  test('서버 검증 토큰으로 Firebase 로그인 후 기존 로그인 옵션을 적용한다', () async {
    final auth = KakaoAuth();
    final preferences = MemoryPreferences();
    final container = ProviderContainer(
      overrides: [
        firebaseAuthProvider.overrideWithValue(auth),
        loginPreferencesProvider.overrideWithValue(preferences),
        kakaoAccessTokenProvider.overrideWithValue(() async => 'kakao-access'),
        kakaoLoginHttpClientProvider.overrideWithValue(
          MockClient((request) async {
            expect(request.url.path, '/auth/kakao');
            expect(jsonDecode(request.body), {'access_token': 'kakao-access'});
            return http.Response('{"custom_token":"verified-firebase"}', 200);
          }),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container
        .read(authVmProvider.notifier)
        .signInWithKakao(autoLogin: true, rememberEmail: true);
    expect(auth.customToken, 'verified-firebase');
    expect(preferences.autoLogin, isTrue);
    expect(preferences.email, 'google@example.com');
  });

  test('계정 충돌이면 Firebase에 로그인하지 않고 기존 저장 이메일을 보존한다', () async {
    final auth = KakaoAuth();
    final preferences = MemoryPreferences()..email = 'old@example.com';
    final container = ProviderContainer(
      overrides: [
        firebaseAuthProvider.overrideWithValue(auth),
        loginPreferencesProvider.overrideWithValue(preferences),
        kakaoAccessTokenProvider.overrideWithValue(() async => 'kakao-access'),
        kakaoLoginHttpClientProvider.overrideWithValue(
          MockClient((_) async => http.Response('{}', 409)),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container
        .read(authVmProvider.notifier)
        .signInWithKakao(autoLogin: true, rememberEmail: true);
    expect(auth.customToken, isNull);
    expect(preferences.autoLogin, isFalse);
    expect(preferences.email, 'old@example.com');
    expect(container.read(authVmProvider).hasError, isTrue);
  });

  test('카카오 인증 취소는 서버 요청 없이 종료한다', () async {
    final container = ProviderContainer(
      overrides: [
        firebaseAuthProvider.overrideWithValue(KakaoAuth()),
        loginPreferencesProvider.overrideWithValue(MemoryPreferences()),
        kakaoAccessTokenProvider.overrideWithValue(
          () async => throw KakaoLoginCancelled(),
        ),
        kakaoLoginHttpClientProvider.overrideWithValue(
          MockClient((_) async => throw StateError('must not request')),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container
        .read(authVmProvider.notifier)
        .signInWithKakao(autoLogin: true, rememberEmail: false);
    expect(container.read(authVmProvider).hasError, isFalse);
  });
}
