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
    backgroundColor: paper,
    surfaceTintColor: Colors.transparent,
    foregroundColor: ink,
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
              backgroundColor: AppColors.surface,
              foregroundColor: ink,
              side: const BorderSide(color: line),
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
        const Text(
          'SUPPORT',
          style: TextStyle(
            color: Color(0xFFA77762),
            fontSize: 8,
            letterSpacing: 1.5,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          title,
          style: const TextStyle(
            color: ink,
            fontSize: 24,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    ),
    actions: const [MenuHeaderIcon(icon: Icons.help_outline)],
  );

  static Widget status(bool answered) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
    decoration: BoxDecoration(
      color: answered ? const Color(0xFFE5EEDC) : AppColors.peachSoft,
      borderRadius: BorderRadius.circular(24),
    ),
    child: Text(
      answered ? '답변 완료' : '답변 대기',
      style: TextStyle(
        color: answered ? AppColors.sageDark : const Color(0xFFA46F59),
        fontSize: 11,
        fontWeight: FontWeight.w700,
      ),
    ),
  );

  static InputDecoration input(String hint) => InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: Color(0xFFB4AAA5), fontSize: 13),
    filled: true,
    fillColor: AppColors.surface,
    contentPadding: const EdgeInsets.all(17),
    counterStyle: const TextStyle(color: muted, fontSize: 10),
    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: line),
    ),
    disabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: line),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: const BorderSide(color: peach, width: 2),
    ),
  );
}
