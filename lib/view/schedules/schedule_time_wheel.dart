import 'package:ondolbom/l10n/app_strings.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:ondolbom/theme/app_colors.dart';

// 적용 전의 휠 선택은 등록 화면에 반영하지 않는다.
class ScheduleTimeWheel extends StatefulWidget {
  const ScheduleTimeWheel({
    super.key,
    required this.isStart,
    required this.initialTime,
    this.startTime,
  });
  final bool isStart;
  final TimeOfDay initialTime;
  final TimeOfDay? startTime;

  @override
  State<ScheduleTimeWheel> createState() => _ScheduleTimeWheelState();
}

class _ScheduleTimeWheelState extends State<ScheduleTimeWheel> {
  late int hour;
  late int minute;
  late final List<int> minutes;
  late final FixedExtentScrollController hourController;
  late final FixedExtentScrollController minuteController;

  @override
  void initState() {
    super.initState();
    hour = widget.initialTime.hour;
    minute = widget.initialTime.minute;
    minutes = List.generate(12, (index) => index * 5);
    // 과거 일정이 5분 단위가 아니어도 기존 값을 임의로 바꾸지 않는다.
    if (!minutes.contains(minute)) {
      minutes.add(minute);
      minutes.sort();
    }
    hourController = FixedExtentScrollController(initialItem: hour);
    minuteController = FixedExtentScrollController(
      initialItem: minutes.indexOf(minute),
    );
  }

  @override
  void dispose() {
    hourController.dispose();
    minuteController.dispose();
    super.dispose();
  }

  int? presetEnd(int duration) {
    final start = widget.startTime;
    if (start == null) return null;
    final end = start.hour * 60 + start.minute + duration;
    // 현재 일정은 같은 날짜 안에서 등록하므로 자정을 넘겨 순환시키지 않는다.
    return end < 24 * 60 ? end : null;
  }

  void selectPreset(int duration) {
    final end = presetEnd(duration);
    if (end == null) return;
    final selectedMinute = end % 60;
    if (!minutes.contains(selectedMinute)) {
      minutes.add(selectedMinute);
      minutes.sort();
    }
    setState(() {
      hour = end ~/ 60;
      minute = selectedMinute;
    });
    hourController.jumpToItem(hour);
    minuteController.jumpToItem(minutes.indexOf(minute));
  }

  Widget wheel({required bool hours}) {
    final values = hours ? List.generate(24, (index) => index) : minutes;
    return Expanded(
      child: Container(
        decoration: BoxDecoration(
          color: AppColors.of(context).background,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: AppColors.of(context).border),
        ),
        child: CupertinoPicker(
          key: ValueKey(hours ? 'hour-wheel' : 'minute-wheel'),
          scrollController: hours ? hourController : minuteController,
          itemExtent: MediaQuery.textScalerOf(context).scale(21) + 27,
          useMagnifier: true,
          magnification: 1.08,
          selectionOverlay: Container(
            margin: const EdgeInsets.symmetric(horizontal: 4),
            decoration: BoxDecoration(
              color: AppColors.of(context).primary.withValues(alpha: 0.22),
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          onSelectedItemChanged: (index) => setState(() {
            if (hours) {
              hour = values[index];
            } else {
              minute = values[index];
            }
          }),
          children: [
            for (final value in values)
              Center(
                child: Text(
                  '${value.toString().padLeft(2, '0')} ${hours ? AppStrings.tr(context, '시') : AppStrings.tr(context, '분')}',
                  style: TextStyle(
                    fontFamily: 'Pretendard',
                    fontSize: 21,
                    fontWeight: FontWeight.w600,
                    color: AppColors.of(context).textPrimary,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final timeText =
        '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.of(context).border,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            const SizedBox(height: 22),
            Text(
              widget.isStart
                  ? AppStrings.tr(context, '시작 시간 선택')
                  : AppStrings.tr(context, '종료 시간 선택'),
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 18),
            Text(
              timeText,
              key: const ValueKey('selected-time'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 40,
                fontWeight: FontWeight.bold,
                color: AppColors.of(context).textPrimary,
              ),
            ),
            const SizedBox(height: 18),
            SizedBox(
              height: 220,
              child: Row(
                children: [
                  wheel(hours: true),
                  const SizedBox(width: 16),
                  wheel(hours: false),
                ],
              ),
            ),
            if (!widget.isStart && widget.startTime != null) ...[
              const SizedBox(height: 22),
              Text(
                AppStrings.tr(context, '시작 시간 기준 빠른 설정'),
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final duration in [120, 240, 480])
                    ChoiceChip(
                      label: Text(
                        AppStrings.format(context, "+{0}시간", [duration ~/ 60]),
                      ),
                      selected: presetEnd(duration) == hour * 60 + minute,
                      onSelected: presetEnd(duration) == null
                          ? null
                          : (_) => selectPreset(duration),
                      selectedColor: AppColors.of(context).primary,
                      backgroundColor: AppColors.of(context).surface,
                      showCheckmark: false,
                      labelStyle: TextStyle(
                        color: AppColors.of(context).textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                      side: BorderSide(color: AppColors.of(context).border),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 10,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                ],
              ),
            ],
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(0, 48),
                    ),
                    child: Text(AppStrings.tr(context, '취소')),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(
                      context,
                      TimeOfDay(hour: hour, minute: minute),
                    ),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 48),
                    ),
                    child: Text(AppStrings.tr(context, '시간 적용')),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
