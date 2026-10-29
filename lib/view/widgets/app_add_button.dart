import 'package:flutter/material.dart';
import 'package:ondolbom/theme/app_colors.dart';

/// 목록의 추가 동작을 같은 크기·색상으로 표시한다. 권한과 저장 흐름은 호출 화면이 결정한다.
class AppAddButton extends StatelessWidget {
  const AppAddButton({
    super.key,
    required this.tooltip,
    required this.onPressed,
  });
  final String tooltip;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => FloatingActionButton(
    tooltip: tooltip,
    onPressed: onPressed,
    backgroundColor: AppColors.peachLight,
    foregroundColor: AppColors.textPrimary,
    elevation: 2,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: const BorderSide(color: AppColors.border),
    ),
    child: const Icon(Icons.add, size: 32),
  );
}
