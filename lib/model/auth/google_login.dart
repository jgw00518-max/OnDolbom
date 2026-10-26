import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_sign_in/google_sign_in.dart';

// 테스트에서는 계정 선택 SDK를 실행하지 않고 자격증명으로 대체한다.
final googleCredentialProvider = Provider<Future<AuthCredential> Function()>(
  (ref) => GoogleLogin.credential,
);

class GoogleLoginCancelled implements Exception {}

/// Google SDK의 검증 가능한 ID 토큰을 Firebase 자격증명으로 변환한다.
class GoogleLogin {
  static Future<void>? _initialization;

  static Future<AuthCredential> credential() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      throw FirebaseAuthException(code: 'social-platform-not-configured');
    }
    final google = GoogleSignIn.instance;
    try {
      // 플러그인 초기화는 프로세스에서 한 번만 실행한다.
      try {
        await (_initialization ??= google.initialize());
      } catch (_) {
        _initialization = null;
        rethrow;
      }
      // 이전 Google 계정을 자동 재사용하지 않고 사용자가 계정을 선택하게 한다.
      await google.signOut();
      final account = await google.authenticate();
      final token = account.authentication.idToken;
      if (token == null || token.isEmpty) {
        throw FirebaseAuthException(code: 'invalid-google-token');
      }
      return GoogleAuthProvider.credential(idToken: token);
    } on GoogleSignInException catch (error) {
      if (error.code == GoogleSignInExceptionCode.canceled) {
        throw GoogleLoginCancelled();
      }
      // SDK 내부 메시지나 토큰을 화면·로그에 노출하지 않는다.
      throw FirebaseAuthException(code: 'google-login-configuration');
    }
  }
}
