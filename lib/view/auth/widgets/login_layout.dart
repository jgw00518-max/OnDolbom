import 'package:ondolbom/theme/app_colors.dart';
import 'package:flutter/material.dart';

/// 첨부한 App.tsx/index.css의 표시만 담당한다. 인증 콜백·입력값은 LoginView가 관리한다.
class LoginLayout extends StatelessWidget {
  const LoginLayout({
    super.key,
    required this.formKey,
    required this.email,
    required this.password,
    required this.busy,
    required this.rememberEmail,
    required this.autoLogin,
    required this.onSubmit,
    required this.onRememberEmail,
    required this.onAutoLogin,
    required this.onPasswordReset,
    required this.onGoogle,
    required this.onKakao,
    required this.onNaver,
    required this.onSignup,
    this.preferencesError,
    this.authError,
  });
  final GlobalKey<FormState> formKey;
  final TextEditingController email, password;
  final bool busy, rememberEmail, autoLogin;
  final String? preferencesError, authError;
  final VoidCallback onSubmit,
      onPasswordReset,
      onGoogle,
      onKakao,
      onNaver,
      onSignup;
  final ValueChanged<bool> onRememberEmail, onAutoLogin;

  static const _ink = AppColors.textPrimary;
  static const _peach = AppColors.primary;
  static const _sage = AppColors.sage;
  static const _paper = AppColors.background;
  static const _muted = Color(0xFF716B68);
  static const _line = Color(0xFFE6DED9);

