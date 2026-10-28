import 'package:ondolbom/theme/app_colors.dart';
import 'package:ondolbom/view/medications/medication_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ondolbom/model/medications/medication.dart';
import 'package:ondolbom/vm/family_room/family_context.dart';
import 'package:ondolbom/vm/medications/medication_vm.dart';

class MedicationFormDialog extends ConsumerStatefulWidget {
  const MedicationFormDialog({super.key, required this.query});
  final MedicationQuery query;
  @override
  ConsumerState<MedicationFormDialog> createState() =>
      _MedicationFormDialogState();
}

class _MedicationFormDialogState extends ConsumerState<MedicationFormDialog> {
  final _form = GlobalKey<FormState>();
  final _info = TextEditingController();
  final _dosage = TextEditingController();
  final _unit = TextEditingController();
  final _minutes = TextEditingController(text: '30');
  String _meal = '아침';
  String _timing = '식후';
  bool _saving = false;
  bool _dirty = false;
  bool _finished = false;
  bool _submitted = false;

  @override
  void dispose() {
    for (final controller in [_info, _dosage, _unit, _minutes]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _close(bool saved) {
    setState(() => _finished = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop(saved);
    });
  }

  Future<void> _cancel() async {
    if (_saving) return;
    if (_dirty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('작성을 취소할까요?'),
          content: const Text('입력한 약 정보는 저장되지 않아요.'),
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
      );
      if (discard != true || !mounted) return;
    }
    _close(false);
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _submitted = true);
    if (!_form.currentState!.validate()) return;
    if (ref.read(familyContextProvider) != widget.query.context) return;
    if (!ref.read(medicationCreateAllowedProvider(widget.query.context))) {
      return;
    }
    setState(() => _saving = true);
    try {
      await ref
          .read(medicationVmProvider(widget.query).notifier)
          .create(
            info: _info.text,
            time: '$_meal $_timing ${int.parse(_minutes.text)}분',
            dosage: _dosage.text,
            unit: _unit.text,
          );
      if (mounted) _close(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            error is MedicationFailure
                ? error.message
                : '저장하지 못했어요. 다시 시도해 주세요.',
          ),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final sameSpace = ref.watch(familyContextProvider) == widget.query.context;
    final allowed = ref.watch(
      medicationCreateAllowedProvider(widget.query.context),
    );
    InputDecoration field(String label, {String? hint}) =>
        MedicationStyle.field(label, hint: hint);
    return PopScope(
      canPop: _finished || (!_dirty && !_saving),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancel();
      },
      child: Dialog(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        shape: MedicationStyle.shape,
        clipBehavior: Clip.antiAlias,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 440,
            maxHeight: MediaQuery.sizeOf(context).height * 0.85,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              MedicationHeading(
                title: '약 추가',
                onClose: _saving ? null : _cancel,
              ),
              const Divider(height: 1),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Form(
                    key: _form,
                    autovalidateMode: _submitted
                        ? AutovalidateMode.onUserInteraction
                        : AutovalidateMode.disabled,
                    onChanged: () {
                      if (!_dirty) setState(() => _dirty = true);
                    },
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        MedicationDateLabel(date: widget.query.date),
                        const SizedBox(height: 20),
                        const Text(
                          '복약 시간과 약',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                initialValue: _meal,
                                decoration: field('식사').copyWith(
                                  isDense: true,
                                  floatingLabelBehavior:
                                      FloatingLabelBehavior.always,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 12,
                                  ),
                                ),
                                isExpanded: true,
                                iconSize: 18,
                                style: Theme.of(context).textTheme.bodyMedium,
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
                                onChanged: _saving
                                    ? null
                                    : (value) => setState(() {
                                        _meal = value!;
                                        _dirty = true;
                                      }),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: DropdownButtonFormField<String>(
                                initialValue: _timing,
                                decoration: field('복약 시점').copyWith(
                                  isDense: true,
                                  floatingLabelBehavior:
                                      FloatingLabelBehavior.always,
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 12,
                                  ),
                                ),
                                isExpanded: true,
                                iconSize: 18,
                                style: Theme.of(context).textTheme.bodyMedium,
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
                                onChanged: _saving
                                    ? null
                                    : (value) => setState(() {
                                        _timing = value!;
                                        _dirty = true;
                                      }),
                              ),
                            ),
                            const SizedBox(width: 6),
                            Expanded(
                              child: TextFormField(
                                key: const ValueKey('medication-minutes'),
                                controller: _minutes,
                                enabled: !_saving,
                                decoration: field('몇 분').copyWith(
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
                        const SizedBox(height: 20),
                        TextFormField(
                          key: const ValueKey('medication-info'),
                          controller: _info,
                          enabled: !_saving,
                          decoration: field('약 이름 · 정보'),
                          maxLength: 100,
                          validator: (value) => (value ?? '').trim().isEmpty
                              ? '약 정보를 입력해 주세요.'
                              : null,
                        ),
                        const SizedBox(height: 12),
                        TextFormField(
                          key: const ValueKey('medication-dosage'),
                          controller: _dosage,
                          enabled: !_saving,
                          decoration: field('용량', hint: '소수점 최대 3자리'),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          validator: (value) =>
                              isValidMedicationDosage(value ?? '')
                              ? null
                              : '0보다 큰 용량을 소수점 3자리 이내로 입력해 주세요.',
                        ),
                        const SizedBox(height: 20),
                        TextFormField(
                          key: const ValueKey('medication-unit'),
                          controller: _unit,
                          enabled: !_saving,
                          decoration: field('단위', hint: '정, 포, mL 등'),
                          maxLength: 20,
                          validator: (value) => (value ?? '').trim().isEmpty
                              ? '단위를 입력해 주세요.'
                              : null,
                        ),
                        if (!sameSpace)
                          Text(
                            '선택한 공간이 변경됐어요. 닫은 후 다시 작성해 주세요.',
                            style: TextStyle(color: colors.error),
                          ),
                        if (!allowed)
                          Text(
                            '현재 공간의 주보호자만 투약일지를 작성할 수 있어요.',
                            style: TextStyle(color: colors.error),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const Divider(height: 1),
              Container(
                color: AppColors.surface,
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    OutlinedButton(
                      onPressed: _saving ? null : _cancel,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(80, 48),
                      ),
                      child: const Text('취소'),
                    ),
                    const Spacer(),
                    FilledButton(
                      onPressed: _saving || !sameSpace || !allowed
                          ? null
                          : _save,
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(110, 48),
                      ),
                      child: Text(_saving ? '등록 중…' : '추가'),
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
