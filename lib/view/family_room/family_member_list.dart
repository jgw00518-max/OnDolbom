import 'package:ondolbom/view/family_room/membership_exit_dialog.dart';
import 'package:ondolbom/theme/app_colors.dart';
import 'package:ondolbom/vm/family_room/family_room_notifier.dart';
import 'package:ondolbom/view/widgets/app_back_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ondolbom/model/family/family_member.dart';
import 'package:ondolbom/vm/family_room/family_member_vm.dart';

class FamilyMemberList extends ConsumerWidget {
  const FamilyMemberList({super.key, required this.familyRoomId});

  final String familyRoomId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final members = ref.watch(familyMembersProvider(familyRoomId));
    final state = ref.watch(familyRoomProvider);
    final canManage =
        state.selectedRoomId == familyRoomId &&
        state.selectedParticipation?.isRepresentative == true &&
        state.selectedParticipation?.isActive == true;

    return Scaffold(
      appBar: AppBar(
        leadingWidth: 62,
        leading: const AppBackLeading(),
        title: const Text('함께하는 가족'),
        actions: [
          IconButton(
            tooltip: '새로고침',
            onPressed: () {
              ref.invalidate(familyMembersProvider(familyRoomId));
            },
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: members.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  error.toString().replaceFirst('Exception: ', ''),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                OutlinedButton(
                  onPressed: () {
                    ref.invalidate(familyMembersProvider(familyRoomId));
                  },
                  child: const Text('다시 조회'),
                ),
              ],
            ),
          ),
        ),
        data: (items) {
          if (items.isEmpty) {
            return const Center(child: Text('참여 중인 가족이 없습니다.'));
          }

          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Text(
                '우리 공간의 가족 ${items.length}명',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF403C39),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                '소중한 일상을 함께 돌보는 가족들이에요.',
                style: TextStyle(
                  fontSize: 14,
                  color: Color(0xFF78716A),
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 24),
              Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  border: Border.all(color: AppColors.border),
                  borderRadius: BorderRadius.circular(24),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  children: [
                    for (var i = 0; i < items.length; i++) ...[
                      if (i > 0)
                        const Divider(
                          height: 1,
                          indent: 20,
                          endIndent: 20,
                          color: AppColors.border,
                        ),
                      FamilyMemberCard(
                        member: items[i],
                        canManage: canManage,
                        onRemove: state.isLoading
                            ? null
                            : () async {
                                final removed = await showDialog<bool>(
                                  context: context,
                                  barrierDismissible: false,
                                  builder: (_) => MembershipExitDialog(
                                    familyRoomId: familyRoomId,
                                    target: items[i],
                                  ),
                                );
                                if (!context.mounted || removed != true) return;
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('가족의 공간 참여를 종료했습니다.'),
                                  ),
                                );
                              },
                      ),
                    ],
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 이름·역할과 관리 버튼을 분리해 가족별 작업 대상을 명확히 보여 준다.
class FamilyMemberCard extends StatelessWidget {
  const FamilyMemberCard({
    super.key,
    required this.member,
    this.canManage = false,
    this.onRemove,
  });
  final FamilyMember member;
  final bool canManage;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final name = member.name?.trim();
    final displayName = name == null || name.isEmpty ? '가족' : name;
    final email = member.email?.trim();
    final owner = member.isRepresentative;
    final actions = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        _button(
          context,
          '이전',
          '주보호자 이전',
          Icons.workspace_premium_outlined,
          AppColors.sageDark,
        ),
        _button(
          context,
          '강퇴',
          '가족 강퇴',
          Icons.person_remove_outlined,
          Theme.of(context).colorScheme.error,
          onPressed: onRemove,
        ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 작은 화면·큰 글씨에서는 버튼을 다음 줄로 내려 이름과 겹치지 않게 한다.
          final stacked =
              constraints.maxWidth < 300 ||
              MediaQuery.textScalerOf(context).scale(14) > 18;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              CircleAvatar(
                radius: 25,
                backgroundColor: owner
                    ? AppColors.peachLight
                    : AppColors.sageLight,
                child: Text(
                  displayName.characters.first,
                  style: const TextStyle(
                    color: AppColors.sageDark,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 8,
                      runSpacing: 5,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          displayName,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.peachSoft,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            member.roleName,
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      email == null || email.isEmpty ? '등록된 이메일이 없습니다.' : email,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textSecondary,
                      ),
                    ),
                    if (canManage && !owner && stacked) ...[
                      const SizedBox(height: 12),
                      actions,
                    ],
                  ],
                ),
              ),
              if (canManage && !owner && !stacked) ...[
                const SizedBox(width: 12),
                actions,
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _button(
    BuildContext context,
    String label,
    String feature,
    IconData icon,
    Color color, {
    VoidCallback? onPressed,
  }) => Tooltip(
    message: feature,
    child: OutlinedButton.icon(
      // 주보호자 이전은 준비 중이며 강퇴만 확인창과 실제 API로 연결한다.
      onPressed: label == '강퇴'
          ? onPressed
          : () => ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text('$feature 기능은 준비 중이에요.'))),
      icon: Icon(icon, size: 16),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        backgroundColor: AppColors.surface,
        minimumSize: const Size(64, 44),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        side: const BorderSide(color: AppColors.border),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
  );
}
