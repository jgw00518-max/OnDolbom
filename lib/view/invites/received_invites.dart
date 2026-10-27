import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ondolbom/model/invites/family_invite.dart';
import 'package:ondolbom/vm/auth/auth_vm.dart';
import 'package:ondolbom/vm/invites/invite_vm.dart';

class ReceivedInvites extends ConsumerStatefulWidget {
  const ReceivedInvites({super.key});

  @override
  ConsumerState<ReceivedInvites> createState() => _ReceivedInvitesState();
}

class _ReceivedInvitesState extends ConsumerState<ReceivedInvites> {
  String? acceptingInviteId;
  String? errorMessage;
  bool showSent = false;

  @override
  Widget build(BuildContext context) {
    final invites = showSent
        ? ref.watch(sentInvitesProvider)
        : ref.watch(receivedInvitesProvider);
    final isAccepting = acceptingInviteId != null;

    return PopScope(
      canPop: !isAccepting,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('가족 초대'),
          automaticallyImplyLeading: false,
          leading: IconButton(
            tooltip: '뒤로',
            onPressed: isAccepting ? null : () => Navigator.pop(context),
            icon: const Icon(Icons.arrow_back),
          ),
          actions: [
            IconButton(
              tooltip: '새로고침',
              onPressed: isAccepting
                  ? null
                  : () {
                      if (showSent) {
                        ref.invalidate(sentInvitesProvider);
                      } else {
                        ref.invalidate(receivedInvitesProvider);
                      }
                    },
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 16, 18, 8),
              child: SizedBox(
                width: double.infinity,
                child: SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment<bool>(
                      value: false,
                      icon: Icon(Icons.mail_outline),
                      label: Text('받은 초대'),
                    ),
                    ButtonSegment<bool>(
                      value: true,
                      icon: Icon(Icons.send_outlined),
                      label: Text('보낸 초대'),
                    ),
                  ],
                  selected: {showSent},
                  showSelectedIcon: false,
                  onSelectionChanged: isAccepting
                      ? null
                      : (selection) {
                          setState(() {
                            showSent = selection.first;
                            errorMessage = null;
                          });
                        },
                ),
              ),
            ),

