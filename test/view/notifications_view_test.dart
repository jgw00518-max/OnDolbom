import 'package:ondolbom/model/schedules/schedule.dart';
import 'package:ondolbom/model/family/family_room.dart';
import 'package:ondolbom/model/family/participate.dart';
import 'package:ondolbom/model/auth/user_profile.dart';
import 'package:ondolbom/vm/auth/user_profile_vm.dart';
import 'package:ondolbom/vm/schedules/schedule_vm.dart';
import 'package:ondolbom/view/schedules/schedule_detail.dart';
import '../vm/notifications_vm_test.dart' show NotificationTestAuth;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondolbom/model/auth/app_user.dart';
import 'package:ondolbom/model/notifications/schedule_notification.dart';
import 'package:ondolbom/view/notifications/notifications_view.dart';
import 'package:ondolbom/vm/auth/auth_vm.dart';
import 'package:ondolbom/vm/notifications/notifications_vm.dart';
import 'package:ondolbom/vm/family_room/family_room_notifier.dart';
import 'package:ondolbom/vm/family_room/family_room_state.dart';

class EmptyNotifications extends NotificationsVm {
  @override
  Future<NotificationList> build() async => const NotificationList([], null);
}

class OneNotification extends NotificationsVm {
  String? opened;
  static const notification = ScheduleNotification(
    id: '1',
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
  Future<ScheduleNotification> open(
    String notificationId, {
    ScheduleNotification? deleted,
  }) async {
    opened = notificationId;
    return notification;
  }
}

class NoRooms extends FamilyRoomNotifier {
  @override
  FamilyRoomState build() => const FamilyRoomState();
  @override
  Future<void> fetchRooms() async {}
}

final latest = Schedule(
  seq: 7,
  date: latestDate,
  startTime: '09:00',
  endTime: '10:00',
  state: '미완료',
  name: '최신 일정',
  acceptedBy: 'family',
  reconfirmRequired: true,
  reconfirmUserId: 'family',
  historySeq: 12,
);
final latestDate = DateTime(2026, 10, 24);
const detailQuery = (familyRoomId: 'space', year: 2026, month: 10);

class LinkedNotification extends OneNotification {
  @override
  Future<({Schedule item, ScheduleQuery query})> detail(
    ScheduleNotification notification,
  ) async => (item: latest, query: detailQuery);
}

class ActiveRooms extends NoRooms {
  @override
  FamilyRoomState build() => FamilyRoomState(
    selectedRoomId: 'space',
    rooms: const [
      FamilyRoom(
        familyRoomId: 'space',
        careRecipientName: '대상자',
        createdBy: 'owner',
      ),
    ],
    participations: {
      'space': Participate(
        participateSeq: 1,
        userId: 'family',
        familyRoomId: 'space',
        isRepresentative: false,
        joinedAt: DateTime(2026),
      ),
    },
  );
}

void main() {
  testWidgets(
    'Notification opens existing detail with reconfirm controls for current assignee',
    (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            firebaseAuthProvider.overrideWithValue(NotificationTestAuth()),
            authUserProvider.overrideWith(
              (ref) => Stream.value(const AppUser(uid: 'verified')),
            ),
            userProfileProvider.overrideWith(
              (ref) async => const UserProfile(userId: 'family'),
            ),
            notificationsVmProvider.overrideWith(LinkedNotification.new),
            familyRoomProvider.overrideWith(ActiveRooms.new),
            scheduleListProvider(
              detailQuery,
            ).overrideWith((ref) async => [latest]),
          ],
          child: const MaterialApp(home: NotificationsView()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('대상자 · 돌봄'));
      await tester.pumpAndSettle();
      expect(find.byType(ScheduleDetail), findsOneWidget);
      expect(find.text('최신 일정'), findsOneWidget);
      expect(find.text('재수락'), findsOneWidget);
      expect(find.text('거절'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

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
    'Notification rechecks membership and blocks inaccessible detail',
    (tester) async {
      final vm = OneNotification();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authUserProvider.overrideWith(
              (ref) => Stream.value(const AppUser(uid: 'test')),
            ),
            notificationsVmProvider.overrideWith(() => vm),
            familyRoomProvider.overrideWith(NoRooms.new),
          ],
          child: const MaterialApp(home: NotificationsView()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('대상자 · 돌봄'), findsOneWidget);
      expect(find.textContaining('읽지 않음'), findsOneWidget);
      await tester.tap(find.text('대상자 · 돌봄'));
      await tester.pumpAndSettle();
      expect(vm.opened, '1');
      expect(find.text('가족 공간 참여 상태를 확인해 주세요.'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
    },
  );
}
