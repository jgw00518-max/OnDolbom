import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ondolbom/vm/auth/auth_vm.dart';
import 'package:ondolbom/model/auth/login_preferences.dart';
import 'package:ondolbom/view/auth/password_reset_view.dart';
import 'package:ondolbom/view/auth/signup_view.dart';
import 'package:ondolbom/view/auth/widgets/login_layout.dart';

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
    super.dispose();
  }

  void _submit() {
    // 화면 입력 검증 후 VM에 위임한다. 서버 호출이나 인증 SDK는 화면에서 직접 쓰지 않는다.
    if (!_form.currentState!.validate()) return;
    final vm = ref.read(authVmProvider.notifier);
    vm.signIn(
      _email.text,
      _password.text,
      rememberEmail: _rememberEmail,
      autoLogin: _autoLogin,
    );
  }

  @override
  Widget build(BuildContext context) {
    final operation = ref.watch(authVmProvider);
    final busy = operation.isLoading || _preferencesBusy;
    return LoginLayout(
      formKey: _form,
      email: _email,
      password: _password,
      busy: busy,
      rememberEmail: _rememberEmail,
      autoLogin: _autoLogin,
      preferencesError: _preferencesError,
      authError: operation.hasError ? authErrorMessage(operation.error!) : null,
      onSubmit: _submit,
      onRememberEmail: _changeRememberEmail,
      onAutoLogin: (value) => setState(() => _autoLogin = value),
      onPasswordReset: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PasswordResetView(initialEmail: _email.text.trim()),
        ),
      ),
      onGoogle: () => ref
          .read(authVmProvider.notifier)
          .signInWithGoogle(
            autoLogin: _autoLogin,
            rememberEmail: _rememberEmail,
          ),
      onKakao: () => ref
          .read(authVmProvider.notifier)
          .signInWithKakao(
            autoLogin: _autoLogin,
            rememberEmail: _rememberEmail,
          ),
      onNaver: () => ref
          .read(authVmProvider.notifier)
          .signInWithNaver(
            autoLogin: _autoLogin,
            rememberEmail: _rememberEmail,
          ),
      onSignup: () {
        ref.read(authVmProvider.notifier).clearError();
        _password.clear();
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => SignupView(initialEmail: _email.text.trim()),
          ),
        );
      },
    );
  }
}
