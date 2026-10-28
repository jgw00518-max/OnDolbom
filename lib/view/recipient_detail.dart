import 'package:ondolbom/view/widgets/app_back_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ondolbom/model/family/family_room.dart';
import 'package:ondolbom/view/family_room/recipient_edit.dart';
import 'package:ondolbom/vm/family_room/family_room_notifier.dart';

class RecipientDetail extends ConsumerWidget {
  const RecipientDetail({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(familyRoomProvider);
    final room = state.selectedRoom;
    final participation = state.selectedParticipation;
    final colors = Theme.of(context).colorScheme;

    if (room == null || participation == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('대상자 정보')),
        body: const Center(child: Text('선택한 공간이 없습니다.')),
      );
    }

    // 날짜만 표시한다.
    final birthDate = room.birthDate;
    final birthText = birthDate == null
        ? '미등록'
        : '${birthDate.year}-'
              '${birthDate.month.toString().padLeft(2, '0')}-'
              '${birthDate.day.toString().padLeft(2, '0')}';

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leadingWidth: 62,
        leading: const AppBackLeading(),
        title: const Text('온돌봄'),
        actions: [
          IconButton(
            onPressed: () => preparingAction(context),
            icon: const Icon(Icons.notifications_none),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(
            '${room.careRecipientName} 님의 돌봄 공간',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 24),

          // 제목과 수정 버튼
          Row(
            children: [
              const Expanded(
                child: Text(
                  '대상자 정보',
                  style: TextStyle(fontSize: 26, fontWeight: FontWeight.bold),
                ),
              ),

              // 수정은 현재 공간의 주보호자에게만 표시한다.
              if (participation.isRepresentative)
                FilledButton.tonal(
                  onPressed: () => editAction(context, ref, room),
                  child: const Text('수정'),
                ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 16),

          // 대상자 정보 카드
          Card(
            color: colors.surface,
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${room.careRecipientName} 님',
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 28),

                  // 확정한 성별 코드에 맞춰 한글로 표시한다.
                  infoRow(context, '성별', switch (room.gender) {
                    1 => '남성',
                    2 => '여성',
                    null => '미등록',
                    _ => '확인 필요',
                  }),
                  infoRow(context, '생년월일', birthText),
                  infoRow(context, '특이사항', room.specialNotes),
                  infoRow(context, '돌봄 장소', room.careAddress),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  } // build

  // ----- function -----

  // 같은 형태의 정보 행을 반복해서 사용한다.
  Widget infoRow(BuildContext context, String title, String? value) {
    final colors = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 100,
            child: Text(
              title,
              style: TextStyle(fontSize: 16, color: colors.onSurfaceVariant),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value == null || value.trim().isEmpty ? '미등록' : value,
              style: const TextStyle(fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }

  void preparingAction(BuildContext context) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('아직 연결하지 않은 기능입니다.')));
  }

  // 편집 화면에서 저장하면 공간 정보를 다시 조회한다.
  Future<void> editAction(
    BuildContext context,
    WidgetRef ref,
    FamilyRoom room,
  ) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => RecipientEdit(room: room)),
    );

    if (!context.mounted || saved != true) {
      return;
    }

    await ref.read(familyRoomProvider.notifier).fetchRooms();

    if (!context.mounted) {
      return;
    }

    final state = ref.read(familyRoomProvider);

    final message = state.errorMessage != null
        ? '저장은 완료되었지만 최신 정보를 불러오지 못했습니다. 공간 목록을 새로고침해 주세요.'
        : '대상자 정보를 수정했습니다.';

    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }
} // class
