import 'package:flutter/material.dart';
import 'package:ondolbom/view/notifications/notifications_view.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ondolbom/view/medications/medication_list_view.dart';
import 'package:ondolbom/view/chats/chat_view.dart';
import 'package:ondolbom/view/memos/memo_list_view.dart';
import 'package:ondolbom/view/recipient_detail.dart';
import 'package:ondolbom/view/schedules/schedule_list.dart';
import 'package:ondolbom/vm/family_room_notifier.dart';
import 'package:ondolbom/view/invites/invite_create.dart';

class FamilyRoomHome extends ConsumerWidget {
  const FamilyRoomHome({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(familyRoomProvider);
    final room = state.selectedRoom;
    final colors = Theme.of(context).colorScheme;

    if (room == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('돌봄 공간')),
        body: const Center(child: Text('공간을 선택해 주세요.')),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('온돌봄'),
        actions: [
          IconButton(
            tooltip: '알림',
            // 공간 목록과 동일한 알림 화면으로 이동한다.
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const NotificationsView(),
              ),
            ),
            icon: const Icon(Icons.notifications_none),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // 현재 선택한 공간
          Text(
            '${room.careRecipientName} 님의 돌봄 공간',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 24),

          // 소개 문구
          const Text(
            '나의 일상에,',
            style: TextStyle(fontSize: 30, fontWeight: FontWeight.bold),
          ),
          Text(
            '안심을 더하다',
            style: TextStyle(
              fontSize: 30,
              fontWeight: FontWeight.bold,
              color: colors.primary,
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            '소중한 사람의 오늘도,\n온돌봄이 함께합니다.',
            style: TextStyle(fontSize: 17, height: 1.6),
          ),
          const SizedBox(height: 32),

          const Text(
            '돌봄 메뉴',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 16),

          // 첫 번째 메뉴 줄
          Row(
            children: [
              menuButton(
                '투약일지',
                Icons.medication_outlined,
                () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const MedicationListView(),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              menuButton(
                '실시간 채팅',
                Icons.chat_bubble_outline,
                () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const ChatView()),
                ),
              ),
              const SizedBox(width: 10),
              menuButton(
                '메모',
                Icons.edit_outlined,
                () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const MemoListView()),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // 두 번째 메뉴 줄
          Row(
            children: [
              menuButton(
                '일정',
                Icons.calendar_month_outlined,
                () => scheduleAction(context, room.familyRoomId),
              ),
              const SizedBox(width: 10),
              menuButton(
                '대상자 정보',
                Icons.people_outline,
                () => recipientAction(context),
              ),
              const SizedBox(width: 10),

              if (state.selectedParticipation?.isRepresentative == true)
                menuButton(
                  '가족 초대',
                  Icons.person_add_alt_1,
                  () => inviteCreateAction(
                    context,
                    room.familyRoomId,
                    room.careRecipientName,
                  ),
                )
              else
                const Expanded(child: SizedBox()),
            ],
          ),
          const SizedBox(height: 28),

          // 오늘의 일정
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Expanded(
                        child: Text(
                          '오늘의 일정',
                          style: TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () =>
                            scheduleAction(context, room.familyRoomId),
                        child: const Text('전체 일정'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  const Text('일정 조회 기능 연결 전입니다.'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  } // build

  // ----- function -----

  // 반복되는 메뉴 모양을 만든다.
  Widget menuButton(String title, IconData icon, VoidCallback action) {
    return Expanded(
      child: SizedBox(
        height: 115,
        child: OutlinedButton(
          onPressed: action,
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.all(8),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 30),
              const SizedBox(height: 12),
              Text(title, textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }

  // 대상자 정보 화면으로 이동한다.
  void recipientAction(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const RecipientDetail()),
    );
  }

  // 모든 참여 가족이 일정 달력·목록으로 이동한다.
  void scheduleAction(BuildContext context, String familyRoomId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ScheduleList(familyRoomId: familyRoomId),
      ),
    );
  }

  // 아직 연결하지 않은 기능을 안내한다.
  void preparingAction(BuildContext context) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('아직 연결하지 않은 기능입니다.')));
  }

  // 주보호자가 가족 초대 화면으로 이동한다.
  Future<void> inviteCreateAction(
    BuildContext context,
    String familyRoomId,
    String recipientName,
  ) async {
    final created = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => InviteCreate(
          familyRoomId: familyRoomId,
          recipientName: recipientName,
        ),
      ),
    );

    if (!context.mounted || created != true) {
      return;
    }

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('초대를 등록했습니다. 초대받은 계정에서 받은 초대를 확인해 주세요.')),
    );
  }
}
