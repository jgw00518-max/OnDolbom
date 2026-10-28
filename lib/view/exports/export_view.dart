import 'package:ondolbom/view/widgets/app_back_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ondolbom/model/exports/export_options.dart';
import 'package:ondolbom/vm/exports/export_vm.dart';
import 'package:ondolbom/vm/family_room/family_context.dart';

class ExportView extends ConsumerStatefulWidget {
  const ExportView({super.key, required this.selected});
  final FamilyContext selected;

  @override
  ConsumerState<ExportView> createState() => _ExportViewState();
}

class _ExportViewState extends ConsumerState<ExportView> {
  late DateTime _start;
  late DateTime _end;
  bool _memos = true;
  bool _chats = true;
  bool _includeImages = false;
  ExportFormat _format = ExportFormat.html;

  @override
  void initState() {
    super.initState();
    _end = ref.read(exportTodayProvider);
    _start = DateTime(_end.year, _end.month, 1);
  }

  void _change(VoidCallback update) {
    ref.read(exportVmProvider(widget.selected).notifier).clear();
    setState(update);
  }

  Future<void> _pickDate(bool start) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: start ? _start : _end,
      firstDate: start ? DateTime(1000) : _start,
      lastDate: start ? _end : ref.read(exportTodayProvider),
      helpText: start ? '시작일 선택' : '종료일 선택',
      cancelText: '취소',
      confirmText: '선택',
    );
    if (!mounted || picked == null) return;
    if (ref.read(familyContextProvider) != widget.selected) return;
    _change(() {
      if (start) {
        _start = picked;
      } else {
        _end = picked;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final current = ref.watch(familyContextProvider);
    final state = ref.watch(exportVmProvider(widget.selected));
    final allowed =
        current == widget.selected &&
        current.familyRoomId.isNotEmpty &&
        current.userId.isNotEmpty;
    final enabled = allowed && !state.busy;
    final colors = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        leadingWidth: 62,
        leading: const AppBackLeading(),
        title: const Text('메모·채팅 내보내기'),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              widget.selected.roomName,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 24),
            const Text('내보낼 기간', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _dateField(
                    '시작일',
                    _start,
                    'export-start',
                    enabled ? () => _pickDate(true) : null,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _dateField(
                    '종료일',
                    _end,
                    'export-end',
                    enabled ? () => _pickDate(false) : null,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              '종료일은 오늘까지 선택할 수 있어요.',
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 24),
            const Text('내보낼 범위', style: TextStyle(fontWeight: FontWeight.bold)),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('메모'),
              value: _memos,
              onChanged: enabled
                  ? (value) => _change(() => _memos = value ?? false)
                  : null,
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              title: const Text('채팅'),
              value: _chats,
              onChanged: enabled
                  ? (value) => _change(() => _chats = value ?? false)
                  : null,
            ),
            if (!_memos && !_chats)
              Text(
                '메모 또는 채팅을 하나 이상 선택해 주세요.',
                style: TextStyle(color: colors.error),
              ),
            const SizedBox(height: 24),
            const Text(
              '이미지 포함 여부',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            RadioGroup<bool>(
              groupValue: _includeImages,
              onChanged: (value) {
                if (enabled && value != null) {
                  _change(() => _includeImages = value);
                }
              },
              child: Row(
                children: [
                  Expanded(
                    child: RadioListTile<bool>(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('포함'),
                      value: true,
                      enabled: enabled,
                    ),
                  ),
                  Expanded(
                    child: RadioListTile<bool>(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('제외'),
                      value: false,
                      enabled: enabled,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const Text('파일 형식', style: TextStyle(fontWeight: FontWeight.bold)),
            RadioGroup<ExportFormat>(
              groupValue: _format,
              onChanged: (value) {
                if (enabled && value != null) {
                  _change(() => _format = value);
                }
              },
              child: Row(
                children: [
                  Expanded(
                    child: RadioListTile<ExportFormat>(
                      key: const Key('export-format-html'),
                      contentPadding: EdgeInsets.zero,
                      title: const Text('HTML'),
                      value: ExportFormat.html,
                      enabled: enabled,
                    ),
                  ),
                  Expanded(
                    child: RadioListTile<ExportFormat>(
                      key: const Key('export-format-pdf'),
                      contentPadding: EdgeInsets.zero,
                      title: const Text('PDF'),
                      value: ExportFormat.pdf,
                      enabled: enabled,
                    ),
                  ),
                ],
              ),
            ),
            Text(
              _format == ExportFormat.html
                  ? 'HTML 문서와 이미지를 ZIP으로 받아 압축 해제 후 열 수 있어요.'
                  : 'PDF 문서 한 개로 받아 바로 열 수 있어요.',
              style: TextStyle(color: colors.onSurfaceVariant),
            ),
            const SizedBox(height: 8),
            const Text('투약 정보·투약일지는 포함되지 않습니다.'),
            const SizedBox(height: 24),
            if (!allowed)
              Text(
                '계정 또는 가족 공간이 변경됐어요. 화면을 다시 열어 주세요.',
                style: TextStyle(color: colors.error),
              )
            else ...[
              if (state.busy) ...[
                const LinearProgressIndicator(),
                const SizedBox(height: 12),
                Text(
                  state.phase == ExportPhase.generating
                      ? '파일을 생성하고 있어요…'
                      : '파일을 저장하고 있어요…',
                  semanticsLabel: '내보내기 진행 상태',
                ),
                const SizedBox(height: 16),
              ],
              if (state.error != null) ...[
                Semantics(
                  liveRegion: true,
                  child: Text(
                    state.error!,
                    style: TextStyle(color: colors.error),
                  ),
                ),
                const SizedBox(height: 16),
              ],
              if (state.message != null) ...[
                Semantics(liveRegion: true, child: Text(state.message!)),
                const SizedBox(height: 16),
              ],
              if (state.file != null) ...[
                Text(state.file!.name),
                const SizedBox(height: 12),
                FilledButton.icon(
                  key: const Key('export-save'),
                  onPressed: enabled
                      ? () => ref
                            .read(exportVmProvider(widget.selected).notifier)
                            .save()
                      : null,
                  icon: const Icon(Icons.download_outlined),
                  label: const Text('파일 다운로드'),
                ),
                const SizedBox(height: 12),
              ],
              OutlinedButton.icon(
                key: const Key('export-generate'),
                onPressed: enabled && (_memos || _chats)
                    ? () => ref
                          .read(exportVmProvider(widget.selected).notifier)
                          .generate(
                            ExportOptions(
                              startDate: _start,
                              endDate: _end,
                              memos: _memos,
                              chats: _chats,
                              includeImages: _includeImages,
                              format: _format,
                            ),
                          )
                    : null,
                icon: const Icon(Icons.folder_zip_outlined),
                label: Text(
                  state.file != null
                      ? '파일 다시 생성'
                      : state.error != null
                      ? '다시 요청'
                      : '파일 생성',
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _dateField(
    String label,
    DateTime date,
    String key,
    VoidCallback? onTap,
  ) {
    return InkWell(
      key: Key(key),
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          enabled: onTap != null,
          border: const OutlineInputBorder(),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 12,
            vertical: 16,
          ),
        ),
        child: Row(
          children: [
            Expanded(child: Text(exportDate(date))),
            const Icon(Icons.calendar_month_outlined, size: 20),
          ],
        ),
      ),
    );
  }
}
