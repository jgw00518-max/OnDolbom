import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:ondolbom/view/auth/widgets/signup_layout.dart';
import 'package:ondolbom/vm/auth/signup_vm.dart';

/// 기존 회원가입 입력 검증과 활성화 조건을 그대로 사용한다.
class SignupFields extends StatelessWidget {
  const SignupFields({
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
  final SignupStep step;
  final TextEditingController email, code, password, confirmation;
  final bool busy;
  final int remaining;
  final VoidCallback onResend;
  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      SignupField(
        label: '이메일',
        child: TextFormField(
          controller: email,
          enabled: !busy && step == SignupStep.email,
          style: TextStyle(
            color: step == SignupStep.email
                ? SignupLayout.ink
                : const Color(0xFF667057),
            fontSize: 14,
          ),
          decoration: SignupLayout.inputDecoration(
            'example@email.com',
            confirmed: step != SignupStep.email,
          ),
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          validator: (value) =>
              RegExp(
                r'^[^\s@]+@[^\s@]+\.[^\s@]+$',
              ).hasMatch(value?.trim() ?? '')
              ? null
              : '이메일 형식을 확인해 주세요.',
        ),
      ),
      if (step == SignupStep.code) ...[
        const SizedBox(height: 18),
        SignupField(
          label: '인증번호',
          child: TextFormField(
            controller: code,
            enabled: !busy,
            style: const TextStyle(color: SignupLayout.ink, fontSize: 14),
            decoration: SignupLayout.inputDecoration('인증번호 6자리'),
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(6),
            ],
            validator: (value) => RegExp(r'^\d{6}$').hasMatch(value ?? '')
                ? null
                : '6자리 인증번호를 입력해 주세요.',
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          '가입 가능한 이메일이면 인증번호가 발송됩니다. 10분 안에 입력해 주세요. 기존 계정은 로그인 화면을 이용해 주세요.',
          style: TextStyle(
            color: Color(0xFF827B78),
            fontSize: 12,
            height: 1.65,
          ),
        ),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton(
            onPressed: busy || remaining > 0 ? null : onResend,
            style: TextButton.styleFrom(foregroundColor: SignupLayout.ink),
            child: Text(
              remaining > 0 ? '${remaining + 1}초 후 다시 보내기' : '인증번호 다시 보내기',
              style: const TextStyle(
                fontSize: 12,
                decoration: TextDecoration.underline,
              ),
            ),
          ),
        ),
      ],
      if (step == SignupStep.password) ...[
        const SizedBox(height: 18),
        SignupField(
          label: '비밀번호',
          child: TextFormField(
            controller: password,
            enabled: !busy,
            obscureText: true,
            style: const TextStyle(color: SignupLayout.ink, fontSize: 14),
            // 목업의 8자 조건 대신 기존 서비스 조건인 6~128자를 유지한다.
            decoration: SignupLayout.inputDecoration('6~128자의 비밀번호'),
            validator: (value) =>
                (value?.length ?? 0) >= 6 && (value?.length ?? 0) <= 128
                ? null
                : '비밀번호는 6~128자로 입력해 주세요.',
          ),
        ),
        const SizedBox(height: 18),
        SignupField(
          label: '비밀번호 확인',
          child: TextFormField(
            controller: confirmation,
            enabled: !busy,
            obscureText: true,
            style: const TextStyle(color: SignupLayout.ink, fontSize: 14),
            decoration: SignupLayout.inputDecoration('비밀번호를 한 번 더 입력해 주세요'),
            validator: (value) =>
                value == password.text ? null : '비밀번호가 일치하지 않습니다.',
          ),
        ),
        const SizedBox(height: 10),
        const Text(
          '이메일 인증 후 5분 안에 가입해 주세요. 이름과 전화번호는 가입 후 입력합니다.',
          style: TextStyle(
            color: Color(0xFF827B78),
            fontSize: 12,
            height: 1.65,
          ),
        ),
      ],
    ],
  );
}
