import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ondolbom/vm/family_room/family_room_notifier.dart';
import 'package:ondolbom/view/family_room/family_room_home.dart';
import 'package:ondolbom/view/family_room/family_room_create.dart';
import 'package:ondolbom/view/notifications/notifications_view.dart';
import 'package:ondolbom/vm/auth/auth_vm.dart';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:ondolbom/view/invites/received_invites.dart';

class FamilyRoomList extends ConsumerStatefulWidget {
  const FamilyRoomList({super.key});

  @override
  ConsumerState<FamilyRoomList> createState() =>
      _FamilyRoomListState();
}

class _FamilyRoomListState
    extends ConsumerState<FamilyRoomList> {
  @override
  void initState() {
    super.initState();

    // Swagger 테스트 후 삭제한다.
FirebaseAuth.instance.currentUser?.getIdToken().then((token) {
  debugPrint('SWAGGER_TOKEN: $token');
});

    // 첫 화면이 만들어진 다음 한 번 조회한다.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      ref.read(familyRoomProvider.notifier).fetchRooms();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(familyRoomProvider);

        return Scaffold(
      appBar: AppBar(
        title: const Text('가족 공간'),
        actions: [
            IconButton(
            tooltip: '받은 가족 초대',
            icon: const Icon(Icons.mail_outline),
            onPressed: () => inviteAction(context),
          ),
          // 전체 공간의 알림을 연다.
          IconButton(
            tooltip: '알림',
            icon: const Icon(Icons.notifications_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const NotificationsView(),
              ),
            ),
          ),

          // 가족 공간 목록을 새로 조회한다.
          IconButton(
            tooltip: '새로고침',
            onPressed: state.isLoading
                ? null
                : () {
                    ref
                        .read(familyRoomProvider.notifier)
                        .fetchRooms();
                  },
            icon: const Icon(Icons.refresh),
          ),

          // A가 구현한 로그아웃 함수를 사용한다.
          IconButton(
            tooltip: '로그아웃',
            icon: const Icon(Icons.logout),
            onPressed: () async {
              await ref.read(authVmProvider.notifier).signOut();
            },
          ),
        ],
      ),
      body: Builder(
        builder: (context) {
          if (state.isLoading) {
            return const Center(
              child: CircularProgressIndicator(),
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
                      onPressed: () {
                        ref
                            .read(familyRoomProvider.notifier)
                            .fetchRooms();
                      },
                      child: const Text('다시 조회'),
                    ),
                  ],
                ),
              ),
            );
          }
          if (state.rooms.isEmpty) {
  final colors = Theme.of(context).colorScheme;

  return ListView(
    padding: const EdgeInsets.all(24),
    children: [
      const SizedBox(height: 20),
      const Text(
        '돌봄 공간 선택',
        style: TextStyle(
          fontSize: 30,
          fontWeight: FontWeight.bold,
        ),
      ),
      const SizedBox(height: 12),
      Text(
        '참여 중인 공간 0개',
        style: TextStyle(
          fontSize: 16,
          color: colors.onSurfaceVariant,
        ),
      ),
      const SizedBox(height: 64),

      // 참여 공간이 없는 상태
      Center(
        child: Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: colors.secondaryContainer,
            borderRadius: BorderRadius.circular(28),
          ),
          child: Icon(
            Icons.eco_outlined,
            size: 36,
            color: colors.onSecondaryContainer,
          ),
        ),
      ),
      const SizedBox(height: 28),
      const Text(
        '참여 중인 공간이 없어요',
        textAlign: TextAlign.center,
        style: TextStyle(
          fontSize: 23,
          fontWeight: FontWeight.bold,
        ),
      ),
      const SizedBox(height: 64),

      // 공간 생성
      SizedBox(
        height: 56,
        child: OutlinedButton.icon(
          onPressed: () => createRoomAction(context),
          icon: const Icon(Icons.add),
          label: const Text(
            '새 돌봄 공간 만들기',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
            ),
          ),
          style: OutlinedButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
      ),
      const SizedBox(height: 28),

      // 받은 초대 확인
      Card(
        margin: EdgeInsets.zero,
        color: colors.surface,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '가족 초대',
                style: TextStyle(
                  fontSize: 23,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: FilledButton.tonal(
                  onPressed: () => inviteAction(context),
                  child: const Text(
                    '받은 가족 초대 확인',
                    style: TextStyle(
                      fontSize: 17,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ],
  );
}

          return ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const Text(
                  '가족 공간을 선택해 주세요',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 16),

                // 참여 중인 공간을 카드로 표시한다.
                ...state.rooms.map((room) {
                  final member =
                      state.participations[room.familyRoomId]!;

                  final isSelected =
                      state.selectedRoomId == room.familyRoomId;

                  return Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    color: isSelected
                        ? Theme.of(context).colorScheme.secondaryContainer
                        : null,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(
                        color: isSelected
                            ? Theme.of(context).colorScheme.primary
                            : Colors.grey.shade300,
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: () {
                        // 누른 공간을 현재 공간으로 선택한다.
                        ref
                            .read(familyRoomProvider.notifier)
                            .selectRoom(room.familyRoomId);

                        // 선택한 공간의 홈 화면으로 이동한다.
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const FamilyRoomHome(),
                          ),
                        );
                      },
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.home_outlined),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '${room.careRecipientName} 돌봄 공간',
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                if (isSelected)
                                  Icon(
                                    Icons.check_circle,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primary,
                                  ),
                              ],
                            ),
                            const SizedBox(height: 12),
                            Text(
                              '내 역할: '
                              '${member.isRepresentative ? '주보호자' : '일반 가족'}',
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '돌봄 주소: ${room.careAddress ?? '미등록'}',
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 8),

          SizedBox(
            width: double.infinity,
            height: 56,
            child: OutlinedButton.icon(
              onPressed: () => createRoomAction(context),
              icon: const Icon(Icons.add),
              label: const Text(
                '새 돌봄 공간 만들기',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                ),
              ),
              style: OutlinedButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
              ),
            ),
          ),
          ],
        );
        },
      ),
    );
  } // build
// ----- function -----

Future<void> createRoomAction(BuildContext context) async {
  final created = await Navigator.push<bool>(
    context,
    MaterialPageRoute(
      builder: (context) => const FamilyRoomCreate(),
    ),
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
    MaterialPageRoute(
      builder: (_) => const ReceivedInvites(),
    ),
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
