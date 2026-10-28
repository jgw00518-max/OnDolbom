import 'package:flutter/material.dart';
import 'package:ondolbom/theme/app_colors.dart';

/// 화면 공통 뒤로가기 버튼. 입력 중 이탈 확인은 화면의 콜백에서 처리한다.
class AppBackButton extends StatelessWidget {
  const AppBackButton({super.key, this.onPressed, this.enabled = true});

  final VoidCallback? onPressed;
  final bool enabled;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 42,
    child: Tooltip(
      message: '이전 화면',
      child: OutlinedButton(
        onPressed: !enabled
            ? null
            : onPressed ??
                  () {
                    Navigator.maybePop(context);
                  },
        style: OutlinedButton.styleFrom(
          padding: EdgeInsets.zero,
          backgroundColor: AppColors.surface,
          foregroundColor: AppColors.textPrimary,
          side: const BorderSide(color: AppColors.border),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(13),
          ),
        ),
        child: const Icon(Icons.chevron_left, semanticLabel: '뒤로'),
      ),
    ),
  );
}

/// AppBar의 leadingWidth: 62와 함께 사용한다.
class AppBackLeading extends StatelessWidget {
  const AppBackLeading({super.key, this.onPressed, this.enabled = true});

  final VoidCallback? onPressed;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 14),
    child: Center(
      child: AppBackButton(onPressed: onPressed, enabled: enabled),
    ),
  );
}
