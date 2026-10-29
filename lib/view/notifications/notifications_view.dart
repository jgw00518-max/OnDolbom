import 'package:ondolbom/view/widgets/menu_header_icon.dart';
import 'package:ondolbom/vm/activity/activity_vm.dart';
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

  Future<void> _deleteNotification({String? id}) => _perform(() async {
    final uid = ref.read(authUserProvider).asData?.value?.uid;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(id == null ? '알림을 전체 삭제할까요?' : '이 알림을 삭제할까요?'),
        content: const Text('내 알림 목록에서만 삭제합니다. 다른 가족의 알림과 일정은 유지됩니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (!mounted ||
        confirmed != true ||
        ref.read(authUserProvider).asData?.value?.uid != uid) {
      return;
    }
    await ref
        .read(notificationsVmProvider.notifier)
        .deleteNotifications(id: id);
  });

  static const _ink = AppColors.textPrimary;
  static const _muted = AppColors.textSecondary;
  // 목록 관리 버튼은 본문보다 차분한 색상으로 표시한다.
  static const _deleteFill = Color(0xFFF0ECE9);
  static const _deleteInk = Color(0xFF9A8F89);

  // 서버에서 받은 삭제 당시 일시를 읽기 쉽게 표시한다.
  String _deletedTime(String value) {
    final match = RegExp(r'^(\d{1,2}):(\d{2})').firstMatch(value);
    return match == null ? value : '${match[1]!.padLeft(2, '0')}:${match[2]}';
  }

  Widget _deletedInfoRow(String label, String value) => Padding(
    padding: const EdgeInsets.only(bottom: 16),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 86,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 15,
              color: AppColors.textSecondary,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(fontSize: 15, color: AppColors.textPrimary),
          ),
        ),
      ],
    ),
  );

  // 조회 권한 재검사·읽음 처리·현재 일정 상세 표시는 기존 VM 흐름을 유지한다.
  void _open(ScheduleNotification item) => _perform(() async {
    final uid = ref.read(authUserProvider).asData?.value?.uid;
    final schedule = await ref
        .read(notificationsVmProvider.notifier)
        .open(item.id, deleted: item.type == 'schedule_deleted' ? item : null);
    if (!mounted) return;
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
      throw const NotificationsError('돌봄 공간 참여 상태를 확인해 주세요.');
    }
    if (rooms.selectedRoomId != schedule.spaceId) {
      // 알림이 속한 공간으로 자동 전환하되 실제 참여 권한은 위에서 먼저 확인한다.
      roomsVm.selectRoom(schedule.spaceId);
    }
    if (ref.read(familyRoomProvider).selectedRoomId != schedule.spaceId) {
      throw const NotificationsError('현재 접근할 수 없는 돌봄 공간입니다.');
    }
    if (schedule.type == 'schedule_deleted') {
      await showDialog<void>(
        context: context,
        builder: (context) => Dialog(
          backgroundColor: AppColors.background,
          surfaceTintColor: Colors.transparent,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 24,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 540),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  ColoredBox(
                    color: AppColors.surface,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(22, 16, 10, 16),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text(
                              '일정 삭제 안내',
                              style: TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: '닫기',
                            onPressed: () => Navigator.pop(context),
                            icon: const Icon(
                              Icons.close,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.all(22),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 7,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFFB87568,
                              ).withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: const Text(
                              '삭제된 일정',
                              style: TextStyle(
                                color: Color(0xFF9B5C50),
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 18),
                        Text(
                          schedule.scheduleName?.trim().isNotEmpty == true
                              ? schedule.scheduleName!
                              : '돌봄 일정',
                          style: const TextStyle(
                            fontSize: 23,
                            fontWeight: FontWeight.bold,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 12),
                        const Text(
                          '이 일정은 삭제되었습니다.',
                          style: TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 15,
                          ),
                        ),
                        const SizedBox(height: 24),
                        _deletedInfoRow('날짜', schedule.date),
                        _deletedInfoRow(
                          '시작시간',
                          _deletedTime(schedule.startTime),
                        ),
                        _deletedInfoRow('종료시간', _deletedTime(schedule.endTime)),
                        const SizedBox(height: 12),
                        FilledButton(
                          onPressed: () => Navigator.pop(context),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 48),
                          ),
                          child: const Text('닫기'),
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
      return;
    }
    final detail = await ref
        .read(notificationsVmProvider.notifier)
        .detail(schedule);
    if (!mounted || ref.read(authUserProvider).asData?.value?.uid != uid) {
      return;
    }
    if (ref.read(familyRoomProvider).selectedRoomId != schedule.spaceId) {
      throw const NotificationsError('선택한 돌봄 공간이 변경되었습니다. 다시 열어 주세요.');
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
                    item.type == 'schedule_reconfirm_expired'
                        ? Icons.timer_off_outlined
                        : item.type == 'schedule_reconfirm_unanswered'
                        ? Icons.person_off_outlined
                        : item.type == 'schedule_reconfirm_unverified'
                        ? Icons.priority_high_rounded
                        : item.type == 'schedule_withdrawn'
                        ? Icons.person_remove_outlined
                        : item.type == 'schedule_reminder'
                        ? Icons.alarm_outlined
                        : item.type == 'schedule_reconfirm'
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
                          const Spacer(),
                          IconButton(
                            tooltip: '알림 삭제',
                            style: IconButton.styleFrom(
                              foregroundColor: const Color(0xFFB3A49D),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onPressed: _busy
                                ? null
                                : () => _deleteNotification(id: item.id),
                            icon: const Icon(Icons.delete_outline, size: 21),
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
                fontSize: 24,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        actions: [
          MenuHeaderIcon(
            icon: Icons.notifications_none,
            backgroundColor: AppColors.peachLight,
            foregroundColor: const Color(0xFF875C49),
            unreadCount: unread,
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
                  onPressed: () {
                    ref.invalidate(notificationsVmProvider);
                    // 사용자가 직접 새로고침하면 배지 캐시도 우회한다.
                    ref.read(activityProvider.notifier).refresh(force: true);
                  },
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
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final summary = Text(
                            page.nextBeforeId != null
                                ? '불러온 알림 중 $unread개의 미확인 알림'
                                : unread > 0
                                ? '$unread개의 읽지 않은 알림'
                                : '모든 알림을 확인했어요',
                            style: const TextStyle(
                              color: _ink,
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              height: 1.4,
                              letterSpacing: -0.5,
                            ),
                          );
                          final actions = Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              if (unread > 0)
                                Tooltip(
                                  message: '읽지 않은 알림을 모두 읽음으로 변경합니다.',
                                  child: TextButton.icon(
                                    // 다른 목록 작업과 겹치지 않도록 공통 잠금을 사용한다.
                                    onPressed: _busy
                                        ? null
                                        : () => _perform(
                                            () => ref
                                                .read(
                                                  notificationsVmProvider
                                                      .notifier,
                                                )
                                                .markAllRead(),
                                          ),
                                    style: TextButton.styleFrom(
                                      backgroundColor: AppColors.peachSoft,
                                      disabledBackgroundColor:
                                          AppColors.peachSoft,
                                      foregroundColor: const Color(0xFFA46F59),
                                      disabledForegroundColor: const Color(
                                        0xFFA46F59,
                                      ),
                                      minimumSize: const Size(0, 36),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 9,
                                        vertical: 8,
                                      ),
                                      textStyle: const TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      shape: const StadiumBorder(),
                                    ),
                                    icon: const Icon(Icons.check, size: 14),
                                    label: const Text('모두 읽음'),
                                  ),
                                ),
                              TextButton.icon(
                                onPressed:
                                    _busy ||
                                        (page.items.isEmpty &&
                                            page.nextBeforeId == null)
                                    ? null
                                    : () => _deleteNotification(),
                                style: TextButton.styleFrom(
                                  backgroundColor: _deleteFill,
                                  foregroundColor: _deleteInk,
                                  minimumSize: const Size(0, 36),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 9,
                                    vertical: 8,
                                  ),
                                  textStyle: const TextStyle(
                                    fontSize: 10,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  shape: const StadiumBorder(),
                                ),
                                icon: const Icon(
                                  Icons.delete_outline,
                                  size: 14,
                                ),
                                label: const Text('전체 삭제'),
                              ),
                            ],
                          );
                          // 좁은 화면·큰 글씨에서는 버튼을 다음 줄로 옮겨 문구가 눌리지 않게 한다.
                          if (constraints.maxWidth < 340 ||
                              MediaQuery.textScalerOf(context).scale(18) > 21) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                summary,
                                const SizedBox(height: 10),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: actions,
                                ),
                              ],
                            );
                          }
                          return Row(
                            children: [
                              Expanded(child: summary),
                              const SizedBox(width: 8),
                              actions,
                            ],
                          );
                        },
                      ),
                      const SizedBox(height: 16),
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
