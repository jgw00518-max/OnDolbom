import 'package:ondolbom/view/widgets/app_date_picker.dart';
import 'package:ondolbom/view/widgets/discard_changes_dialog.dart';
import 'package:ondolbom/theme/app_colors.dart';
import 'package:ondolbom/view/widgets/app_back_button.dart';
import 'package:ondolbom/view/medications/medication_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ondolbom/model/medications/medication.dart';
import 'package:ondolbom/vm/family_room/family_context.dart';
import 'package:ondolbom/vm/medications/medication_vm.dart';

class MedicationFormView extends ConsumerStatefulWidget {
  const MedicationFormView({super.key, required this.query});
  final MedicationQuery query;
  @override
  ConsumerState<MedicationFormView> createState() => _MedicationFormViewState();
}

class _MedicationFormViewState extends ConsumerState<MedicationFormView> {
  final _form = GlobalKey<FormState>();
  final _info = TextEditingController();
  final _dosage = TextEditingController();
  final _unit = TextEditingController();
  final _minutes = TextEditingController(text: '30');
  final _days = TextEditingController(text: '7');
  bool _customPeriod = false;
  int _periodDays = 2;
  String _meal = '아침';
  String _timing = '식후';
  bool _saving = false;
  bool _dirty = false;
  bool _finished = false;
  bool _submitted = false;
  late DateTime _startDate;
  MedicationQuery get _query =>
      (context: widget.query.context, date: medicationDateKey(_startDate));

  @override
  void initState() {
    super.initState();
    _startDate = DateTime.parse(widget.query.date);
  }

  Future<void> _pickStartDate() async {
    if (_saving) return;
    final date = await showAppDatePicker(
      context: context,
      initialDate: _startDate,
      firstDate: DateTime(1900),
      lastDate: DateTime(2100, 12, 31),
    );
    if (mounted && date != null && date != _startDate) {
      setState(() {
        _startDate = date;
        _dirty = true;
      });
    }
  }

  @override
  void dispose() {
    for (final controller in [_info, _dosage, _unit, _minutes, _days]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _close(bool saved) {
    setState(() => _finished = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) Navigator.of(context).pop(saved ? _startDate : null);
    });
  }

