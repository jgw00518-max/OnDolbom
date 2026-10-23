import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ondolbom/model/auth/app_user.dart';

// 인증 SDK 접근 지점을 하나로 모아 사용하고 테스트에서는 대체할 수 있게 한다.
final firebaseAuthProvider = Provider<FirebaseAuth>(
  (ref) => FirebaseAuth.instance,
);
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
  Future<void> signIn(String email, String password) => _run(() async {
    await ref
        .read(firebaseAuthProvider)
        .signInWithEmailAndPassword(email: email.trim(), password: password);
  });

  // 계정 생성 성공 시 Firebase가 자동 로그인한다. 가족 프로필은 이후 별도 등록한다.
  Future<void> signUp(String email, String password) => _run(() async {
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
    _ => '인증에 실패했습니다. 잠시 후 다시 시도해 주세요.',
  };
}
