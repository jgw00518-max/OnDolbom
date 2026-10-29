import 'package:ondolbom/view/widgets/app_back_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ondolbom/vm/schedules/schedule_vm.dart';
import 'package:ondolbom/model/schedules/schedule.dart';
import 'package:ondolbom/vm/family_room/family_room_notifier.dart';

// 등록한 날짜와 알림 발행 결과를 목록에 전달한다.
typedef ScheduleCreateResult = ({DateTime date, bool published});
// 변경한 날짜와 실제 변경 여부를 이전 화면에 전달한다.
typedef ScheduleEditResult = ({DateTime date, bool changed});

class ScheduleCreate extends ConsumerStatefulWidget {
  const ScheduleCreate({
    super.key,
    required this.familyRoomId,
    required this.recipientName,
    this.initialDate,
    this.initialSchedule,
  });

  final String familyRoomId;
  final String recipientName;
  final DateTime? initialDate;
  final Schedule? initialSchedule;

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

  bool isSaving = false;
  String? errorMessage;

  @override
  void initState() {
    super.initState();

    final item = widget.initialSchedule;

    if (item == null) {
      selectedDate = DateUtils.dateOnly(widget.initialDate ?? DateTime.now());
      return;
    }

    // 편집할 일정의 최신 내용을 입력창에 채운다.
    selectedDate = DateUtils.dateOnly(item.date);
    nameController.text = item.name ?? '';
    memoController.text = item.memo ?? '';

    final startParts = item.startTime.split(':');
    final endParts = item.endTime.split(':');

    startTime = TimeOfDay(
      hour: int.parse(startParts[0]),
      minute: int.parse(startParts[1]),
    );
    endTime = TimeOfDay(
      hour: int.parse(endParts[0]),
      minute: int.parse(endParts[1]),
    );
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
      appBar: AppBar(
        leadingWidth: 62,
        leading: const AppBackLeading(),
        title: Text(widget.initialSchedule == null ? '일정 등록' : '일정 변경'),
      ),
      body: Form(
        key: formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
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

            // 시작·종료 시간을 24시간 표기로 선택한다.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: timeDropdowns(true)),
                const SizedBox(width: 12),
                Expanded(child: timeDropdowns(false)),
              ],
            ),
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
              child: Text(
                isSaving
                    ? '저장 중…'
                    : widget.initialSchedule == null
                    ? '일정 등록'
                    : '변경 내용 저장',
              ),
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