  InputDecoration _decoration(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: Color(0xFFB3AAA5), fontSize: 14),
    filled: true,
    fillColor: _paper,
    isDense: true,
    constraints: const BoxConstraints(minHeight: 52),
    contentPadding: const EdgeInsets.symmetric(horizontal: 17, vertical: 16),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(13),
      borderSide: const BorderSide(color: _line),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(13),
      borderSide: const BorderSide(color: _line),
    ),
    disabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(13),
      borderSide: const BorderSide(color: _line),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(13),
      borderSide: const BorderSide(color: _peach),
    ),
    errorMaxLines: 2,
  );

  Widget _check(String label, bool value, ValueChanged<bool> change) => InkWell(
    onTap: busy ? null : () => change(!value),
    borderRadius: BorderRadius.circular(5),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 16,
            height: 16,
            child: Checkbox(
              value: value,
              onChanged: busy ? null : (v) => change(v ?? false),
              fillColor: WidgetStateProperty.resolveWith(
                (states) => states.contains(WidgetState.selected)
                    ? _sage
                    : Colors.white,
              ),
              checkColor: _ink,
              side: const BorderSide(color: Color(0xFFD8CDC7)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(5),
              ),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ),
          const SizedBox(width: 7),
          Text(label, style: const TextStyle(color: _muted, fontSize: 12)),
        ],
      ),
    ),
  );

  Widget _options(bool stacked) {
    final checks = [
      _check('아이디 저장', rememberEmail, onRememberEmail),
      SizedBox(width: stacked ? 0 : 16, height: stacked ? 10 : 0),
      _check('자동 로그인', autoLogin, onAutoLogin),
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 17, bottom: 24),
      child: Row(
        crossAxisAlignment: stacked
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.center,
        children: [
          if (stacked)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: checks,
            )
          else
            Row(mainAxisSize: MainAxisSize.min, children: checks),
          const SizedBox(width: 12),
          Expanded(
            child: Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: busy ? null : onPasswordReset,
                style: TextButton.styleFrom(
                  foregroundColor: _ink,
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 24),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text(
                  '비밀번호 찾기',
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontSize: 12,
                    decoration: TextDecoration.underline,
                    height: 1.5,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _social(String label, String assetPath, VoidCallback callback) =>
      Tooltip(
        message: label,
        child: Semantics(
          label: label,
          button: true,
          child: SizedBox(
            width: 48,
            height: 48,
            child: OutlinedButton(
              onPressed: busy ? null : callback,
              style: OutlinedButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(48, 48),
                backgroundColor: Colors.transparent,
                disabledBackgroundColor: Colors.transparent,
                side: BorderSide.none,
                shape: const CircleBorder(),
              ),
              // 배경을 포함한 공식 이미지를 버튼 전체에 표시하고 기존 인증 동작을 유지한다.
              child: Opacity(
                opacity: busy ? 0.45 : 1,
                child: Image.asset(
                  assetPath,
                  width: 48,
                  height: 48,
                  fit: BoxFit.contain,
                  excludeFromSemantics: true,
                ),
              ),
            ),
          ),
        ),
      );

  Widget _formPanel({
    required bool mobile,
    required bool stackedChecks,
    required double horizontalPadding,
  }) => Padding(
    padding: EdgeInsets.fromLTRB(
      horizontalPadding,
      mobile ? 32 : 50,
      horizontalPadding,
      mobile ? 44 : 50,
    ),
    child: AutofillGroup(
      child: Form(
        key: formKey,
        child: Column(
          mainAxisAlignment: mobile
              ? MainAxisAlignment.start
              : MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (mobile) ...[
              const Text(
                '온돌봄',
                style: TextStyle(
                  color: _ink,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.72,
                ),
              ),
              const SizedBox(height: 64),
            ],
            const Text(
              'SIGN IN',
              style: TextStyle(
                color: Color(0xFF8D6554),
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 2.2,
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              '로그인',
              style: TextStyle(
                color: _ink,
                fontSize: 32,
                height: 1.25,
                fontWeight: FontWeight.w800,
                letterSpacing: -1.6,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              '계정에 로그인하고 서비스를 계속 이용해 보세요.',
              style: TextStyle(
                color: Color(0xFF827B78),
                fontSize: 14,
                height: 1.65,
              ),
            ),
            SizedBox(height: mobile ? 30 : 32),
            const Text(
              '아이디',
              style: TextStyle(
                color: _ink,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 9),
            Semantics(
              label: '이메일',
              child: TextFormField(
                controller: email,
                enabled: !busy,
                style: const TextStyle(color: _ink, fontSize: 14),
                decoration: _decoration('이메일을 입력해 주세요'),
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.next,
                autofillHints: const [AutofillHints.email],
                autocorrect: false,
                validator: (value) {
                  final input = value?.trim() ?? '';
                  if (input.isEmpty) return '이메일을 입력해 주세요.';
                  if (!RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$').hasMatch(input)) {
                    return '이메일 형식을 확인해 주세요.';
                  }
                  return null;
                },
              ),
            ),
            const SizedBox(height: 18),
            const Text(
              '비밀번호',
              style: TextStyle(
                color: _ink,
                fontSize: 13,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 9),
            TextFormField(
              controller: password,
              enabled: !busy,
              obscureText: true,
              style: const TextStyle(color: _ink, fontSize: 14),
              decoration: _decoration('비밀번호를 입력해 주세요'),
              autofillHints: const [AutofillHints.password],
              enableSuggestions: false,
              autocorrect: false,
              textInputAction: TextInputAction.done,
              validator: (value) =>
                  value == null || value.isEmpty ? '비밀번호를 입력해 주세요.' : null,
              onFieldSubmitted: (_) {
                if (!busy) onSubmit();
              },
            ),
            _options(stackedChecks),
            Container(
              height: 54,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                boxShadow: busy
                    ? []
                    : [
                        BoxShadow(
                          color: _ink.withValues(alpha: 0.18),
                          offset: const Offset(0, 10),
                          blurRadius: 24,
                        ),
                      ],
              ),
              child: FilledButton(
                onPressed: busy ? null : onSubmit,
                style: FilledButton.styleFrom(
                  backgroundColor: _peach,
                  foregroundColor: _ink,
                  disabledBackgroundColor: _peach.withValues(alpha: 0.3),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                child: Text(
                  busy ? '로그인 중' : '로그인',
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
            // 기존 오류 안내만 표시한다. React 목업의 가짜 로그인 상태는 사용하지 않는다.
            Padding(
              padding: const EdgeInsets.only(top: 7),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 18),
                child: Column(
                  children: [
                    if (preferencesError != null)
                      Text(
                        preferencesError!,
                        style: const TextStyle(
                          color: Color(0xFFB3261E),
                          fontSize: 12,
                        ),
                      ),
                    if (authError != null)
                      Text(
                        authError!,
                        style: const TextStyle(
                          color: Color(0xFFB3261E),
                          fontSize: 12,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const Row(
              children: [
                Expanded(child: Divider(color: Color(0xFFEEE6E1))),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 14),
                  child: Text(
                    '간편 로그인',
                    style: TextStyle(color: Color(0xFFA09894), fontSize: 11),
                  ),
                ),
                Expanded(child: Divider(color: Color(0xFFEEE6E1))),
              ],
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _social(
                  'Google로 계속하기',
                  'assets/images/auth/google.png',
                  onGoogle,
                ),
                const SizedBox(width: 12),
                _social('카카오로 계속하기', 'assets/images/auth/kakao.png', onKakao),
                const SizedBox(width: 12),
                _social('네이버로 계속하기', 'assets/images/auth/naver.png', onNaver),
              ],
            ),
            const SizedBox(height: 26),
            Wrap(
              alignment: WrapAlignment.center,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              children: [
                const Text(
                  '아직 회원이 아니신가요?',
                  style: TextStyle(color: Color(0xFF8D8581), fontSize: 12),
                ),
                TextButton(
                  onPressed: busy ? null : onSignup,
                  style: TextButton.styleFrom(
                    foregroundColor: _ink,
                    padding: EdgeInsets.zero,
                    minimumSize: const Size(0, 24),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  child: Container(
                    padding: const EdgeInsets.only(bottom: 4),
                    decoration: const BoxDecoration(
                      border: Border(
                        bottom: BorderSide(color: _peach, width: 2),
                      ),
                    ),
                    child: const Text(
                      '이메일로 회원가입',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: _paper,
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final mobile = constraints.maxWidth <= 760;
          // CSS의 400px 분기와 큰 글꼴을 함께 고려한다. 입력 컨트롤러·콜백은 공통이다.
          final stacked =
              constraints.maxWidth <= 400 ||
              MediaQuery.textScalerOf(context).scale(12) > 15;
          if (mobile) {
            return SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: _formPanel(
                mobile: true,
                stackedChecks: stacked,
                horizontalPadding: 24,
              ),
            );
          }
          final shellWidth = (constraints.maxWidth - 48).clamp(0.0, 980.0);
          return ColoredBox(
            color: AppColors.peachSoft,
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 40,
                ),
                child: Container(
                  width: shellWidth,
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: _paper,
                    borderRadius: BorderRadius.circular(32),
                    border: Border.all(color: _ink.withValues(alpha: 0.08)),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF604636).withValues(alpha: 0.16),
                        offset: const Offset(0, 30),
                        blurRadius: 80,
                      ),
                    ],
                  ),
                  child: IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Expanded(flex: 42, child: _WelcomePanel()),
                        Expanded(
                          flex: 58,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(minHeight: 690),
                            child: _formPanel(
                              mobile: false,
                              stackedChecks: stacked,
                              horizontalPadding: (constraints.maxWidth * 0.06)
                                  .clamp(42.0, 74.0),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    ),
  );
}

class _WelcomePanel extends StatelessWidget {
  const _WelcomePanel();
  @override
  Widget build(BuildContext context) => ColoredBox(
    color: AppColors.primary,
    child: Stack(
      children: [
        const Padding(
          padding: EdgeInsets.symmetric(horizontal: 42, vertical: 44),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '온돌봄',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              SizedBox(height: 100),
              Text(
                'WELCOME BACK',
                style: TextStyle(
                  color: Color(0xFF755747),
                  fontSize: 11,
                  letterSpacing: 2.2,
                  fontWeight: FontWeight.w800,
                ),
              ),
              SizedBox(height: 12),
              Text(
                '오늘도,\n따뜻하게 시작해요.',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 34,
                  height: 1.28,
                  letterSpacing: -1.6,
                  fontWeight: FontWeight.w800,
                ),
              ),
              SizedBox(height: 18),
              Text(
                '당신의 하루에 편안한 리듬을 더해드릴게요.',
                style: TextStyle(
                  color: Color(0xFF786052),
                  fontSize: 14,
                  height: 1.7,
                ),
              ),
            ],
          ),
        ),
        Positioned(
          right: 56,
          bottom: 117,
          child: Container(
            width: 74,
            height: 74,
            decoration: const BoxDecoration(
              color: AppColors.peachLight,
              shape: BoxShape.circle,
            ),
          ),
        ),
        Positioned(
          left: 53,
          bottom: -86,
          child: Transform.rotate(
            angle: -0.14,
            child: Container(
              width: 380,
              height: 230,
              decoration: const BoxDecoration(
                color: AppColors.peachLight,
                borderRadius: BorderRadius.vertical(
                  top: Radius.elliptical(190, 115),
                ),
              ),
            ),
          ),
        ),
        Positioned(
          right: 80,
          bottom: -130,
          child: Transform.rotate(
            angle: 0.26,
            child: Container(
              width: 360,
              height: 250,
              decoration: const BoxDecoration(
                color: AppColors.sage,
                borderRadius: BorderRadius.vertical(
                  top: Radius.elliptical(180, 125),
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}
