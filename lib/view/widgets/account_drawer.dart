import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ondolbom/view/inquiries/inquiries_view.dart';
import 'package:ondolbom/view/invites/received_invites.dart';
import 'package:ondolbom/view/notifications/notifications_view.dart';
import 'package:ondolbom/view/auth/personal_settings_view.dart';
import 'package:ondolbom/vm/family_room/family_room_notifier.dart';
import 'package:ondolbom/vm/auth/auth_vm.dart';
import 'package:ondolbom/vm/auth/user_profile_vm.dart';

/// 공간 선택 전·후에 같은 계정 메뉴를 사용한다. 공간 역할을 계정 정보로 표시하지 않는다.
class AccountDrawer extends ConsumerWidget {
  const AccountDrawer({super.key, this.familyRoomId});
  final String? familyRoomId;
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(userProfileProvider);
    final user = ref.watch(authUserProvider).asData?.value;
    final data = profile.asData?.value;
    final operation = ref.watch(authVmProvider);
    void open(Widget page) {
      final navigator = Navigator.of(context);
      navigator.pop();
      navigator.push(MaterialPageRoute<void>(builder: (_) => page));
    }

    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: IconButton(
                tooltip: '메뉴 닫기',
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.close),
              ),
            ),
            const CircleAvatar(
              radius: 32,
              child: Icon(Icons.person_outline, size: 36),
            ),
            const SizedBox(height: 16),
            Text(
              data?.name ?? '가족 사용자',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: 8),
            Text(data?.email ?? user?.email ?? '', textAlign: TextAlign.center),
            if (data?.phone != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(data!.phone!, textAlign: TextAlign.center),
              ),
            if (profile.isLoading)
              const Padding(
                padding: EdgeInsets.all(12),
                child: LinearProgressIndicator(),
              ),
            if (profile.hasError)
              TextButton(
                onPressed: () => ref.invalidate(userProfileProvider),
                child: const Text('사용자 정보 다시 확인'),
              ),
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 20),
              child: Divider(),
            ),
            // 기능이 늘어나면 이 아래에 메뉴 항목을 추가한다.
            ListTile(
              leading: const Icon(Icons.mail_outline),
              title: const Text('초대'),
              onTap: () async {
                final navigator = Navigator.of(context);
                final rooms = ref.read(familyRoomProvider.notifier);
                navigator.pop();
                final accepted = await navigator.push<bool>(
                  MaterialPageRoute(builder: (_) => const ReceivedInvites()),
                );
                if (navigator.mounted && accepted == true) {
                  await rooms.fetchRooms();
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.notifications_outlined),
              title: const Text('알림'),
              onTap: () => open(const NotificationsView()),
            ),
            ListTile(
              leading: const Icon(Icons.help_outline),
              title: const Text('문의'),
              subtitle: const Text('내 문의와 관리자 답변 확인'),
              onTap: () {
                final navigator = Navigator.of(context);
                navigator.pop();
                navigator.push(
                  MaterialPageRoute<void>(
                    builder: (_) => InquiriesView(familyRoomId: familyRoomId),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings_outlined),
              title: const Text('개인 설정'),
              onTap: () => open(const PersonalSettingsView()),
            ),
            const Divider(),
            ListTile(
              leading: const Icon(Icons.logout),
              title: Text(operation.isLoading ? '로그아웃 중…' : '로그아웃'),
              enabled: !operation.isLoading,
              onTap: () async {
                // 로그인 스트림으로 Drawer가 사라져도 참조 가능한 객체를 먼저 확보한다.
                final navigator = Navigator.of(context);
                final messenger = ScaffoldMessenger.of(context);
                final container = ProviderScope.containerOf(
                  context,
                  listen: false,
                );
                final vm = ref.read(authVmProvider.notifier);
                Scaffold.of(context).closeDrawer();
                await vm.signOut();
                if (!navigator.mounted) return;
                final result = container.read(authVmProvider);
                if (result.hasError) {
                  if (messenger.mounted) {
                    messenger.showSnackBar(
                      SnackBar(content: Text(authErrorMessage(result.error!))),
                    );
                  }
                  return;
                }
                // 공간 내부 경로도 제거해 로그아웃 후 이전 화면으로 돌아가지 않도록 한다.
                navigator.popUntil((route) => route.isFirst);
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// 왼쪽 끝의 버튼으로 공통 Drawer를 연다.
class AccountMenuButton extends StatelessWidget {
  const AccountMenuButton({super.key});
  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: '계정 메뉴',
    icon: const Icon(Icons.menu),
    onPressed: () => Scaffold.of(context).openDrawer(),
  );
}
