import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ondolbom/vm/auth/auth_vm.dart';
import 'package:ondolbom/vm/auth/signup_vm.dart';

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
    return Scaffold(
      appBar: AppBar(title: const Text('이메일 회원가입')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Form(
                key: _form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(switch (step) {
                      SignupStep.email => '이메일 인증을 완료한 후 회원가입할 수 있습니다.',
                      SignupStep.code =>
                        '가입 가능한 이메일이면 인증번호가 발송됩니다. 이메일에서 확인한 6자리 번호를 10분 안에 입력해 주세요. 기존 계정은 로그인 화면을 이용해 주세요.',
                      SignupStep.password =>
                        '이메일 인증이 완료되었습니다. 5분 안에 비밀번호를 설정해 가입해 주세요. 이름과 전화번호는 가입 후 입력합니다.',
                    }),
                    const SizedBox(height: 24),
                    TextFormField(
                      controller: _email,
                      enabled: !busy && step == SignupStep.email,
                      decoration: const InputDecoration(labelText: '이메일'),
                      keyboardType: TextInputType.emailAddress,
                      autocorrect: false,
                      validator: (value) =>
                          RegExp(
                            r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                          ).hasMatch(value?.trim() ?? '')
                          ? null
                          : '이메일 형식을 확인해 주세요.',
                    ),
                    if (step == SignupStep.code) ...[
                      TextFormField(
                        controller: _code,
                        enabled: !busy,
                        decoration: const InputDecoration(labelText: '인증번호'),
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                          LengthLimitingTextInputFormatter(6),
                        ],
                        validator: (value) =>
                            RegExp(r'^\d{6}$').hasMatch(value ?? '')
                            ? null
                            : '6자리 인증번호를 입력해 주세요.',
                      ),
                      TextButton(
                        onPressed: busy || remaining > 0
                            ? null
                            : () async {
                                await vm.send(_email.text);
                                if (mounted) _code.clear();
                              },
                        child: Text(
                          remaining > 0
                              ? '${remaining + 1}초 후 다시 보내기'
                              : '인증번호 다시 보내기',
                        ),
                      ),
                    ],
                    if (step == SignupStep.password) ...[
                      TextFormField(
                        controller: _password,
                        enabled: !busy,
                        obscureText: true,
                        decoration: const InputDecoration(labelText: '비밀번호'),
                        validator: (value) =>
                            (value?.length ?? 0) >= 6 &&
                                (value?.length ?? 0) <= 128
                            ? null
                            : '비밀번호는 6~128자로 입력해 주세요.',
                      ),
                      TextFormField(
                        controller: _confirmation,
                        enabled: !busy,
                        obscureText: true,
                        decoration: const InputDecoration(labelText: '비밀번호 확인'),
                        validator: (value) =>
                            value == _password.text ? null : '비밀번호가 일치하지 않습니다.',
                      ),
                    ],
                    if (operation.hasError)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Text(authErrorMessage(operation.error!)),
                      ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: busy ? null : _submit,
                      child: Text(
                        busy
                            ? '처리 중…'
                            : switch (step) {
                                SignupStep.email => '인증번호 전송',
                                SignupStep.code => '인증번호 확인',
                                SignupStep.password => '이메일로 가입',
                              },
                      ),
                    ),
                    TextButton(
                      onPressed: busy
                          ? null
                          : () {
                              ref.read(authVmProvider.notifier).clearError();
                              Navigator.of(context).pop();
                            },
                      child: const Text('로그인으로 돌아가기'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
