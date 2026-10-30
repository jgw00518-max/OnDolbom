import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ondolbom/vm/activity/activity_vm.dart';
import 'package:ondolbom/vm/notifications/notifications_vm.dart';

// 메뉴를 연 순간의 ID를 고정한다. 열린 동안 푸시로 갱신된 미조회 내용은 읽지 않는다.
final careMenuSnapshotProvider = Provider.autoDispose
    .family<List<String>, ({String room, String category})>(
      (ref, key) => List<String>.of(
        ref.read(activityProvider).menuIds(key.room, key.category),
      ),
    );

/// 목록을 정상적으로 받은 뒤 진입 당시 알림만 확인한다. 오류·로딩 화면은 읽지 않는다.
void watchCareMenuRead(
  BuildContext context,
  WidgetRef ref,
  String room,
  String category,
  bool ready,
) {
  if (!ref.exists(activityProvider)) return;
  final ids = ref.watch(
    careMenuSnapshotProvider((room: room, category: category)),
  );
  if (!ready || room.isEmpty || ids.isEmpty) return;
  WidgetsBinding.instance.addPostFrameCallback((_) async {
    if (!context.mounted) return;
    try {
      final changed = await ref
          .read(activityProvider.notifier)
          .markCareMenuRead(room, category, ids);
      if (changed && context.mounted && ref.exists(notificationsVmProvider)) {
        ref.invalidate(notificationsVmProvider);
      }
    } catch (_) {
      // 서버 권한·저장 실패 시 점을 지우지 않는다. 다시 목록을 열면 재시도한다.
    }
  });
}
