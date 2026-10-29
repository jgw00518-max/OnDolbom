import 'package:ondolbom/model/notifications/schedule_notification.dart';
import 'dart:convert';
import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ondolbom/model/auth/app_user.dart';
import 'package:ondolbom/vm/auth/auth_vm.dart';
import 'package:ondolbom/vm/auth/user_profile_vm.dart';
import 'package:ondolbom/vm/notifications/notifications_vm.dart';

class NotificationTestUser extends Fake implements User {
  @override
  String get uid => 'verified';
  @override
  Future<String?> getIdToken([bool forceRefresh = false]) async => 'test-token';
}

class NotificationTestAuth extends Fake implements FirebaseAuth {
  @override
  User get currentUser => NotificationTestUser();
}

Map<String, dynamic> item() => {
  'notification_id': '1',
  'family_room_id': 'space',
  'care_recipient_name': '가족',
  'schedule_seq': 7,
  'schedule_name': '돌봄',
  'schedule_date': '2026-10-24',
  'start_time': '09:00:00',
  'end_time': '10:00:00',
  'created_at': '2026-10-23T09:00:00',
  'read_at': null,
};

void main() {
  test('중복 응답·겹친 페이지는 ID로 합치고 다른 이벤트와 읽음은 보존한다', () async {
    final pendingPage = Completer<http.Response>();
    final pageRequested = Completer<void>();
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/read')) {
        return http.Response(jsonEncode({'read_at': 'read-now'}), 200);
      }
      if (request.url.path.endsWith('/schedule')) {
        return http.Response(
          jsonEncode(item()),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }
      if (request.url.queryParameters['before_id'] != null) {
        pageRequested.complete();
        return pendingPage.future;
      }
      return http.Response(
        jsonEncode({
          'results': [item(), item()],
          'next_before_id': '1',
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
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
    addTearDown(client.close);
    final subscription = container.listen(notificationsVmProvider, (_, _) {});
    addTearDown(subscription.close);
    expect(
      (await container.read(notificationsVmProvider.future)).items.length,
      1,
    );
    final vm = container.read(notificationsVmProvider.notifier);
    final loading = vm.loadMore();
    await pageRequested.future;
    await vm.open('1');
    pendingPage.complete(
      http.Response(
        jsonEncode({
          'results': [
            item(),
            {...item(), 'notification_id': 'different-event'},
            item(),
          ],
          'next_before_id': null,
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      ),
    );
    await loading;
    final result = container.read(notificationsVmProvider).requireValue;
    expect(result.items.map((item) => item.id), ['1', 'different-event']);
    expect(result.items.first.readAt, 'read-now');
    expect(result.nextBeforeId, isNull);
  });

  test(
    'List uses ID token; opening rechecks schedule then marks read',
    () async {
      final calls = <String>[];
      final client = MockClient((request) async {
        calls.add('${request.method} ${request.url.path}');
        expect(request.headers['Authorization'], 'Bearer test-token');
        final body = request.url.path.endsWith('/schedule')
            ? {...item(), 'schedule_memo': '메모'}
            : request.url.path.endsWith('/read')
            ? {'notification_id': '1', 'read_at': '2026-10-23T10:00:00'}
            : {
                'results': [item()],
                'next_before_id': null,
              };
        return http.Response(
          jsonEncode(body),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
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
      addTearDown(client.close);
      final sub = container.listen(notificationsVmProvider, (_, _) {});
      addTearDown(sub.close);
      expect(
        (await container.read(notificationsVmProvider.future)).items.single.id,
        '1',
      );
      final schedule = await container
          .read(notificationsVmProvider.notifier)
          .open('1');
      expect(schedule.memo, '메모');
      expect(
        calls.indexOf('GET /schedules/schedule-notifications/1/schedule'),
        lessThan(
          calls.indexOf('POST /schedules/schedule-notifications/1/read'),
        ),
      );
    },
  );

  test(
    'String cursors and full latest reconfirm detail are preserved',
    () async {
      const identifier = 'schedule_reconfirm_7_12';
      final event = {
        ...item(),
        'notification_id': identifier,
        'notification_type': 'schedule_reconfirm',
      };
      final calls = <Uri>[];
      final client = MockClient((request) async {
        calls.add(request.url);
        final Map<String, dynamic> body;
        if (request.url.path == '/schedules') {
          body = {
            'results': [
              {
                ...item(),
                'schedule_state': '미완료',
                'reconfirm_required': true,
                'reconfirm_user_id': 'family',
                'history_seq': 12,
                'accepted_by': 'family',
                'previous_schedule': {...item(), 'schedule_name': '변경 전'},
              },
            ],
          };
        } else {
          expect(request.url.queryParameters['scope'], 'v2');
          body = {
            'results': request.url.queryParameters['before_id'] == null
                ? [event]
                : [],
            'next_before_id': request.url.queryParameters['before_id'] == null
                ? identifier
                : null,
          };
        }
        return http.Response(
          jsonEncode(body),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
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
      addTearDown(client.close);
      final sub = container.listen(notificationsVmProvider, (_, _) {});
      addTearDown(sub.close);
      final page = await container.read(notificationsVmProvider.future);
      expect(page.items.single.title, '변경된 일정을 다시 확인해 주세요');
      await container.read(notificationsVmProvider.notifier).loadMore();
      expect(calls.last.queryParameters['before_id'], identifier);
      final detail = await container
          .read(notificationsVmProvider.notifier)
          .detail(page.items.single);
      expect(detail.item.reconfirmRequired, isTrue);
      expect(detail.item.historySeq, 12);
      expect(detail.item.previousSchedule?.name, '변경 전');
      expect(detail.query, (familyRoomId: 'space', year: 2026, month: 10));
      expect(calls.last.queryParameters['family_room_id'], 'space');
    },
  );

  test(
    'Deleted notification marks read without opening the deleted schedule',
    () async {
      final event = {
        ...item(),
        'notification_id': 'schedule_deleted_7_12',
        'notification_type': 'schedule_deleted',
      };
      final calls = <String>[];
      final client = MockClient((request) async {
        calls.add('${request.method} ${request.url.path}');
        final body = request.method == 'POST'
            ? {'read_at': 'read'}
            : {
                'results': [event],
                'next_before_id': null,
              };
        return http.Response(
          jsonEncode(body),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
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
      addTearDown(client.close);
      final sub = container.listen(notificationsVmProvider, (_, _) {});
      addTearDown(sub.close);
      await container.read(notificationsVmProvider.future);
      final deleted = ScheduleNotification.fromJson(event);
      final result = await container
          .read(notificationsVmProvider.notifier)
          .open(deleted.id, deleted: deleted);
      expect(result.title, '돌봄 일정이 삭제되었어요');
      expect(calls.where((path) => path.endsWith('/schedule')), isEmpty);
      expect(
        container
            .read(notificationsVmProvider)
            .asData!
            .value
            .items
            .single
            .readAt,
        'read',
      );
    },
  );

  test('Server setup error is not treated as empty list', () async {
    final client = MockClient((_) async => http.Response('', 503));
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
    addTearDown(client.close);
    final sub = container.listen(notificationsVmProvider, (_, _) {});
    addTearDown(sub.close);
    await expectLater(
      container.read(notificationsVmProvider.future),
      throwsA(isA<NotificationsError>()),
    );
  });
}