  // 00:00부터 23:55까지 5분 간격으로 선택한다.
  Widget timeDropdowns(bool isStart) {
    final selectedTime = isStart ? startTime : endTime;
    final selectedMinutes = selectedTime == null
        ? null
        : selectedTime.hour * 60 + selectedTime.minute;

    final minutesList = List.generate(288, (index) => index * 5);

    // 기존 일정이 5분 단위가 아니어도 현재 값은 그대로 표시한다.
    if (selectedMinutes != null && !minutesList.contains(selectedMinutes)) {
      minutesList.add(selectedMinutes);
      minutesList.sort();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          isStart ? '시작 시간' : '종료 시간',
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: Color(0xFF403C39),
          ),
        ),
        const SizedBox(height: 10),
        DropdownButtonFormField<int>(
          key: ValueKey(isStart ? 'start-time' : 'end-time'),
          initialValue: selectedMinutes,
          isExpanded: true,
          menuMaxHeight: 320,
          dropdownColor: Colors.white,
          borderRadius: BorderRadius.circular(14),
          hint: const Text('시간 선택'),
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 18,
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: const BorderSide(color: Color(0xFFE8DFD7)),
            ),
          ),
          items: minutesList.map((minutes) {
            final hour = (minutes ~/ 60).toString().padLeft(2, '0');
            final minute = (minutes % 60).toString().padLeft(2, '0');

            return DropdownMenuItem<int>(
              value: minutes,
              child: Text('$hour:$minute'),
            );
          }).toList(),
          validator: (value) => value == null ? '시간을 선택해 주세요.' : null,
          onChanged: isSaving
              ? null
              : (value) {
                  if (value == null) {
                    return;
                  }

                  setState(() {
                    final time = TimeOfDay(
                      hour: value ~/ 60,
                      minute: value % 60,
                    );

                    if (isStart) {
                      startTime = time;
                    } else {
                      endTime = time;
                    }

                    errorMessage = null;
                  });
                },
        ),
      ],
    );
  }

  // 입력값을 확인하고 신규 등록 또는 변경 저장을 요청한다.
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

    // 요청 전에 입력값을 고정한다.
    final date = selectedDate;
    final item = widget.initialSchedule;

    final dateText =
        '${date.year}-'
        '${date.month.toString().padLeft(2, '0')}-'
        '${date.day.toString().padLeft(2, '0')}';

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
      final vm = ref.read(scheduleVmProvider);

      if (item == null) {
        // 전달된 일정이 없으면 새 일정을 등록한다.
        final published = await vm.createSchedule(
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

        Navigator.pop<ScheduleCreateResult>(context, (
          date: date,
          published: published,
        ));
      } else {
        // 전달된 일정이 있으면 해당 일정의 변경 이력을 저장한다.
        final changed = await vm.updateSchedule(
          scheduleSeq: item.seq,
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
        final timeChanged =
            !DateUtils.isSameDay(item.date, date) ||
            item.startTime != startText.substring(0, 5) ||
            item.endTime != endText.substring(0, 5);

        if (changed && timeChanged) {
          await showUrgentChangeNotice(item.seq, date);
        }

        if (!mounted) return;
        Navigator.pop<ScheduleEditResult>(context, (
          date: date,
          changed: changed,
        ));
      }
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
  } // build

  // 저장 성공 후 서버가 긴급 요청으로 판단한 경우 안내창을 표시한다.
  Future<void> showUrgentChangeNotice(int scheduleSeq, DateTime date) async {
    final rooms = ref.read(familyRoomProvider);

    if (rooms.selectedRoomId != widget.familyRoomId ||
        rooms.selectedParticipation?.isRepresentative != true) {
      return;
    }

    Schedule? saved;

    try {
      final schedules = await ref.read(scheduleVmProvider).fetchSchedules((
        familyRoomId: widget.familyRoomId,
        year: date.year,
        month: date.month,
      ));

      for (final schedule in schedules) {
        if (schedule.seq == scheduleSeq) {
          saved = schedule;
          break;
        }
      }
    } catch (_) {
      // 저장 후 조회 실패를 저장 실패로 표시하지 않는다.
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('일정은 저장됐습니다. 최신 내용을 다시 확인해 주세요.')),
      );
      return;
    }

    if (!mounted ||
        saved == null ||
        !saved.reconfirmRequired ||
        !saved.reconfirmIsUrgent) {
      return;
    }

    final currentRooms = ref.read(familyRoomProvider);

    if (currentRooms.selectedRoomId != widget.familyRoomId ||
        currentRooms.selectedParticipation?.isRepresentative != true) {
      return;
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Dialog(
        backgroundColor: const Color(0xFFFFFCF8),
        surfaceTintColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: const BorderSide(color: Color(0xFFE8DFD7)),
        ),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 48,
                      height: 48,
                      decoration: const BoxDecoration(
                        color: Color(0xFFFFEBD9),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.phone_outlined,
                        color: Color(0xFF99522F),
                        size: 25,
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '긴급 일정 변경',
                            style: TextStyle(
                              fontSize: 21,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF403C39),
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            '변경 내용을 저장했어요',
                            style: TextStyle(
                              fontSize: 13,
                              color: Color(0xFF78716A),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 22),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF1E5),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0xFFF0DDCC)),
                  ),
                  child: const Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '시작이 임박한 일정입니다.',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF99522F),
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        '기존 담당 가족에게 전화로 변경 내용을 안내해 주세요.',
                        style: TextStyle(
                          fontSize: 15,
                          height: 1.55,
                          color: Color(0xFF554B43),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 18,
                      color: Color(0xFF8A7B6E),
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '전화로 확인한 뒤에도 담당 가족이 앱에서 '
                        '재수락하거나 거절해야 합니다.',
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.5,
                          color: Color(0xFF78716A),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: FilledButton(
                    onPressed: () => Navigator.pop(dialogContext),
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFFAC5D32),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text(
                      '확인',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
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
} // class
