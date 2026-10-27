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
}
