import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ondolbom/model/settings/locale_preferences.dart';

final initialLocaleProvider = Provider<Locale?>((ref) => null);

class LocaleSetting {
  const LocaleSetting(this.locale, {this.saving = false, this.error});
  final Locale locale;
  final bool saving;
  final String? error;
}

final localeSettingProvider = AsyncNotifierProvider<LocaleVm, LocaleSetting>(
  LocaleVm.new,
  retry: (_, _) => null,
);

class LocaleVm extends AsyncNotifier<LocaleSetting> {
  @override
  FutureOr<LocaleSetting> build() {
    final initial = ref.watch(initialLocaleProvider);
    return initial == null
        ? ref.watch(localePreferencesProvider).read().then(LocaleSetting.new)
        : LocaleSetting(initial);
  }

  Future<void> select(String language) async {
    if (!['ko', 'en'].contains(language)) return;
    final previous = state.asData?.value;
    if (previous == null || previous.saving) return;
    state = AsyncData(LocaleSetting(previous.locale, saving: true));
    try {
      // 저장 성공 후 전환하며 실패하면 열린 화면의 언어를 그대로 유지한다.
      await ref.read(localePreferencesProvider).write(language);
      if (ref.mounted) {
        state = AsyncData(
          LocaleSetting(
            language == 'en'
                ? const Locale('en', 'US')
                : const Locale('ko', 'KR'),
          ),
        );
      }
    } catch (_) {
      if (ref.mounted) {
        state = AsyncData(
          LocaleSetting(
            previous.locale,
            error: '언어 설정을 저장하지 못했습니다. 다시 시도해 주세요.',
          ),
        );
      }
    }
  }
}