  Future<void> _cancel() async {
    if (_saving) return;
    if (_dirty) {
      final discard = await showDialog<bool>(
        context: context,
        builder: (context) => const DiscardChangesDialog(
          title: '작성을 취소할까요?',
          message: '입력한 약 정보는 저장되지 않아요.',
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
          .read(medicationVmProvider(_query).notifier)
          .create(
            info: _info.text,
            time: '$_meal $_timing ${int.parse(_minutes.text)}분',
            dosage: _dosage.text,
            unit: _unit.text,
            durationDays: _customPeriod ? int.parse(_days.text) : _periodDays,
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

  InputDecoration _field({String? hint, String? suffix}) {
    final common = MedicationStyle.field('', hint: hint);
    return InputDecoration(
      hintText: hint,
      suffixText: suffix,
      hintStyle: const TextStyle(color: AppColors.textSecondary, fontSize: 13),
      filled: true,
      fillColor: AppColors.background,
      border: common.border,
      enabledBorder: common.enabledBorder,
      focusedBorder: common.focusedBorder,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      errorMaxLines: 3,
      counterText: '',
    );
  }

  Widget _card(Widget child) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(24),
      border: Border.all(color: AppColors.border),
      boxShadow: [
        BoxShadow(
          color: AppColors.textPrimary.withValues(alpha: .035),
          blurRadius: 22,
          offset: const Offset(0, 8),
        ),
      ],
    ),
    child: child,
  );

  Widget _section(String title) => Padding(
    padding: const EdgeInsets.only(top: 28, bottom: 14),
    child: Text(
      title,
      style: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w800,
        color: AppColors.textPrimary,
      ),
    ),
  );

  Widget _control(String label, Widget child) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        label,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: AppColors.textSecondary,
        ),
      ),
      const SizedBox(height: 10),
      child,
    ],
  );

  Widget _mode(bool custom, String label) => Expanded(
    child: TextButton(
      key: ValueKey(
        custom ? 'medication-custom-mode' : 'medication-preset-mode',
      ),
      onPressed: _saving
          ? null
          : () => setState(() {
              _customPeriod = custom;
              _dirty = true;
            }),
      style: TextButton.styleFrom(
        foregroundColor: _customPeriod == custom
            ? AppColors.textPrimary
            : AppColors.textSecondary,
        backgroundColor: _customPeriod == custom
            ? AppColors.surface
            : Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 15),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
      ),
      child: Text(label),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final sameSpace = ref.watch(familyContextProvider) == widget.query.context;
    final allowed = ref.watch(
      medicationCreateAllowedProvider(widget.query.context),
    );
    // 날짜를 변경한 경우에도 저장 완료까지 해당 날짜의 기존 VM 수명을 유지한다.
    ref.watch(medicationVmProvider(_query).select((_) => null));
    final colors = Theme.of(context).colorScheme;
    final meal = _control(
      '식사',
      DropdownButtonFormField<String>(
        key: const ValueKey('medication-meal'),
        initialValue: _meal,
        isExpanded: true,
        decoration: _field(),
        style: Theme.of(context).textTheme.bodyMedium,
        icon: const Icon(Icons.keyboard_arrow_down, size: 20),
        items: ['아침', '점심', '저녁']
            .map((value) => DropdownMenuItem(value: value, child: Text(value)))
            .toList(),
        onChanged: _saving
            ? null
            : (value) => setState(() {
                _meal = value!;
                _dirty = true;
              }),
      ),
    );
    final timing = _control(
      '복약 시점',
      DropdownButtonFormField<String>(
        key: const ValueKey('medication-timing'),
        initialValue: _timing,
        isExpanded: true,
        decoration: _field(),
        style: Theme.of(context).textTheme.bodyMedium,
        icon: const Icon(Icons.keyboard_arrow_down, size: 20),
        items: ['식전', '식후']
            .map((value) => DropdownMenuItem(value: value, child: Text(value)))
            .toList(),
        onChanged: _saving
            ? null
            : (value) => setState(() {
                _timing = value!;
                _dirty = true;
              }),
      ),
    );
    final minutes = _control(
      '간격',
      TextFormField(
        key: const ValueKey('medication-minutes'),
        controller: _minutes,
        enabled: !_saving,
        decoration: _field(suffix: '분'),
        keyboardType: TextInputType.number,
        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
        validator: (value) =>
            int.tryParse(value ?? '') == null || value!.length > 4
            ? '0~9999분 입력'
            : null,
      ),
    );
    return PopScope(
      canPop: _finished || (!_dirty && !_saving),
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _cancel();
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          toolbarHeight: 88,
          leadingWidth: 70,
          leading: AppBackLeading(onPressed: _cancel, enabled: !_saving),
          centerTitle: true,
          foregroundColor: AppColors.textPrimary,
          title: const Column(
            children: [
              Text(
                'MEDICATION',
                style: TextStyle(
                  fontSize: 9,
                  letterSpacing: 2,
                  color: AppColors.textSecondary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              SizedBox(height: 4),
              Text(
                '약 추가',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800),
              ),
            ],
          ),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 20),
              child: Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: AppColors.sageLight,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.medication_outlined,
                  color: AppColors.sageDark,
                  size: 24,
                ),
              ),
            ),
          ],
        ),
        body: SafeArea(
          top: false,
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 24, 20, 28),
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
                      Material(
                        color: AppColors.peachLight,
                        borderRadius: BorderRadius.circular(24),
                        clipBehavior: Clip.antiAlias,
                        child: InkWell(
                          key: const ValueKey('medication-start-date'),
                          onTap: _saving ? null : _pickStartDate,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 18,
                              vertical: 14,
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: AppColors.peachSoft,
                                    borderRadius: BorderRadius.circular(15),
                                  ),
                                  child: const Icon(
                                    Icons.calendar_today_outlined,
                                    color: AppColors.sageDark,
                                    size: 23,
                                  ),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text(
                                        '복용 시작일',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.w700,
                                          color: AppColors.sageDark,
                                        ),
                                      ),
                                      const SizedBox(height: 5),
                                      Text(
                                        medicationDateKey(_startDate),
                                        style: const TextStyle(
                                          fontSize: 19,
                                          fontWeight: FontWeight.w800,
                                          color: AppColors.textPrimary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                const Icon(
                                  Icons.calendar_month_outlined,
                                  size: 22,
                                  color: AppColors.textPrimary,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      _section('복용 기간'),
                      _card(
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Container(
                              padding: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                color: AppColors.background,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Row(
                                children: [
                                  _mode(false, '기간 선택'),
                                  _mode(true, '직접 입력'),
                                ],
                              ),
                            ),
                            const SizedBox(height: 20),
                            // 디자인은 탭으로 바꾸고 기존 기간·직접 입력 값과 검증 규칙은 유지한다.
                            if (!_customPeriod)
                              _control(
                                '복용 기간',
                                DropdownButtonFormField<int>(
                                  key: const ValueKey('medication-period'),
                                  initialValue: _periodDays,
                                  isExpanded: true,
                                  decoration: _field(),
                                  icon: const Icon(Icons.keyboard_arrow_down),
                                  items: const [
                                    DropdownMenuItem(
                                      value: 2,
                                      child: Text('2일'),
                                    ),
                                    DropdownMenuItem(
                                      value: 3,
                                      child: Text('3일'),
                                    ),
                                    DropdownMenuItem(
                                      value: 5,
                                      child: Text('5일'),
                                    ),
                                    DropdownMenuItem(
                                      value: 7,
                                      child: Text('7일'),
                                    ),
                                    DropdownMenuItem(
                                      value: 30,
                                      child: Text('1개월 (30일)'),
                                    ),
                                    DropdownMenuItem(
                                      value: 90,
                                      child: Text('3개월 (90일)'),
                                    ),
                                  ],
                                  onChanged: _saving
                                      ? null
                                      : (value) => setState(() {
                                          _periodDays = value!;
                                          _dirty = true;
                                        }),
                                ),
                              )
                            else
                              _control(
                                '복용 일수',
                                TextFormField(
                                  key: const ValueKey('medication-period-days'),
                                  controller: _days,
                                  enabled: !_saving,
                                  decoration: _field(suffix: '일'),
                                  keyboardType: TextInputType.number,
                                  inputFormatters: [
                                    FilteringTextInputFormatter.digitsOnly,
                                    LengthLimitingTextInputFormatter(3),
                                  ],
                                  validator: (value) {
                                    final days = int.tryParse(value ?? '');
                                    return days == null ||
                                            days < 1 ||
                                            days > 365
                                        ? '1~365일 입력'
                                        : null;
                                  },
                                ),
                              ),
                            const SizedBox(height: 14),
                            const Text(
                              '선택한 시작일을 포함해 매일 투약 일정이 추가돼요.\n직접 입력은 최대 365일까지 가능해요.',
                              style: TextStyle(
                                fontSize: 11,
                                height: 1.6,
                                color: AppColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      _section('복약 시간'),
                      _card(
                        LayoutBuilder(
                          builder: (context, constraints) {
                            // 작은 화면·큰 글씨에서는 입력 칸을 나눠 드롭다운과 단위가 겹치지 않게 한다.
                            if (constraints.maxWidth < 270 ||
                                MediaQuery.textScalerOf(context).scale(14) >
                                    17) {
                              return Column(
                                children: [
                                  Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Expanded(child: meal),
                                      const SizedBox(width: 12),
                                      Expanded(child: timing),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  minutes,
                                ],
                              );
                            }
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(child: meal),
                                const SizedBox(width: 10),
                                Expanded(child: timing),
                                const SizedBox(width: 10),
                                Expanded(child: minutes),
                              ],
                            );
                          },
                        ),
                      ),
                      _section('약 정보'),
                      _card(
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _control(
                              '약 이름 · 정보',
                              TextFormField(
                                key: const ValueKey('medication-info'),
                                controller: _info,
                                enabled: !_saving,
                                decoration: _field(hint: '예: 혈압약, 흰색 원형 알약'),
                                maxLength: 100,
                                validator: (value) =>
                                    (value ?? '').trim().isEmpty
                                    ? '약 정보를 입력해 주세요.'
                                    : null,
                              ),
                            ),
                            const SizedBox(height: 20),
                            const Text(
                              '1회 복용량',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    key: const ValueKey('medication-dosage'),
                                    controller: _dosage,
                                    enabled: !_saving,
                                    decoration: _field(hint: '용량 · 예: 1'),
                                    keyboardType:
                                        const TextInputType.numberWithOptions(
                                          decimal: true,
                                        ),
                                    validator: (value) =>
                                        isValidMedicationDosage(value ?? '')
                                        ? null
                                        : '0보다 큰 용량을 소수점 3자리 이내로 입력해 주세요.',
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: TextFormField(
                                    key: const ValueKey('medication-unit'),
                                    controller: _unit,
                                    enabled: !_saving,
                                    decoration: _field(hint: '단위 · 정, 포, mL'),
                                    maxLength: 20,
                                    validator: (value) =>
                                        (value ?? '').trim().isEmpty
                                        ? '단위를 입력해 주세요.'
                                        : null,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (!sameSpace)
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Text(
                            '선택한 공간이 변경됐어요. 닫은 후 다시 작성해 주세요.',
                            style: TextStyle(color: colors.error),
                          ),
                        ),
                      if (!allowed)
                        Padding(
                          padding: const EdgeInsets.only(top: 16),
                          child: Text(
                            '현재 공간의 주보호자만 투약일지를 작성할 수 있어요.',
                            style: TextStyle(color: colors.error),
                          ),
                        ),
                      const SizedBox(height: 28),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _saving ? null : _cancel,
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size.fromHeight(54),
                                foregroundColor: AppColors.textPrimary,
                                backgroundColor: AppColors.surface,
                                side: const BorderSide(color: AppColors.border),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18),
                                ),
                              ),
                              child: const Text('취소'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            flex: 2,
                            child: FilledButton.icon(
                              onPressed: _saving || !sameSpace || !allowed
                                  ? null
                                  : _save,
                              icon: const Icon(Icons.check, size: 20),
                              label: Text(_saving ? '등록 중…' : '약 추가하기'),
                              style: FilledButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: AppColors.textPrimary,
                                minimumSize: const Size.fromHeight(54),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(18),
                                ),
                                textStyle: const TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w800,
                                ),
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
          ),
        ),
      ),
    );
  }
}
