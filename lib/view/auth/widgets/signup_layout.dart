import 'package:ondolbom/theme/app_colors.dart';
import 'package:flutter/material.dart';

/// 회원가입의 표시만 담당한다. 실제 인증·재발송·가입 처리는 SignupView/VM에서 유지한다.
class SignupLayout extends StatelessWidget {
  const SignupLayout({
    super.key,
    required this.step,
    required this.formKey,
    required this.fields,
    required this.busy,
    required this.onSubmit,
    required this.onBack,
    this.error,
    this.title,
    this.description,
    this.buttonLabel,
    this.eyebrow,
    this.asideHeading,
    this.asideDescription,
    this.asideEyebrow = 'JOIN US',
    this.stepLabel = '회원가입',
    this.showBack = true,
    this.allowBackWhileBusy = false,
  });
  final int step;
  final GlobalKey<FormState> formKey;
  final List<Widget> fields;
  final bool busy;
  final VoidCallback onSubmit, onBack;
  final String? error;
  // 인증 단계 화면들이 같은 디자인을 쓰되 처리 로직은 각 View에 둔다.
  final String? title,
      description,
      buttonLabel,
      eyebrow,
      asideHeading,
      asideDescription;
  final String asideEyebrow, stepLabel;
  final bool showBack, allowBackWhileBusy;
  static const ink = AppColors.textPrimary;
  static const peach = AppColors.primary;
  static const paper = AppColors.background;

