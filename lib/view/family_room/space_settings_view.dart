import 'package:ondolbom/l10n/app_strings.dart';
import 'package:ondolbom/view/family_room/membership_exit_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ondolbom/theme/app_colors.dart';
import 'package:ondolbom/view/widgets/app_back_button.dart';
import 'package:ondolbom/view/exports/export_view.dart';
import 'package:ondolbom/view/invites/invite_create.dart';
import 'package:ondolbom/view/family_room/family_member_list.dart';
import 'package:ondolbom/view/family_room/family_room_delete_dialog.dart';
import 'package:ondolbom/vm/family_room/family_context.dart';
import 'package:ondolbom/vm/family_room/family_room_notifier.dart';

/// 선택한 공간의 조회·관리 기능을 역할별로 모은 화면이다.
class SpaceSettingsView extends ConsumerWidget {
  const SpaceSettingsView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(familyRoomProvider);
    final room = state.selectedRoom;
    final guardian =
        state.selectedParticipation?.isRepresentative == true &&
        state.selectedParticipation?.isActive == true;
    final danger = Theme.of(context).colorScheme.error;
    if (room == null) {
      return Scaffold(
        appBar: AppBar(
          leading: const AppBackLeading(),
          title: Text(AppStrings.tr(context, '공간 설정')),
        ),
        body: Center(child: Text(AppStrings.tr(context, '공간을 선택해 주세요.'))),
      );
    }
    return Scaffold(
      appBar: AppBar(
        leading: const AppBackLeading(),
        leadingWidth: 62,
        centerTitle: true,
        title: Text(AppStrings.tr(context, '공간 설정')),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 20),
            child: Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: AppColors.of(context).sageLight,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(
                Icons.settings_outlined,
                color: AppColors.of(context).sageDark,
              ),
            ),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 28, 20, 32),
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 16,
            runSpacing: 12,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    AppStrings.tr(context, '우리 가족'),
                    style: TextStyle(
                      color: AppColors.of(context).textSecondary,
                    ),
                  ),
                  SizedBox(height: 8),
                  Text(
                    AppStrings.tr(context, '공간을 관리해요'),
                    style: TextStyle(fontSize: 25, fontWeight: FontWeight.w800),
                  ),
                ],
              ),
              Chip(
                avatar: Icon(
                  guardian
                      ? Icons.workspace_premium_outlined
                      : Icons.person_outline,
                  size: 18,
                  color: AppColors.of(context).sageDark,
                ),
                label: Text(
                  guardian
                      ? AppStrings.tr(context, '주보호자')
                      : AppStrings.tr(context, '일반 가족'),
                ),
                backgroundColor: AppColors.of(context).sageLight,
                side: BorderSide.none,
              ),
            ],
          ),
          const SizedBox(height: 28),
          _label(AppStrings.tr(context, '공간 정보')),
          _group(context, [
            if (guardian)
              _action(
                context,
                AppStrings.tr(context, '가족 초대'),
                AppStrings.tr(context, '새로운 가족을 공간에 초대해요'),
                Icons.person_add_alt_outlined,
                AppColors.of(context).sageLight,
                () async {
                  final sent = await Navigator.of(context).push<bool>(
                    MaterialPageRoute(
                      builder: (_) => InviteCreate(
                        familyRoomId: room.familyRoomId,
                        recipientName: room.careRecipientName,
                      ),
                    ),
                  );
                  if (!context.mounted || sent == null) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        AppStrings.error(
                          context,
                          sent
                              ? AppStrings.tr(context, '초대를 등록하고 이메일을 발송했습니다.')
                              : AppStrings.tr(
                                  context,
                                  '초대는 등록했지만 이메일 발송에 실패했습니다.',
                                ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            _action(
              context,
              AppStrings.tr(context, '함께하는 가족'),
              AppStrings.tr(context, '참여 중인 가족과 공간별 역할을 확인해요'),
              Icons.groups_outlined,
              AppColors.of(context).sageLight,
              () => _open(
                context,
                FamilyMemberList(familyRoomId: room.familyRoomId),
              ),
            ),
          ]),
          const SizedBox(height: 24),
          // 가족 조회는 눌렀을 때만 요청하고, 기록 내보내기는 공간 관리에 둔다.
          _label(AppStrings.tr(context, '공간 관리')),
          _group(context, [
            _action(
              context,
              AppStrings.tr(context, '메모 및 채팅 내보내기'),
              AppStrings.tr(context, '공간의 기록을 파일로 저장해요'),
              Icons.file_download_outlined,
              AppColors.of(context).peachSoft,
              () {
                final selected = ref.read(familyContextProvider);
                if (selected.familyRoomId != room.familyRoomId) return;
                _open(context, ExportView(selected: selected));
              },
            ),

            _action(
              context,
              AppStrings.tr(context, '공간에서 나가기'),
              AppStrings.tr(context, '내 계정만 이 공간에서 나가요'),
              Icons.logout,
              AppColors.of(context).peachSoft,
              state.isLoading
                  ? null
                  : () async {
                      if (guardian) {
                        _notice(
                          context,
                          AppStrings.tr(
                            context,
                            '공간에서 나가려면 먼저 주보호자 이전이 필요해요. 함께하는 가족에서 이전해 주세요.',
                          ),
                        );
                        return;
                      }
                      final navigator = Navigator.of(context);
                      final left = await showDialog<bool>(
                        context: context,
                        barrierDismissible: false,
                        builder: (_) => MembershipExitDialog(
                          familyRoomId: room.familyRoomId,
                        ),
                      );
                      if (!context.mounted || left != true) return;
                      final notifier = ref.read(familyRoomProvider.notifier);
                      navigator.popUntil((route) => route.isFirst);
                      await notifier.fetchRooms();
                    },
              color: danger,
            ),
            if (guardian)
              _action(
                context,
                AppStrings.tr(context, '돌봄 공간 삭제'),
                AppStrings.tr(context, '공간을 삭제 처리하고 가족의 접근을 종료해요'),
                Icons.delete_outline,
                AppColors.of(context).peachSoft,
                state.isLoading
                    ? null
                    : () async {
                        // 기존 이름 확인과 서버 권한 검사를 유지하며 실제 삭제 흐름을 이동한다.
                        final navigator = Navigator.of(context);
                        final deleted = await showDialog<bool>(
                          context: context,
                          barrierDismissible: false,
                          builder: (_) => FamilyRoomDeleteDialog(room: room),
                        );
                        if (!context.mounted || deleted != true) return;
                        final notifier = ref.read(familyRoomProvider.notifier);
                        navigator.popUntil((route) => route.isFirst);
                        await notifier.fetchRooms();
                      },
                color: danger,
              ),
          ]),
        ],
      ),
    );
  }

  Widget _label(String text, {Color color = AppColors.textSecondary}) =>
      Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(
          text,
          style: TextStyle(color: color, fontWeight: FontWeight.w700),
        ),
      );

  Widget _group(BuildContext context, List<Widget> children) => Material(
    color: AppColors.of(context).surface,
    shape: RoundedRectangleBorder(
      side: BorderSide(color: AppColors.of(context).border),
      borderRadius: BorderRadius.circular(24),
    ),
    clipBehavior: Clip.antiAlias,
    child: Column(
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0)
            Divider(
              height: 1,
              indent: 20,
              endIndent: 20,
              color: AppColors.of(context).border,
            ),
          children[i],
        ],
      ],
    ),
  );

  Widget _action(
    BuildContext context,
    String title,
    String subtitle,
    IconData icon,
    Color background,
    VoidCallback? action, {
    Color color = AppColors.textPrimary,
  }) => ListTile(
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    leading: Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(15),
      ),
      child: Icon(icon, color: color),
    ),
    title: Text(
      title,
      style: TextStyle(fontWeight: FontWeight.w700, color: color),
    ),
    subtitle: Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Text(
        subtitle,
        style: TextStyle(
          fontSize: 12,
          color: AppColors.of(context).textSecondary,
        ),
      ),
    ),
    trailing: Icon(
      Icons.chevron_right,
      color: AppColors.of(context).textSecondary,
    ),
    onTap: action,
  );

  void _open(BuildContext context, Widget page) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

  void _notice(BuildContext context, String message) => ScaffoldMessenger.of(
    context,
  ).showSnackBar(SnackBar(content: Text(AppStrings.error(context, message))));
}
