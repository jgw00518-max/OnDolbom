import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ondolbom/model/settings/theme_preferences.dart';

// 실제 앱은 실행 전에 읽은 값을 전달해 다크 모드 시작 시 밝은 화면이 깜빡이지 않게 한다.
final initialThemeModeProvider = Provider<ThemeMode?>((ref) => null);

class ThemeSetting {
  const ThemeSetting(this.mode, {this.saving = false, this.error});
  final ThemeMode mode;
  final bool saving;
  final String? error;
}

final themeModeProvider = AsyncNotifierProvider<ThemeVm, ThemeSetting>(
  ThemeVm.new,
  retry: (_, _) => null,
);

class ThemeVm extends AsyncNotifier<ThemeSetting> {
  @override
  FutureOr<ThemeSetting> build() {
    final initial = ref.watch(initialThemeModeProvider);
    if (initial != null) return ThemeSetting(initial);
    return ref.watch(themePreferencesProvider).read().then(ThemeSetting.new);
  }

  Future<void> select(bool dark) async {
    final old = state.asData?.value;
    if (old == null || old.saving) return;
    state = AsyncData(ThemeSetting(old.mode, saving: true));
    try {
      final mode = dark ? ThemeMode.dark : ThemeMode.light;
      // 저장 실패 시 현재 모드를 유지한다. 인증·계정 데이터와는 독립적인 기기 설정이다.
      await ref.read(themePreferencesProvider).write(mode);
      if (ref.mounted) state = AsyncData(ThemeSetting(mode));
    } catch (_) {
      if (ref.mounted) {
        state = AsyncData(
          ThemeSetting(old.mode, error: '화면 설정을 저장하지 못했습니다. 다시 시도해 주세요.'),
        );
      }
    }
  }
}
