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
      child: AlertDialog(
        scrollable: true,
        title: Text(removing ? '가족을 강퇴할까요?' : '공간에서 나갈까요?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              removing
                  ? '${widget.target!.name ?? '선택한 가족'}님의 공간 접근이 종료됩니다.'
                  : '이 공간의 기록을 더 이상 조회할 수 없습니다.',
            ),
            const SizedBox(height: 12),
            const Text(
              '맡고 있던 미완료 일정은 담당자 없는 상태로 변경됩니다. 작성한 메모·채팅과 완료 기록은 보존됩니다.',
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: _busy ? null : _submit,
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.textPrimary,
            ),
            child: Text(
              _busy
                  ? '처리 중…'
                  : removing
                  ? '강퇴'
                  : '나가기',
            ),
          ),
        ],
      ),
    );
  }
}
