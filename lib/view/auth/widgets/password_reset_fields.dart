import 'package:ondolbom/l10n/app_strings.dart';
import 'package:ondolbom/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ondolbom/view/auth/widgets/signup_layout.dart';
import 'package:ondolbom/vm/auth/password_reset_vm.dart';

/// 회원가입과 같은 입력창 디자인을 사용하고 기존 재설정 검증 조건을 유지한다.
class PasswordResetFields extends StatelessWidget {
  const PasswordResetFields({
    super.key,
    required this.step,
    required this.email,
    required this.code,
    required this.password,
    required this.confirmation,
    required this.busy,
    required this.remaining,
    required this.onResend,
  });
  final PasswordResetStep step;
  final TextEditingController email, code, password, confirmation;
  final bool busy;
  final int remaining;
  final VoidCallback onResend;
  static const _inputStyle = TextStyle(color: SignupLayout.ink, fontSize: 14);
  static const _helpStyle = TextStyle(
    color: Color(0xFF827B78),
    fontSize: 12,
    height: 1.65,
  );
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (step == PasswordResetStep.email || step == PasswordResetStep.code)
        SignupField(
          label: AppStrings.tr(context, '가입 이메일'),
          child: TextFormField(
            controller: email,
            enabled: !busy && step == PasswordResetStep.email,
            style: TextStyle(
              color: step == PasswordResetStep.email
                  ? AppColors.resolve(context, SignupLayout.ink)
                  : AppColors.resolve(context, const Color(0xFF667057)),
              fontSize: 14,
            ),
            decoration: SignupLayout.inputDecoration(
              context,
              'example@email.com',
              confirmed: step == PasswordResetStep.code,
            ),
            keyboardType: TextInputType.emailAddress,
            autocorrect: false,
            validator: (value) =>
                RegExp(
                  r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
                ).hasMatch(value?.trim() ?? '')
                ? null
                : AppStrings.tr(context, '이메일 형식을 확인해 주세요.'),
          ),
        ),
      if (step == PasswordResetStep.email) ...[
        const SizedBox(height: 10),
        Text(
          AppStrings.tr(context, 'Google·카카오·네이버 전용 계정은 해당 로그인 버튼을 이용해 주세요.'),
          style: AppColors.resolveTextStyle(context, _helpStyle),
        ),
      ],
      if (step == PasswordResetStep.code) ...[
        const SizedBox(height: 18),
        SignupField(
          label: AppStrings.tr(context, '인증번호'),
          child: TextFormField(
            controller: code,
            enabled: !busy,
            style: AppColors.resolveTextStyle(context, _inputStyle),
            decoration: SignupLayout.inputDecoration(
              context,
              AppStrings.tr(context, '인증번호 6자리'),
            ),
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
            validator: (value) => RegExp(r'^\d{6}$').hasMatch(value ?? '')
                ? null
                : AppStrings.tr(context, '6자리 인증번호를 입력해 주세요.'),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          AppStrings.tr(
            context,
            '재설정 가능한 계정이면 인증번호가 발송됩니다. 받은편지함·스팸함을 확인하고 10분 안에 입력해 주세요.',
          ),
          style: AppColors.resolveTextStyle(context, _helpStyle),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: busy || remaining > 0 ? null : onResend,
            style: TextButton.styleFrom(
              foregroundColor: AppColors.resolve(context, SignupLayout.ink),
            ),
            child: Text(
              remaining > 0
                  ? AppStrings.format(context, '{0}초 후 다시 보내기', [remaining + 1])
                  : AppStrings.tr(context, '인증번호 다시 보내기'),
              style: const TextStyle(
                fontSize: 12,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ),
      ],
      if (step == PasswordResetStep.password) ...[
        SignupField(
          label: AppStrings.tr(context, '새 비밀번호'),
          child: TextFormField(
            controller: password,
            enabled: !busy,
            obscureText: true,
            style: AppColors.resolveTextStyle(context, _inputStyle),
            decoration: SignupLayout.inputDecoration(
              context,
              AppStrings.tr(context, '6~128자의 비밀번호'),
            ),
            validator: (value) =>
                (value?.length ?? 0) >= 6 && (value?.length ?? 0) <= 128
                ? null
                : AppStrings.tr(context, '비밀번호는 6~128자로 입력해 주세요.'),
          ),
        ),
        const SizedBox(height: 18),
        SignupField(
          label: AppStrings.tr(context, '새 비밀번호 확인'),
          child: TextFormField(
            controller: confirmation,
            enabled: !busy,
            obscureText: true,
            style: AppColors.resolveTextStyle(context, _inputStyle),
            decoration: SignupLayout.inputDecoration(
              context,
              AppStrings.tr(context, '비밀번호를 한 번 더 입력해 주세요'),
            ),
            validator: (value) => value == password.text
                ? null
                : AppStrings.tr(context, '비밀번호가 일치하지 않습니다.'),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          AppStrings.tr(context, '이메일 확인 후 5분 안에 새 비밀번호를 설정해 주세요.'),
          style: AppColors.resolveTextStyle(context, _helpStyle),
        ),
      ],
      if (step == PasswordResetStep.done)
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColors.resolve(context, const Color(0xFFF3F6EF)),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Text(
            AppStrings.tr(context, '비밀번호가 변경되었습니다. 새 비밀번호로 로그인해 주세요.'),
            style: TextStyle(
              color: AppColors.resolve(context, Color(0xFF667057)),
              fontSize: 14,
              height: 1.7,
            ),
          ),
        ),
    ],
  );
}
