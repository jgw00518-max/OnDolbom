import 'package:flutter/material.dart';
import 'package:ondolbom/l10n/app_strings.dart';
import 'package:ondolbom/theme/app_colors.dart';

/// 메모 화면과 같은 원형 아이콘·제목·보조 문구를 사용한다. 큰 글씨에서는 스크롤한다.
class AppEmptyState extends StatelessWidget {
  const AppEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
  });
  final IconData icon;
  final String title;
  final String description;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => SingleChildScrollView(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: constraints.hasBoundedHeight ? constraints.maxHeight : 0,
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.of(context).peachSoft,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icon,
                    size: 36,
                    color: AppColors.of(context).sageDark,
                  ),
                ),
                const SizedBox(height: 18),
                Text(
                  AppStrings.tr(context, title),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: AppColors.of(context).textPrimary,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  AppStrings.tr(context, description),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.of(context).textSecondary,
                    height: 1.6,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
