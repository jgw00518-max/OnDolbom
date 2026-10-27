import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ondolbom/model/family/family_room.dart';
import 'package:ondolbom/vm/family_room/family_room_notifier.dart';

class FamilyRoomDeleteDialog extends ConsumerStatefulWidget {
  const FamilyRoomDeleteDialog({super.key, required this.room});
  final FamilyRoom room;

  @override
  ConsumerState<FamilyRoomDeleteDialog> createState() =>
      _FamilyRoomDeleteDialogState();
}

class _FamilyRoomDeleteDialogState
    extends ConsumerState<FamilyRoomDeleteDialog> {
  final _name = TextEditingController();
  bool _deleting = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    if (_deleting || _name.text.trim() != widget.room.careRecipientName) return;
    setState(() {
      _deleting = true;
      _error = null;
    });
    try {
      await ref
          .read(familyRoomProvider.notifier)
          .deleteRoom(
            familyRoomId: widget.room.familyRoomId,
            recipientName: widget.room.careRecipientName,
            confirmationName: _name.text,
          );
      if (mounted) Navigator.of(context).pop(true);
    } on FamilyRoomDeleteFailure catch (error) {
      if (mounted) setState(() => _error = error.message);
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(familyRoomProvider);
    final allowed =
        state.selectedRoomId == widget.room.familyRoomId &&
        state.selectedRoom?.careRecipientName ==
            widget.room.careRecipientName &&
        state.selectedParticipation?.isRepresentative == true &&
        state.selectedParticipation?.isActive == true;
    final errorColor = Theme.of(context).colorScheme.error;
    return PopScope(
      canPop: !_deleting,
      child: AlertDialog(
        scrollable: true,
        title: const Text(
          '가족 공간을 삭제할까요?',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('모든 가족이 이 공간을 이용할 수 없게 됩니다.'),
            const SizedBox(height: 20),
            Text(
              '삭제하려면 돌봄 대상자 이름을 입력해 주세요.',
            ),
            const SizedBox(height: 12),
            TextField(
              key: const Key('family-room-delete-name'),
              controller: _name,
              enabled: allowed && !_deleting,
              autocorrect: false,
              decoration: const InputDecoration(
                labelText: '돌봄 대상자 이름',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() => _error = null),
            ),
            if (!allowed || _error != null) ...[
              const SizedBox(height: 12),
              Semantics(
                liveRegion: true,
                child: Text(
                  !allowed ? '공간 또는 권한이 변경됐어요. 화면을 다시 열어 주세요.' : _error!,
                  style: TextStyle(color: errorColor),
                ),
              ),
            ],
          ],
        ),
        actions: [
          FilledButton(
            key: const Key('family-room-delete-confirm'),
            style: FilledButton.styleFrom(
              backgroundColor: errorColor,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed:
                allowed &&
                    !_deleting &&
                    !state.isLoading &&
                    _name.text.trim() == widget.room.careRecipientName
                ? _delete
                : null,
            child: Text(_deleting ? '삭제 중…' : '공간 삭제'),
          ),
          TextButton(
            onPressed: _deleting
                ? null
                : () => Navigator.of(context).pop(false),
            child: const Text('취소'),
          ),
        ],
      ),
    );
  }
}
