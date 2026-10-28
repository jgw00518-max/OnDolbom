import 'package:ondolbom/view/schedules/schedule_detail.dart';
import 'package:ondolbom/vm/family_room/family_room_notifier.dart';
import 'package:ondolbom/vm/schedules/schedule_vm.dart';
import 'package:ondolbom/theme/app_colors.dart';
import 'package:ondolbom/model/notifications/schedule_notification.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ondolbom/vm/auth/auth_vm.dart';
import 'package:ondolbom/vm/notifications/notifications_vm.dart';

class NotificationsView extends ConsumerStatefulWidget {
  const NotificationsView({super.key});
  @override
  ConsumerState<NotificationsView> createState() => _NotificationsViewState();
}

class _NotificationsViewState extends ConsumerState<NotificationsView> {
  bool _busy = false;

  Future<void> _perform(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.toString())));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static const _ink = AppColors.textPrimary;
  static const _muted = AppColors.textSecondary;

  // 조회 권한 재검사·읽음 처리·현재 일정 상세 표시는 기존 VM 흐름을 유지한다.
  void _open(ScheduleNotification item) => _perform(() async {
    final uid = ref.read(authUserProvider).asData?.value?.uid;
    final schedule = await ref
        .read(notificationsVmProvider.notifier)
        .open(item.id, deleted: item.type == 'schedule_deleted' ? item : null);
    if (!mounted) return;
    if (schedule.type == 'schedule_deleted') {
      await showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('일정 삭제 안내'),
          content: Text(
            '${schedule.scheduleName ?? '돌봄 일정'} 일정이 삭제되었습니다.\n${schedule.date} ${schedule.startTime} ~ ${schedule.endTime}',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('닫기'),
            ),
          ],
        ),
      );
      return;
    }
    // 최신 참여 목록으로 공간 권한을 확인한 뒤 기존 일정 상세를 재사용한다.
    if (ref.read(authUserProvider).asData?.value?.uid != uid) return;
    final roomsVm = ref.read(familyRoomProvider.notifier);
    await roomsVm.fetchRooms();
    if (!mounted || ref.read(authUserProvider).asData?.value?.uid != uid) {
      return;
    }
    final rooms = ref.read(familyRoomProvider);
    if (!rooms.rooms.any((room) => room.familyRoomId == schedule.spaceId) ||
        rooms.participations[schedule.spaceId]?.isActive != true) {
      throw const NotificationsError('가족 공간 참여 상태를 확인해 주세요.');
    }
    if (rooms.selectedRoomId != schedule.spaceId) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('가족 공간 전환'),
          content: Text('${schedule.recipientName} 님의 돌봄 공간으로 이동할까요?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('이동'),
            ),
          ],
        ),
      );
      if (!mounted ||
          confirmed != true ||
          ref.read(authUserProvider).asData?.value?.uid != uid) {
        return;
      }
      roomsVm.selectRoom(schedule.spaceId);
    }
    final detail = await ref
        .read(notificationsVmProvider.notifier)
        .detail(schedule);
    if (!mounted || ref.read(authUserProvider).asData?.value?.uid != uid) {
      return;
    }
    if (ref.read(familyRoomProvider).selectedRoomId != schedule.spaceId) {
      throw const NotificationsError('선택한 가족 공간이 변경되었습니다. 다시 열어 주세요.');
    }
    ref.invalidate(scheduleListProvider(detail.query));
    await showDialog<void>(
      context: context,
      builder: (_) => ScheduleDetail(item: detail.item, query: detail.query),
    );
  });

  Widget _card(ScheduleNotification item) {
    final unread = item.readAt == null;
    final date = DateTime.tryParse(item.createdAt);
    final time = date == null
        ? item.createdAt
        : '${date.month}월 ${date.day}일 ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    final textColor = unread ? _ink : const Color(0xFF827C78);
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Material(
        color: unread ? const Color(0xFFFFF8F3) : Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(
            color: unread ? const Color(0xFFF1C1A8) : const Color(0xFFF0E6DF),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: _busy ? null : () => _open(item),
          child: Padding(
            padding: const EdgeInsets.all(17),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: unread
                        ? AppColors.sageLight
                        : const Color(0xFFE8EEDf),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    item.type == 'schedule_reconfirm'
                        ? Icons.event_repeat_outlined
                        : item.type == 'schedule_recruitment'
                        ? Icons.group_add_outlined
                        : item.type == 'schedule_changed'
                        ? Icons.edit_calendar_outlined
                        : Icons.calendar_month_outlined,
                    color: unread
                        ? AppColors.sageDark
                        : const Color(0xFF929D85),
                    size: 23,
                  ),
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Text(
                              '${item.recipientName} · ${item.scheduleName ?? '새 돌봄 일정'}',
                              style: TextStyle(
                                color: unread
                                    ? const Color(0xFFA46F59)
                                    : _muted,
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              time,
                              textAlign: TextAlign.right,
                              style: const TextStyle(
                                color: _muted,
                                fontSize: 10,
                              ),
                            ),
                          ),
                          if (unread) ...[
                            const SizedBox(width: 4),
                            Container(
                              width: 7,
                              height: 7,
                              margin: const EdgeInsets.only(top: 3),
                              decoration: const BoxDecoration(
                                color: AppColors.primary,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        item.title,
                        style: TextStyle(
                          color: textColor,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          height: 1.45,
                        ),
                      ),
                      const SizedBox(height: 7),
                      Text(
                        '${item.date} ${item.startTime} ~ ${item.endTime}',
                        style: TextStyle(
                          color: unread ? const Color(0xFF8C7A70) : _muted,
                          fontSize: 12,
                          height: 1.6,
                        ),
                      ),
                      if (item.memo?.isNotEmpty ?? false)
                        Text(
                          item.memo!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: _muted,
                            fontSize: 12,
                            height: 1.6,
                          ),
                        ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Container(
                            width: 5,
                            height: 5,
                            decoration: BoxDecoration(
                              color: unread
                                  ? AppColors.primary
                                  : const Color(0xFFCFC8C3),
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            unread ? '읽지 않음' : '읽음',
                            style: TextStyle(
                              color: unread
                                  ? const Color(0xFFA46F59)
                                  : const Color(0xFFAAA09B),
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authUserProvider, (previous, next) {
      if (previous?.asData?.value?.uid != next.asData?.value?.uid &&
          next.hasValue) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    });
    final list = ref.watch(notificationsVmProvider);
    final unread =
        list.asData?.value.items.where((item) => item.readAt == null).length ??
        0;
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        surfaceTintColor: Colors.transparent,
        foregroundColor: _ink,
        toolbarHeight: 88,
        centerTitle: true,
        leadingWidth: 62,
        leading: Padding(
          padding: const EdgeInsets.only(left: 14),
          child: Center(
            child: SizedBox.square(
              dimension: 42,
              child: OutlinedButton(
                onPressed: () => Navigator.maybePop(context),
                style: OutlinedButton.styleFrom(
                  padding: EdgeInsets.zero,
                  backgroundColor: AppColors.surface,
                  foregroundColor: _ink,
                  side: const BorderSide(color: AppColors.border),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13),
                  ),
                ),
                child: const Icon(Icons.chevron_left),
              ),
            ),
          ),
        ),
        title: const Column(
          children: [
            Text(
              'NOTIFICATIONS',
              style: TextStyle(
                color: Color(0xFFA77762),
                fontSize: 8,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.5,
              ),
            ),
            SizedBox(height: 3),
            Text(
              '알림',
              style: TextStyle(
                color: _ink,
                fontSize: 22,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        actions: [
          Container(
            width: 42,
            height: 42,
            margin: const EdgeInsets.only(right: 6),
            decoration: BoxDecoration(
              color: AppColors.peachLight,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                const Center(
                  child: Icon(
                    Icons.notifications_none,
                    color: Color(0xFF875C49),
                    size: 23,
                  ),
                ),
                if (unread > 0)
                  Positioned(
                    right: -3,
                    top: -3,
                    child: Container(
                      width: 21,
                      height: 21,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _ink,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                      child: Text(
                        unread > 99 ? '99+' : '$unread',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            tooltip: '새로고침',
            onPressed: _busy
                ? null
                : () => ref.invalidate(notificationsVmProvider),
            icon: const Icon(Icons.refresh, size: 21),
          ),
        ],
      ),
      body: list.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
        error: (error, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(error.toString(), textAlign: TextAlign.center),
                TextButton(
                  onPressed: () => ref.invalidate(notificationsVmProvider),
                  child: const Text('다시 시도'),
                ),
              ],
            ),
          ),
        ),
        data: (page) => page.items.isEmpty && page.nextBeforeId == null
            ? const Center(child: Text('확인할 알림이 없습니다.'))
            : Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 560),
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(16, 24, 16, 32),
                    children: [
                      const Text(
                        '새로운 소식',
                        style: TextStyle(color: _muted, fontSize: 12),
                      ),
                      const SizedBox(height: 6),
                      // 아직 다음 페이지가 있으면 현재 목록의 수라는 사실을 명시한다.
                      Text(
                        page.nextBeforeId != null
                            ? '불러온 알림 중 $unread개의 미확인 알림'
                            : unread > 0
                            ? '$unread개의 읽지 않은 알림'
                            : '모든 알림을 확인했어요',
                        style: const TextStyle(
                          color: _ink,
                          fontSize: 22,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -0.8,
                        ),
                      ),
                      const SizedBox(height: 24),
                      for (final item in page.items) _card(item),
                      if (page.nextBeforeId != null)
                        TextButton(
                          onPressed: _busy
                              ? null
                              : () => _perform(
                                  () => ref
                                      .read(notificationsVmProvider.notifier)
                                      .loadMore(),
                                ),
                          child: const Text('더 보기'),
                        ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}
