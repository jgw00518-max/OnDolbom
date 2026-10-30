import 'package:flutter/material.dart';

/// 최근 온돌봄 디자인에서 확정한 밝은 모드 팔레트.
/// 화면별로 같은 색상 값을 반복하지 않고 용도에 맞는 이름을 참조한다.
abstract final class AppColors {
  static const primary = Color(0xFFF6B08A);
  static const textPrimary = Color(0xFF3E3A39);
  static const background = Color(0xFFFFFAF7);
  static const surface = Colors.white;
  static const peachLight = Color(0xFFFFD6B5);
  static const peachSoft = Color(0xFFFCEEE3);
  static const textSecondary = Color(0xFF9A8F89);
  static const border = Color(0xFFEADDD5);
  static const sageLight = Color(0xFFDCE6CF);
  static const sageDark = Color(0xFF60704F);
  static const sage = Color(0xFFB7C8A1);
  static const notificationDot = Color(0xFFE53935);

  static final _darkMappings = <Color, Color>{
    primary: primary,
    textPrimary: Color(0xFFF2E9E3),
    background: Color(0xFF1E1B19),
    surface: Color(0xFF292522),
    peachLight: Color(0xFF523B2D),
    peachSoft: Color(0xFF382B24),
    textSecondary: Color(0xFFBCAFA5),
    border: Color(0xFF51453E),
    sageLight: Color(0xFF303C2B),
    sageDark: Color(0xFFB7C8A1),
    sage: Color(0xFFB7C8A1),
  };

  static AppPalette of(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark
      ? AppPalette.dark
      : AppPalette.light;

  /// 기존 화면의 보조 색상도 동일한 팔레트로 변환한다. 이미지·브랜드 에셋은 변환하지 않는다.
  static Color resolve(
    BuildContext context,
    Color color, {
    bool onAccent = false,
  }) {
    if (Theme.of(context).brightness != Brightness.dark) return color;
    final opacity = color.a;
    final opaque = color.withValues(alpha: 1);
    if (opacity == 0) return color;
    if (onAccent) {
      final hsl = HSLColor.fromColor(opaque);
      if (opaque == textPrimary ||
          (hsl.saturation < 0.2 && opaque.computeLuminance() < 0.15)) {
        return textPrimary.withValues(alpha: opacity);
      }
      return color;
    }
    if (_darkMappings.values.contains(opaque)) return color;
    final mapped = _darkMappings[opaque];
    if (mapped != null) return mapped.withValues(alpha: opacity);
    final hsl = HSLColor.fromColor(opaque);
    final luminance = opaque.computeLuminance();
    Color result;
    if (luminance > 0.7) {
      result = hsl.saturation > 0.12 && hsl.hue >= 65 && hsl.hue <= 165
          ? AppPalette.dark.sageLight
          : hsl.saturation > 0.15 && hsl.hue < 65
          ? AppPalette.dark.peachSoft
          : AppPalette.dark.surface;
    } else if (hsl.saturation < 0.2) {
      result = luminance < 0.12
          ? AppPalette.dark.textPrimary
          : AppPalette.dark.textSecondary;
    } else if (hsl.hue >= 65 && hsl.hue <= 165) {
      result = luminance > 0.35
          ? AppPalette.dark.sageLight
          : AppPalette.dark.sageDark;
    } else if (hsl.hue < 65 || hsl.hue > 340) {
      result = luminance > 0.4
          ? AppPalette.dark.peachLight
          : const Color(0xFFE6AE91);
    } else {
      result = color; // 제공업체 색상과 의미가 있는 파랑·보라 등은 그대로 사용한다.
    }
    return result.withValues(alpha: opacity);
  }

  static TextStyle resolveTextStyle(BuildContext context, TextStyle style) =>
      style.copyWith(
        color: style.color == null ? null : resolve(context, style.color!),
      );
}

/// 밝은 모드와 어두운 모드에서 동일한 역할을 가지는 색상 묶음.
class AppPalette {
  const AppPalette({
    required this.background,
    required this.surface,
    required this.textPrimary,
    required this.textSecondary,
    required this.peachLight,
    required this.peachSoft,
    required this.sageLight,
    required this.sageDark,
    required this.border,
  });
  final Color background,
      surface,
      textPrimary,
      textSecondary,
      peachLight,
      peachSoft,
      sageLight,
      sageDark,
      border;
  Color get primary => AppColors.primary;
  Color get sage => AppColors.sage;
  Color get notificationDot => AppColors.notificationDot;
  static const light = AppPalette(
    background: AppColors.background,
    surface: AppColors.surface,
    textPrimary: AppColors.textPrimary,
    textSecondary: AppColors.textSecondary,
    peachLight: AppColors.peachLight,
    peachSoft: AppColors.peachSoft,
    sageLight: AppColors.sageLight,
    sageDark: AppColors.sageDark,
    border: AppColors.border,
  );
  static const dark = AppPalette(
    background: Color(0xFF1E1B19),
    surface: Color(0xFF292522),
    textPrimary: Color(0xFFF2E9E3),
    textSecondary: Color(0xFFBCAFA5),
    peachLight: Color(0xFF523B2D),
    peachSoft: Color(0xFF382B24),
    sageLight: Color(0xFF303C2B),
    sageDark: Color(0xFFB7C8A1),
    border: Color(0xFF51453E),
  );
}
