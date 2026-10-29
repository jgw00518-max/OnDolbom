import 'package:ondolbom/view/widgets/menu_header_icon.dart';
import 'package:ondolbom/theme/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ondolbom/vm/family_room/family_room_notifier.dart';
import 'package:ondolbom/view/family_room/family_room_home.dart';
import 'package:ondolbom/view/family_room/family_room_create.dart';

import 'package:ondolbom/view/invites/received_invites.dart';
import 'package:ondolbom/view/widgets/account_drawer.dart';

class FamilyRoomList extends ConsumerStatefulWidget {
  const FamilyRoomList({super.key});

  @override
  ConsumerState<FamilyRoomList> createState() => _FamilyRoomListState();
}

class _FamilyRoomListState extends ConsumerState<FamilyRoomList> {
  @override
  void initState() {
    super.initState();

    // 첫 화면이 만들어진 다음 한 번 조회한다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      ref.read(familyRoomProvider.notifier).fetchRooms();
    });
  }

  // 화면 디자인만 변경하고 기존 공간 조회·선택·생성 동작은 유지한다.
  static const _ink = AppColors.textPrimary;
  static const _paper = AppColors.background;
  static const _muted = Color(0xFF918782);

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(familyRoomProvider);
    return Scaffold(
      backgroundColor: _paper,
      drawer: const AccountDrawer(),
      // 목록 안의 생성 카드를 대신하며 기존 공간 생성·완료 후 갱신을 재사용한다.
      floatingActionButton: FloatingActionButton(
        tooltip: '새 돌봄 공간 만들기',
        onPressed: () => createRoomAction(context),
        backgroundColor: AppColors.peachLight,
        foregroundColor: AppColors.textPrimary,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: AppColors.border),
        ),
        child: const Icon(Icons.add, size: 32),
      ),
      appBar: AppBar(
        backgroundColor: _paper,
        foregroundColor: _ink,
        surfaceTintColor: Colors.transparent,
        toolbarHeight: 88,
        automaticallyImplyLeading: false,
        leading: const AccountMenuButton(),
        centerTitle: true,
        title: const Column(
          children: [
            Text(
              'OUR HOME',
              style: TextStyle(
                color: Color(0xFFA77762),
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: 2,
              ),
            ),
            SizedBox(height: 3),
            Text(
              '돌봄 공간',
              style: TextStyle(
                color: _ink,
                fontSize: 24,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        actions: const [MenuHeaderIcon(icon: Icons.home_outlined)],
      ),
      body: Builder(
        builder: (context) {
          if (state.isLoading) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            );
          }
          if (state.errorMessage != null) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(state.errorMessage!),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: () =>
                          ref.read(familyRoomProvider.notifier).fetchRooms(),
                      child: const Text('다시 조회'),
                    ),
                  ],
                ),
              ),
            );
          }
          return Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 112),
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '함께하는 공간',
                              style: TextStyle(color: _muted, fontSize: 12),
                            ),
                            SizedBox(height: 5),
                            Text(
                              '어느 가족과 함께할까요?',
                              style: TextStyle(
                                color: _ink,
                                fontSize: 23,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.8,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 9,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.peachSoft,
                          borderRadius: BorderRadius.circular(30),
                        ),
                        child: Text(
                          '${state.rooms.length}개의 공간',
                          style: const TextStyle(
                            color: Color(0xFF966B58),
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 22),
                  if (state.rooms.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 48),
                      child: Text(
                        '참여 중인 공간이 없어요',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: _muted, fontSize: 18),
                      ),
                    ),
                  ...state.rooms.asMap().entries.map((entry) {
                    final room = entry.value;
                    final member = state.participations[room.familyRoomId]!;
                    final selected = state.selectedRoomId == room.familyRoomId;
                    final tone = [
                      AppColors.peachLight,
                      AppColors.sageLight,
                      AppColors.peachSoft,
                    ][entry.key % 3];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(
                                0xFF594135,
                              ).withValues(alpha: 0.05),
                              blurRadius: 24,
                              offset: const Offset(0, 8),
                            ),
                          ],
                        ),
                        child: Material(
                          color: AppColors.surface,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                            side: BorderSide(
                              color: selected
                                  ? AppColors.primary
                                  : const Color(0xFFEEE3DC),
                              width: selected ? 2 : 1,
                            ),
                          ),
                          clipBehavior: Clip.antiAlias,
                          child: InkWell(
                            onTap: () {
                              ref
                                  .read(familyRoomProvider.notifier)
                                  .selectRoom(room.familyRoomId);
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const FamilyRoomHome(),
                                ),
                              );
                            },
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(minHeight: 128),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 15,
                                  vertical: 18,
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 46,
                                      height: 46,
                                      decoration: BoxDecoration(
                                        color: tone,
                                        borderRadius: BorderRadius.circular(15),
                                      ),
                                      child: const Icon(
                                        Icons.home_outlined,
                                        color: Color(0xFF8C5941),
                                        size: 24,
                                      ),
                                    ),
                                    const SizedBox(width: 13),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '${room.careRecipientName} 돌봄 공간',
                                            style: const TextStyle(
                                              color: _ink,
                                              fontSize: 16,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          const SizedBox(height: 7),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 7,
                                              vertical: 4,
                                            ),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFFF6EEE9),
                                              borderRadius:
                                                  BorderRadius.circular(30),
                                            ),
                                            child: Text(
                                              member.isRepresentative
                                                  ? '주보호자'
                                                  : '일반 가족',
                                              style: const TextStyle(
                                                color: Color(0xFF936B59),
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(height: 8),
                                          Text(
                                            '돌봄 주소: ${room.careAddress ?? '미등록'}',
                                            style: const TextStyle(
                                              color: _muted,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Icon(
                                      selected
                                          ? Icons.check_circle_outline
                                          : Icons.chevron_right,
                                      color: selected
                                          ? const Color(0xFFA77762)
                                          : const Color(0xFFB9AEA8),
                                      size: 21,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    );
                  }),
                  if (state.rooms.isEmpty) ...[
                    const SizedBox(height: 20),
                    TextButton(
                      onPressed: () => inviteAction(context),
                      child: const Text('받은 가족 초대 확인'),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
  // ----- function -----

  Future<void> createRoomAction(BuildContext context) async {
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (context) => const FamilyRoomCreate()),
    );

    if (!mounted) {
      return;
    }

    if (created == true) {
      await ref.read(familyRoomProvider.notifier).fetchRooms();
    }
  }

  // 받은 초대 화면으로 이동하고 수락 후 공간 목록을 갱신한다.
  Future<void> inviteAction(BuildContext context) async {
    final accepted = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => const ReceivedInvites()),
    );

    if (!mounted || !context.mounted || accepted != true) {
      return;
    }

    await ref.read(familyRoomProvider.notifier).fetchRooms();

    if (!mounted || !context.mounted) {
      return;
    }

    final state = ref.read(familyRoomProvider);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          state.errorMessage == null
              ? '초대를 수락했습니다. 참여한 공간을 선택해 주세요.'
              : '초대를 수락했습니다. 공간 목록은 다시 새로고침해 주세요.',
        ),
      ),
    );
  }
} // class
