import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final themePreferencesProvider = Provider<ThemePreferences>(
  (ref) => ThemePreferences(),
);

/// 계정 정보와 분리된 기기별 화면 설정. 기본은 기존 밝은 모드다.
class ThemePreferences {
  Future<ThemeMode> read() async =>
      await SharedPreferencesAsync().getBool('appearance.dark_mode') == true
      ? ThemeMode.dark
      : ThemeMode.light;
  Future<void> write(ThemeMode mode) => SharedPreferencesAsync().setBool(
    'appearance.dark_mode',
    mode == ThemeMode.dark,
  );
}
