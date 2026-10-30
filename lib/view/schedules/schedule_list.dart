import 'package:ondolbom/l10n/app_strings.dart';
import 'package:ondolbom/view/widgets/menu_header_icon.dart';
import 'package:ondolbom/view/widgets/app_add_button.dart';
import 'package:ondolbom/view/widgets/app_back_button.dart';
import 'package:ondolbom/theme/app_colors.dart';
import 'package:ondolbom/view/schedules/schedule_detail.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ondolbom/model/schedules/schedule.dart';
import 'package:ondolbom/view/schedules/schedule_create.dart';
import 'package:ondolbom/vm/family_room/family_room_notifier.dart';
import 'package:ondolbom/vm/schedules/schedule_vm.dart';

class ScheduleList extends ConsumerStatefulWidget {
  const ScheduleList({super.key, required this.familyRoomId, this.initialDate});
  final String familyRoomId;
  final DateTime? initialDate;

  @override
  ConsumerState<ScheduleList> createState() => _ScheduleListState();
}

class _ScheduleListState extends ConsumerState<ScheduleList> {
  late DateTime selectedDate;
  late DateTime displayedMonth;

  @override
  void initState() {
    super.initState();
    selectedDate = DateUtils.dateOnly(widget.initialDate ?? DateTime.now());
    displayedMonth = DateTime(selectedDate.year, selectedDate.month);
  }

  ScheduleQuery get query => (
    familyRoomId: widget.familyRoomId,
    year: displayedMonth.year,
    month: displayedMonth.month,
  );

