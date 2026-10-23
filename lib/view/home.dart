import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ondolbom/view/medications/medication_list_view.dart';
import 'package:ondolbom/view/memos/memo_list_view.dart';
import 'package:ondolbom/vm/family_context.dart';
import 'package:ondolbom/vm/auth/auth_vm.dart';
import 'package:ondolbom/vm/auth/user_profile_vm.dart';
import 'package:ondolbom/view/auth/profile_form_view.dart';
import 'package:ondolbom/view/notifications/notifications_view.dart';
import 'package:ondolbom/view/family_room_list.dart';

class Home extends ConsumerWidget {
  const Home({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authUserProvider).asData?.value;
    final operation = ref.watch(authVmProvider);
    // Firebase 로그인과 MySQL 사용자 등록은 별개이므로 서버 프로필을 추가 조회한다.
    final profile = ref.watch(userProfileProvider);
    final registration = ref.watch(profileRegistrationProvider);
    // MySQL 사용자 정보 등록까지 완료하면 공간 목록을 보여준다.
    if (profile.asData?.value != null) {
      return const FamilyRoomList();
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('온돌봄'),
        actions: [
          // 프로필 등록이 확인된 가족만 앱 내 알림 화면에 진입한다.
          if (profile.asData?.value != null)
            IconButton(
              tooltip: '알림',
              icon: const Icon(Icons.notifications_outlined),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const NotificationsView(),
                ),
              ),
            ),
        ],
      ),
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
                  // 서버가 미등록으로 응답한 경우에만 필수 정보 입력 폼을 표시한다.
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
                  // 프로필 저장 도중 계정을 바꾸지 않도록 로그아웃도 잠시 막는다.
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
