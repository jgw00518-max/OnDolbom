import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondolbom/model/auth/app_user.dart';
import 'package:ondolbom/model/notifications/schedule_notification.dart';
import 'package:ondolbom/view/notifications/notifications_view.dart';
import 'package:ondolbom/vm/auth/auth_vm.dart';
import 'package:ondolbom/vm/notifications/notifications_vm.dart';

class EmptyNotifications extends NotificationsVm {
  @override
  Future<NotificationList> build() async => const NotificationList([], null);
}

class OneNotification extends NotificationsVm {
  int? opened;
  static const notification = ScheduleNotification(
    id: 1,
    spaceId: 'space',
    recipientName: '대상자',
    scheduleId: 7,
    scheduleName: '돌봄',
    date: '2026-10-24',
    startTime: '09:00:00',
    endTime: '10:00:00',
    createdAt: '2026-10-23T10:00:00',
    readAt: null,
    memo: '메모',
  );
  @override
  Future<NotificationList> build() async =>
      const NotificationList([notification], null);
  @override
  Future<ScheduleNotification> open(int notificationId) async {
    opened = notificationId;
    return notification;
  }
}

void main() {
  testWidgets('Empty inbox shows explicit empty state', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authUserProvider.overrideWith(
            (ref) => Stream.value(const AppUser(uid: 'test')),
          ),
          notificationsVmProvider.overrideWith(EmptyNotifications.new),
        ],
        child: const MaterialApp(home: NotificationsView()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('확인할 알림이 없습니다.'), findsOneWidget);
  });

  testWidgets(
    'Notification shows recipient and opens checked schedule details',
    (tester) async {
      final vm = OneNotification();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authUserProvider.overrideWith(
              (ref) => Stream.value(const AppUser(uid: 'test')),
            ),
            notificationsVmProvider.overrideWith(() => vm),
          ],
          child: const MaterialApp(home: NotificationsView()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('대상자 · 돌봄'), findsOneWidget);
      expect(find.textContaining('읽지 않음'), findsOneWidget);
      await tester.tap(find.text('대상자 · 돌봄'));
      await tester.pumpAndSettle();
      expect(vm.opened, 1);
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.textContaining('메모'), findsOneWidget);
      await tester.tap(find.text('닫기'));
      await tester.pumpAndSettle();
    },
  );
}