  @override
  Widget build(BuildContext context) {
    final rooms = ref.watch(familyRoomProvider);
    final room = rooms.selectedRoom;
    if (room == null || room.familyRoomId != widget.familyRoomId) {
      return Scaffold(
        appBar: AppBar(
          leadingWidth: 62,
          leading: const AppBackLeading(),
          title: Text(AppStrings.tr(context, '돌봄 일정')),
        ),
        body: Center(child: Text(AppStrings.tr(context, '돌봄 공간을 다시 선택해 주세요.'))),
      );
    }
    final schedules = ref.watch(scheduleListProvider(query));
    return Scaffold(
      backgroundColor: AppColors.resolve(context, const Color(0xFFFFFBF7)),
      appBar: AppBar(
        leadingWidth: 62,
        leading: const AppBackLeading(),
        backgroundColor: AppColors.resolve(context, const Color(0xFFFFFBF7)),
        foregroundColor: AppColors.resolve(context, const Color(0xFF403C39)),
        titleTextStyle: TextStyle(
          fontSize: 24,
          fontWeight: FontWeight.w800,
          color: AppColors.resolve(context, Color(0xFF403C39)),
        ),
        title: Text(AppStrings.tr(context, '돌봄 일정')),
        actions: const [MenuHeaderIcon(icon: Icons.calendar_month_outlined)],
      ),
      floatingActionButton:
          rooms.selectedParticipation?.isRepresentative == true
          ? AppAddButton(
              key: const ValueKey('schedule-add'),
              tooltip: AppStrings.tr(context, '일정 등록'),
              onPressed: () => createAction(room.careRecipientName),
            )
          : null,
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 18, 12, 104),
        children: [
          calendar(schedules.asData?.value ?? const []),
          const SizedBox(height: 24),
          schedules.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, _) => Column(
              children: [
                Text(
                  AppStrings.error(
                    context,
                    error.toString().replaceFirst('Exception: ', ''),
                  ),
                ),
                TextButton(
                  onPressed: () => ref.invalidate(scheduleListProvider(query)),
                  child: Text(AppStrings.tr(context, '다시 조회')),
                ),
              ],
            ),
            data: (items) => daySchedules(items),
          ),
        ],
      ),
    );
  }

  // ----- function -----

  // 목업의 흰색 월 달력과 복숭아색 선택 표시를 사용한다.
  Widget calendar(List<Schedule> schedules) {
    final firstDay = DateTime(displayedMonth.year, displayedMonth.month);
    final offset = firstDay.weekday % 7;
    final days = DateUtils.getDaysInMonth(
      displayedMonth.year,
      displayedMonth.month,
    );
    final cellCount = ((offset + days + 6) ~/ 7) * 7;
    final counts = <int, int>{};
    for (final item in schedules) {
      counts.update(item.date.day, (value) => value + 1, ifAbsent: () => 1);
    }
    return Container(
      decoration: BoxDecoration(
        color: AppColors.of(context).surface,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: AppColors.resolve(context, const Color(0xFFE8DFD7)),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 18),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                tooltip: AppStrings.tr(context, '이전 달'),
                onPressed:
                    displayedMonth.year == 1900 && displayedMonth.month == 1
                    ? null
                    : () => changeMonth(-1),
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Text(
                  AppStrings.monthYear(context, displayedMonth),
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                    color: AppColors.resolve(context, Color(0xFF403C39)),
                  ),
                ),
              ),
              IconButton(
                tooltip: AppStrings.tr(context, '다음 달'),
                onPressed:
                    displayedMonth.year == 2100 && displayedMonth.month == 12
                    ? null
                    : () => changeMonth(1),
                icon: const Icon(Icons.chevron_right),
              ),
            ],
          ),
          Row(
            children: [
              Expanded(
                child: Text(
                  AppStrings.tr(context, '돌봄이 필요한 날을 확인하세요'),
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.resolve(context, Color(0xFF78716A)),
                  ),
                ),
              ),
              TextButton(
                onPressed: todayAction,
                child: Text(AppStrings.tr(context, '오늘')),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children:
                (AppStrings.isEnglish(context)
                        ? ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat']
                        : ['일', '월', '화', '수', '목', '금', '토'])
                    .asMap()
                    .entries
                    .map(
                      (entry) => Expanded(
                        child: Center(
                          child: Text(
                            entry.value,
                            style: TextStyle(
                              fontSize: 14,
                              color: entry.key == 0
                                  ? AppColors.resolve(
                                      context,
                                      const Color(0xFFD07858),
                                    )
                                  : entry.key == 6
                                  ? AppColors.resolve(
                                      context,
                                      const Color(0xFF7C9FA9),
                                    )
                                  : AppColors.resolve(
                                      context,
                                      const Color(0xFF78716A),
                                    ),
                            ),
                          ),
                        ),
                      ),
                    )
                    .toList(),
          ),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: 4,
              crossAxisSpacing: 2,
              mainAxisExtent: 64,
            ),
            itemCount: cellCount,
            itemBuilder: (context, index) {
              final day = index - offset + 1;
              if (day < 1 || day > days) return const SizedBox.shrink();
              final date = DateTime(
                displayedMonth.year,
                displayedMonth.month,
                day,
              );
              final selected = DateUtils.isSameDay(date, selectedDate);
              final today = DateUtils.isSameDay(date, DateTime.now());
              final count = counts[day] ?? 0;
              return Semantics(
                selected: selected,
                button: true,
                label: AppStrings.format(context, "{0}월 {1}일, 일정 {2}건", [
                  date.month,
                  day,
                  count,
                ]),
                child: InkWell(
                  key: ValueKey('schedule-day-$day'),
                  borderRadius: BorderRadius.circular(13),
                  onTap: () => setState(() => selectedDate = date),
                  child: Container(
                    margin: const EdgeInsets.all(1),
                    decoration: BoxDecoration(
                      color: selected
                          ? AppColors.of(context).peachLight
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(13),
                      border: selected
                          ? Border.all(
                              color: AppColors.resolve(
                                context,
                                const Color(0xFFC78159),
                              ),
                              width: 2,
                            )
                          : null,
                      boxShadow: selected
                          ? [
                              const BoxShadow(
                                color: Color(0xFFFBEADD),
                                spreadRadius: 2,
                              ),
                            ]
                          : null,
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          '$day',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: today
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: today && !selected
                                ? AppColors.resolve(
                                    context,
                                    const Color(0xFF99522F),
                                  )
                                : AppColors.resolve(
                                    context,
                                    const Color(0xFF403C39),
                                  ),
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          count == 0
                              ? ''
                              : AppStrings.format(context, "{0}건", [count]),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 10,
                            color: AppColors.resolve(
                              context,
                              Color(0xFF6C5A4B),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget daySchedules(List<Schedule> schedules) {
    final items = schedules
        .where((item) => DateUtils.isSameDay(item.date, selectedDate))
        .toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                AppStrings.format(context, "{0}월 {1}일", [
                  selectedDate.month,
                  selectedDate.day,
                ]),
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: AppColors.resolve(context, Color(0xFF403C39)),
                ),
              ),
            ),
            Text(
              AppStrings.format(context, "{0}개 일정", [items.length]),
              style: TextStyle(
                fontSize: 15,
                color: AppColors.resolve(context, Color(0xFF78716A)),
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        if (items.isEmpty)
          Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: Text(
                AppStrings.tr(context, '등록된 돌봄 일정이 없어요'),
                style: TextStyle(
                  color: AppColors.resolve(context, Color(0xFF78716A)),
                ),
              ),
            ),
          ),
        ...items.map(
          (item) => Container(
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
              color: AppColors.of(context).surface,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: AppColors.resolve(context, const Color(0xFFE8DFD7)),
              ),
            ),
            child: Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(20),
              clipBehavior: Clip.antiAlias,
              child: InkWell(
                onTap: () => detailAction(item),
                child: Padding(
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Flexible(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: item.acceptedBy == null
                                    ? AppColors.resolve(
                                        context,
                                        const Color(0xFFF0F2EE),
                                      )
                                    : AppColors.resolve(
                                        context,
                                        const Color(0xFFFFEBD9),
                                      ),
                                borderRadius: BorderRadius.circular(24),
                              ),
                              child: Text(
                                item.assignment,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.resolve(
                                    context,
                                    Color(0xFF756B60),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            '${item.startTime} – ${item.endTime}',
                            style: TextStyle(
                              fontSize: 12,
                              color: AppColors.resolve(
                                context,
                                Color(0xFF78716A),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Text(
                        item.title,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: AppColors.resolve(context, Color(0xFF403C39)),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          Text(
                            AppStrings.tr(context, '담당자'),
                            style: TextStyle(
                              color: AppColors.resolve(
                                context,
                                Color(0xFF78716A),
                              ),
                            ),
                          ),
                          Text(
                            item.acceptedBy == null
                                ? AppStrings.tr(context, '모집 중')
                                : item.acceptedName ??
                                      AppStrings.tr(context, '가족'),
                            style: TextStyle(
                              color: AppColors.resolve(
                                context,
                                Color(0xFF99522F),
                              ),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            AppStrings.tr(context, item.state),
                            style: TextStyle(
                              color: AppColors.resolve(
                                context,
                                Color(0xFF78716A),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              AppStrings.format(context, "등록 · {0}", [
                                item.creatorName ??
                                    AppStrings.tr(context, '가족'),
                              ]),
                              style: TextStyle(
                                fontSize: 13,
                                color: AppColors.resolve(
                                  context,
                                  Color(0xFF78716A),
                                ),
                              ),
                            ),
                          ),
                          OutlinedButton(
                            onPressed: () => detailAction(item),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.resolve(
                                context,
                                const Color(0xFF403C39),
                              ),
                              side: BorderSide(
                                color: AppColors.resolve(
                                  context,
                                  Color(0xFFD8C6BA),
                                ),
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: Text(
                              AppStrings.tr(context, '일정 확인'),
                              style: TextStyle(fontWeight: FontWeight.bold),
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
      ],
    );
  }

  void changeMonth(int amount) {
    setState(() {
      displayedMonth = DateTime(
        displayedMonth.year,
        displayedMonth.month + amount,
      );
      selectedDate = displayedMonth;
    });
  }

  void todayAction() {
    setState(() {
      selectedDate = DateUtils.dateOnly(DateTime.now());
      displayedMonth = DateTime(selectedDate.year, selectedDate.month);
    });
  }

  Future<void> createAction(String recipientName) async {
    final result = await Navigator.push<ScheduleCreateResult>(
      context,
      MaterialPageRoute(
        builder: (_) => ScheduleCreate(
          familyRoomId: widget.familyRoomId,
          recipientName: recipientName,
          initialDate: selectedDate,
        ),
      ),
    );
    if (!mounted || result == null) return;
    setState(() {
      selectedDate = result.date;
      displayedMonth = DateTime(result.date.year, result.date.month);
    });
    ref.invalidate(scheduleListProvider(query));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          AppStrings.error(
            context,
            result.published
                ? AppStrings.tr(context, '일정이 등록되었습니다.')
                : AppStrings.tr(context, '일정이 등록되었습니다. 가족 알림은 발행 대기 중입니다.'),
          ),
        ),
      ),
    );
  }

  // 편집 결과를 받아 변경한 날짜의 최신 목록을 표시한다.
  Future<void> detailAction(Schedule item) async {
    final previousQuery = query;

    final result = await showDialog<ScheduleEditResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ScheduleDetail(item: item, query: previousQuery),
    );

    if (!mounted || result == null) {
      return;
    }

    if (ref.read(familyRoomProvider).selectedRoomId != widget.familyRoomId) {
      return;
    }

    // 변경 전 월의 조회 결과를 갱신한다.
    ref.invalidate(scheduleListProvider(previousQuery));

    setState(() {
      selectedDate = DateUtils.dateOnly(result.date);
      displayedMonth = DateTime(result.date.year, result.date.month);
    });

    // 다른 달로 변경했다면 해당 월도 새로 조회한다.
    if (query != previousQuery) {
      ref.invalidate(scheduleListProvider(query));
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          AppStrings.error(
            context,
            result.changed
                ? AppStrings.tr(context, '일정을 변경했습니다.')
                : AppStrings.tr(context, '변경된 내용이 없습니다.'),
          ),
        ),
      ),
    );
  }
}