  static InputDecoration inputDecoration(
    String hint, {
    bool confirmed = false,
  }) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(13),
      borderSide: BorderSide(
        color: confirmed ? const Color(0xFFE4E8DF) : const Color(0xFFE6DED9),
      ),
    );
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: Color(0xFFB3AAA5), fontSize: 14),
      filled: true,
      fillColor: confirmed ? const Color(0xFFF3F6EF) : paper,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 17, vertical: 16),
      constraints: const BoxConstraints(minHeight: 52),
      border: border,
      enabledBorder: border,
      disabledBorder: border,
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(13),
        borderSide: const BorderSide(color: peach),
      ),
      errorMaxLines: 3,
    );
  }

  Widget _formPanel(bool mobile, double padding) => Padding(
    padding: EdgeInsets.fromLTRB(
      padding,
      mobile ? 32 : 52,
      padding,
      mobile ? 44 : 52,
    ),
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
                color: ink,
                fontSize: 18,
                fontWeight: FontWeight.w800,
                letterSpacing: -0.72,
              ),
            ),
            const SizedBox(height: 64),
          ],
          Text(
            eyebrow ?? 'STEP $step OF 3',
            style: const TextStyle(
              color: Color(0xFF8D6554),
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 2.2,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            title ??
                switch (step) {
                  1 => '이메일로 시작하기',
                  2 => '인증번호 확인',
                  _ => '비밀번호 만들기',
                },
            style: const TextStyle(
              color: ink,
              fontSize: 32,
              height: 1.25,
              fontWeight: FontWeight.w800,
              letterSpacing: -1.6,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            description ??
                switch (step) {
                  1 => '가입에 사용할 이메일 주소를 입력해 주세요.',
                  2 => '이메일에서 확인한 인증번호를 입력해 주세요.',
                  _ => '안전하게 사용할 비밀번호를 설정해 주세요.',
                },
            style: const TextStyle(
              color: Color(0xFF827B78),
              fontSize: 14,
              height: 1.65,
            ),
          ),
          const SizedBox(height: 34),
          ...fields,
          const SizedBox(height: 24),
          Container(
            height: 54,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              boxShadow: busy
                  ? []
                  : [
                      BoxShadow(
                        color: ink.withValues(alpha: 0.18),
                        offset: const Offset(0, 10),
                        blurRadius: 24,
                      ),
                    ],
            ),
            child: FilledButton(
              onPressed: busy ? null : onSubmit,
              style: FilledButton.styleFrom(
                backgroundColor: peach,
                disabledBackgroundColor: peach.withValues(alpha: 0.3),
                foregroundColor: ink,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(
                busy
                    ? '처리 중…'
                    : buttonLabel ??
                          switch (step) {
                            1 => '인증번호 전송',
                            2 => '인증번호 확인',
                            _ => '이메일로 가입',
                          },
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 18),
              child: error == null
                  ? const SizedBox.shrink()
                  : Text(
                      error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFFB3261E),
                        fontSize: 12,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 12),
          if (showBack)
            Align(
              child: TextButton.icon(
                onPressed: busy && !allowBackWhileBusy ? null : onBack,
                icon: const Icon(Icons.arrow_back, size: 16),
                style: TextButton.styleFrom(foregroundColor: ink),
                label: const Text(
                  '로그인으로 돌아가기',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ),
            ),
        ],
      ),
    ),
  );

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: paper,
    body: SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.maxWidth <= 760) {
            return SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: _formPanel(true, 24),
            );
          }
          return ColoredBox(
            color: AppColors.peachSoft,
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 40,
                ),
                child: Container(
                  width: (constraints.maxWidth - 48).clamp(0.0, 900.0),
                  clipBehavior: Clip.antiAlias,
                  decoration: BoxDecoration(
                    color: paper,
                    borderRadius: BorderRadius.circular(32),
                    border: Border.all(color: ink.withValues(alpha: 0.08)),
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
                        Expanded(
                          flex: 38,
                          child: _SignupAside(
                            step: step,
                            heading: asideHeading,
                            description: asideDescription,
                            eyebrow: asideEyebrow,
                            stepLabel: stepLabel,
                          ),
                        ),
                        Expanded(
                          flex: 62,
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(minHeight: 620),
                            child: _formPanel(
                              false,
                              (constraints.maxWidth * 0.06).clamp(42.0, 74.0),
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

class SignupField extends StatelessWidget {
  const SignupField({super.key, required this.label, required this.child});
  final String label;
  final Widget child;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        label,
        style: const TextStyle(
          color: SignupLayout.ink,
          fontSize: 13,
          fontWeight: FontWeight.w700,
        ),
      ),
      const SizedBox(height: 9),
      child,
    ],
  );
}

class _SignupAside extends StatelessWidget {
  const _SignupAside({
    required this.step,
    this.heading,
    this.description,
    required this.eyebrow,
    required this.stepLabel,
  });
  final int step;
  final String? heading, description;
  final String eyebrow, stepLabel;
  @override
  Widget build(BuildContext context) => ColoredBox(
    color: AppColors.peachLight,
    child: Stack(
      children: [
        Positioned(
          right: -75,
          bottom: -100,
          child: Container(
            width: 290,
            height: 290,
            decoration: const BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.sage,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 38, vertical: 44),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '온돌봄',
                style: TextStyle(
                  color: SignupLayout.ink,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 105),
              Text(
                eyebrow,
                style: const TextStyle(
                  color: Color(0xFF8D6554),
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 2.2,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                heading ?? '온돌봄과 함께할 준비가 거의 끝났어요.',
                style: const TextStyle(
                  color: SignupLayout.ink,
                  fontSize: 31,
                  height: 1.35,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -1.7,
                ),
              ),
              const SizedBox(height: 17),
              Text(
                description ?? '간단한 이메일 인증 후 새로운 계정을 만들어 보세요.',
                style: const TextStyle(
                  color: Color(0xFF82705F),
                  fontSize: 13,
                  height: 1.7,
                ),
              ),
              const SizedBox(height: 60),
              Semantics(
                label: '$stepLabel $step단계',
                child: Row(
                  children: [
                    for (var i = 1; i <= 3; i++)
                      Padding(
                        padding: const EdgeInsets.only(right: 12),
                        child: Container(
                          width: 31,
                          height: 31,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: i <= step
                                ? SignupLayout.ink
                                : Colors.transparent,
                            border: Border.all(
                              color: i <= step
                                  ? SignupLayout.ink
                                  : SignupLayout.ink.withValues(alpha: 0.2),
                            ),
                          ),
                          child: Text(
                            i < step ? '✓' : '$i',
                            style: TextStyle(
                              color: i <= step
                                  ? Colors.white
                                  : SignupLayout.ink.withValues(alpha: 0.55),
                              fontSize: 11,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}
