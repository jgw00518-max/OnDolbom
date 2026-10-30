import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ondolbom/model/auth/app_user.dart';
import 'package:ondolbom/model/notifications/schedule_notification.dart';
import 'package:ondolbom/theme/app_theme.dart';
import 'package:ondolbom/view/notifications/notifications_view.dart';
import 'package:ondolbom/view/schedules/schedule_detail.dart';
import 'package:ondolbom/vm/auth/auth_vm.dart';
import 'package:ondolbom/vm/auth/user_profile_vm.dart';
import 'package:ondolbom/vm/notifications/notifications_vm.dart';
import 'vm/notifications_vm_test.dart' show NotificationTestAuth;

Map<String, dynamic> roomNotice() => {
  'notification_id': 'family_room_deleted_version',
  'notification_type': 'family_room_deleted',
  'family_room_id': 'deleted-room',
  'care_recipient_name': '가족',
  'room_deleted_at': '2026-10-30 10:00:00',
  'created_at': '2026-10-30T10:00:00',
  'read_at': null,
};

void main() {
  test('공간 삭제 알림은 일정 번호 없이 읽고 삭제 시각과 유형을 보존한다', () {
    final notice = ScheduleNotification.fromJson(roomNotice());
    expect(notice.isRoomDeletion, isTrue);
    expect(notice.scheduleId, isNull);
    expect(notice.withReadAt('read').roomDeletedAt, '2026-10-30 10:00:00');
    expect(notice.withReadAt('read').readAt, 'read');
  });

  testWidgets('삭제된 공간에 진입하지 않고 권한 재확인·읽음 후 안내를 열고 개인 삭제한다', (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      expect(request.headers['Authorization'], 'Bearer test-token');
      Object body;
      if (request.method == 'DELETE') {
        body = {'deleted': true};
      } else if (request.url.path.endsWith('/room')) {
        body = roomNotice();
      } else if (request.url.path.endsWith('/read')) {
        body = {'read_at': 'read'};
      } else if (request.url.path == '/schedules/schedule-notifications') {
        body = {
          'results': [roomNotice()],
          'next_before_id': null,
        };
      } else {
        fail('삭제된 공간·일정으로 접근하면 안 됩니다: ${request.url.path}');
      }
      return http.Response(
        jsonEncode(body),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    addTearDown(client.close);
    final container = ProviderContainer(
      overrides: [
        firebaseAuthProvider.overrideWithValue(NotificationTestAuth()),
        authUserProvider.overrideWith(
          (ref) => Stream.value(const AppUser(uid: 'verified')),
        ),
        authHttpClientProvider.overrideWithValue(client),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!,
          ),
          home: const NotificationsView(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('가족 돌봄 공간'), findsOneWidget);
    expect(find.textContaining('새 돌봄 일정'), findsNothing);
    await tester.tap(find.text('참여하던 돌봄 공간이 삭제되었어요'));
    await tester.pumpAndSettle();
    expect(find.text('돌봄 공간 삭제 안내'), findsOneWidget);
    expect(find.textContaining('2026-10-30 10:00:00'), findsOneWidget);
    expect(find.byType(ScheduleDetail), findsNothing);
    expect(
      container.read(notificationsVmProvider).asData!.value.items.single.readAt,
      'read',
    );
    expect(
      requests
          .where(
            (r) => r.url.path.endsWith('/room') || r.url.path.endsWith('/read'),
          )
          .map((r) => r.url.path),
      [
        '/schedules/schedule-notifications/family_room_deleted_version/room',
        '/schedules/schedule-notifications/family_room_deleted_version/read',
      ],
    );
    await tester.ensureVisible(find.widgetWithText(FilledButton, '확인'));
    await tester.tap(find.widgetWithText(FilledButton, '확인'));
    await tester.pumpAndSettle();
    final trash = find.byTooltip('알림 삭제');
    await tester.ensureVisible(trash);
    await tester.pumpAndSettle();
    await tester.tap(trash);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '삭제'));
    await tester.pumpAndSettle();
    expect(
      container.read(notificationsVmProvider).asData!.value.items,
      isEmpty,
    );
    expect(requests.last.method, 'DELETE');
    expect(tester.takeException(), isNull);
  });

  test('공간 삭제 안내 조회 권한이 없어지면 읽음 요청이나 일정 요청을 보내지 않는다', () async {
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      return request.url.path.endsWith('/room')
          ? http.Response('{}', 404)
          : http.Response(
              jsonEncode({
                'results': [roomNotice()],
                'next_before_id': null,
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
    });
    addTearDown(client.close);
    final container = ProviderContainer(
      overrides: [
        firebaseAuthProvider.overrideWithValue(NotificationTestAuth()),
        authUserProvider.overrideWith(
          (ref) => Stream.value(const AppUser(uid: 'verified')),
        ),
        authHttpClientProvider.overrideWithValue(client),
      ],
    );
    addTearDown(container.dispose);
    final sub = container.listen(notificationsVmProvider, (_, _) {});
    addTearDown(sub.close);
    final page = await container.read(notificationsVmProvider.future);
    await expectLater(
      container
          .read(notificationsVmProvider.notifier)
          .open(page.items.single.id, deleted: page.items.single),
      throwsA(isA<NotificationsError>()),
    );
    expect(requests.where((r) => r.url.path.endsWith('/read')), isEmpty);
    expect(requests.last.url.path.endsWith('/room'), isTrue);
    expect(
      container.read(notificationsVmProvider).asData!.value.items.single.readAt,
      isNull,
    );
  });
}
