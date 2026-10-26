import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final loginPreferencesProvider = Provider<LoginPreferences>(
  (ref) => LoginPreferences(),
);

/// 이 기기의 로그인 옵션만 보관한다. 비밀번호·토큰은 저장하지 않는다.
class LoginPreferences {
  SharedPreferencesAsync get _preferences => SharedPreferencesAsync();
  static const emailKey = 'auth.remembered_email';
  static const autoLoginKey = 'auth.auto_login';

  // 기존 설치도 사용자가 직접 선택하기 전에는 자동 로그인하지 않는다.
  Future<bool> readAutoLogin() async =>
      await _preferences.getBool(autoLoginKey) ?? false;

  Future<void> saveAutoLogin(bool enabled) =>
      _preferences.setBool(autoLoginKey, enabled);

  Future<String?> readEmail() => _preferences.getString(emailKey);

  Future<void> saveEmail(String email) =>
      _preferences.setString(emailKey, email.trim());

  // 다른 기능의 환경 설정은 지우지 않고 저장한 이메일만 제거한다.
  Future<void> clearEmail() => _preferences.remove(emailKey);
}
