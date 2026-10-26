import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ondolbom/model/auth/signup_api.dart';
import 'package:ondolbom/vm/auth/auth_vm.dart';

enum SignupStep { email, code, password }

final signupVmProvider =
    NotifierProvider.autoDispose<SignupVm, AsyncValue<SignupStep>>(
      SignupVm.new,
    );

class SignupVm extends Notifier<AsyncValue<SignupStep>> {
  String _email = '', _requestId = '', _token = '';
  SignupStep step = SignupStep.email;
  DateTime? resendAt;

  @override
  AsyncValue<SignupStep> build() => const AsyncData(SignupStep.email);

  Future<void> _run(Future<void> Function(SignupApi) action) async {
    if (state.isLoading) return;
    final api = ref.read(signupApiProvider);
    state = const AsyncLoading();
    try {
      await action(api);
      if (ref.mounted) state = AsyncData(step);
    } catch (error, stack) {
      if (ref.mounted) state = AsyncError(error, stack);
    }
  }

  Future<void> send(String email) async {
    if (resendAt != null && DateTime.now().isBefore(resendAt!)) return;
    await _run((api) async {
      final value = email.trim().toLowerCase();
      if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value)) {
        throw const SignupFailure('이메일 형식을 확인해 주세요.');
      }
      final result = await api.post('request', {'email': value});
      if (!ref.mounted) return;
      _email = value;
      _requestId = result['request_id'] as String;
      _token = '';
      resendAt = DateTime.now().add(const Duration(seconds: 60));
      step = SignupStep.code;
    });
  }

  Future<void> verify(String code) => _run((api) async {
    if (step != SignupStep.code || !RegExp(r'^\d{6}$').hasMatch(code.trim())) {
      throw const SignupFailure('6자리 인증번호를 입력해 주세요.');
    }
    final result = await api.post('verify', {
      'email': _email,
      'request_id': _requestId,
      'code': code.trim(),
    });
    if (!ref.mounted) return;
    _token = result['verification_token'] as String;
    step = SignupStep.password;
  });

  Future<void> complete(String password, String confirmation) => _run((
    _,
  ) async {
    if (step != SignupStep.password ||
        _token.isEmpty ||
        password.length < 6 ||
        password.length > 128 ||
        password != confirmation) {
      throw const SignupFailure('이메일 인증과 비밀번호 확인을 완료해 주세요. 비밀번호는 6~128자입니다.');
    }
    // 가입 API 호출과 이후 Firebase 로그인은 AuthVm에서 기존 인증 스트림으로 연결한다.
    final authVm = ref.read(authVmProvider.notifier);
    await authVm.signUp(
      _email,
      password,
      requestId: _requestId,
      verificationToken: _token,
    );
    if (!ref.mounted) return;
    final operation = ref.read(authVmProvider);
    if (operation.hasError) throw operation.error!;
    _token = '';
  });
}
