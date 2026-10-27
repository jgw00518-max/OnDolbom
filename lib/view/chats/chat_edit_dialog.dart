import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ondolbom/model/chats/chat_message.dart';
import 'package:ondolbom/vm/chats/chat_vm.dart';
import 'package:ondolbom/vm/family_room/family_context.dart';

class ChatEditDialog extends ConsumerStatefulWidget {
  const ChatEditDialog({
    super.key,
    required this.selected,
    required this.message,
  });
  final FamilyContext selected;
  final ChatMessage message;
  @override
  ConsumerState<ChatEditDialog> createState() => _ChatEditDialogState();
}

class _ChatEditDialogState extends ConsumerState<ChatEditDialog> {
  late final _content = TextEditingController(text: widget.message.content);
  final _form = GlobalKey<FormState>();
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _content.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(chatVmProvider(widget.selected).notifier)
          .updateMessage(widget.message, _content.text);
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) {
        setState(
          () => _error = error is ChatFailure
              ? error.message
              : '수정하지 못했어요. 입력 내용을 확인하고 다시 시도해 주세요.',
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sameContext = ref.watch(familyContextProvider) == widget.selected;
    if (!sameContext) {
      return AlertDialog(
        title: const Text('메시지 수정'),
        content: const Text('선택한 공간이나 로그인 계정이 변경되었습니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('닫기'),
          ),
        ],
      );
    }
    final state = ref.watch(chatVmProvider(widget.selected));
    final current = state.messages
        .where((item) => item.seq == widget.message.seq)
        .firstOrNull;
    final allowed =
        sameContext &&
        current != null &&
        !current.isDeleted &&
        current.userId == widget.selected.userId &&
        state.status == ChatStatus.connected &&
        !state.loadingHistory &&
        current.content == widget.message.content &&
        current.updatedAt == widget.message.updatedAt;
    return PopScope(
      canPop: !_saving,
      child: AlertDialog(
        title: const Text('메시지 수정'),
        content: SingleChildScrollView(
          child: Form(
            key: _form,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (widget.message.hasImage)
                  const Text('첨부 사진은 유지되며 설명만 수정합니다.'),
                TextFormField(
                  key: const ValueKey('chat-edit-input'),
                  controller: _content,
                  enabled: allowed && !_saving,
                  minLines: 2,
                  maxLines: 6,
                  maxLength: 4000,
                  decoration: const InputDecoration(labelText: '메시지 내용'),
                  validator: (value) {
                    final text = value?.trim() ?? '';
                    if (text.isEmpty && !widget.message.hasImage) {
                      return '텍스트 메시지 내용은 비울 수 없습니다.';
                    }
                    if (text.runes.length > 4000) return '최대 4,000자까지 입력해 주세요.';
                    return null;
                  },
                ),
                if (!allowed)
                  const Text('메시지 또는 연결 상태가 변경되었습니다. 닫은 뒤 다시 확인해 주세요.'),
                if (_error != null)
                  Text(
                    _error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: _saving ? null : () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed:
                allowed &&
                    !_saving &&
                    !state.changing.contains(widget.message.seq)
                ? _save
                : null,
            child: Text(_saving ? '저장 중…' : '저장'),
          ),
        ],
      ),
    );
  }
}
