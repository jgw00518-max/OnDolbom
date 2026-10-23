import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ondolbom/view/memos/memo_style.dart';
import 'package:ondolbom/vm/memos/memo_vm.dart';

class MemoFormView extends ConsumerStatefulWidget {
  const MemoFormView({super.key, required this.selected});
  final MemoContext selected;
  @override
  ConsumerState<MemoFormView> createState() => _MemoFormViewState();
}

class _MemoFormViewState extends ConsumerState<MemoFormView> {
  final _content = TextEditingController();
  final _form = GlobalKey<FormState>();
  bool _saving = false;
  bool _saved = false;

  @override
  void dispose() {
    _content.dispose();
    super.dispose();
  }

  Future<bool> _canLeave() async {
    if (_saving) return false;
    if (_saved || _content.text.trim().isEmpty) return true;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('작성을 취소할까요?'),
            content: const Text('작성 중인 메모는 저장되지 않아요.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('계속 작성'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('작성 취소'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _leave() async {
    if (await _canLeave() && mounted) {
      setState(() => _saved = true);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).pop();
      });
    }
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(memoVmProvider(widget.selected).notifier)
          .createMemo(_content.text);
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saved = true;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).pop();
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('메모를 등록했어요.')));
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is MemoFailure ? error.message : '저장하지 못했어요. 다시 시도해 주세요.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    // 이전 공간에서 열어 둔 작성 화면이 새 공간의 데이터로 저장되지 않도록 한다.
    final current = ref.watch(memoContextProvider);
    final sameSpace = current == widget.selected;
    return PopScope(
      canPop: _saved || (!_saving && _content.text.trim().isEmpty),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_saving) _leave();
      },
      child: MemoLayout(
        roomName: widget.selected.roomName,
        title: '메모 쓰기',
        onBack: _saving ? null : _leave,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '메모 내용',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _content,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  enabled: !_saving,
                  minLines: 7,
                  maxLines: 14,
                  maxLength: 10000,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    hintText: '가족에게 전하고 싶은 이야기를 남겨 주세요.',
                  ),
                  validator: (value) =>
                      (value ?? '').trim().isEmpty ? '메모 내용을 입력해 주세요.' : null,
                ),
                const SizedBox(height: 8),
                Text(
                  '작은 돌봄 기록도 가족에게 큰 도움이 돼요.',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
                if (!sameSpace)
                  const Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text('선택한 공간이 변경됐어요. 목록으로 돌아가 다시 작성해 주세요.'),
                  ),
                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _saving ? null : _leave,
                        child: const Text('취소'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: FilledButton(
                        onPressed: _saving || !sameSpace ? null : _save,
                        child: Text(_saving ? '등록 중…' : '메모 등록'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
