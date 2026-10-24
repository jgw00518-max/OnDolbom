import 'package:ondolbom/view/schedules/schedule_detail.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ondolbom/model/schedules/schedule.dart';
import 'package:ondolbom/view/schedules/schedule_create.dart';
import 'package:ondolbom/vm/family_room_notifier.dart';
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
        appBar: AppBar(title: const Text('돌봄 일정')),
        body: const Center(child: Text('가족 공간을 다시 선택해 주세요.')),
      );
    }
    final schedules = ref.watch(scheduleListProvider(query));
    return Scaffold(
      backgroundColor: const Color(0xFFFFFBF7),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFFFBF7),
        foregroundColor: const Color(0xFF403C39),
        titleTextStyle: const TextStyle(
          fontSize: 22,
          fontWeight: FontWeight.bold,
          color: Color(0xFF403C39),
        ),
        title: const Text('돌봄 일정'),
        actions: [
          IconButton(
            tooltip: '새로고침',
            onPressed: () => ref.invalidate(scheduleListProvider(query)),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(12, 18, 12, 28),
        children: [
          Text('${room.careRecipientName} 님의 돌봄 공간'),
          const SizedBox(height: 16),
          if (rooms.selectedParticipation?.isRepresentative == true)
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.tonalIcon(
                key: const ValueKey('schedule-add'),
                onPressed: () => createAction(room.careRecipientName),
                icon: const Icon(Icons.add),
                label: const Text('일정 등록'),
              ),
            ),
          const SizedBox(height: 12),
          calendar(schedules.asData?.value ?? const []),
          const SizedBox(height: 24),
          schedules.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, _) => Column(
              children: [
                Text(error.toString().replaceFirst('Exception: ', '')),
                TextButton(
                  onPressed: () => ref.invalidate(scheduleListProvider(query)),
                  child: const Text('다시 조회'),
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
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE8DFD7)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 18),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                tooltip: '이전 달',
                onPressed:
                    displayedMonth.year == 1900 && displayedMonth.month == 1
                    ? null
                    : () => changeMonth(-1),
                icon: const Icon(Icons.chevron_left),
              ),
              Expanded(
                child: Text(
                  '${displayedMonth.year}년 ${displayedMonth.month}월',
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 19,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF403C39),
                  ),
                ),
              ),
              IconButton(
                tooltip: '다음 달',
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
              const Expanded(
                child: Text(
                  '돌봄이 필요한 날을 확인하세요',
                  style: TextStyle(fontSize: 12, color: Color(0xFF78716A)),
                ),
              ),
              TextButton(onPressed: todayAction, child: const Text('오늘')),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: ['일', '월', '화', '수', '목', '금', '토']
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
                              ? const Color(0xFFD07858)
                              : entry.key == 6
                              ? const Color(0xFF7C9FA9)
                              : const Color(0xFF78716A),
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
                label: '${date.month}월 $day일, 일정 $count건',
                child: InkWell(
                  key: ValueKey('schedule-day-$day'),
                  borderRadius: BorderRadius.circular(13),
                  onTap: () => setState(() => selectedDate = date),
                  child: Container(
                    margin: const EdgeInsets.all(1),
                    decoration: BoxDecoration(
                      color: selected
                          ? const Color(0xFFFFD6B5)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(13),
                      border: selected
                          ? Border.all(color: const Color(0xFFC78159), width: 2)
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
                                ? const Color(0xFF99522F)
                                : const Color(0xFF403C39),
                          ),
                        ),
                        const SizedBox(height: 5),
                        Text(
                          count == 0 ? '' : '$count건',
                          style: const TextStyle(
                            fontSize: 10,
                            color: Color(0xFF6C5A4B),
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
                '${selectedDate.month}월 ${selectedDate.day}일',
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF403C39),
                ),
              ),
            ),
            Text(
              '${items.length}개 일정',
              style: const TextStyle(fontSize: 15, color: Color(0xFF78716A)),
            ),
          ],
        ),
        const SizedBox(height: 18),
        if (items.isEmpty)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 32),
            child: Center(
              child: Text(
                '등록된 돌봄 일정이 없어요',
                style: TextStyle(color: Color(0xFF78716A)),
              ),
            ),
          ),
        ...items.map(
          (item) => Container(
            margin: const EdgeInsets.only(bottom: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: const Color(0xFFE8DFD7)),
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
                                    ? const Color(0xFFF0F2EE)
                                    : const Color(0xFFFFEBD9),
                                borderRadius: BorderRadius.circular(24),
                              ),
                              child: Text(
                                item.assignment,
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF756B60),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Text(
                            '${item.startTime} – ${item.endTime}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF78716A),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Text(
                        item.title,
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF403C39),
                        ),
                      ),
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        children: [
                          const Text(
                            '담당자',
                            style: TextStyle(color: Color(0xFF78716A)),
                          ),
                          Text(
                            item.acceptedBy == null
                                ? '모집 중 · 1명'
                                : '${item.acceptedName ?? '가족'} · 1명',
                            style: const TextStyle(
                              color: Color(0xFF99522F),
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            item.state,
                            style: const TextStyle(color: Color(0xFF78716A)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 18),
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              '등록 · ${item.creatorName ?? '가족'}',
                              style: const TextStyle(
                                fontSize: 13,
                                color: Color(0xFF78716A),
                              ),
                            ),
                          ),
                          OutlinedButton(
                            onPressed: () => detailAction(item),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFF403C39),
                              side: const BorderSide(color: Color(0xFFD8C6BA)),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 10,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text(
                              '일정 확인',
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
          result.published ? '일정이 등록되었습니다.' : '일정이 등록되었습니다. 가족 알림은 발행 대기 중입니다.',
        ),
      ),
    );
  }

  // 목록과 같은 월별 상태를 상세 화면에서도 사용한다.
  void detailAction(Schedule item) {
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => ScheduleDetail(item: item, query: query),
    );
  }
}
