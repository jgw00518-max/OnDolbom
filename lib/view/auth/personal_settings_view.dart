import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ondolbom/vm/auth/auth_vm.dart';
import 'package:ondolbom/vm/auth/personal_settings_vm.dart';
import 'package:ondolbom/vm/auth/user_profile_vm.dart';

class PersonalSettingsView extends ConsumerWidget {
  const PersonalSettingsView({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(userProfileProvider).asData?.value;
    final user = ref.watch(authUserProvider).asData?.value;
    final settings = ref.watch(personalSettingsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('개인 설정')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text('내 정보', style: Theme.of(context).textTheme.titleLarge),
          ListTile(
            title: const Text('이름'),
            subtitle: Text(profile?.name ?? '등록 정보 없음'),
          ),
          ListTile(
            title: const Text('이메일'),
            subtitle: Text(profile?.email ?? user?.email ?? '등록 정보 없음'),
          ),
          ListTile(
            title: const Text('전화번호'),
            subtitle: Text(profile?.phone ?? '등록 정보 없음'),
          ),
          const Divider(),
          Text('이 기기의 로그인 설정', style: Theme.of(context).textTheme.titleLarge),
          settings.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, _) => Column(
              children: [
                Text(error.toString()),
                TextButton(
                  onPressed: () => ref.invalidate(personalSettingsProvider),
                  child: const Text('설정 다시 불러오기'),
                ),
              ],
            ),
            data: (value) => Column(
              children: [
                SwitchListTile(
                  title: const Text('아이디 저장'),
                  subtitle: const Text('현재 로그인한 이메일을 로그인 화면에 표시합니다.'),
                  value: value.rememberEmail,
                  onChanged: settings.isLoading
                      ? null
                      : (v) => ref
                            .read(personalSettingsProvider.notifier)
                            .save(rememberEmail: v),
                ),
                SwitchListTile(
                  title: const Text('자동 로그인'),
                  subtitle: const Text('앱을 다시 실행할 때 로그인 상태를 유지합니다.'),
                  value: value.autoLogin,
                  onChanged: settings.isLoading
                      ? null
                      : (v) => ref
                            .read(personalSettingsProvider.notifier)
                            .save(autoLogin: v),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
