import 'package:ondolbom/theme/app_colors.dart';
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
        title: const Text(
          '메모·채팅 내보내기',
          style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
        ),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _ExportSection(
                    title: '내보낼 기간',
                    icon: Icons.date_range_outlined,
                    children: [
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
                        style: const TextStyle(
                          fontSize: 12,
                          height: 1.6,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _ExportSection(
                    title: '내보낼 범위',
                    icon: Icons.checklist_rounded,
                    children: [
                      CheckboxListTile(
                        activeColor: AppColors.sageDark,
                        checkColor: AppColors.surface,
                        contentPadding: EdgeInsets.zero,
                        controlAffinity: ListTileControlAffinity.leading,
                        title: const Text('메모'),
                        value: _memos,
                        onChanged: enabled
                            ? (value) => _change(() => _memos = value ?? false)
                            : null,
                      ),
                      CheckboxListTile(
                        activeColor: AppColors.sageDark,
                        checkColor: AppColors.surface,
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
                          style: TextStyle(
                            color: colors.error,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _ExportSection(
                    title: '이미지 포함 여부',
                    icon: Icons.image_outlined,
                    children: [
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
                                activeColor: AppColors.sageDark,
                                contentPadding: EdgeInsets.zero,
                                title: const Text('포함'),
                                value: true,
                                enabled: enabled,
                              ),
                            ),
                            Expanded(
                              child: RadioListTile<bool>(
                                activeColor: AppColors.sageDark,
                                contentPadding: EdgeInsets.zero,
                                title: const Text('제외'),
                                value: false,
                                enabled: enabled,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  _ExportSection(
                    title: '파일 형식',
                    icon: Icons.description_outlined,
                    children: [
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
                                activeColor: AppColors.sageDark,
                                key: const Key('export-format-html'),
                                contentPadding: EdgeInsets.zero,
                                title: const Text('HTML'),
                                value: ExportFormat.html,
                                enabled: enabled,
                              ),
                            ),
                            Expanded(
                              child: RadioListTile<ExportFormat>(
                                activeColor: AppColors.sageDark,
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
                        style: const TextStyle(
                          fontSize: 12,
                          height: 1.6,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: AppColors.peachSoft,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.info_outline,
                          size: 18,
                          color: AppColors.sageDark,
                        ),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '투약일지, 일정은 포함되지 않습니다.',
                            style: TextStyle(
                              fontSize: 14,
                              height: 1.6,
                              color: AppColors.textPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                  if (!allowed)
                    Text(
                      '계정 또는 돌봄 공간이 변경됐어요. 화면을 다시 열어 주세요.',
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
                          style: TextStyle(
                            color: colors.error,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                    ],
                    if (state.message != null) ...[
                      Semantics(liveRegion: true, child: Text(state.message!)),
                      const SizedBox(height: 16),
                    ],
                    if (state.file != null) ...[
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: AppColors.sageLight,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          children: [
                            const Icon(
                              Icons.task_alt,
                              color: AppColors.sageDark,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                state.file!.name,
                                style: const TextStyle(
                                  fontSize: 13,
                                  height: 1.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.icon(
                        key: const Key('export-save'),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(50),
                          textStyle: const TextStyle(fontSize: 16),
                        ),
                        onPressed: enabled
                            ? () => ref
                                  .read(
                                    exportVmProvider(widget.selected).notifier,
                                  )
                                  .save()
                            : null,
                        icon: const Icon(Icons.download_outlined),
                        label: const Text('파일 다운로드'),
                      ),
                      const SizedBox(height: 12),
                    ],
                    OutlinedButton.icon(
                      key: const Key('export-generate'),
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size.fromHeight(50),
                        backgroundColor: state.file == null
                            ? AppColors.primary
                            : AppColors.surface,
                        foregroundColor: AppColors.textPrimary,
                        side: state.file == null
                            ? BorderSide.none
                            : const BorderSide(color: AppColors.border),
                        textStyle: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      onPressed: enabled && (_memos || _chats)
                          ? () => ref
                                .read(
                                  exportVmProvider(widget.selected).notifier,
                                )
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
          ),
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
          filled: true,
          fillColor: AppColors.background,
          labelStyle: const TextStyle(
            color: AppColors.sageDark,
            fontWeight: FontWeight.w700,
          ),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: const BorderSide(color: AppColors.border),
          ),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 16,
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                exportDate(date),
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const Icon(
              Icons.calendar_month_outlined,
              size: 18,
              color: AppColors.sageDark,
            ),
          ],
        ),
      ),
    );
  }
}

class _ExportSection extends StatelessWidget {
  const _ExportSection({
    required this.title,
    required this.icon,
    required this.children,
  });
  final String title;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Material(
    color: AppColors.surface,
    clipBehavior: Clip.antiAlias,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(22),
      side: const BorderSide(color: AppColors.border),
    ),
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: AppColors.sageDark),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    ),
  );
}
