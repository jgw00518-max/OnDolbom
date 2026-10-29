import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ondolbom/vm/schedules/schedule_vm.dart';

// 등록한 날짜와 알림 발행 결과를 목록에 전달한다.
typedef ScheduleCreateResult = ({DateTime date, bool published});

class ScheduleCreate extends ConsumerStatefulWidget {
  const ScheduleCreate({
    super.key,
    required this.familyRoomId,
    required this.recipientName,
    this.initialDate,
  });

  final String familyRoomId;
  final String recipientName;
  final DateTime? initialDate;

  @override
  ConsumerState<ScheduleCreate> createState() => _ScheduleCreateState();
}

class _ScheduleCreateState extends ConsumerState<ScheduleCreate> {
  final formKey = GlobalKey<FormState>();

  final nameController = TextEditingController();
  final memoController = TextEditingController();

  DateTime selectedDate = DateUtils.dateOnly(DateTime.now());
  TimeOfDay? startTime;
  TimeOfDay? endTime;
  int? startPeriod;
  int? startHour;
  int? startMinute;
  int? endPeriod;
  int? endHour;
  int? endMinute;

  bool isSaving = false;
  String? errorMessage;

  @override
  void initState() {
    super.initState();
    selectedDate = DateUtils.dateOnly(widget.initialDate ?? DateTime.now());
  }

  // 화면이 닫히면 입력 컨트롤러를 정리한다.
  @override
  void dispose() {
    nameController.dispose();
    memoController.dispose();

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('일정 등록')),
      body: Form(
        key: formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text('${widget.recipientName} 님의 돌봄 공간'),
            const SizedBox(height: 24),

            // 일정명
            TextFormField(
              enabled: !isSaving,
              controller: nameController,
              maxLength: 50,
              decoration: const InputDecoration(
                labelText: '일정명 (선택)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),

            // 날짜
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('날짜'),
              subtitle: Text(
                '${selectedDate.year}-'
                '${selectedDate.month.toString().padLeft(2, '0')}-'
                '${selectedDate.day.toString().padLeft(2, '0')}',
              ),
              trailing: const Icon(Icons.calendar_month),
              onTap: isSaving ? null : () => selectDate(),
            ),
            const Divider(),

            // 오전·오후, 시, 분을 나누어 선택한다.
            timeDropdowns(true),
            const SizedBox(height: 20),
            timeDropdowns(false),
            const SizedBox(height: 24),

            // 일정 메모
            TextFormField(
              enabled: !isSaving,
              controller: memoController,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(
                labelText: '일정 메모 (선택)',
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 16),

            if (errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  errorMessage!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),

            FilledButton(
              onPressed: isSaving ? null : () => saveAction(),
              child: Text(isSaving ? '등록 중…' : '일정 등록'),
            ),
          ],
        ),
      ),
    );
  } // build

  // 날짜를 선택한다.
  Future<void> selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: selectedDate,
      firstDate: DateTime(1900),
      lastDate: DateTime(2100, 12, 31),
    );

    if (!mounted || picked == null) {
      return;
    }

    setState(() {
      selectedDate = picked;
    });
  }

  // 분은 00분과 30분만 선택할 수 있다.
  Widget timeDropdowns(bool isStart) {
    final period = isStart ? startPeriod : endPeriod;
    final hour = isStart ? startHour : endHour;
    final minute = isStart ? startMinute : endMinute;
    final prefix = isStart ? 'start' : 'end';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(isStart ? '시작 시간' : '종료 시간'),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: DropdownButtonFormField<int>(
                key: ValueKey('$prefix-period'),
                initialValue: period,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: '오전·오후',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 0, child: Text('오전')),
                  DropdownMenuItem(value: 1, child: Text('오후')),
                ],
                validator: (value) => value == null ? '필수 선택' : null,
                onChanged: isSaving
                    ? null
                    : (value) => changeTime(isStart, 'period', value),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonFormField<int>(
                key: ValueKey('$prefix-hour'),
                initialValue: hour,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: '시',
                  border: OutlineInputBorder(),
                ),
                items: List.generate(
                  12,
                  (index) => DropdownMenuItem(
                    value: index + 1,
                    child: Text('${index + 1}시'),
                  ),
                ),
                validator: (value) => value == null ? '필수 선택' : null,
                onChanged: isSaving
                    ? null
                    : (value) => changeTime(isStart, 'hour', value),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonFormField<int>(
                key: ValueKey('$prefix-minute'),
                initialValue: minute,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: '분',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 0, child: Text('00분')),
                  DropdownMenuItem(value: 30, child: Text('30분')),
                ],
                validator: (value) => value == null ? '필수 선택' : null,
                onChanged: isSaving
                    ? null
                    : (value) => changeTime(isStart, 'minute', value),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // 오전 12시는 00시, 오후 12시는 12시로 변환한다.
  void changeTime(bool isStart, String part, int? value) {
    if (value == null) return;
    setState(() {
      if (isStart) {
        if (part == 'period') startPeriod = value;
        if (part == 'hour') startHour = value;
        if (part == 'minute') startMinute = value;
        if (startPeriod != null && startHour != null && startMinute != null) {
          startTime = TimeOfDay(
            hour: startHour! % 12 + startPeriod! * 12,
            minute: startMinute!,
          );
        }
      } else {
        if (part == 'period') endPeriod = value;
        if (part == 'hour') endHour = value;
        if (part == 'minute') endMinute = value;
        if (endPeriod != null && endHour != null && endMinute != null) {
          endTime = TimeOfDay(
            hour: endHour! % 12 + endPeriod! * 12,
            minute: endMinute!,
          );
        }
      }
      errorMessage = null;
    });
  }

  // 입력값을 확인하고 일정을 등록한다.
  Future<void> saveAction() async {
    if (isSaving || !formKey.currentState!.validate()) {
      return;
    }

    if (startTime == null || endTime == null) {
      setState(() {
        errorMessage = '시작 시간과 종료 시간을 선택해 주세요.';
      });
      return;
    }

    final startMinutes = startTime!.hour * 60 + startTime!.minute;
    final endMinutes = endTime!.hour * 60 + endTime!.minute;

    if (startMinutes >= endMinutes) {
      setState(() {
        errorMessage = '종료 시간은 시작 시간보다 늦어야 합니다.';
      });
      return;
    }

    // 요청 전에 현재 입력값을 고정한다.
    final dateText =
        '${selectedDate.year}-'
        '${selectedDate.month.toString().padLeft(2, '0')}-'
        '${selectedDate.day.toString().padLeft(2, '0')}';

    final startText =
        '${startTime!.hour.toString().padLeft(2, '0')}:'
        '${startTime!.minute.toString().padLeft(2, '0')}:00';

    final endText =
        '${endTime!.hour.toString().padLeft(2, '0')}:'
        '${endTime!.minute.toString().padLeft(2, '0')}:00';

    final name = nameController.text;
    final memo = memoController.text;

    setState(() {
      isSaving = true;
      errorMessage = null;
    });

    try {
      final published = await ref
          .read(scheduleVmProvider)
          .createSchedule(
            familyRoomId: widget.familyRoomId,
            scheduleDate: dateText,
            startTime: startText,
            endTime: endText,
            name: name,
            memo: memo,
          );

      if (!mounted) {
        return;
      }

      // 이전 화면에 등록 성공과 알림 발행 여부를 전달한다.
      Navigator.pop(context, (date: selectedDate, published: published));
    } catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        errorMessage = error.toString().replaceFirst('Exception: ', '');
      });
    } finally {
      if (mounted) {
        setState(() {
          isSaving = false;
        });
      }
    }
  }
} // class
