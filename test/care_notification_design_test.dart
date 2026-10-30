import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ondolbom/view/widgets/care_menu_read.dart';
import 'package:ondolbom/model/notifications/schedule_notification.dart';
import 'package:ondolbom/theme/app_colors.dart';
import 'package:ondolbom/theme/app_theme.dart';
import 'package:ondolbom/view/family_room/family_room_home.dart';
import 'package:ondolbom/view/notifications/care_notification_dialog.dart';
import 'package:ondolbom/vm/activity/activity_vm.dart';

class SnapshotActivity extends ActivityVm {
  @override
  ActivityCounts build() => const ActivityCounts(
    careMenu: {
      'room': {
        'memos': ['initial'],
      },
    },
  );
  void incoming() => state = const ActivityCounts(
    careMenu: {
      'room': {
        'memos': ['initial', 'incoming'],
      },
    },
  );
}

void main() {
  test('메뉴 진입 후 도착한 새 알림은 진입 당시 확인 목록에 포함하지 않는다', () {
    final container = ProviderContainer(
      overrides: [activityProvider.overrideWith(SnapshotActivity.new)],
    );
    addTearDown(container.dispose);
    final provider = careMenuSnapshotProvider((
      room: 'room',
      category: 'memos',
    ));
    final listener = container.listen(provider, (_, _) {});
    addTearDown(listener.close);
    expect(container.read(provider), ['initial']);
    (container.read(activityProvider.notifier) as SnapshotActivity).incoming();
    expect(container.read(provider), ['initial']);
  });

  test('돌봄 메뉴 미읽음은 공간·종류별로 분리하며 장애 시 기존 상태를 유지한다', () {
    final counts = const ActivityCounts().merge({
      'care_menu': {
        'a': {
          'memos': ['memo'],
          'schedules': ['schedule'],
        },
        'b': {
          'medications': ['med'],
        },
      },
    });
    expect(counts.menuIds('a', 'memos'), ['memo']);
    expect(counts.menuIds('a', 'medications'), isEmpty);
    expect(counts.merge({'care_menu': null}).menuIds('a', 'memos'), ['memo']);
    expect(counts.merge({'care_menu': {}}).menuIds('a', 'memos'), isEmpty);
  });
  testWidgets('빨간 점이 생겨도 돌봄 메뉴 아이콘 크기를 유지한다', (tester) async {
    Future<void> mount(bool news) => tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Row(
              children: [
                const FamilyRoomHome().menuButton(
                  context,
                  '메모',
                  Icons.edit_outlined,
                  () {},
                  hasNews: news,
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await mount(false);
    final before = tester.getSize(find.byIcon(Icons.edit_outlined));
    await mount(true);
    expect(tester.getSize(find.byIcon(Icons.edit_outlined)), before);
    final badge = tester.widget<Badge>(find.byType(Badge));
    expect(badge.isLabelVisible, isTrue);
    expect(badge.label, isNull);
    expect(badge.backgroundColor, AppColors.notificationDot);
  });
  testWidgets('공간 알림 상세는 좁은 화면·큰 글씨·다크 모드에서도 스크롤로 확인한다', (tester) async {
    tester.view.physicalSize = const Size(320, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    for (final kind in [
      'representative_transferred',
      'member_left',
      'member_removed',
      'memo_created',
      'medication_created',
      'member_joined',
      'family_room_deleted',
    ]) {
      final item = ScheduleNotification(
        id: kind,
        type: kind,
        spaceId: 'room',
        recipientName: '소중한 가족',
        scheduleId: null,
        scheduleName: null,
        date: '',
        startTime: '',
        endTime: '',
        createdAt: '2026-10-30T12:00:00',
        readAt: null,
      );
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.dark,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.4)),
            child: child!,
          ),
          home: Scaffold(body: CareNotificationDialog(item: item)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text(item.title), findsOneWidget);
      expect(find.text('확인'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
}
