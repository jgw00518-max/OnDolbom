import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ondolbom/model/auth/app_user.dart';
import 'package:ondolbom/model/auth/login_preferences.dart';
import 'package:ondolbom/model/auth/google_login.dart';
import 'package:ondolbom/model/auth/kakao_login.dart';
import 'package:ondolbom/model/auth/naver_login.dart';
import 'package:ondolbom/vm/auth/user_profile_vm.dart' show apiBaseUrlProvider;

// 인증 SDK 접근 지점을 하나로 모아 사용하고 테스트에서는 대체할 수 있게 한다.
final firebaseAuthProvider = Provider<FirebaseAuth>(
  (ref) => FirebaseAuth.instance,
);

/// 앱 시작 시에만 적용한다. 로그인 중에는 현재 세션을 유지한다.
Future<void> restoreLoginSession(
  FirebaseAuth auth,
  LoginPreferences preferences,
) async {
  // 세션 복원이 끝난 뒤 검사하고 홈 화면 표시 전에 미선택 세션을 종료한다.
  await auth.authStateChanges().first;
  if (!await preferences.readAutoLogin()) {
    await auth.signOut();
  }
}

// Firebase가 복원한 로그인 상태와 가입·로그인·로그아웃 결과를 화면에 전달한다.
// null은 비로그인이며, Firebase 인증만으로 MySQL 프로필 등록을 보장하지 않는다.
final authUserProvider = StreamProvider<AppUser?>((ref) {
  return ref
      .watch(firebaseAuthProvider)
      .authStateChanges()
      .map(
        (user) =>
            user == null ? null : AppUser(uid: user.uid, email: user.email),
      );
});
// 인증 동작의 진행·실패 상태. 로그인 사용자 데이터는 위 스트림에서 관리한다.
final authVmProvider = NotifierProvider<AuthVm, AsyncValue<void>>(AuthVm.new);

