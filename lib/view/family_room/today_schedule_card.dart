import 'package:ondolbom/model/schedules/schedule.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ondolbom/theme/app_colors.dart';
import 'package:ondolbom/view/schedules/schedule_detail.dart';
import 'package:ondolbom/view/schedules/schedule_list.dart';
import 'package:ondolbom/vm/schedules/schedule_vm.dart';

// 홈과 일정 화면은 같은 월별 조회를 구독한다.
class TodayScheduleCard extends ConsumerWidget {
  const TodayScheduleCard({super.key, required this.familyRoomId});
  final String familyRoomId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final today = DateUtils.dateOnly(DateTime.now());
    final query = (
      familyRoomId: familyRoomId,
      year: today.year,
      month: today.month,
    );
    final schedules = ref.watch(scheduleListProvider(query));
    return Card(
      color: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: const BorderSide(color: AppColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    '오늘의 일정',
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: '오늘 일정 새로고침',
                  onPressed: schedules.isLoading
                      ? null
                      : () => ref.invalidate(scheduleListProvider(query)),
                  icon: const Icon(
                    Icons.refresh,
                    size: 21,
                    color: AppColors.sageDark,
                  ),
                ),
                TextButton(
                  onPressed: () async {
                    await Navigator.push(
                      context,
                      MaterialPageRoute<void>(
                        builder: (_) => ScheduleList(
                          familyRoomId: familyRoomId,
                          initialDate: today,
                        ),
                      ),
                    );
                    if (context.mounted) {
                      ref.invalidate(scheduleListProvider(query));
                    }
                  },
                  style: TextButton.styleFrom(
                    foregroundColor: AppColors.sageDark,
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  child: const Text('전체 일정 ›'),
                ),
              ],
            ),
            Text(
              '${today.month}월 ${today.day}일 · 오늘의 돌봄을 함께 확인해요',
              style: const TextStyle(
                fontSize: 12,
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: 18),
            schedules.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (_, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '오늘 일정을 불러오지 못했습니다.',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                  TextButton(
                    onPressed: () =>
                        ref.invalidate(scheduleListProvider(query)),
                    child: const Text('다시 조회'),
                  ),
                ],
              ),
              data: (items) {
                // 지난 시간의 일정도 오늘 날짜라면 표시한다.
                final entries =
                    items
                        .where((item) => DateUtils.isSameDay(item.date, today))
                        .toList()
                      ..sort((a, b) => a.startTime.compareTo(b.startTime));
                if (entries.isEmpty) {
                  return const Row(
                    children: [
                      Icon(
                        Icons.calendar_month_outlined,
                        color: AppColors.sageDark,
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          '오늘 등록된 일정이 없습니다.',
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  );
                }
                return Column(
                  children: [
                    for (var index = 0; index < entries.length; index++) ...[
                      if (index > 0) const SizedBox(height: 12),
                      scheduleTile(entries[index], () async {
                        await showDialog<void>(
                          context: context,
                          builder: (_) => ScheduleDetail(
                            item: entries[index],
                            query: query,
                          ),
                        );
                        if (context.mounted) {
                          ref.invalidate(scheduleListProvider(query));
                        }
                      }),
                    ],
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // 시간·담당 상태·제목을 나누어 홈에서도 읽기 쉽게 표시한다.
  Widget scheduleTile(Schedule item, VoidCallback onTap) {
    final recruiting = item.acceptedBy == null;
    final accent = recruiting || item.reconfirmRequired
        ? const Color(0xFFAC6B4B)
        : AppColors.sageDark;
    final tint = recruiting || item.reconfirmRequired
        ? AppColors.peachSoft
        : AppColors.sageLight.withValues(alpha: 0.45);
    final status = item.reconfirmRequired
        ? '재수락 요청 중'
        : recruiting
        ? '담당자 모집 중'
        : '담당자 등록 완료';
    return Material(
      color: AppColors.background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: const BorderSide(color: AppColors.border),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 10,
                runSpacing: 10,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.schedule_rounded, size: 16, color: accent),
                      const SizedBox(width: 6),
                      Text(
                        '${item.startTime} ~ ${item.endTime}',
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: tint,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      status,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: accent,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                item.title,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  height: 1.4,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: const BoxDecoration(
                      color: AppColors.surface,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      recruiting
                          ? Icons.groups_outlined
                          : Icons.person_outline_rounded,
                      size: 16,
                      color: AppColors.sageDark,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      recruiting
                          ? '함께할 가족을 기다리고 있어요'
                          : '담당 가족 · ${item.acceptedName ?? '가족'}',
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    item.state,
                    style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textSecondary,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
