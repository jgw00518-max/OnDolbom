import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ondolbom/model/family/family_member.dart';
import 'package:ondolbom/theme/app_colors.dart';
import 'package:ondolbom/vm/auth/auth_vm.dart';
import 'package:ondolbom/vm/family_room/family_room_notifier.dart';

class RepresentativeTransferDialog extends ConsumerStatefulWidget {
  const RepresentativeTransferDialog({
    super.key,
    required this.familyRoomId,
    required this.target,
  });
  final String familyRoomId;
  final FamilyMember target;

  @override
  ConsumerState<RepresentativeTransferDialog> createState() =>
      _RepresentativeTransferDialogState();
}

class _RepresentativeTransferDialogState
    extends ConsumerState<RepresentativeTransferDialog> {
  bool _busy = false;
  String? _error;
  late final Object _sessionKey;
  late final String? _uid;

  @override
  void initState() {
    super.initState();
    _sessionKey = ref.read(familyRoomProvider.notifier).sessionKey;
    _uid = ref.read(firebaseAuthProvider).currentUser?.uid;
  }

  bool get _sameSession =>
      _uid != null &&
      ref.read(familyRoomProvider.notifier).isCurrentRequest(_sessionKey, _uid);

  Future<void> _submit() async {
    if (_busy || widget.target.isRepresentative) return;
    // 확인창이 열린 뒤 계정이 바뀌었다면 새 계정으로 이전 요청을 보내지 않는다.
    if (!_sameSession) {
      setState(() => _error = '로그인 상태가 변경됐어요. 화면을 다시 열어 주세요.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(familyRoomProvider.notifier)
          .transferRepresentative(
            familyRoomId: widget.familyRoomId,
            targetUserId: widget.target.userId,
          );
      if (mounted) Navigator.of(context).pop(true);
    } on RepresentativeTransferFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(familyRoomProvider);
    final allowed =
        _sameSession &&
        state.selectedRoomId == widget.familyRoomId &&
        state.selectedParticipation?.isActive == true &&
        state.selectedParticipation?.isRepresentative == true &&
        state.selectedParticipation?.userId != widget.target.userId &&
        !widget.target.isRepresentative;
    final name = widget.target.name?.trim();
    final displayName = name == null || name.isEmpty ? '선택한 가족' : name;
    return PopScope(
      canPop: !_busy,
      child: AlertDialog(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        titlePadding: EdgeInsets.zero,
        contentPadding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
        actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        actionsOverflowButtonSpacing: 8,
        title: Container(
          padding: const EdgeInsets.all(20),
          color: AppColors.peachSoft,
          child: const Row(
            children: [
              Icon(
                Icons.workspace_premium_outlined,
                size: 28,
                color: AppColors.sageDark,
              ),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  '주보호자를 이전할까요?',
                  style: TextStyle(
                    fontSize: 21,
                    height: 1.4,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: AppColors.border),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const CircleAvatar(
                      radius: 20,
                      backgroundColor: AppColors.sageLight,
                      child: Icon(
                        Icons.person_outline,
                        color: AppColors.sageDark,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '이전받을 가족',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.sageDark,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '$displayName 님에게 주보호자를 이전합니다.',
                            style: const TextStyle(
                              fontSize: 16,
                              color: AppColors.textPrimary,
                              fontWeight: FontWeight.w700,
                              height: 1.5,
                            ),
                          ),
                          if (widget.target.email?.trim().isNotEmpty ==
                              true) ...[
                            const SizedBox(height: 6),
                            Text(
                              widget.target.email!,
                              style: const TextStyle(
                                fontSize: 13,
                                height: 1.5,
                                color: AppColors.sageDark,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.peachSoft,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.swap_horiz_rounded,
                          size: 20,
                          color: AppColors.sageDark,
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '내 역할이 변경돼요',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                    SizedBox(height: 10),
                    Text(
                      '나는 일반 가족으로 계속 참여하며, 주보호자 관리 권한을 잃습니다.\n기존 돌봄 기록과 채팅은 유지됩니다.',
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.7,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              if (!allowed && !_busy) ...[
                const SizedBox(height: 12),
                Text(
                  '공간 또는 권한이 변경됐어요. 목록을 다시 확인해 주세요.',
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.6,
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ],
              if (_error != null) ...[
                const SizedBox(height: 12),
                Semantics(
                  liveRegion: true,
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      _error!,
                      style: TextStyle(
                        fontSize: 14,
                        height: 1.6,
                        color: Theme.of(context).colorScheme.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.pop(context, false),
            style: TextButton.styleFrom(
              minimumSize: const Size(72, 48),
              backgroundColor: AppColors.surface,
              foregroundColor: AppColors.textPrimary,
              side: const BorderSide(color: AppColors.border),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              textStyle: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: _busy || state.isLoading || !allowed ? null : _submit,
            style: FilledButton.styleFrom(
              minimumSize: const Size(140, 48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              textStyle: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            child: Text(_busy ? '이전 중…' : '주보호자 이전'),
          ),
        ],
      ),
    );
  }
}
