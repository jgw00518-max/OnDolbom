import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ondolbom/vm/auth/auth_vm.dart';
import 'package:ondolbom/vm/auth/user_profile_vm.dart';
import 'package:ondolbom/view/auth/profile_form_view.dart';

class Home extends ConsumerWidget {
  const Home({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authUserProvider).asData?.value;
    final operation = ref.watch(authVmProvider);
    final profile = ref.watch(userProfileProvider);
    final registration = ref.watch(profileRegistrationProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('온돌봄')),
      body: SingleChildScrollView(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(user?.email ?? '로그인됨'),
                const SizedBox(height: 12),
                const Text('Firebase 로그인이 완료되었습니다.'),
                profile.when(
                  loading: () => const Padding(
                    padding: EdgeInsets.all(12),
                    child: CircularProgressIndicator(),
                  ),
                  error: (error, _) => Column(
                    children: [
                      Text(error.toString(), textAlign: TextAlign.center),
                      TextButton(
                        onPressed: () => ref.invalidate(userProfileProvider),
                        child: const Text('사용자 정보 다시 확인'),
                      ),
                    ],
                  ),
                  data: (value) => value == null
                      ? const ProfileFormView()
                      : Text(
                          '${value.name ?? value.email ?? '가족'}님, 사용자 정보가 연결되었습니다.',
                          textAlign: TextAlign.center,
                        ),
                ),
                if (operation.hasError)
                  Text(authErrorMessage(operation.error!)),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: operation.isLoading || registration.isLoading
                      ? null
                      : () {
                          ref.read(authVmProvider.notifier).signOut();
                        },
                  child: Text(operation.isLoading ? '처리 중…' : '로그아웃'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
