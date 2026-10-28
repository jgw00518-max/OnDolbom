import 'package:flutter/material.dart';
import 'package:ondolbom/theme/app_colors.dart';

/// 앱 기본 색상을 최근 디자인으로 맞춘다. 화면별 크기·배치는 변경하지 않는다.
abstract final class AppTheme {
  static const fontFamily = 'Pretendard';

  static final light = ThemeData(
    // 앱에 포함한 글꼴을 사용해 네트워크 없이 동일한 글꼴을 표시한다.
    fontFamily: fontFamily,
    useMaterial3: true,
    colorScheme:
        ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          brightness: Brightness.light,
        ).copyWith(
          primary: AppColors.primary,
          onPrimary: AppColors.textPrimary,
          surface: AppColors.surface,
          onSurface: AppColors.textPrimary,
          onSurfaceVariant: AppColors.textSecondary,
          secondary: AppColors.sageDark,
          onSecondary: AppColors.surface,
          secondaryContainer: AppColors.peachSoft,
          onSecondaryContainer: AppColors.textPrimary,
          outline: AppColors.border,
          outlineVariant: AppColors.border,
        ),
    scaffoldBackgroundColor: AppColors.background,
    datePickerTheme: DatePickerThemeData(
      backgroundColor: AppColors.background,
      surfaceTintColor: Colors.transparent,
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: AppColors.border),
      ),
      headerBackgroundColor: AppColors.peachSoft,
      headerForegroundColor: AppColors.textPrimary,
      headerHeadlineStyle: const TextStyle(
        fontFamily: fontFamily,
        fontSize: 26,
        fontWeight: FontWeight.w800,
      ),
      headerHelpStyle: const TextStyle(
        fontFamily: fontFamily,
        fontSize: 14,
        fontWeight: FontWeight.w600,
      ),
      weekdayStyle: const TextStyle(
        fontFamily: fontFamily,
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: AppColors.sageDark,
      ),
      dayStyle: const TextStyle(
        fontFamily: fontFamily,
        fontSize: 15,
        fontWeight: FontWeight.w500,
      ),
      dayForegroundColor: WidgetStateProperty.resolveWith(_dateForeground),
      dayBackgroundColor: WidgetStateProperty.resolveWith(_dateBackground),
      todayForegroundColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.disabled)
            ? AppColors.textSecondary
            : states.contains(WidgetState.selected)
            ? AppColors.surface
            : AppColors.sageDark,
      ),
      todayBackgroundColor: WidgetStateProperty.resolveWith(_dateBackground),
      todayBorder: const BorderSide(color: AppColors.sageDark, width: 1.5),
      dayOverlayColor: WidgetStatePropertyAll(
        AppColors.sageDark.withValues(alpha: 0.12),
      ),
      yearStyle: const TextStyle(
        fontFamily: fontFamily,
        fontSize: 15,
        fontWeight: FontWeight.w600,
      ),
      yearForegroundColor: WidgetStateProperty.resolveWith(_dateForeground),
      yearBackgroundColor: WidgetStateProperty.resolveWith(_dateBackground),
      dividerColor: AppColors.border,
      subHeaderForegroundColor: AppColors.textPrimary,
      cancelButtonStyle: TextButton.styleFrom(
        foregroundColor: AppColors.textPrimary,
        minimumSize: const Size(64, 44),
        backgroundBuilder: (context, states, child) =>
            Padding(padding: const EdgeInsets.only(bottom: 12), child: child),
        textStyle: const TextStyle(
          fontFamily: fontFamily,
          fontSize: 14,
          fontWeight: FontWeight.w600,
        ),
      ),
      confirmButtonStyle: TextButton.styleFrom(
        backgroundColor: Colors.transparent,
        foregroundColor: AppColors.textPrimary,
        minimumSize: const Size(64, 44),
        // 기본 달력의 고정된 actions 여백 안에서 버튼 배경도 함께 안쪽으로 옮긴다.
        backgroundBuilder: (context, states, child) => Padding(
          padding: const EdgeInsets.only(right: 8, bottom: 12),
          child: DecoratedBox(
            key: const ValueKey('date-picker-confirm-background'),
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(12),
            ),
            child: child,
          ),
        ),
        textStyle: const TextStyle(
          fontFamily: fontFamily,
          fontSize: 14,
          fontWeight: FontWeight.w700,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      inputDecorationTheme: InputDecorationThemeData(
        filled: true,
        fillColor: AppColors.surface,
        labelStyle: const TextStyle(color: AppColors.textPrimary),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.border),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: AppColors.sageDark, width: 1.5),
        ),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.background,
      foregroundColor: AppColors.textPrimary,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      titleTextStyle: TextStyle(
        fontFamily: fontFamily,
        color: AppColors.textPrimary,
        fontSize: 28,
        fontWeight: FontWeight.bold,
      ),
    ),
    cardTheme: CardThemeData(
      color: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 16),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: AppColors.border),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.textPrimary,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(foregroundColor: AppColors.textPrimary),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.textPrimary,
        side: const BorderSide(color: AppColors.border),
      ),
    ),
    floatingActionButtonTheme: const FloatingActionButtonThemeData(
      backgroundColor: AppColors.primary,
      foregroundColor: AppColors.textPrimary,
    ),
    dividerTheme: const DividerThemeData(color: AppColors.border),
    inputDecorationTheme: const InputDecorationTheme(
      fillColor: AppColors.surface,
      hintStyle: TextStyle(color: AppColors.textSecondary),
    ),
  );

  static Color _dateForeground(Set<WidgetState> states) {
    if (states.contains(WidgetState.disabled)) {
      return AppColors.textSecondary.withValues(alpha: 0.55);
    }
    return states.contains(WidgetState.selected)
        ? AppColors.surface
        : AppColors.textPrimary;
  }

  static Color _dateBackground(Set<WidgetState> states) =>
      !states.contains(WidgetState.disabled) &&
          states.contains(WidgetState.selected)
      ? AppColors.sageDark
      : Colors.transparent;
}
