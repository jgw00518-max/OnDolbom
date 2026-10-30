import 'package:flutter/material.dart';
import 'package:ondolbom/theme/app_colors.dart';

/// 앱의 공통 색상·글꼴·헤더 높이를 관리한다.
abstract final class AppTheme {
  static const fontFamily = 'Pretendard';
  // 돌봄 공간 목록과 같은 헤더 높이로 상태 표시줄 아래 간격을 통일한다.
  static const toolbarHeight = 88.0;

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
    switchTheme: _switchTheme(false),
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
      toolbarHeight: toolbarHeight,
      centerTitle: true,
      backgroundColor: AppColors.background,
      foregroundColor: AppColors.textPrimary,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      titleTextStyle: TextStyle(
        fontFamily: fontFamily,
        color: AppColors.textPrimary,
        fontSize: 24,
        fontWeight: FontWeight.w800,
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
      backgroundColor: AppColors.peachLight,
      foregroundColor: AppColors.textPrimary,
    ),
    dividerTheme: const DividerThemeData(color: AppColors.border),
    inputDecorationTheme: const InputDecorationTheme(
      fillColor: AppColors.surface,
      hintStyle: TextStyle(color: AppColors.textSecondary),
    ),
  );

  /// 밝은 테마와 글꼴·치수는 공유하고 배경·텍스트·입력·팝업 색상만 변경한다.
  static final dark = _darkTheme();
  static ThemeData _darkTheme() {
    const p = AppPalette.dark;
    final scheme =
        ColorScheme.fromSeed(
          seedColor: AppColors.primary,
          brightness: Brightness.dark,
        ).copyWith(
          primary: AppColors.primary,
          onPrimary: AppColors.textPrimary,
          surface: p.surface,
          onSurface: p.textPrimary,
          onSurfaceVariant: p.textSecondary,
          secondary: p.sageDark,
          onSecondary: p.background,
          secondaryContainer: p.peachSoft,
          onSecondaryContainer: p.textPrimary,
          outline: p.border,
          outlineVariant: p.border,
        );
    final base = ThemeData(
      useMaterial3: true,
      fontFamily: fontFamily,
      colorScheme: scheme,
    );
    return base.copyWith(
      scaffoldBackgroundColor: p.background,
      switchTheme: _switchTheme(true),
      appBarTheme: light.appBarTheme.copyWith(
        backgroundColor: p.background,
        foregroundColor: p.textPrimary,
        titleTextStyle: light.appBarTheme.titleTextStyle?.copyWith(
          color: p.textPrimary,
        ),
      ),
      cardTheme: light.cardTheme.copyWith(
        color: p.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(color: p.border),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: p.surface,
        modalBackgroundColor: p.surface,
        surfaceTintColor: Colors.transparent,
      ),
      drawerTheme: DrawerThemeData(backgroundColor: p.background),
      dividerTheme: DividerThemeData(color: p.border),
      inputDecorationTheme: InputDecorationTheme(
        fillColor: p.surface,
        hintStyle: TextStyle(color: p.textSecondary),
        labelStyle: TextStyle(color: p.textSecondary),
      ),
      filledButtonTheme: light.filledButtonTheme,
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: p.textPrimary),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: p.textPrimary,
          side: BorderSide(color: p.border),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: p.peachLight,
        foregroundColor: p.textPrimary,
      ),
      datePickerTheme: DatePickerThemeData(
        backgroundColor: p.surface,
        headerBackgroundColor: p.peachSoft,
        headerForegroundColor: p.textPrimary,
        dayForegroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? p.background
              : states.contains(WidgetState.disabled)
              ? p.textSecondary.withValues(alpha: .4)
              : p.textPrimary,
        ),
        dayBackgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? p.sageDark
              : Colors.transparent,
        ),
        todayForegroundColor: WidgetStateProperty.resolveWith(
          (states) =>
              states.contains(WidgetState.selected) ? p.background : p.sageDark,
        ),
        todayBorder: BorderSide(color: p.sageDark),
      ),
    );
  }

  // 꺼짐은 회갈색 트랙과 밝은 손잡이, 켜짐은 살구색 트랙과 진한 손잡이로 구분한다.
  // 설정 화면의 두 토글이 개별 색상을 덮어쓰지 않고 이 기준을 공유한다.
  static SwitchThemeData _switchTheme(bool dark) => SwitchThemeData(
    thumbColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) {
        return dark ? const Color(0xFFA99B91) : const Color(0xFFF4F0EC);
      }
      if (states.contains(WidgetState.selected)) return AppColors.textPrimary;
      return dark ? const Color(0xFFE2D5CC) : Colors.white;
    }),
    trackColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) {
        return dark ? const Color(0xFF413A35) : const Color(0xFFDDD4CD);
      }
      if (states.contains(WidgetState.selected)) return AppColors.primary;
      return dark ? const Color(0xFF544A43) : const Color(0xFFD1C4BB);
    }),
    trackOutlineColor: WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.disabled)) {
        return dark ? const Color(0xFF65584E) : const Color(0xFFBDAEA3);
      }
      if (states.contains(WidgetState.selected)) return const Color(0xFFA66A47);
      return dark ? const Color(0xFF9E8A7C) : const Color(0xFF88796E);
    }),
    trackOutlineWidth: const WidgetStatePropertyAll(1.2),
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
