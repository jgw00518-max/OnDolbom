import 'package:ondolbom/l10n/app_strings.dart';
import 'package:ondolbom/view/widgets/discard_changes_dialog.dart';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:ondolbom/theme/app_colors.dart';
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
          builder: (context) => DiscardChangesDialog(
            title: _editing
                ? AppStrings.tr(context, '수정을 취소할까요?')
                : AppStrings.tr(context, '작성을 취소할까요?'),
            message: _editing
                ? AppStrings.tr(context, '변경한 내용은 저장되지 않아요.')
                : AppStrings.tr(context, '작성 중인 메모는 저장되지 않아요.'),
            continueLabel: _editing ? '계속 수정' : '계속 작성',
            discardLabel: _editing ? '수정 취소' : '작성 취소',
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
          SnackBar(
            content: Text(
              AppStrings.error(
                context,
                _editing
                    ? AppStrings.tr(context, '메모를 수정했어요.')
                    : AppStrings.tr(context, '메모를 등록했어요.'),
              ),
            ),
          ),
        );
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            AppStrings.error(
              context,
              error is MemoFailure
                  ? error.message
                  : AppStrings.tr(context, '저장하지 못했어요. 다시 시도해 주세요.'),
            ),
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
              AppStrings.error(
                context,
                error is MemoFailure
                    ? error.message
                    : AppStrings.tr(
                        context,
                        '사진을 선택하지 못했어요. 사진 접근 권한을 확인해 주세요.',
                      ),
              ),
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
        title: _editing
            ? AppStrings.tr(context, '메모 수정')
            : AppStrings.tr(context, '메모 쓰기'),
        onBack: _busy ? null : _leave,
        footer: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _busy ? null : _leave,
                child: Text(AppStrings.tr(context, '취소')),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: FilledButton(
                onPressed: _busy || !_allowed ? null : _save,
                child: Text(
                  _saving
                      ? (_editing
                            ? AppStrings.tr(context, '저장 중…')
                            : AppStrings.tr(context, '등록 중…'))
                      : (_editing
                            ? AppStrings.tr(context, '수정 저장')
                            : AppStrings.tr(context, '메모 등록')),
                ),
              ),
            ),
          ],
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Form(
            key: _form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: AppColors.of(context).peachSoft,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    AppStrings.tr(context, '작은 돌봄 기록도 가족에게 큰 도움이 돼요.'),
                    style: TextStyle(fontSize: 13, height: 1.6),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  AppStrings.tr(context, '메모 내용'),
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _content,
                  autovalidateMode: AutovalidateMode.onUserInteraction,
                  enabled: !_busy,
                  minLines: 7,
                  maxLines: 14,
                  maxLength: 2000,
                  onChanged: (_) => setState(() {}),
                  style: const TextStyle(fontSize: 15, height: 1.8),
                  decoration: InputDecoration(
                    hintText: AppStrings.tr(
                      context,
                      '오늘은 어떤 하루였나요?\n가족에게 전하고 싶은 이야기를 남겨 주세요.',
                    ),
                    filled: true,
                    contentPadding: const EdgeInsets.all(20),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide(
                        color: AppColors.of(context).border,
                      ),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(20),
                      borderSide: BorderSide(
                        color: AppColors.of(context).border,
                      ),
                    ),
                  ),
                  validator: (value) => (value ?? '').trim().isEmpty
                      ? AppStrings.tr(context, '메모 내용을 입력해 주세요.')
                      : null,
                ),

                const SizedBox(height: 16),
                Text(
                  AppStrings.tr(context, '사진 첨부 (선택 · 한 장)'),
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
                      errorBuilder: (_, _, _) => Text(
                        AppStrings.tr(
                          context,
                          '사진을 표시할 수 없어요. 다른 사진을 선택해 주세요.',
                        ),
                      ),
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
                        _picking
                            ? AppStrings.tr(context, '사진 선택 중…')
                            : (_hasImage
                                  ? AppStrings.tr(context, '사진 교체')
                                  : AppStrings.tr(context, '사진 첨부')),
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
                        label: Text(AppStrings.tr(context, '사진 제거')),
                      ),
                  ],
                ),
                Text(
                  AppStrings.tr(context, 'JPG, PNG, WEBP · 최대 5MB'),
                  style: TextStyle(fontSize: 12),
                ),
                if (!sameSpace)
                  Padding(
                    padding: EdgeInsets.only(top: 12),
                    child: Text(
                      AppStrings.tr(
                        context,
                        '선택한 공간이 변경됐어요. 목록으로 돌아가 다시 작성해 주세요.',
                      ),
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
