import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ondolbom/model/auth/login_preferences.dart';
import 'package:ondolbom/vm/auth/auth_vm.dart';

typedef PersonalSettings = ({bool rememberEmail, bool autoLogin});
final personalSettingsProvider =
    AsyncNotifierProvider.autoDispose<PersonalSettingsVm, PersonalSettings>(
      PersonalSettingsVm.new,
      retry: (_, _) => null,
    );

class PersonalSettingsVm extends AsyncNotifier<PersonalSettings> {
  @override
  Future<PersonalSettings> build() async {
    ref.watch(authUserProvider);
    final preferences = ref.watch(loginPreferencesProvider);
    final email = await preferences.readEmail();
    return (
      rememberEmail: email != null,
      autoLogin: await preferences.readAutoLogin(),
    );
  }

  Future<void> save({bool? rememberEmail, bool? autoLogin}) async {
    if (state.isLoading || !state.hasValue) return;
    final previous = state.requireValue;
    final preferences = ref.read(loginPreferencesProvider);
    final user = ref.read(authUserProvider).asData?.value;
    state = const AsyncLoading();
    try {
      if (rememberEmail != null) {
        if (rememberEmail) {
          if (user?.email == null) throw StateError('Email unavailable');
          // 이미 로그인한 계정의 이메일만 저장한다. 비밀번호·토큰은 저장하지 않는다.
          await preferences.saveEmail(user!.email!);
        } else {
          await preferences.clearEmail();
        }
      }
      if (autoLogin != null) await preferences.saveAutoLogin(autoLogin);
      if (ref.mounted) {
        state = AsyncData((
          rememberEmail: rememberEmail ?? previous.rememberEmail,
          autoLogin: autoLogin ?? previous.autoLogin,
        ));
      }
    } catch (_, stack) {
      if (ref.mounted) {
        state = AsyncError('설정을 저장하지 못했습니다. 다시 불러온 후 시도해 주세요.', stack);
      }
    }
  }
}
