import 'dart:convert';
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
  'notification_id': 1,
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
            ? {'notification_id': 1, 'read_at': '2026-10-23T10:00:00'}
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
        1,
      );
      final schedule = await container
          .read(notificationsVmProvider.notifier)
          .open(1);
      expect(schedule.memo, '메모');
      expect(
        calls.indexOf('GET /notifications/1/schedule'),
        lessThan(calls.indexOf('POST /notifications/1/read')),
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
