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

  @override
  Widget build(BuildContext context) {
    // 로그아웃·계정 변경 시 이전 계정의 알림 경로를 닫는다.
    ref.listen(authUserProvider, (previous, next) {
      if (previous?.asData?.value?.uid != next.asData?.value?.uid &&
          next.hasValue) {
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    });
    final list = ref.watch(notificationsVmProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('알림'),
        actions: [
          IconButton(
            tooltip: '새로고침',
            onPressed: _busy
                ? null
                : () => ref.invalidate(notificationsVmProvider),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: list.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => Center(
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
        data: (page) => page.items.isEmpty && page.nextBeforeId == null
            ? const Center(child: Text('확인할 알림이 없습니다.'))
            : ListView(
                children: [
                  for (final item in page.items)
                    ListTile(
                      enabled: !_busy,
                      leading: Icon(
                        item.readAt == null
                            ? Icons.notifications_active
                            : Icons.notifications_none,
                      ),
                      title: Text(
                        '${item.recipientName} · ${item.scheduleName ?? '새 돌봄 일정'}',
                      ),
                      subtitle: Text(
                        '${item.date} ${item.startTime} ~ ${item.endTime}\n${item.readAt == null ? '읽지 않음' : '읽음'}',
                      ),
                      isThreeLine: true,
                      onTap: () => _perform(() async {
                        final schedule = await ref
                            .read(notificationsVmProvider.notifier)
                            .open(item.id);
                        if (!context.mounted) return;
                        // 일정 담당자 화면 연결 전까지 서버가 확인한 현재 일정 내용을 표시한다.
                        await showDialog<void>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: Text(schedule.scheduleName ?? '돌봄 일정'),
                            content: Text(
                              '${schedule.recipientName}\n${schedule.date}\n${schedule.startTime} ~ ${schedule.endTime}\n${schedule.memo ?? ''}',
                            ),
                            actions: [
                              TextButton(
                                onPressed: () => Navigator.pop(context),
                                child: const Text('닫기'),
                              ),
                            ],
                          ),
                        );
                      }),
                    ),
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
    );
  }
}
