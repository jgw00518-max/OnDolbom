import 'package:ondolbom/vm/auth/auth_vm.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ondolbom/model/family/family_room_onboarding_preferences.dart';

final familyRoomOnboardingProvider =
    NotifierProvider<FamilyRoomOnboardingVm, bool>(FamilyRoomOnboardingVm.new);

// 배포 기본값은 최초 1회 표시다. 반복 표시는 테스트에서 명시적으로 켤 때만 사용한다.
final familyRoomOnboardingRepeatOnLoginProvider = Provider<bool>(
  (ref) => false,
);

class FamilyRoomOnboardingVm extends Notifier<bool> {
  bool _checking = false;
  bool _completedInSession = false;
  int _session = 0;
  @override
  bool build() {
    ref.watch(authUserProvider.select((value) => value.asData?.value?.uid));
    _session++;
    _checking = false;
    _completedInSession = false;
    return false;
  }

  // 여러 목록 화면이 열려도 안내를 동시에 중복 표시하지 않는다.
  Future<bool> begin() async {
    if (_checking || state || _completedInSession) return false;
    _checking = true;
    final session = _session;
    try {
      final repeat = ref.read(familyRoomOnboardingRepeatOnLoginProvider);
      final completed = repeat
          ? false
          : await ref
                .read(familyRoomOnboardingPreferencesProvider)
                .readCompleted();
      if (!ref.mounted || session != _session || completed) return false;
      state = true;
      return true;
    } catch (_) {
      // 저장소 조회 장애가 기존 공간 진입을 막지 않도록 한다.
      debugPrint('온보딩 완료 여부를 읽지 못했습니다.');
      return false;
    } finally {
      if (session == _session) _checking = false;
    }
  }

  void release() {
    if (ref.mounted) state = false;
  }

  Future<void> finish() async {
    _completedInSession = true;
    state = false;
    try {
      await ref.read(familyRoomOnboardingPreferencesProvider).complete();
    } catch (_) {
      // 이번 실행에서는 재표시하지 않는다. 로컬 저장 실패를 성공으로 보고하지 않는다.
      debugPrint('온보딩 완료 상태를 저장하지 못했습니다.');
    }
  }
}
