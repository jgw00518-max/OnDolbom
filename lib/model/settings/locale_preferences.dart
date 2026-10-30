import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final localePreferencesProvider = Provider<LocalePreferences>(
  (ref) => LocalePreferences(),
);

/// 언어는 계정이 아닌 기기에 저장한다. 기존 기본 언어는 한국어다.
class LocalePreferences {
  Future<Locale> read() async =>
      await SharedPreferencesAsync().getString('appearance.language') == 'en'
      ? const Locale('en', 'US')
      : const Locale('ko', 'KR');
  Future<void> write(String language) =>
      SharedPreferencesAsync().setString('appearance.language', language);
}
