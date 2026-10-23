import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ondolbom/model/auth/app_user.dart';

final firebaseAuthProvider = Provider<FirebaseAuth>(
  (ref) => FirebaseAuth.instance,
);
final authUserProvider = StreamProvider<AppUser?>((ref) {
  return ref
      .watch(firebaseAuthProvider)
      .authStateChanges()
      .map(
        (user) =>
            user == null ? null : AppUser(uid: user.uid, email: user.email),
      );
});
final authVmProvider = NotifierProvider<AuthVm, AsyncValue<void>>(AuthVm.new);

class AuthVm extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncData(null);

  Future<void> signIn(String email, String password) => _run(() async {
    await ref
        .read(firebaseAuthProvider)
        .signInWithEmailAndPassword(email: email.trim(), password: password);
  });

  Future<void> signUp(String email, String password) => _run(() async {
    await ref
        .read(firebaseAuthProvider)
        .createUserWithEmailAndPassword(
          email: email.trim(),
          password: password,
        );
  });

  Future<void> signOut() =>
      _run(() => ref.read(firebaseAuthProvider).signOut());

  void clearError() {
    if (!state.isLoading) state = const AsyncData(null);
  }

  Future<void> _run(Future<void> Function() action) async {
    if (state.isLoading) return;
    state = const AsyncLoading();
    state = await AsyncValue.guard(action);
  }
}

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
