import 'package:ondolbom/l10n/app_strings.dart';
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
      color: AppColors.of(context).surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(24),
        side: BorderSide(color: AppColors.of(context).border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    AppStrings.tr(context, '오늘의 일정'),
                    style: TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: AppColors.of(context).textPrimary,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: AppStrings.tr(context, '오늘 일정 새로고침'),
                  onPressed: schedules.isLoading
                      ? null
                      : () => ref.invalidate(scheduleListProvider(query)),
                  icon: Icon(
                    Icons.refresh,
                    size: 21,
                    color: AppColors.of(context).sageDark,
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
                    foregroundColor: AppColors.of(context).sageDark,
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  child: Text(AppStrings.tr(context, '전체 일정 ›')),
                ),
              ],
            ),
            Text(
              AppStrings.format(context, "{0}월 {1}일 · 오늘의 돌봄을 함께 확인해요", [
                today.month,
                today.day,
              ]),
              style: TextStyle(
                fontSize: 12,
                color: AppColors.of(context).textSecondary,
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
                  Text(
                    AppStrings.tr(context, '오늘 일정을 불러오지 못했습니다.'),
                    style: TextStyle(
                      color: AppColors.of(context).textSecondary,
                    ),
                  ),
                  TextButton(
                    onPressed: () =>
                        ref.invalidate(scheduleListProvider(query)),
                    child: Text(AppStrings.tr(context, '다시 조회')),
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
                  return Row(
                    children: [
                      Icon(
                        Icons.calendar_month_outlined,
                        color: AppColors.of(context).sageDark,
                      ),
                      SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          AppStrings.tr(context, '오늘 등록된 일정이 없습니다.'),
                          style: TextStyle(
                            fontSize: 13,
                            color: AppColors.of(context).textSecondary,
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
                      scheduleTile(context, entries[index], () async {
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
  Widget scheduleTile(BuildContext context, Schedule item, VoidCallback onTap) {
    final recruiting = item.acceptedBy == null;
    final accent = recruiting || item.reconfirmRequired
        ? AppColors.resolve(context, const Color(0xFFAC6B4B))
        : AppColors.of(context).sageDark;
    final tint = recruiting || item.reconfirmRequired
        ? AppColors.of(context).peachSoft
        : AppColors.of(context).sageLight.withValues(alpha: 0.45);
    final status = item.reconfirmRequired
        ? '재수락 요청 중'
        : recruiting
        ? '담당자 모집 중'
        : '담당자 등록 완료';
    return Material(
      color: AppColors.of(context).background,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: AppColors.of(context).border),
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
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: AppColors.of(context).textPrimary,
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
                      AppStrings.tr(context, status),
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
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  height: 1.4,
                  color: AppColors.of(context).textPrimary,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppColors.of(context).surface,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      recruiting
                          ? Icons.groups_outlined
                          : Icons.person_outline_rounded,
                      size: 16,
                      color: AppColors.of(context).sageDark,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      recruiting
                          ? AppStrings.tr(context, '함께할 가족을 기다리고 있어요')
                          : AppStrings.format(context, "담당 가족 · {0}", [
                              item.acceptedName ?? AppStrings.tr(context, '가족'),
                            ]),
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.of(context).textPrimary,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    AppStrings.tr(context, item.state),
                    style: TextStyle(
                      fontSize: 11,
                      color: AppColors.of(context).textSecondary,
                    ),
                  ),
                  const SizedBox(width: 4),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 18,
                    color: AppColors.of(context).textSecondary,
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
