import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ondolbom/vm/auth/password_reset_vm.dart';

class PasswordResetView extends ConsumerStatefulWidget {
  const PasswordResetView({super.key, this.initialEmail = ''});
  final String initialEmail;
  @override
  ConsumerState<PasswordResetView> createState() => _PasswordResetViewState();
}

class _PasswordResetViewState extends ConsumerState<PasswordResetView> {
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
    return Scaffold(
      appBar: AppBar(title: const Text('비밀번호 찾기')),
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
                      PasswordResetStep.email =>
                        '가입한 이메일로 인증번호를 보냅니다. Google·카카오·네이버 전용 계정은 해당 로그인 버튼을 이용해 주세요.',
                      PasswordResetStep.code =>
                        '재설정 가능한 계정이면 인증번호가 발송됩니다. 이메일에 로그인해 받은편지함·스팸함을 확인한 후 앱에 6자리 인증번호를 입력해 주세요. 유효시간은 10분입니다.',
                      PasswordResetStep.password =>
                        '이메일 확인이 완료되었습니다. 5분 안에 새 비밀번호를 설정해 주세요.',
                      PasswordResetStep.done =>
                        '비밀번호가 변경되었습니다. 새 비밀번호로 로그인해 주세요.',
                    }),
                    const SizedBox(height: 24),
                    if (step == PasswordResetStep.email ||
                        step == PasswordResetStep.code)
                      TextFormField(
                        controller: _email,
                        enabled:
                            !request.isLoading &&
                            step == PasswordResetStep.email,
                        decoration: const InputDecoration(labelText: '가입 이메일'),
                        keyboardType: TextInputType.emailAddress,
                        autocorrect: false,
                        validator: (value) =>
                            RegExp(
                              r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                            ).hasMatch(value?.trim() ?? '')
                            ? null
                            : '이메일 형식을 확인해 주세요.',
                      ),
                    if (step == PasswordResetStep.code) ...[
                      TextFormField(
                        controller: _code,
                        enabled: !request.isLoading,
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
                        onPressed: request.isLoading || remaining > 0
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
                    if (step == PasswordResetStep.password) ...[
                      TextFormField(
                        controller: _password,
                        enabled: !request.isLoading,
                        obscureText: true,
                        decoration: const InputDecoration(labelText: '새 비밀번호'),
                        validator: (value) =>
                            (value?.length ?? 0) >= 6 &&
                                (value?.length ?? 0) <= 128
                            ? null
                            : '비밀번호는 6~128자로 입력해 주세요.',
                      ),
                      TextFormField(
                        controller: _confirmation,
                        enabled: !request.isLoading,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: '새 비밀번호 확인',
                        ),
                        validator: (value) =>
                            value == _password.text ? null : '비밀번호가 일치하지 않습니다.',
                      ),
                    ],
                    if (request.hasError)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Text(request.error.toString()),
                      ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: request.isLoading ? null : _submit,
                      child: Text(
                        request.isLoading
                            ? '처리 중…'
                            : switch (step) {
                                PasswordResetStep.email => '인증번호 전송',
                                PasswordResetStep.code => '인증번호 확인',
                                PasswordResetStep.password => '비밀번호 재설정',
                                PasswordResetStep.done => '로그인으로 돌아가기',
                              },
                      ),
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
