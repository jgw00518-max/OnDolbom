import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ondolbom/model/invites/family_invite.dart';
import 'package:ondolbom/vm/auth/auth_vm.dart';
import 'package:ondolbom/vm/invites/invite_vm.dart';

class ReceivedInvites extends ConsumerStatefulWidget {
  const ReceivedInvites({super.key});

  @override
  ConsumerState<ReceivedInvites> createState() =>
      _ReceivedInvitesState();
}

class _ReceivedInvitesState
    extends ConsumerState<ReceivedInvites> {
  String? acceptingInviteId;
  String? errorMessage;

  @override
  Widget build(BuildContext context) {
    final invites = ref.watch(receivedInvitesProvider);
    final isAccepting = acceptingInviteId != null;

    return PopScope(
      canPop: !isAccepting,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('받은 가족 초대'),
          automaticallyImplyLeading: false,
          leading: IconButton(
            tooltip: '뒤로',
            onPressed: isAccepting
                ? null
                : () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back),
          ),
          actions: [
            IconButton(
              tooltip: '새로고침',
              onPressed: isAccepting
                  ? null
                  : () {
                      ref.invalidate(receivedInvitesProvider);
                    },
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: Column(
          children: [
            if (errorMessage != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  errorMessage!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ),

            Expanded(
              child: invites.when(
                loading: () => const Center(
                  child: CircularProgressIndicator(),
                ),
                error: (error, stackTrace) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          error
                              .toString()
                              .replaceFirst('Exception: ', ''),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 12),
                        OutlinedButton(
                          onPressed: isAccepting
                              ? null
                              : () {
                                  ref.invalidate(
                                    receivedInvitesProvider,
                                  );
                                },
                          child: const Text('다시 조회'),
                        ),
                      ],
                    ),
                  ),
                ),
                data: (items) {
                  if (items.isEmpty) {
                    return const Center(
                      child: Text('받은 가족 초대가 없습니다.'),
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.all(18),
                    itemCount: items.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 14),
                    itemBuilder: (context, index) {
                      return inviteCard(items[index]);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ----- function -----

  // 초대받은 공간과 초대한 가족을 표시한다.
  Widget inviteCard(FamilyInvite invite) {
    final isAccepting =
        acceptingInviteId == invite.inviteId;

    final dateText =
        '${invite.inviteAt.year}-'
        '${invite.inviteAt.month.toString().padLeft(2, '0')}-'
        '${invite.inviteAt.day.toString().padLeft(2, '0')}';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: const Color(0xFFE8DFD7),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 6,
            ),
            decoration: BoxDecoration(
              color: const Color(0xFFFFEBD9),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              invite.inviteStatus,
              style: const TextStyle(
                color: Color(0xFF875634),
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(height: 16),

          Text(
            '${invite.recipientName} 님의 돌봄 공간',
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 14),

          Text(
            '초대한 가족: ${invite.inviterName ?? '가족'}',
          ),
          const SizedBox(height: 6),
          Text('받은 이메일: ${invite.inviteEmail}'),
          const SizedBox(height: 6),
          Text('초대 날짜: $dateText'),
          const SizedBox(height: 18),

          const Text(
            '수락하면 이 공간의 일반 가족으로 참여합니다.',
            style: TextStyle(
              color: Color(0xFF78716A),
            ),
          ),
          const SizedBox(height: 18),

          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: acceptingInviteId != null
                  ? null
                  : () => acceptAction(invite),
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFF7AC82),
                foregroundColor: const Color(0xFF553724),
                padding: const EdgeInsets.symmetric(
                  vertical: 15,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                isAccepting ? '수락 중…' : '초대 수락',
              ),
            ),
          ),
        ],
      ),
    );
  }

  // 초대를 수락하고 이전 화면에 성공 여부를 전달한다.
  Future<void> acceptAction(FamilyInvite invite) async {
    if (acceptingInviteId != null) {
      return;
    }

    final uid =
        ref.read(firebaseAuthProvider).currentUser?.uid;

    setState(() {
      acceptingInviteId = invite.inviteId;
      errorMessage = null;
    });

    try {
      await ref
          .read(inviteVmProvider)
          .acceptInvite(invite.inviteId);

      if (!mounted) {
        return;
      }

      if (ref.read(firebaseAuthProvider).currentUser?.uid != uid) {
        setState(() {
          acceptingInviteId = null;
          errorMessage = '로그인 상태가 변경되었습니다.';
        });
        return;
      }

      ref.invalidate(receivedInvitesProvider);

      // 뒤로 이동 제한을 해제한 다음 목록으로 돌아간다.
      setState(() {
        acceptingInviteId = null;
      });

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          Navigator.pop(context, true);
        }
      });
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        acceptingInviteId = null;
        errorMessage = error
            .toString()
            .replaceFirst('Exception: ', '');
      });

      // 이미 처리된 초대라면 최신 목록으로 갱신한다.
      ref.invalidate(receivedInvitesProvider);
    }
  }
}