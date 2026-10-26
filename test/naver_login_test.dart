import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ondolbom/model/auth/login_preferences.dart';
import 'package:ondolbom/model/auth/naver_login.dart';
import 'package:ondolbom/vm/auth/auth_vm.dart';

import 'kakao_login_test.dart' show KakaoAuth;
import 'login_preferences_test.dart' show MemoryPreferences;

const stateValue = 'server-random-state';
http.Response startResponse() => http.Response(
  jsonEncode({
    'state': stateValue,
    'authorization_url':
        'https://nid.naver.com/oauth2.0/authorize?state=$stateValue',
  }),
  200,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('앱 전용 난수로 서버 코드 교환을 수행하고 기존 로그인 옵션을 유지한다', () async {
    final auth = KakaoAuth();
    final preferences = MemoryPreferences();
    String? challenge;
    final container = ProviderContainer(
      overrides: [
        firebaseAuthProvider.overrideWithValue(auth),
        loginPreferencesProvider.overrideWithValue(preferences),
        naverBrowserProvider.overrideWithValue(
          (url) async =>
              'ondolbomnaver://oauth?state=$stateValue&code=provider-code',
        ),
        naverHttpClientProvider.overrideWithValue(
          MockClient((request) async {
            final body = jsonDecode(request.body) as Map<String, dynamic>;
            expect(body.containsKey('client_secret'), isFalse);
            if (request.url.path.endsWith('/start')) {
              challenge = body['challenge'] as String;
              return startResponse();
            }
            expect(request.url.path, '/auth/naver/exchange');
            expect(
              sha256
                  .convert(utf8.encode(body['verifier'] as String))
                  .toString(),
              challenge,
            );
            expect(body['code'], 'provider-code');
            return http.Response('{"custom_token":"server-verified"}', 200);
          }),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container
        .read(authVmProvider.notifier)
        .signInWithNaver(autoLogin: true, rememberEmail: true);
    expect(auth.customToken, 'server-verified');
    expect(preferences.autoLogin, isTrue);
    expect(preferences.email, 'google@example.com');
  });

  test('다른 state의 응답은 코드 교환 전에 차단한다', () async {
    var calls = 0;
    final client = MockClient((_) async {
      calls++;
      return startResponse();
    });
    await expectLater(
      NaverLogin.authenticate(
        'http://localhost:8000',
        client,
        (_) async => 'ondolbomnaver://oauth?state=foreign&code=forged',
      ),
      throwsA(isA<NaverLoginFailure>()),
    );
    expect(calls, 1);
    client.close();
  });

  test('브라우저 취소 시 Firebase 로그인과 자동 로그인 설정을 진행하지 않는다', () async {
    final auth = KakaoAuth();
    final preferences = MemoryPreferences();
    final container = ProviderContainer(
      overrides: [
        firebaseAuthProvider.overrideWithValue(auth),
        loginPreferencesProvider.overrideWithValue(preferences),
        naverBrowserProvider.overrideWithValue(
          (_) async => throw PlatformException(code: 'CANCELED'),
        ),
        naverHttpClientProvider.overrideWithValue(
          MockClient((_) async => startResponse()),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container
        .read(authVmProvider.notifier)
        .signInWithNaver(autoLogin: true, rememberEmail: false);
    expect(container.read(authVmProvider).hasError, isFalse);
    expect(auth.customToken, isNull);
    expect(preferences.autoLogin, isFalse);
  });
}
