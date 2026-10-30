import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

final familyRoomOnboardingPreferencesProvider =
    Provider<FamilyRoomOnboardingPreferences>(
      (ref) => FamilyRoomOnboardingPreferences(),
    );

// 계정 정보와 분리한 기기 설치 기준 설정이다. 로그아웃 때 지우지 않는다.
class FamilyRoomOnboardingPreferences {
  static const completedKey = 'family_room.onboarding.completed';
  Future<bool> readCompleted() async =>
      await SharedPreferencesAsync().getBool(completedKey) ?? false;
  Future<void> complete() =>
      SharedPreferencesAsync().setBool(completedKey, true);
}
