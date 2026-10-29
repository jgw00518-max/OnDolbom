import 'package:flutter/material.dart';
import 'package:ondolbom/theme/app_colors.dart';

Future<DateTime?> showAppDatePicker({
  required BuildContext context,
  required DateTime initialDate,
  required DateTime firstDate,
  required DateTime lastDate,
}) {
  return showDialog<DateTime>(
    context: context,
    builder: (_) => _AppDatePicker(
      initialDate: initialDate,
      firstDate: DateUtils.dateOnly(firstDate),
      lastDate: DateUtils.dateOnly(lastDate),
    ),
  );
}

class _AppDatePicker extends StatefulWidget {
  const _AppDatePicker({
    required this.initialDate,
    required this.firstDate,
    required this.lastDate,
  });
  final DateTime initialDate;
  final DateTime firstDate;
  final DateTime lastDate;
  @override
  State<_AppDatePicker> createState() => _AppDatePickerState();
}

class _AppDatePickerState extends State<_AppDatePicker> {
  late DateTime selected = DateUtils.dateOnly(widget.initialDate);
  int calendarVersion = 0;
  bool inputMode = false;
  final inputKey = GlobalKey<FormState>();

  ButtonStyle get actionStyle => TextButton.styleFrom(
    backgroundColor: AppColors.primary,
    foregroundColor: AppColors.textPrimary,
    minimumSize: const Size(64, 44),
    textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
  );

  @override
  Widget build(BuildContext context) {
    final today = DateUtils.dateOnly(DateTime.now());
    final todayAllowed =
        !today.isBefore(widget.firstDate) && !today.isAfter(widget.lastDate);
    return Dialog(
      backgroundColor: AppColors.background,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                color: AppColors.peachSoft,
                padding: const EdgeInsets.fromLTRB(20, 18, 12, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '날짜 선택',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 18),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            MaterialLocalizations.of(
                              context,
                            ).formatMediumDate(selected),
                            style: const TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        TextButton(
                          key: const ValueKey('date-picker-today'),
                          style: actionStyle,
                          onPressed: todayAllowed
                              ? () => setState(() {
                                  selected = today;
                                  inputMode = false;
                                  calendarVersion++;
                                })
                              : null,
                          child: const Text('오늘'),
                        ),
                        IconButton(
                          tooltip: inputMode ? '달력으로 선택' : '날짜 직접 입력',
                          onPressed: () =>
                              setState(() => inputMode = !inputMode),
                          icon: Icon(
                            inputMode
                                ? Icons.calendar_month_outlined
                                : Icons.edit_outlined,
                            size: 22,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              if (inputMode)
                Padding(
                  padding: const EdgeInsets.all(20),
                  child: Form(
                    key: inputKey,
                    child: InputDatePickerFormField(
                      initialDate: selected,
                      firstDate: widget.firstDate,
                      lastDate: widget.lastDate,
                      onDateSaved: (date) => selected = date,
                      onDateSubmitted: (date) =>
                          setState(() => selected = date),
                    ),
                  ),
                )
              else
                CalendarDatePicker(
                  key: ValueKey(calendarVersion),
                  initialDate: selected,
                  firstDate: widget.firstDate,
                  lastDate: widget.lastDate,
                  currentDate: today,
                  onDateChanged: (date) => setState(() => selected = date),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('취소'),
                    ),
                    const SizedBox(width: 12),
                    TextButton(
                      key: const ValueKey('date-picker-apply'),
                      style: actionStyle,
                      onPressed: () {
                        if (inputMode) {
                          if (inputKey.currentState?.validate() != true) return;
                          inputKey.currentState!.save();
                        }
                        Navigator.pop(context, selected);
                      },
                      child: const Text('확인'),
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
