import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ondolbom/model/auth/password_reset_api.dart';

enum PasswordResetStep { email, code, password, done }

final passwordResetProvider =
    NotifierProvider.autoDispose<
      PasswordResetVm,
      AsyncValue<PasswordResetStep>
    >(PasswordResetVm.new);

class PasswordResetVm extends Notifier<AsyncValue<PasswordResetStep>> {
  String _email = '', _requestId = '', _token = '';
  PasswordResetStep step = PasswordResetStep.email;
  DateTime? resendAt;
  @override
  AsyncValue<PasswordResetStep> build() =>
      const AsyncData(PasswordResetStep.email);

  Future<void> _run(Future<void> Function(PasswordResetApi) action) async {
    if (state.isLoading) return;
    final api = ref.read(passwordResetApiProvider);
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
      final value = email.trim();
      if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(value)) {
        throw const PasswordResetFailure('이메일 형식을 확인해 주세요.');
      }
      final result = await api.post('request', {'email': value});
      if (!ref.mounted) return;
      _email = value;
      _requestId = result['request_id'] as String;
      _token = '';
      resendAt = DateTime.now().add(const Duration(seconds: 60));
      step = PasswordResetStep.code;
    });
  }

  Future<void> verify(String code) => _run((api) async {
    if (step != PasswordResetStep.code ||
        !RegExp(r'^\d{6}$').hasMatch(code.trim())) {
      throw const PasswordResetFailure('6자리 인증번호를 입력해 주세요.');
    }
    final result = await api.post('verify', {
      'email': _email,
      'request_id': _requestId,
      'code': code.trim(),
    });
    if (!ref.mounted) return;
    _token = result['reset_token'] as String;
    step = PasswordResetStep.password;
  });

  Future<void> confirm(String password, String confirmation) =>
      _run((api) async {
        if (step != PasswordResetStep.password ||
            password.length < 6 ||
            password.length > 128 ||
            password != confirmation) {
          throw const PasswordResetFailure('비밀번호 길이와 확인 입력을 확인해 주세요.');
        }
        await api.post('confirm', {
          'email': _email,
          'request_id': _requestId,
          'reset_token': _token,
          'password': password,
        });
        if (!ref.mounted) return;
        // 재설정 후 자동 로그인하지 않는다. 일회용 증명은 메모리에서도 지운다.
        _token = '';
        step = PasswordResetStep.done;
      });
}
