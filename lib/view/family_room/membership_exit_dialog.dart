import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ondolbom/model/family/family_member.dart';
import 'package:ondolbom/theme/app_colors.dart';
import 'package:ondolbom/vm/family_room/family_member_vm.dart';
import 'package:ondolbom/vm/family_room/family_room_notifier.dart';

/// 탈퇴와 강퇴 모두 영향 범위를 확인한 다음 요청하며 중복 제출을 막는다.
class MembershipExitDialog extends ConsumerStatefulWidget {
  const MembershipExitDialog({
    super.key,
    required this.familyRoomId,
    this.target,
  });
  final String familyRoomId;
  final FamilyMember? target;
  @override
  ConsumerState<MembershipExitDialog> createState() =>
      _MembershipExitDialogState();
}

class _MembershipExitDialogState extends ConsumerState<MembershipExitDialog> {
  bool _busy = false;
  String? _error;
  Future<void> _submit() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(familyRoomProvider.notifier)
          .endMembership(
            familyRoomId: widget.familyRoomId,
            participateSeq: widget.target?.participateSeq,
          );
      if (!mounted) return;
      ref.invalidate(familyMembersProvider(widget.familyRoomId));
      Navigator.of(context).pop(true);
    } on FamilyRoomMembershipFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final removing = widget.target != null;
    return PopScope(
      canPop: !_busy,
      child: Dialog(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ColoredBox(
                  color: AppColors.surface,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(22, 24, 22, 20),
                    child: Text(
                      removing ? '가족을 강퇴할까요?' : '공간에서 나갈까요?',
                      style: const TextStyle(
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ),
                const Divider(height: 1),
                Padding(
                  padding: const EdgeInsets.all(22),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        removing
                            ? '${widget.target!.name ?? '선택한 가족'}님의 공간 접근이 종료됩니다.'
                            : '이 공간의 기록을 더 이상 조회할 수 없습니다.',
                        style: const TextStyle(
                          fontSize: 15,
                          height: 1.6,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: AppColors.peachSoft,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const Text(
                          '맡고 있던 미완료 일정은 담당자 없는 상태로 변경됩니다.\n'
                          '작성한 메모·채팅과 완료 기록은 보존됩니다.',
                          style: TextStyle(
                            fontSize: 13,
                            height: 1.6,
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 12),
                        Text(
                          _error!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _busy
                                  ? null
                                  : () => Navigator.pop(context, false),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(0, 48),
                              ),
                              child: const Text('취소'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: FilledButton(
                              onPressed: _busy ? null : _submit,
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFFB87568),
                                foregroundColor: Colors.white,
                                minimumSize: const Size(0, 48),
                              ),
                              child: Text(
                                _busy
                                    ? '처리 중…'
                                    : removing
                                    ? '강퇴'
                                    : '나가기',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
