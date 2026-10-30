import 'package:ondolbom/l10n/app_strings.dart';
import 'package:ondolbom/view/widgets/menu_header_icon.dart';
import 'package:ondolbom/theme/app_colors.dart';
import 'package:flutter/material.dart';

/// 문의 세 화면의 표현만 공유한다. API·작성 상태·입력 검증은 각 화면에서 유지한다.
abstract final class InquiryStyle {
  static const ink = AppColors.textPrimary;
  static const paper = AppColors.background;
  static const peach = AppColors.primary;
  static const muted = AppColors.textSecondary;
  static const line = AppColors.border;

  static AppBar header(
    BuildContext context,
    String title, {
    bool busy = false,
  }) => AppBar(
    backgroundColor: AppColors.resolve(context, paper),
    surfaceTintColor: Colors.transparent,
    foregroundColor: AppColors.resolve(context, ink),
    toolbarHeight: 88,
    centerTitle: true,
    leadingWidth: 62,
    leading: Padding(
      padding: const EdgeInsets.only(left: 14),
      child: Center(
        child: SizedBox.square(
          dimension: 42,
          child: OutlinedButton(
            onPressed: busy ? null : () => Navigator.maybePop(context),
            style: OutlinedButton.styleFrom(
              padding: EdgeInsets.zero,
              backgroundColor: AppColors.of(context).surface,
              foregroundColor: AppColors.resolve(context, ink),
              side: BorderSide(color: AppColors.resolve(context, line)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(13),
              ),
            ),
            child: const Icon(Icons.chevron_left),
          ),
        ),
      ),
    ),
    title: Column(
      children: [
        Text(
          'SUPPORT',
          style: TextStyle(
            color: AppColors.resolve(context, Color(0xFFA77762)),
            fontSize: 8,
            letterSpacing: 1.5,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          title,
          style: TextStyle(
            color: AppColors.resolve(context, ink),
            fontSize: 24,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
    actions: const [MenuHeaderIcon(icon: Icons.help_outline)],
  );

  static Widget status(BuildContext context, bool answered) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: answered
          ? AppColors.resolve(context, const Color(0xFFE5EEDC))
          : AppColors.of(context).peachSoft,
      borderRadius: BorderRadius.circular(24),
    ),
    child: Text(
      answered
          ? AppStrings.tr(context, '답변 완료')
          : AppStrings.tr(context, '답변 대기'),
      style: TextStyle(
        color: answered
            ? AppColors.of(context).sageDark
            : AppColors.resolve(context, const Color(0xFFA46F59)),
        fontSize: 11,
        fontWeight: FontWeight.w700,
      ),
    ),
  );

  static InputDecoration input(BuildContext context, String hint) =>
      InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(
          color: AppColors.resolve(context, Color(0xFFB4AAA5)),
          fontSize: 13,
        ),
        filled: true,
        fillColor: AppColors.of(context).surface,
        contentPadding: const EdgeInsets.all(17),
        counterStyle: TextStyle(
          color: AppColors.resolve(context, muted),
          fontSize: 10,
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppColors.resolve(context, line)),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: AppColors.resolve(context, line)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(
            color: AppColors.resolve(context, peach),
            width: 2,
          ),
        ),
      );
}
