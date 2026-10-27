import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ondolbom/vm/auth/auth_vm.dart';
import 'package:ondolbom/vm/auth/signup_vm.dart';
import 'package:ondolbom/view/auth/widgets/signup_layout.dart';
import 'package:ondolbom/view/auth/widgets/signup_fields.dart';

class SignupView extends ConsumerStatefulWidget {
  const SignupView({super.key, this.initialEmail = ''});
  final String initialEmail;
  @override
  ConsumerState<SignupView> createState() => _SignupViewState();
}

class _SignupViewState extends ConsumerState<SignupView> {
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
    // 외부 이메일 앱에 다녀온 시간도 재발송 대기에 반영한다.
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
    final vm = ref.read(signupVmProvider.notifier);
    switch (vm.step) {
      case SignupStep.email:
        await vm.send(_email.text);
      case SignupStep.code:
        await vm.verify(_code.text);
      case SignupStep.password:
        await vm.complete(_password.text, _confirmation.text);
        _password.clear();
        _confirmation.clear();
        if (!mounted) return;
        if (!ref.read(signupVmProvider).hasError &&
            !ref.read(authVmProvider).hasError) {
          // 로그인 스트림이 Home으로 전환하므로 가입 화면만 닫는다.
          Navigator.of(context).pop();
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final operation = ref.watch(signupVmProvider);
    final vm = ref.read(signupVmProvider.notifier);
    final step = vm.step;
    final busy = operation.isLoading || ref.watch(authVmProvider).isLoading;
    final remaining = vm.resendAt?.difference(DateTime.now()).inSeconds ?? 0;
    return SignupLayout(
      step: step.index + 1,
      formKey: _form,
      busy: busy,
      error: operation.hasError ? authErrorMessage(operation.error!) : null,
      fields: [
        SignupFields(
          step: step,
          email: _email,
          code: _code,
          password: _password,
          confirmation: _confirmation,
          busy: busy,
          remaining: remaining,
          onResend: () async {
            await vm.send(_email.text);
            if (mounted) _code.clear();
          },
        ),
      ],
      onSubmit: _submit,
      onBack: () {
        ref.read(authVmProvider.notifier).clearError();
        Navigator.of(context).pop();
      },
    );
  }
}