            // 이 아래 기존 코드 유지
            if (errorMessage != null)
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  errorMessage!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),

            Expanded(
              child: invites.when(
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
                        const SizedBox(height: 12),
                        OutlinedButton(
                          onPressed: isAccepting
                              ? null
                              : () {
                                  if (showSent) {
                                    ref.invalidate(sentInvitesProvider);
                                  } else {
                                    ref.invalidate(receivedInvitesProvider);
                                  }
                                },
                          child: const Text('다시 조회'),
                        ),
                      ],
                    ),
                  ),
                ),
                data: (items) {
                  if (items.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          showSent
                              ? '주보호자로 관리하는 공간에 보낸 초대가 없습니다.'
                              : '받은 가족 초대가 없습니다.',
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }

                  return ListView.separated(
                    padding: const EdgeInsets.all(18),
                    itemCount: items.length,
                    separatorBuilder: (context, index) =>
                        const SizedBox(height: 14),
                    itemBuilder: (context, index) {
                      final invite = items[index];

                      if (!showSent) {
                        return inviteCard(invite);
                      }

                      final dateText =
                          '${invite.inviteAt.year}-'
                          '${invite.inviteAt.month.toString().padLeft(2, '0')}-'
                          '${invite.inviteAt.day.toString().padLeft(2, '0')} '
                          '${invite.inviteAt.hour.toString().padLeft(2, '0')}:'
                          '${invite.inviteAt.minute.toString().padLeft(2, '0')}';

                      final dateLabel =
                          invite.inviteStatus == '발송대기' ||
                              invite.inviteStatus == '발송실패'
                          ? '초대 생성 시각'
                          : '발송 시각';

                      return Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFFE8DFD7)),
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
                            Text('받는 이메일: ${invite.inviteEmail}'),
                            const SizedBox(height: 6),
                            Text('초대한 가족: ${invite.inviterName ?? '가족'}'),
                            const SizedBox(height: 6),
                            Text('$dateLabel: $dateText'),
                            if (invite.inviteStatus == '대기') ...[
                              const SizedBox(height: 18),
                              SizedBox(
                                width: double.infinity,
                                child: OutlinedButton(
                                  onPressed: acceptingInviteId != null
                                      ? null
                                      : () => cancelAction(invite),
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: const Color(0xFF99522F),
                                    side: const BorderSide(
                                      color: Color(0xFFE8DFD7),
                                    ),
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 15,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                  ),
                                  child: Text(
                                    acceptingInviteId == invite.inviteId
                                        ? '처리 중…'
                                        : '초대 취소',
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      );
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
    // 만료된 초대는 안내만 표시하고 수락·거절 버튼은 제공하지 않는다.
    if (invite.inviteStatus == '만료') {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFFF8F5F1),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE8DFD7)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xFFEAE5DF),
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Text(
                '만료',
                style: TextStyle(
                  color: Color(0xFF78716A),
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
                color: Color(0xFF756B60),
              ),
            ),
            const SizedBox(height: 14),
            Text('초대한 가족: ${invite.inviterName ?? '가족'}'),
            const SizedBox(height: 6),
            Text('받은 이메일: ${invite.inviteEmail}'),
            const SizedBox(height: 18),
            const Text(
              '초대 유효기간이 지났어요.\n'
              '참여하려면 주보호자에게 새 초대를 요청해 주세요.',
              style: TextStyle(color: Color(0xFF78716A), height: 1.7),
            ),
          ],
        ),
      );
    }
    final isAccepting = acceptingInviteId == invite.inviteId;

    final dateText =
        '${invite.inviteAt.year}-'
        '${invite.inviteAt.month.toString().padLeft(2, '0')}-'
        '${invite.inviteAt.day.toString().padLeft(2, '0')}';

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE8DFD7)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 14),

          Text('초대한 가족: ${invite.inviterName ?? '가족'}'),
          const SizedBox(height: 6),
          Text('받은 이메일: ${invite.inviteEmail}'),
          const SizedBox(height: 6),
          Text('초대 날짜: $dateText'),
          const SizedBox(height: 18),

          const Text(
            '수락하면 이 공간의 일반 가족으로 참여합니다.',
            style: TextStyle(color: Color(0xFF78716A)),
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
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(isAccepting ? '처리 중…' : '초대 수락'),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: acceptingInviteId != null
                  ? null
                  : () => rejectAction(invite),
              style: OutlinedButton.styleFrom(
                foregroundColor: const Color(0xFF78716A),
                side: const BorderSide(color: Color(0xFFE8DFD7)),
                padding: const EdgeInsets.symmetric(vertical: 15),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('초대 거절'),
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

    final uid = ref.read(firebaseAuthProvider).currentUser?.uid;

    setState(() {
      acceptingInviteId = invite.inviteId;
      errorMessage = null;
    });

    try {
      await ref.read(inviteVmProvider).acceptInvite(invite.inviteId);

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
        errorMessage = error.toString().replaceFirst('Exception: ', '');
      });

      // 이미 처리된 초대라면 최신 목록으로 갱신한다.
      ref.invalidate(receivedInvitesProvider);
    }
  }

  // 초대를 거절하고 받은 초대 목록을 갱신한다.
  Future<void> rejectAction(FamilyInvite invite) async {
    // 수락 또는 거절 처리 중에는 다른 요청을 막는다.
    if (acceptingInviteId != null) {
      return;
    }

    setState(() {
      acceptingInviteId = invite.inviteId;
      errorMessage = null;
    });

    try {
      await ref.read(inviteVmProvider).rejectInvite(invite.inviteId);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('초대를 거절했습니다.')));
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        errorMessage = error.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() {
          acceptingInviteId = null;
        });

        // 거절 성공 또는 상태 변경 여부를 최신 목록에서 확인한다.
        ref.invalidate(receivedInvitesProvider);
      }
    }
  } // build

  // 확인창에서 동의하면 보낸 초대를 취소한다.
  Future<void> cancelAction(FamilyInvite invite) async {
    if (acceptingInviteId != null) {
      return;
    }

    // 확인창이 열린 동안에도 다른 처리를 막는다.
    setState(() {
      acceptingInviteId = invite.inviteId;
      errorMessage = null;
    });

    try {
      final confirmed = await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) {
          return AlertDialog(
            backgroundColor: const Color(0xFFFFFCF8),
            surfaceTintColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(horizontal: 24),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
              side: const BorderSide(color: Color(0xFFE8DFD7)),
            ),
            titlePadding: const EdgeInsets.fromLTRB(24, 28, 24, 0),
            contentPadding: const EdgeInsets.fromLTRB(24, 18, 24, 24),
            actionsPadding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            scrollable: true,
            title: Column(
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: const BoxDecoration(
                    color: Color(0xFFFFEBD9),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.mail_outline_rounded,
                    size: 30,
                    color: Color(0xFF99522F),
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  '초대를 취소할까요?',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF403C39),
                  ),
                ),
              ],
            ),
            content: SizedBox(
              width: 360,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF3E8),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Column(
                      children: [
                        const Text(
                          '초대받은 이메일',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF8B796B),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          invite.inviteEmail,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF553724),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    '취소하면 이 초대로는\n가족 공간에 참여할 수 없어요.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14,
                      height: 1.7,
                      color: Color(0xFF78716A),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(dialogContext, false),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF756B60),
                        side: const BorderSide(color: Color(0xFFE8DFD7)),
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text('돌아가기'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(dialogContext, true),
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFFF7AC82),
                        foregroundColor: const Color(0xFF553724),
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        '초대 취소',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      );

      if (!mounted || confirmed != true) {
        return;
      }

      await ref.read(inviteVmProvider).cancelInvite(invite.inviteId);

      if (!mounted) {
        return;
      }

      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('초대를 취소했습니다.')));
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        errorMessage = error.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() {
          acceptingInviteId = null;
        });

        ref.invalidate(sentInvitesProvider);
      }
    }
  }
} // class
