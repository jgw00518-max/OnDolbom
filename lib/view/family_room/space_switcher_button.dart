import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ondolbom/theme/app_colors.dart';
import 'package:ondolbom/view/family_room/family_room_list.dart';
import 'package:ondolbom/vm/auth/auth_vm.dart';
import 'package:ondolbom/vm/family_room/family_room_notifier.dart';

/// 공간 메인에서 목록 복귀와 참여 공간 전환을 한곳에서 제공한다.
class SpaceSwitcherButton extends ConsumerWidget {
  const SpaceSwitcherButton({super.key});

  Future<void> _open(BuildContext context, WidgetRef ref) async {
    final uid = ref.read(authUserProvider).asData?.value?.uid;
    final owner = ref.read(familyRoomProvider).selectedParticipation?.userId;
    // 화면 전체를 덮는 시트 대신 집 버튼 위에 떠 있는 작은 메뉴로 표시한다.
    // 바깥 영역을 누르거나 뒤로 가기를 누르면 선택 없이 닫힌다.
    final choice = await showDialog<({bool list, String? roomId})>(
      context: context,
      barrierColor: Colors.transparent,
      builder: (sheetContext) => Align(
        alignment: Alignment.bottomRight,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
          child: Material(
            color: AppColors.background,
            elevation: 8,
            shadowColor: AppColors.textPrimary.withValues(alpha: .16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
              side: const BorderSide(color: AppColors.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: Consumer(
              builder: (context, ref, _) {
                final state = ref.watch(familyRoomProvider);
                final sameAccount =
                    ref.watch(authUserProvider).asData?.value?.uid == uid;
                // 초대 대기·참여 종료 공간은 참여 목록에 넣지 않는다.
                final rooms = sameAccount
                    ? state.rooms.where((room) {
                        final member = state.participations[room.familyRoomId];
                        return member != null &&
                            member.isActive &&
                            member.userId == owner;
                      }).toList()
                    : [];
                return SizedBox(
                  width: 320,
                  height: (MediaQuery.sizeOf(context).height * .52).clamp(
                    0,
                    440,
                  ),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(14, 8, 14, 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                '공간 이동',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: AppColors.textPrimary,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: '닫기',
                              onPressed: () => Navigator.pop(sheetContext),
                              icon: const Icon(Icons.close),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Material(
                          color: AppColors.peachSoft,
                          borderRadius: BorderRadius.circular(18),
                          child: ListTile(
                            leading: const Icon(
                              Icons.home_outlined,
                              color: AppColors.sageDark,
                            ),
                            title: const Text(
                              '돌봄 공간 목록으로',
                              style: TextStyle(fontWeight: FontWeight.w700),
                            ),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: !sameAccount
                                ? null
                                : () => Navigator.pop(sheetContext, (
                                    list: true,
                                    roomId: null,
                                  )),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          children: [
                            const Expanded(
                              child: Text(
                                '참여 중인 공간',
                                style: TextStyle(fontWeight: FontWeight.w700),
                              ),
                            ),
                            IconButton(
                              tooltip: '공간 목록 새로고침',
                              onPressed: state.isLoading || !sameAccount
                                  ? null
                                  : () => ref
                                        .read(familyRoomProvider.notifier)
                                        .fetchRooms(),
                              icon: const Icon(Icons.refresh, size: 21),
                            ),
                          ],
                        ),
                        if (state.isLoading) const LinearProgressIndicator(),
                        Expanded(
                          child: !sameAccount
                              ? const Center(child: Text('로그인 계정이 변경되었습니다.'))
                              : state.errorMessage != null
                              ? const Center(
                                  child: Text(
                                    '공간 목록을 불러오지 못했습니다. 다시 새로고침해 주세요.',
                                    textAlign: TextAlign.center,
                                  ),
                                )
                              : rooms.isEmpty
                              ? const Center(child: Text('참여 중인 공간이 없습니다.'))
                              : ListView.separated(
                                  itemCount: rooms.length,
                                  separatorBuilder: (_, _) =>
                                      const SizedBox(height: 10),
                                  itemBuilder: (context, index) {
                                    final room = rooms[index];
                                    final selected =
                                        room.familyRoomId ==
                                        state.selectedRoomId;
                                    return Material(
                                      color: selected
                                          ? AppColors.peachSoft
                                          : AppColors.surface,
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(18),
                                        side: BorderSide(
                                          color: selected
                                              ? AppColors.primary
                                              : AppColors.border,
                                        ),
                                      ),
                                      child: ListTile(
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                              horizontal: 12,
                                              vertical: 2,
                                            ),
                                        leading: const Icon(
                                          Icons.home_outlined,
                                          color: AppColors.sageDark,
                                        ),
                                        title: Text(
                                          '${room.careRecipientName} 님의 돌봄 공간',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                          ),
                                        ),
                                        subtitle: Text(
                                          '${state.participations[room.familyRoomId]!.isRepresentative ? '주보호자' : '일반 가족'}${selected ? ' · 현재 공간' : ''}',
                                        ),
                                        trailing: Icon(
                                          selected
                                              ? Icons.check_circle
                                              : Icons.chevron_right,
                                          color: selected
                                              ? AppColors.sageDark
                                              : AppColors.textSecondary,
                                        ),
                                        onTap: state.isLoading
                                            ? null
                                            : () =>
                                                  Navigator.pop(sheetContext, (
                                                    list: false,
                                                    roomId: room.familyRoomId,
                                                  )),
                                      ),
                                    );
                                  },
                                ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
    // 메뉴를 열어 둔 동안 계정·참여 정보가 바뀌면 이전 선택을 적용하지 않는다.
    if (!context.mounted ||
        choice == null ||
        ref.read(authUserProvider).asData?.value?.uid != uid) {
      return;
    }
    final navigator = Navigator.of(context);
    if (choice.list) {
      if (navigator.canPop()) {
        navigator.popUntil((route) => route.isFirst);
      } else {
        // 단독으로 메인을 연 경우에도 목록으로 복귀할 수 있게 한다.
        navigator.pushReplacement(
          MaterialPageRoute<void>(builder: (_) => const FamilyRoomList()),
        );
      }
      return;
    }
    final current = ref.read(familyRoomProvider);
    final member = current.participations[choice.roomId];
    if (member == null ||
        !member.isActive ||
        member.userId != owner ||
        current.isLoading) {
      return;
    }
    // 메인 화면은 선택 상태를 감시하므로 새 경로를 쌓지 않고 즉시 전환된다.
    ref.read(familyRoomProvider.notifier).selectRoom(choice.roomId!);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) => FloatingActionButton(
    heroTag: null,
    tooltip: '돌봄 공간 이동',
    onPressed: () => _open(context, ref),
    backgroundColor: AppColors.peachLight,
    foregroundColor: AppColors.textPrimary,
    elevation: 2,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(18),
      side: const BorderSide(color: AppColors.border),
    ),
    child: const Icon(Icons.home_outlined, size: 30),
  );
}
