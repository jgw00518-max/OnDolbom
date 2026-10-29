import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ondolbom/model/memos/memo.dart';
import 'package:ondolbom/view/memos/memo_style.dart';
import 'package:ondolbom/view/memos/memo_image_view.dart';
import 'package:ondolbom/vm/memos/memo_vm.dart';

typedef MemoFormResult = ({String content, bool hasImage});

class MemoFormView extends ConsumerStatefulWidget {
  const MemoFormView({super.key, required this.selected, this.memo});
  final MemoContext selected;
  final Memo? memo;
  @override
  ConsumerState<MemoFormView> createState() => _MemoFormViewState();
}

class _MemoFormViewState extends ConsumerState<MemoFormView> {
  late final _content = TextEditingController(
    text: widget.memo?.memoContent ?? '',
  );
  final _form = GlobalKey<FormState>();
  bool _saving = false;
  bool _saved = false;
  bool _picking = false;
  Uint8List? _image;
  bool _removeExisting = false;
  bool get _busy => _saving || _picking;
  bool get _hasImage =>
      _image != null || (!_removeExisting && (widget.memo?.hasImage ?? false));
  bool get _editing => widget.memo != null;
  bool get _dirty =>
      _image != null ||
      _removeExisting ||
      (_editing
          ? _content.text != (widget.memo!.memoContent ?? '')
          : _content.text.trim().isNotEmpty);
  bool get _allowed =>
      ref.read(memoContextProvider) == widget.selected &&
      (!_editing ||
          (widget.memo!.userId == widget.selected.userId &&
              widget.selected.userId.isNotEmpty &&
              widget.memo!.familyRoomId == widget.selected.familyRoomId));

  @override
  void dispose() {
    _content.dispose();
    super.dispose();
  }

  Future<bool> _canLeave() async {
    if (_busy) return false;
    if (_saved || !_dirty) return true;
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(_editing ? '수정을 취소할까요?' : '작성을 취소할까요?'),
            content: Text(
              _editing ? '변경한 내용은 저장되지 않아요.' : '작성 중인 메모는 저장되지 않아요.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: Text(_editing ? '계속 수정' : '계속 작성'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: Text(_editing ? '수정 취소' : '작성 취소'),
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
    if (_busy || !_allowed || !_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final vm = ref.read(memoVmProvider(widget.selected).notifier);
      if (_editing) {
        await vm.updateMemo(
          widget.memo!,
          _content.text,
          image: _image,
          removeImage: _image == null && _removeExisting,
        );
      } else {
        await vm.createMemo(_content.text, image: _image);
      }
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saved = true;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final messenger = ScaffoldMessenger.of(context);
        Navigator.of(context).pop<MemoFormResult>((
          content: _content.text.trim(),
          hasImage: _hasImage,
        ));
        messenger.showSnackBar(
          SnackBar(content: Text(_editing ? '메모를 수정했어요.' : '메모를 등록했어요.')),
        );
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

  Future<void> _pickImage() async {
    if (_busy || !_allowed) return;
    setState(() => _picking = true);
    try {
      final bytes = await ref.read(memoImagePickerProvider)();
      if (!mounted || !_allowed || bytes == null) return;
      if (bytes.isEmpty || bytes.length > maxMemoImageBytes) {
        throw const MemoFailure('이미지는 5MB 이하로 첨부해 주세요.');
      }
      setState(() {
        _image = bytes;
        _removeExisting = false;
      });
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is MemoFailure
                  ? error.message
                  : '사진을 선택하지 못했어요. 사진 접근 권한을 확인해 주세요.',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // 이전 공간에서 열어 둔 작성 화면이 새 공간의 데이터로 저장되지 않도록 한다.
    final current = ref.watch(memoContextProvider);
    ref.watch(memoVmProvider(widget.selected));
    final sameSpace = current == widget.selected;
    return PopScope(
      canPop: _saved || (!_busy && !_dirty),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && !_busy) _leave();
      },
      child: MemoLayout(
        roomName: widget.selected.roomName,
        title: _editing ? '메모 수정' : '메모 쓰기',
        onBack: _busy ? null : _leave,
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
                  enabled: !_busy,
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
                const SizedBox(height: 16),
                const Text(
                  '사진 첨부 (선택 · 한 장)',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                if (_hasImage) ...[
                  if (_image != null)
                    Image.memory(
                      _image!,
                      height: 160,
                      width: double.infinity,
                      fit: BoxFit.contain,
                      errorBuilder: (_, _, _) =>
                          const Text('사진을 표시할 수 없어요. 다른 사진을 선택해 주세요.'),
                    )
                  else
                    MemoImageView(
                      memo: widget.memo!,
                      selected: widget.selected,
                      height: 160,
                      expandable: false,
                    ),
                  const SizedBox(height: 8),
                ],
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    OutlinedButton.icon(
                      onPressed: _busy || !_allowed ? null : _pickImage,
                      icon: const Icon(Icons.add_photo_alternate_outlined),
                      label: Text(
                        _picking ? '사진 선택 중…' : (_hasImage ? '사진 교체' : '사진 첨부'),
                      ),
                    ),
                    if (_hasImage)
                      TextButton.icon(
                        onPressed: _busy || !_allowed
                            ? null
                            : () => setState(() {
                                _image = null;
                                _removeExisting =
                                    widget.memo?.hasImage ?? false;
                              }),
                        icon: const Icon(Icons.close),
                        label: const Text('사진 제거'),
                      ),
                  ],
                ),
                const Text(
                  'JPG, PNG, WEBP · 최대 5MB',
                  style: TextStyle(fontSize: 12),
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
                        onPressed: _busy ? null : _leave,
                        child: const Text('취소'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: FilledButton(
                        onPressed: _busy || !_allowed ? null : _save,
                        child: Text(
                          _saving
                              ? (_editing ? '저장 중…' : '등록 중…')
                              : (_editing ? '수정 저장' : '메모 등록'),
                        ),
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
