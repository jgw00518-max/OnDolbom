import 'package:ondolbom/l10n/app_strings.dart';
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
  Widget _menuIcon(BuildContext context, IconData icon) => Container(
    width: 38,
    height: 38,
    decoration: BoxDecoration(
      color: AppColors.of(context).peachSoft,
      borderRadius: BorderRadius.circular(12),
    ),
    child: Icon(icon, size: 20, color: AppColors.resolve(context, _accent)),
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
      backgroundColor: AppColors.resolve(context, const Color(0xFFFFF8F3)),
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
                          Expanded(
                            child: Text(
                              AppStrings.tr(context, '온돌봄'),
                              style: TextStyle(
                                color: AppColors.resolve(context, _ink),
                                fontSize: 19,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: AppStrings.tr(context, '메뉴 닫기'),
                            onPressed: () => Navigator.of(context).pop(),
                            icon: Icon(
                              Icons.close,
                              color: AppColors.resolve(context, _ink),
                              size: 22,
                            ),
                          ),
                        ],
                      ),
                      Container(
                        margin: const EdgeInsets.only(top: 27, bottom: 23),
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: AppColors.of(context).peachLight,
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
                                color: AppColors.of(context).primary,
                                border: Border.all(
                                  color: AppColors.resolve(
                                    context,
                                    const Color(0xFFFFEBD9),
                                  ),
                                  width: 3,
                                ),
                              ),
                              child: Text(
                                name.characters.first,
                                style: TextStyle(
                                  color: AppColors.textPrimary,
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
                                  Text(
                                    AppStrings.tr(context, '반가워요,'),
                                    style: TextStyle(
                                      color: AppColors.resolve(
                                        context,
                                        Color(0xFF8C6553),
                                      ),
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    AppStrings.format(context, "{0} 님", [name]),
                                    style: TextStyle(
                                      color: AppColors.resolve(context, _ink),
                                      fontSize: 19,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    data?.email ?? user?.email ?? '',
                                    style: TextStyle(
                                      color: AppColors.resolve(
                                        context,
                                        Color(0xFF8C7770),
                                      ),
                                      fontSize: 12,
                                    ),
                                  ),
                                  if (data?.phone != null) ...[
                                    const SizedBox(height: 4),
                                    Text(
                                      data!.phone!,
                                      style: TextStyle(
                                        color: AppColors.resolve(
                                          context,
                                          Color(0xFF8C7770),
                                        ),
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
                          child: Text(AppStrings.tr(context, '사용자 정보 다시 확인')),
                        ),
                      Divider(
                        color: AppColors.resolve(context, Color(0xFFEADBD2)),
                        height: 1,
                      ),
                      const SizedBox(height: 11),
                      ListTileTheme(
                        data: ListTileThemeData(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 7,
                          ),
                          minVerticalPadding: 12,
                          horizontalTitleGap: 10,
                          titleTextStyle: TextStyle(
                            color: AppColors.resolve(context, _ink),
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                          ),
                          subtitleTextStyle: TextStyle(
                            color: AppColors.resolve(
                              context,
                              Color(0xFFA1958F),
                            ),
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
                              leading: _menuIcon(context, Icons.mail_outline),
                              trailing: ActivityBadge(count: counts.invites),
                              title: Text(AppStrings.tr(context, '초대')),
                              subtitle: Text(
                                AppStrings.tr(context, '가족을 공간에 초대해 보세요'),
                              ),
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
                              leading: _menuIcon(
                                context,
                                Icons.notifications_outlined,
                              ),
                              trailing: ActivityBadge(
                                count: counts.notifications,
                              ),
                              title: Text(AppStrings.tr(context, '알림')),
                              subtitle: Text(
                                AppStrings.tr(context, '새로운 소식을 확인하세요'),
                              ),
                              onTap: () => open(const NotificationsView()),
                            ),
                            ListTile(
                              leading: _menuIcon(
                                context,
                                Icons.campaign_outlined,
                              ),
                              trailing: ActivityBadge(count: counts.notices),
                              title: Text(AppStrings.tr(context, '공지사항')),
                              onTap: () => open(const NoticesView()),
                            ),
                            ListTile(
                              leading: _menuIcon(context, Icons.help_outline),
                              trailing: ActivityBadge(count: counts.inquiries),
                              title: Text(AppStrings.tr(context, '문의')),
                              subtitle: Text(
                                AppStrings.tr(context, '내 문의와 관리자 답변 확인'),
                              ),
                              onTap: () => open(
                                InquiriesView(familyRoomId: familyRoomId),
                              ),
                            ),
                            ListTile(
                              leading: _menuIcon(
                                context,
                                Icons.settings_outlined,
                              ),
                              trailing: Icon(
                                Icons.chevron_right,
                                size: 18,
                                color: AppColors.resolve(
                                  context,
                                  Color(0xFFB1A59F),
                                ),
                              ),
                              title: Text(AppStrings.tr(context, '개인 설정')),
                              onTap: () => open(const PersonalSettingsView()),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 11),
                      Divider(
                        color: AppColors.resolve(context, Color(0xFFEADBD2)),
                        height: 1,
                      ),
                      const Spacer(),
                      const SizedBox(height: 24),
                      ListTile(
                        textColor: AppColors.resolve(
                          context,
                          const Color(0xFF9B644F),
                        ),
                        iconColor: AppColors.resolve(
                          context,
                          const Color(0xFF9B644F),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 13,
                        ),
                        titleTextStyle: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                        leading: const Icon(Icons.logout),
                        title: Text(
                          operation.isLoading
                              ? AppStrings.tr(context, '로그아웃 중…')
                              : AppStrings.tr(context, '로그아웃'),
                        ),
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
                                    AppStrings.error(
                                      messenger.context,
                                      authErrorMessage(result.error!),
                                    ),
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
      tooltip: AppStrings.tr(context, '계정 메뉴'),
      icon: Semantics(
        label: hasNews
            ? AppStrings.tr(context, '확인할 새 소식 있음')
            : AppStrings.tr(context, '계정 메뉴'),
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
                  decoration: BoxDecoration(
                    color: AppColors.of(context).notificationDot,
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
          label: AppStrings.format(context, "확인할 소식 {0}개", [count]),
          child: Container(
            // ListTile의 높이와 관계없이 가로·세로가 같은 원형을 유지한다.
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.of(context).primary,
              shape: BoxShape.circle,
            ),
            child: Text(
              count > 99 ? '99+' : '$count',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
      ],
      Icon(
        Icons.chevron_right,
        size: 18,
        color: AppColors.resolve(context, Color(0xFFB1A59F)),
      ),
    ],
  );
}
