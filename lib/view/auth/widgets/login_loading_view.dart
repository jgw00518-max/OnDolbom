import 'package:ondolbom/theme/app_colors.dart';
import 'package:flutter/material.dart';

/// 인증 세션 복원과 사용자 정보 조회에 같은 로그인 대기 화면을 사용한다.
class LoginLoadingView extends StatelessWidget {
  const LoginLoadingView({super.key});

  @override
  Widget build(BuildContext context) => const Scaffold(
    backgroundColor: AppColors.background,
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox.square(
            dimension: 28,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: AppColors.primary,
              backgroundColor: Color(0xFFFFEBD9),
            ),
          ),
          SizedBox(height: 20),
          Text(
            '로그인 중',
            style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    ),
  );
}
