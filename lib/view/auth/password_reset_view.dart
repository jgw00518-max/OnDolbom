import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ondolbom/vm/auth/password_reset_vm.dart';
import 'package:ondolbom/view/auth/widgets/signup_layout.dart';
import 'package:ondolbom/view/auth/widgets/password_reset_fields.dart';

class PasswordResetView extends ConsumerStatefulWidget {
  const PasswordResetView({super.key, this.initialEmail = ''});
  final String initialEmail;
  @override
  ConsumerState<PasswordResetView> createState() => _PasswordResetViewState();
}

class _PasswordResetViewState extends ConsumerState<PasswordResetView> {
  static const _resetLabel = '비밀번호 재설정';
  static const _asideHeading = '새 비밀번호로\n안전하게 시작해요.';
  static const _asideDescription = '이메일 인증 후 비밀번호를 재설정하고 온돌봄을 계속 이용해 보세요.';
  String _title(PasswordResetStep step) => switch (step) {
    PasswordResetStep.email => '비밀번호 찾기',
    PasswordResetStep.code => '인증번호 확인',
    PasswordResetStep.password => '새 비밀번호 설정',
    PasswordResetStep.done => '재설정 완료',
  };
  String _description(PasswordResetStep step) => switch (step) {
    PasswordResetStep.email => '가입한 이메일 주소를 입력해 주세요.',
    PasswordResetStep.code => '이메일에서 확인한 인증번호를 입력해 주세요.',
    PasswordResetStep.password => '안전하게 사용할 새 비밀번호를 입력해 주세요.',
    PasswordResetStep.done => '새 비밀번호로 온돌봄을 계속 이용해 보세요.',
  };
  String _buttonLabel(PasswordResetStep step) => switch (step) {
    PasswordResetStep.email => '인증번호 전송',
    PasswordResetStep.code => '인증번호 확인',
    PasswordResetStep.password => '비밀번호 재설정',
    PasswordResetStep.done => '로그인으로 돌아가기',
  };
  final _form = GlobalKey<FormState>();
  late final TextEditingController _email;
  final _code = TextEditingController(),
      _password = TextEditingController(),
      _confirmation = TextEditingController();
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    _email = TextEditingController(text: widget.initialEmail);
    // 외부 메일 앱에 다녀온 시간도 DateTime 기준으로 반영한다.
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    for (final controller in [_email, _code, _password, _confirmation]) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_form.currentState!.validate()) return;
    final vm = ref.read(passwordResetProvider.notifier);
    switch (vm.step) {
      case PasswordResetStep.email:
        await vm.send(_email.text);
      case PasswordResetStep.code:
        await vm.verify(_code.text);
      case PasswordResetStep.password:
        await vm.confirm(_password.text, _confirmation.text);
        _password.clear();
        _confirmation.clear();
      case PasswordResetStep.done:
        if (mounted) Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final request = ref.watch(passwordResetProvider);
    final vm = ref.read(passwordResetProvider.notifier);
    final step = vm.step;
    final remaining = vm.resendAt?.difference(DateTime.now()).inSeconds ?? 0;
    return SignupLayout(
      step: (step.index + 1).clamp(1, 3),
      formKey: _form,
      busy: request.isLoading,
      error: request.hasError ? request.error.toString() : null,
      title: _title(step),
      description: _description(step),
      buttonLabel: _buttonLabel(step),
      eyebrow: step == PasswordResetStep.done ? 'PASSWORD RESET' : null,
      asideEyebrow: 'RESET PASSWORD',
      stepLabel: _resetLabel,
      asideHeading: _asideHeading,
      asideDescription: _asideDescription,
      showBack: step != PasswordResetStep.done,
      allowBackWhileBusy: true,
      fields: [
        PasswordResetFields(
          step: step,
          email: _email,
          code: _code,
          password: _password,
          confirmation: _confirmation,
          busy: request.isLoading,
          remaining: remaining,
          onResend: () async {
            await vm.send(_email.text);
            if (mounted) _code.clear();
          },
        ),
      ],
      onSubmit: _submit,
      onBack: () => Navigator.of(context).pop(),
    );
  }
}
