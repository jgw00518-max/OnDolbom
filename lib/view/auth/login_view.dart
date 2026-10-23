import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ondolbom/vm/auth/auth_vm.dart';

/// 이메일 인증 화면. 로그인 후 Home의 별도 폼에서 MySQL 가족 프로필을 등록한다.
class LoginView extends ConsumerStatefulWidget {
  const LoginView({super.key});
  @override
  ConsumerState<LoginView> createState() => _LoginViewState();
}

class _LoginViewState extends ConsumerState<LoginView> {
  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _confirmation = TextEditingController();
  bool _signUp = false;

  @override
  void dispose() {
    // 화면 종료 시 비밀번호를 포함한 입력 컨트롤러를 정리한다.
    _email.dispose();
    _password.dispose();
    _confirmation.dispose();
    super.dispose();
  }

  void _submit() {
    // 화면 입력 검증 후 VM에 위임한다. 서버 호출이나 인증 SDK는 화면에서 직접 쓰지 않는다.
    if (!_form.currentState!.validate()) return;
    final vm = ref.read(authVmProvider.notifier);
    if (_signUp) {
      vm.signUp(_email.text, _password.text);
    } else {
      vm.signIn(_email.text, _password.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final operation = ref.watch(authVmProvider);
    final busy = operation.isLoading;
    return Scaffold(
      appBar: AppBar(title: Text(_signUp ? '이메일 회원가입' : '온돌봄 로그인')),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: AutofillGroup(
                child: Form(
                  key: _form,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextFormField(
                        controller: _email,
                        enabled: !busy,
                        decoration: const InputDecoration(labelText: '이메일'),
                        keyboardType: TextInputType.emailAddress,
                        autofillHints: const [AutofillHints.email],
                        autocorrect: false,
                        validator: (value) {
                          final email = value?.trim() ?? '';
                          if (email.isEmpty) return '이메일을 입력해 주세요.';
                          if (!RegExp(
                            r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                          ).hasMatch(email)) {
                            return '이메일 형식을 확인해 주세요.';
                          }
                          return null;
                        },
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _password,
                        enabled: !busy,
                        obscureText: true,
                        decoration: const InputDecoration(labelText: '비밀번호'),
                        autofillHints: [
                          _signUp
                              ? AutofillHints.newPassword
                              : AutofillHints.password,
                        ],
                        enableSuggestions: false,
                        autocorrect: false,
                        validator: (value) => value == null || value.isEmpty
                            ? '비밀번호를 입력해 주세요.'
                            : null,
                        onFieldSubmitted: (_) {
                          if (!busy && !_signUp) _submit();
                        },
                      ),
                      // 가입 모드에서만 비밀번호 확인을 추가한다.
                      if (_signUp) ...[
                        const SizedBox(height: 16),
                        TextFormField(
                          controller: _confirmation,
                          enabled: !busy,
                          obscureText: true,
                          decoration: const InputDecoration(
                            labelText: '비밀번호 확인',
                          ),
                          enableSuggestions: false,
                          autocorrect: false,
                          validator: (value) => value != _password.text
                              ? '비밀번호가 일치하지 않습니다.'
                              : null,
                          onFieldSubmitted: (_) {
                            if (!busy) _submit();
                          },
                        ),
                      ],
                      if (operation.hasError)
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Text(
                            authErrorMessage(operation.error!),
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: busy ? null : _submit,
                        child: Text(
                          busy ? '처리 중…' : (_signUp ? '이메일로 가입' : '로그인'),
                        ),
                      ),
                      TextButton(
                        onPressed: busy
                            ? null
                            : () {
                                ref.read(authVmProvider.notifier).clearError();
                                // 모드 전환 시 이전 비밀번호·오류를 남기지 않는다.
                                _password.clear();
                                _confirmation.clear();
                                _form.currentState?.reset();
                                setState(() => _signUp = !_signUp);
                              },
                        child: Text(_signUp ? '로그인으로 돌아가기' : '이메일로 회원가입'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
