import 'package:ondolbom/theme/app_colors.dart';
import 'package:ondolbom/vm/activity/activity_vm.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ondolbom/view/inquiries/inquiries_view.dart';
import 'package:ondolbom/view/notices/notices_view.dart';
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

  static const _ink = AppColors.textPrimary;
  static const _accent = Color(0xFF875C49);

  // 메뉴의 이동 콜백은 유지하고 아이콘·문구·간격만 공통 스타일로 감싼다.
  Widget _menuIcon(IconData icon) => Container(
    width: 38,
    height: 38,
    decoration: BoxDecoration(
      color: AppColors.peachSoft,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Icon(icon, size: 20, color: _accent),
  );
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final counts = ref.watch(activityProvider);
    final profile = ref.watch(userProfileProvider);
    final user = ref.watch(authUserProvider).asData?.value;
    final data = profile.asData?.value;
    final operation = ref.watch(authVmProvider);
    Future<void> open(Widget page) async {
      final navigator = Navigator.of(context);
      final activity = ref.read(activityProvider.notifier);
      navigator.pop();
      await navigator.push(MaterialPageRoute<void>(builder: (_) => page));
      activity.refresh(force: true);
    }

    final name = (data?.name?.trim().isNotEmpty ?? false)
        ? data!.name!
        : '가족 사용자';
    return Drawer(
      width: (MediaQuery.sizeOf(context).width * 0.88).clamp(0.0, 400.0),
      backgroundColor: const Color(0xFFFFF8F3),
      surfaceTintColor: Colors.transparent,
      shape: const RoundedRectangleBorder(),
      child: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: IntrinsicHeight(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(23, 25, 23, 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              '온돌봄',
                              style: TextStyle(
                                color: _ink,
                                fontSize: 19,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: '메뉴 닫기',
                            onPressed: () => Navigator.of(context).pop(),
                            icon: const Icon(
                              Icons.close,
                              color: _ink,
                              size: 22,
                            ),
                          ),
                        ],
                      ),
                      Container(
                        margin: const EdgeInsets.only(top: 27, bottom: 23),
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: AppColors.peachLight,
                          borderRadius: BorderRadius.circular(19),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 56,
                              height: 56,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: AppColors.primary,
                                border: Border.all(
                                  color: const Color(0xFFFFEBD9),
                                  width: 3,
                                ),
                              ),
                              child: Text(
                                name.characters.first,
                                style: const TextStyle(
                                  color: Color(0xFF684331),
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                            const SizedBox(width: 15),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text(
                                    '반가워요,',
                                    style: TextStyle(
                                      color: Color(0xFF8C6553),
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    '$name 님',
                                    style: const TextStyle(
                                      color: _ink,
                                      fontSize: 19,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    data?.email ?? user?.email ?? '',
                                    style: const TextStyle(
                                      color: Color(0xFF8C7770),
                                      fontSize: 12,
                                    ),
                                  ),
                                  if (data?.phone != null) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      data!.phone!,
                                      style: const TextStyle(
                                        color: Color(0xFF8C7770),
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ],
                        ),
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
                      const Divider(color: Color(0xFFEADBD2), height: 1),
                      const SizedBox(height: 11),
                      ListTileTheme(
                        data: ListTileThemeData(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 7,
                          ),
                          minVerticalPadding: 12,
                          horizontalTitleGap: 10,
                          titleTextStyle: const TextStyle(
                            color: _ink,
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                          subtitleTextStyle: const TextStyle(
                            color: Color(0xFFA1958F),
                            fontSize: 11,
                            height: 1.5,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(13),
                          ),
                        ),
                        child: Column(
                          children: [
                            // 기능이 늘어나면 이 아래에 메뉴 항목을 추가한다.
                            ListTile(
                              leading: _menuIcon(Icons.mail_outline),
                              trailing: ActivityBadge(count: counts.invites),
                              title: const Text('초대'),
                              subtitle: const Text('가족을 공간에 초대해 보세요'),
                              onTap: () async {
                                final navigator = Navigator.of(context);
                                final activity = ref.read(
                                  activityProvider.notifier,
                                );
                                final rooms = ref.read(
                                  familyRoomProvider.notifier,
                                );
                                navigator.pop();
                                final accepted = await navigator.push<bool>(
                                  MaterialPageRoute(
                                    builder: (_) => const ReceivedInvites(),
                                  ),
                                );
                                if (navigator.mounted && accepted == true) {
                                  await rooms.fetchRooms();
                                }
                                activity.refresh(force: true);
                              },
                            ),
                            ListTile(
                              leading: _menuIcon(Icons.notifications_outlined),
                              trailing: ActivityBadge(
                                count: counts.notifications,
                              ),
                              title: const Text('알림'),
                              subtitle: const Text('새로운 소식을 확인하세요'),
                              onTap: () => open(const NotificationsView()),
                            ),
                            ListTile(
                              leading: _menuIcon(Icons.campaign_outlined),
                              trailing: ActivityBadge(count: counts.notices),
                              title: const Text('공지사항'),
                              onTap: () => open(const NoticesView()),
                            ),
                            ListTile(
                              leading: _menuIcon(Icons.help_outline),
                              trailing: ActivityBadge(count: counts.inquiries),
                              title: const Text('문의'),
                              subtitle: const Text('내 문의와 관리자 답변 확인'),
                              onTap: () => open(
                                InquiriesView(familyRoomId: familyRoomId),
                              ),
                            ),
                            ListTile(
                              leading: _menuIcon(Icons.settings_outlined),
                              trailing: const Icon(
                                Icons.chevron_right,
                                size: 18,
                                color: Color(0xFFB1A59F),
                              ),
                              title: const Text('개인 설정'),
                              onTap: () => open(const PersonalSettingsView()),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 11),
                      const Divider(color: Color(0xFFEADBD2), height: 1),
                      const Spacer(),
                      const SizedBox(height: 24),
                      ListTile(
                        textColor: const Color(0xFF9B644F),
                        iconColor: const Color(0xFF9B644F),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 13,
                        ),
                        titleTextStyle: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
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
                                SnackBar(
                                  content: Text(
                                    authErrorMessage(result.error!),
                                  ),
                                ),
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
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 왼쪽 끝의 버튼으로 공통 Drawer를 연다.
class AccountMenuButton extends ConsumerWidget {
  const AccountMenuButton({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasNews = ref.watch(
      activityProvider.select((value) => value.hasNews),
    );
    return IconButton(
      tooltip: '계정 메뉴',
      icon: Semantics(
        label: hasNews ? '확인할 새 소식 있음' : '계정 메뉴',
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            const Icon(Icons.menu),
            if (hasNews)
              Positioned(
                right: -3,
                top: -3,
                child: Container(
                  key: const ValueKey('account-news-dot'),
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: AppColors.notificationDot,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
          ],
        ),
      ),
      onPressed: () {
        ref.read(activityProvider.notifier).refresh();
        Scaffold.of(context).openDrawer();
      },
    );
  }
}

/// 0건은 숨기고 큰 숫자는 99+로 표시한다. 화살표는 기존 탐색 방향을 유지한다.
class ActivityBadge extends StatelessWidget {
  const ActivityBadge({super.key, required this.count});
  final int count;
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      if (count > 0) ...[
        Semantics(
          label: '확인할 소식 $count개',
          child: Container(
            // ListTile의 높이와 관계없이 가로·세로가 같은 원형을 유지한다.
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: const BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
            ),
            child: Text(
              count > 99 ? '99+' : '$count',
              style: const TextStyle(
                color: AppColors.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
      ],
      const Icon(Icons.chevron_right, size: 18, color: Color(0xFFB1A59F)),
    ],
  );
}
