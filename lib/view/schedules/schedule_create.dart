import 'package:ondolbom/l10n/app_strings.dart';
import 'package:ondolbom/theme/app_colors.dart';
import 'package:ondolbom/view/schedules/schedule_time_wheel.dart';
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
        title: Text(
          widget.initialSchedule == null
              ? AppStrings.tr(context, '일정 등록')
              : AppStrings.tr(context, '일정 변경'),
        ),
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
              decoration: InputDecoration(
                labelText: AppStrings.tr(context, '일정명 (선택)'),
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),

            // 날짜
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(AppStrings.tr(context, '날짜')),
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
                Expanded(child: timeSelectionField(true)),
                const SizedBox(width: 12),
                Expanded(child: timeSelectionField(false)),
              ],
            ),
            const SizedBox(height: 24),

            // 일정 메모
            TextFormField(
              enabled: !isSaving,
              controller: memoController,
              minLines: 3,
              maxLines: 6,
              decoration: InputDecoration(
                labelText: AppStrings.tr(context, '일정 메모 (선택)'),
                border: OutlineInputBorder(),
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 16),

            if (errorMessage != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  AppStrings.error(context, errorMessage!),
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ),

            FilledButton(
              onPressed: isSaving ? null : () => saveAction(),
              child: Text(
                isSaving
                    ? AppStrings.tr(context, '저장 중…')
                    : widget.initialSchedule == null
                    ? AppStrings.tr(context, '일정 등록')
                    : AppStrings.tr(context, '변경 내용 저장'),
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

  // 시작·종료는 독립 휠로 고르고 적용 버튼을 눌렀을 때만 저장한다.
  Widget timeSelectionField(bool isStart) {
    final selected = isStart ? startTime : endTime;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          isStart
              ? AppStrings.tr(context, '시작 시간')
              : AppStrings.tr(context, '종료 시간'),
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppColors.of(context).textPrimary,
          ),
        ),
        const SizedBox(height: 10),
        FormField<TimeOfDay>(
          key: ValueKey(
            '${isStart ? 'start' : 'end'}-${selected?.hour}-${selected?.minute}',
          ),
          initialValue: selected,
          validator: (value) =>
              value == null ? AppStrings.tr(context, '시간을 선택해 주세요.') : null,
          builder: (field) => InkWell(
            key: ValueKey(isStart ? 'start-time' : 'end-time'),
            borderRadius: BorderRadius.circular(14),
            onTap: isSaving
                ? null
                : () async {
                    final now = TimeOfDay.now();
                    final initial =
                        selected ??
                        (isStart ? null : startTime) ??
                        TimeOfDay(hour: now.hour, minute: now.minute ~/ 5 * 5);
                    final picked = await showModalBottomSheet<TimeOfDay>(
                      context: context,
                      isScrollControlled: true,
                      useSafeArea: true,
                      backgroundColor: AppColors.of(context).surface,
                      shape: const RoundedRectangleBorder(
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(28),
                        ),
                      ),
                      builder: (_) => ScheduleTimeWheel(
                        isStart: isStart,
                        initialTime: initial,
                        startTime: startTime,
                      ),
                    );
                    if (!mounted || picked == null) return;
                    setState(() {
                      if (isStart) {
                        startTime = picked;
                      } else {
                        endTime = picked;
                      }
                      errorMessage = null;
                    });
                  },
            child: InputDecorator(
              decoration: InputDecoration(
                enabled: !isSaving,
                filled: true,
                fillColor: AppColors.of(context).surface,
                errorText: field.errorText,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 18,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide(color: AppColors.of(context).border),
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      selected == null
                          ? AppStrings.tr(context, '시간 선택')
                          : '${selected.hour.toString().padLeft(2, '0')}:${selected.minute.toString().padLeft(2, '0')}',
                      style: TextStyle(
                        color: selected == null
                            ? AppColors.of(context).textSecondary
                            : AppColors.of(context).textPrimary,
                      ),
                    ),
                  ),
                  Icon(
                    Icons.schedule_rounded,
                    size: 20,
                    color: AppColors.of(context).sageDark,
                  ),
                ],
              ),
            ),
          ),
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
        SnackBar(
          content: Text(
            AppStrings.tr(context, '일정은 저장됐습니다. 최신 내용을 다시 확인해 주세요.'),
          ),
        ),
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
        backgroundColor: AppColors.resolve(context, const Color(0xFFFFFCF8)),
        surfaceTintColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
          side: BorderSide(
            color: AppColors.resolve(context, Color(0xFFE8DFD7)),
          ),
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
                      decoration: BoxDecoration(
                        color: AppColors.resolve(context, Color(0xFFFFEBD9)),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.phone_outlined,
                        color: AppColors.resolve(context, Color(0xFF99522F)),
                        size: 25,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppStrings.tr(context, '긴급 일정 변경'),
                            style: TextStyle(
                              fontSize: 21,
                              fontWeight: FontWeight.bold,
                              color: AppColors.resolve(
                                context,
                                Color(0xFF403C39),
                              ),
                            ),
                          ),
                          SizedBox(height: 4),
                          Text(
                            AppStrings.tr(context, '변경 내용을 저장했어요'),
                            style: TextStyle(
                              fontSize: 13,
                              color: AppColors.resolve(
                                context,
                                Color(0xFF78716A),
                              ),
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
                    color: AppColors.resolve(context, const Color(0xFFFFF1E5)),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: AppColors.resolve(
                        context,
                        const Color(0xFFF0DDCC),
                      ),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppStrings.tr(context, '시작이 임박한 일정입니다.'),
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.resolve(context, Color(0xFF99522F)),
                        ),
                      ),
                      SizedBox(height: 8),
                      Text(
                        AppStrings.tr(
                          context,
                          '기존 담당 가족에게 전화로 변경 내용을 안내해 주세요.',
                        ),
                        style: TextStyle(
                          fontSize: 15,
                          height: 1.55,
                          color: AppColors.resolve(context, Color(0xFF554B43)),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 18,
                      color: AppColors.resolve(context, Color(0xFF8A7B6E)),
                    ),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        AppStrings.tr(context, '전화로 확인한 뒤에도 담당 가족이 앱에서 ') +
                            AppStrings.tr(context, '재수락하거나 거절해야 합니다.'),
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.5,
                          color: AppColors.resolve(context, Color(0xFF78716A)),
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
                      backgroundColor: AppColors.resolve(
                        context,
                        const Color(0xFFAC5D32),
                        onAccent: true,
                      ),
                      foregroundColor: AppColors.resolve(
                        context,
                        Colors.white,
                        onAccent: true,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(
                      AppStrings.tr(context, '확인'),
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
