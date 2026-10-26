import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ondolbom/vm/auth/auth_vm.dart';
import 'package:ondolbom/model/auth/login_preferences.dart';
import 'package:ondolbom/view/auth/password_reset_view.dart';

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
  bool _rememberEmail = false;
  bool _autoLogin = false;
  bool _preferencesBusy = true;
  String? _preferencesError;

  @override
  void initState() {
    super.initState();
    _restoreEmail();
  }

  Future<void> _restoreEmail() async {
    try {
      final email = await ref.read(loginPreferencesProvider).readEmail();
      final autoLogin = await ref
          .read(loginPreferencesProvider)
          .readAutoLogin();
      if (!mounted) return;
      // 복원 중 입력을 잠가 늦게 읽은 저장값이 사용자의 입력을 덮어쓰지 않게 한다.
      _email.text = email ?? '';
      _rememberEmail = email != null;
      _autoLogin = autoLogin;
    } catch (_) {
      if (mounted) _preferencesError = '저장한 아이디를 불러오지 못했습니다.';
    } finally {
      if (mounted) setState(() => _preferencesBusy = false);
    }
  }

  Future<void> _changeRememberEmail(bool value) async {
    if (value) {
      setState(() => _rememberEmail = true);
      return;
    }
    setState(() => _preferencesBusy = true);
    try {
      // 선택 해제 시에는 다음 로그인 성공을 기다리지 않고 즉시 삭제한다.
      await ref.read(loginPreferencesProvider).clearEmail();
      if (mounted) {
        setState(() {
          _rememberEmail = false;
          _preferencesError = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _preferencesError = '저장한 아이디를 삭제하지 못했습니다. 다시 시도해 주세요.');
      }
    } finally {
      if (mounted) setState(() => _preferencesBusy = false);
    }
  }

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
      vm.signIn(
        _email.text,
        _password.text,
        rememberEmail: _rememberEmail,
        autoLogin: _autoLogin,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final operation = ref.watch(authVmProvider);
    final busy = operation.isLoading || _preferencesBusy;
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
                      if (!_signUp)
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('아이디 저장'),
                          value: _rememberEmail,
                          controlAffinity: ListTileControlAffinity.leading,
                          onChanged: busy
                              ? null
                              : (value) => _changeRememberEmail(value ?? false),
                        ),
                      if (!_signUp)
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          title: const Text('자동 로그인'),
                          value: _autoLogin,
                          controlAffinity: ListTileControlAffinity.leading,
                          onChanged: busy
                              ? null
                              : (value) =>
                                    setState(() => _autoLogin = value ?? false),
                        ),
                      if (_preferencesError != null) Text(_preferencesError!),
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
                      if (!_signUp) ...[
                        TextButton(
                          onPressed: busy
                              ? null
                              : () => Navigator.of(context).push(
                                  MaterialPageRoute<void>(
                                    builder: (_) => PasswordResetView(
                                      initialEmail: _email.text.trim(),
                                    ),
                                  ),
                                ),
                          child: const Text('비밀번호 찾기'),
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton(
                          onPressed: busy
                              ? null
                              : () => ref
                                    .read(authVmProvider.notifier)
                                    .signInWithGoogle(
                                      autoLogin: _autoLogin,
                                      rememberEmail: _rememberEmail,
                                    ),
                          child: const Text('Google로 계속하기'),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton(
                          onPressed: busy
                              ? null
                              : () => ref
                                    .read(authVmProvider.notifier)
                                    .signInWithKakao(
                                      autoLogin: _autoLogin,
                                      rememberEmail: _rememberEmail,
                                    ),
                          child: const Text('카카오로 계속하기'),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton(
                          onPressed: busy
                              ? null
                              : () => ref
                                    .read(authVmProvider.notifier)
                                    .signInWithNaver(
                                      autoLogin: _autoLogin,
                                      rememberEmail: _rememberEmail,
                                    ),
                          child: const Text('네이버로 계속하기'),
                        ),
                      ],
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