class AuthVm extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  // 이메일 공백만 정리하고 비밀번호 원문은 변경하지 않는다.
  Future<void> signIn(
    String email,
    String password, {
    bool? rememberEmail,
    bool? autoLogin,
  }) => _run(() async {
    // 인증 성공 직후 화면이 바뀌어도 완료할 수 있도록 저장 객체를 먼저 확보한다.
    final preferences = rememberEmail == null && autoLogin == null
        ? null
        : ref.read(loginPreferencesProvider);
    final auth = ref.read(firebaseAuthProvider);
    if (autoLogin != null) {
      // 실패한 로그인에서 이전 계정의 자동 로그인 설정을 재사용하지 않는다.
      await preferences!.saveAutoLogin(false);
    }
    await auth.signInWithEmailAndPassword(
      email: email.trim(),
      password: password,
    );
    if (autoLogin == true) {
      try {
        await preferences!.saveAutoLogin(true);
      } catch (_) {
        // 옵션 저장 실패 시 세션도 종료해 선택과 실제 동작을 일치시킨다.
        await auth.signOut();
        rethrow;
      }
    }
    // 실패한 로그인 이메일은 기존 저장값을 덮어쓰지 않는다.
    if (preferences != null && rememberEmail != null) {
      try {
        if (rememberEmail == true) {
          await preferences.saveEmail(email);
        } else {
          await preferences.clearEmail();
        }
      } catch (_) {
        // 기기 저장 실패를 로그인 실패로 처리하지 않는다. 개인정보는 로그에 남기지 않는다.
        debugPrint('로그인은 완료했지만 아이디 저장 설정을 반영하지 못했습니다.');
      }
    }
  });

  // 최초 Google 인증은 가입, 이후 인증은 로그인이다. MySQL 프로필은 기존 흐름을 사용한다.
  Future<void> signInWithGoogle({
    required bool autoLogin,
    required bool rememberEmail,
  }) => _run(() async {
    final auth = ref.read(firebaseAuthProvider);
    final preferences = ref.read(loginPreferencesProvider);
    final loadCredential = ref.read(googleCredentialProvider);
    await preferences.saveAutoLogin(false);
    AuthCredential credential;
    try {
      credential = await loadCredential();
    } on GoogleLoginCancelled {
      return; // 계정 선택 취소는 로그인 오류로 표시하지 않는다.
    }
    final result = await auth.signInWithCredential(credential);
    if (autoLogin) {
      try {
        await preferences.saveAutoLogin(true);
      } catch (_) {
        await auth.signOut();
        rethrow;
      }
    }
    try {
      final email = result.user?.email;
      if (rememberEmail && email != null && email.isNotEmpty) {
        await preferences.saveEmail(email);
      } else {
        await preferences.clearEmail();
      }
    } catch (_) {
      debugPrint('로그인은 완료했지만 아이디 저장 설정을 반영하지 못했습니다.');
    }
  });

  Future<void> signInWithKakao({
    required bool autoLogin,
    required bool rememberEmail,
  }) => _run(() async {
    final auth = ref.read(firebaseAuthProvider);
    final preferences = ref.read(loginPreferencesProvider);
    final loadAccessToken = ref.read(kakaoAccessTokenProvider);
    final exchange = ref.read(kakaoTokenExchangeProvider);
    final baseUrl = ref.read(apiBaseUrlProvider);
    await preferences.saveAutoLogin(false);
    String accessToken;
    try {
      accessToken = await waitForKakaoLogin(loadAccessToken);
    } on KakaoLoginCancelled {
      return;
    }
    // 서버가 검증·발급한 Firebase 토큰으로 기존 인증·권한 흐름에 합류한다.
    final customToken = await exchange(baseUrl, accessToken);
    final result = await auth.signInWithCustomToken(customToken);
    if (autoLogin) {
      try {
        await preferences.saveAutoLogin(true);
      } catch (_) {
        await auth.signOut();
        rethrow;
      }
    }
    try {
      final email = result.user?.email;
      if (rememberEmail && email != null && email.isNotEmpty) {
        await preferences.saveEmail(email);
      } else {
        await preferences.clearEmail();
      }
    } catch (_) {
      debugPrint('로그인은 완료했지만 아이디 저장 설정을 반영하지 못했습니다.');
    }
  });

  Future<void> signInWithNaver({
    required bool autoLogin,
    required bool rememberEmail,
  }) => _run(() async {
    final auth = ref.read(firebaseAuthProvider);
    final preferences = ref.read(loginPreferencesProvider);
    final login = ref.read(naverCustomTokenProvider);
    final baseUrl = ref.read(apiBaseUrlProvider);
    await preferences.saveAutoLogin(false);
    String customToken;
    try {
      customToken = await login(baseUrl);
    } on NaverLoginCancelled {
      return;
    }
    final result = await auth.signInWithCustomToken(customToken);
    if (autoLogin) {
      try {
        await preferences.saveAutoLogin(true);
      } catch (_) {
        await auth.signOut();
        rethrow;
      }
    }
    try {
      final email = result.user?.email;
      if (rememberEmail && email != null && email.isNotEmpty) {
        await preferences.saveEmail(email);
      } else {
        await preferences.clearEmail();
      }
    } catch (_) {
      debugPrint('로그인은 완료했지만 아이디 저장 설정을 반영하지 못했습니다.');
    }
  });

  // 계정 생성 성공 시 Firebase가 자동 로그인한다. 가족 프로필은 이후 별도 등록한다.
  Future<void> signUp(String email, String password) => _run(() async {
    // 가입 직후 세션은 유지하지만 재실행 자동 로그인은 별도 선택이 필요하다.
    await ref.read(loginPreferencesProvider).saveAutoLogin(false);
    await ref
        .read(firebaseAuthProvider)
        .createUserWithEmailAndPassword(
          email: email.trim(),
          password: password,
        );
  });

  // SDK 로그아웃 결과가 인증 스트림에 반영되면 앱이 로그인 화면으로 전환된다.
  Future<void> signOut() =>
      _run(() => ref.read(firebaseAuthProvider).signOut());

  void clearError() {
    if (!state.isLoading) state = const AsyncData(null);
  }

  Future<void> _run(Future<void> Function() action) async {
    // 연속 클릭을 막고 예외를 화면에서 표시할 AsyncError 상태로 바꾼다.
    if (state.isLoading) return;
    state = const AsyncLoading();
    state = await AsyncValue.guard(action);
  }
}

// SDK 예외 원문 대신 사용자에게 필요한 한국어 안내만 반환한다.
String authErrorMessage(Object error) {
  if (error is NaverLoginFailure) return error.message;
  if (error is KakaoLoginFailure) return error.message;
  if (error is! FirebaseAuthException) return '요청을 처리하지 못했습니다. 다시 시도해 주세요.';
  return switch (error.code) {
    'invalid-email' => '이메일 형식을 확인해 주세요.',
    'weak-password' => '비밀번호가 보안 기준에 맞지 않습니다. 더 강한 비밀번호를 입력해 주세요.',
    'email-already-in-use' => '이미 가입된 이메일입니다. 로그인해 주세요.',
    'invalid-credential' ||
    'user-not-found' ||
    'wrong-password' => '이메일 또는 비밀번호를 확인해 주세요.',
    'user-disabled' => '사용이 중지된 계정입니다.',
    'network-request-failed' => '네트워크 연결을 확인해 주세요.',
    'too-many-requests' => '요청이 많습니다. 잠시 후 다시 시도해 주세요.',
    'operation-not-allowed' => '이메일·비밀번호 로그인 설정을 확인해 주세요.',
    'google-login-configuration' =>
      'Google 로그인 설정을 확인해 주세요. Firebase의 SHA 지문과 Android 설정 파일이 필요합니다.',
    'invalid-google-token' => 'Google 인증 정보를 확인하지 못했습니다. 다시 시도해 주세요.',
    'social-platform-not-configured' => '현재 Google 로그인은 Android에서 지원합니다.',
    'account-exists-with-different-credential' ||
    'credential-already-in-use' => '기존 가입 방식으로 로그인해 주세요. 계정 연결이 필요합니다.',
    _ => '인증에 실패했습니다. 잠시 후 다시 시도해 주세요.',
  };
}
