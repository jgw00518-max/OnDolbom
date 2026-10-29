import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ondolbom/model/medications/medication.dart';
import 'package:ondolbom/vm/family_room/family_context.dart';
import 'package:ondolbom/vm/medications/medication_vm.dart';

class MedicationEditDialog extends ConsumerStatefulWidget {
  const MedicationEditDialog({
    super.key,
    required this.query,
    required this.item,
  });
  final MedicationQuery query;
  final Medication item;
  @override
  ConsumerState<MedicationEditDialog> createState() =>
      _MedicationEditDialogState();
}

class _MedicationEditDialogState extends ConsumerState<MedicationEditDialog> {
  final _form = GlobalKey<FormState>();
  late final _info = TextEditingController(text: widget.item.info ?? '');
  final _minutes = TextEditingController();
  String? _meal;
  String? _timing;
  bool _unstructuredTime = false;
  late final _dosage = TextEditingController(text: widget.item.dosage ?? '');
  late final _unit = TextEditingController(text: widget.item.unit ?? '');
  late DateTime _date = widget.item.date;
  bool _saving = false;
  bool _dirty = false;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    final parsed = RegExp(
      r'^(아침|점심|저녁)\s+(식전|식후)\s+(\d{1,4})분$',
    ).firstMatch(widget.item.time?.trim() ?? '');
    if (parsed != null) {
      _meal = parsed.group(1);
      _timing = parsed.group(2);
      _minutes.text = int.parse(parsed.group(3)!).toString();
    } else {
      // 자유 형식 기록은 임의의 기본값으로 바꾸지 않고 사용자가 명시적으로 선택한다.
      _unstructuredTime = true;
    }
  }

  @override
  void dispose() {
    for (final controller in [_info, _minutes, _dosage, _unit]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _close(DateTime? savedDate) {
    setState(() => _finished = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop(savedDate);
    });
  }

  Future<void> _cancel() async {
    if (_saving) return;
    if (_dirty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('수정을 취소할까요?'),
          content: const Text('변경한 약 정보는 저장되지 않아요.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('계속 수정'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('수정 취소'),
            ),
          ],
        ),
      );
      if (!mounted || discard != true) return;
    }
    _close(null);
  }

  Future<void> _save() async {
    if (_saving || !_form.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await ref
          .read(medicationVmProvider(widget.query).notifier)
          .updateMedication(
            item: widget.item,
            date: _date,
            info: _info.text,
            time: '$_meal $_timing ${int.parse(_minutes.text)}분',
            dosage: _dosage.text,
            unit: _unit.text,
          );
      if (mounted) _close(_date);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is MedicationFailure
                ? error.message
                : '수정하지 못했어요. 다시 시도해 주세요.',
          ),
        ),
      );
    }
  }

  Future<void> _pickDate() async {
    final selected = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime(1),
      lastDate: DateTime(9999, 12, 31),
    );
    if (!mounted || selected == null) return;
    setState(() {
      _date = selected;
      _dirty = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    final sameSpace = ref.watch(familyContextProvider) == widget.query.context;
    final allowed =
        sameSpace &&
        ref.watch(medicationEditAllowedProvider(widget.query.context));
    final colors = Theme.of(context).colorScheme;
    final enabled = !_saving && allowed;
    InputDecoration decoration(String label) => InputDecoration(
      labelText: label,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      errorMaxLines: 3,
    );
    return PopScope(
      canPop: _finished || (!_saving && !_dirty),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancel();
      },
      child: Dialog(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 440,
            maxHeight: MediaQuery.sizeOf(context).height * 0.85,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 8, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '투약 정보 수정',
                        style: Theme.of(
                          context,
                        ).textTheme.titleLarge?.copyWith(color: colors.primary),
                      ),
                    ),
                    IconButton(
                      tooltip: '닫기',
                      onPressed: _saving ? null : _cancel,
                      icon: const Icon(Icons.close),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Form(
                    key: _form,
                    onChanged: () {
                      if (!_dirty) setState(() => _dirty = true);
                    },
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(widget.query.context.roomName),
                        const SizedBox(height: 8),
                        TextButton.icon(
                          key: const ValueKey('medication-edit-date'),
                          onPressed: enabled ? _pickDate : null,
                          icon: const Icon(Icons.calendar_today_outlined),
                          label: Text(medicationDateKey(_date)),
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          key: const ValueKey('medication-edit-info'),
                          controller: _info,
                          enabled: enabled,
                          maxLength: 100,
                          decoration: decoration('약 이름 · 정보'),
                          validator: (value) => (value ?? '').trim().isEmpty
                              ? '약 정보를 입력해 주세요.'
                              : null,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          '복약 시간',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 12),
                        if (_unstructuredTime) ...[
                          Text(
                            '기존 복약 시간: ${widget.item.time ?? '미지정'}\n식사·복약 시점·분을 선택해 주세요.',
                            style: TextStyle(color: colors.onSurfaceVariant),
                          ),
                          const SizedBox(height: 12),
                        ],
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                key: const ValueKey('medication-edit-meal'),
                                initialValue: _meal,
                                isExpanded: true,
                                iconSize: 18,
                                style: Theme.of(context).textTheme.bodyMedium,
                                decoration: decoration('식사').copyWith(
                                  isDense: true,
                                  floatingLabelBehavior:
                                      FloatingLabelBehavior.always,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 12,
                                  ),
                                ),
                                items: ['아침', '점심', '저녁']
                                    .map(
                                      (value) => DropdownMenuItem(
                                        value: value,
                                        child: Text(
                                          value,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    )
                                    .toList(),
                                onChanged: !enabled
                                    ? null
                                    : (value) => setState(() {
                                        _meal = value;
                                        _dirty = true;
                                      }),
                                validator: (value) =>
                                    value == null ? '식사를 선택해 주세요.' : null,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                key: const ValueKey('medication-edit-timing'),
                                initialValue: _timing,
                                isExpanded: true,
                                iconSize: 18,
                                style: Theme.of(context).textTheme.bodyMedium,
                                decoration: decoration('복약 시점').copyWith(
                                  isDense: true,
                                  floatingLabelBehavior:
                                      FloatingLabelBehavior.always,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 12,
                                  ),
                                ),
                                items: ['식전', '식후']
                                    .map(
                                      (value) => DropdownMenuItem(
                                        value: value,
                                        child: Text(
                                          value,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    )
                                    .toList(),
                                onChanged: !enabled
                                    ? null
                                    : (value) => setState(() {
                                        _timing = value;
                                        _dirty = true;
                                      }),
                                validator: (value) =>
                                    value == null ? '시점을 선택해 주세요.' : null,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: TextFormField(
                                key: const ValueKey('medication-edit-minutes'),
                                controller: _minutes,
                                enabled: enabled,
                                decoration: decoration('몇 분').copyWith(
                                  isDense: true,
                                  floatingLabelBehavior:
                                      FloatingLabelBehavior.always,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 12,
                                  ),
                                ),
                                style: Theme.of(context).textTheme.bodyMedium,
                                keyboardType: TextInputType.number,
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                validator: (value) =>
                                    int.tryParse(value ?? '') == null ||
                                        value!.length > 4
                                    ? '0~9999분 입력'
                                    : null,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        TextFormField(
                          key: const ValueKey('medication-edit-dosage'),
                          controller: _dosage,
                          enabled: enabled,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: decoration('용량'),
                          validator: (value) =>
                              isValidMedicationDosage(value ?? '')
                              ? null
                              : '0보다 큰 용량을 소수점 3자리 이내로 입력해 주세요.',
                        ),
                        const SizedBox(height: 20),
                        TextFormField(
                          key: const ValueKey('medication-edit-unit'),
                          controller: _unit,
                          enabled: enabled,
                          maxLength: 20,
                          decoration: decoration('단위'),
                          validator: (value) => (value ?? '').trim().isEmpty
                              ? '단위를 입력해 주세요.'
                              : null,
                        ),
                        if (!sameSpace)
                          Text(
                            '선택한 공간이 변경됐어요. 닫은 후 다시 조회해 주세요.',
                            style: TextStyle(color: colors.error),
                          )
                        else if (!allowed)
                          Text(
                            '현재 공간의 주보호자만 수정할 수 있어요.',
                            style: TextStyle(color: colors.error),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    OutlinedButton(
                      onPressed: _saving ? null : _cancel,
                      child: const Text('취소'),
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: enabled ? _save : null,
                      child: Text(_saving ? '저장 중…' : '수정 저장'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
