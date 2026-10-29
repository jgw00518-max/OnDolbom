import 'dart:async';
import 'dart:convert';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ondolbom/model/auth/app_user.dart';
import 'package:ondolbom/vm/auth/auth_vm.dart';
import 'package:ondolbom/vm/auth/user_profile_vm.dart';
import 'package:ondolbom/vm/notifications/notifications_vm.dart';
import 'vm/notifications_vm_test.dart' as fixture;

http.Response response(Object data, [int status = 200]) => http.Response(
  jsonEncode(data),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

void main() {
  test('모두 읽음은 인증된 POST 후 서버 목록을 다시 조회한다', () async {
    var marked = false;
    final client = MockClient((request) async {
      if (request.method == 'POST') {
        expect(request.url.path, '/schedules/schedule-notifications/read-all');
        expect(request.headers['Authorization'], 'Bearer test-token');
        marked = true;
        return response({'count': 1});
      }
      return response({
        'results': [
          {...fixture.item(), 'read_at': marked ? '2026-10-29 12:00:00' : null},
        ],
        'next_before_id': null,
      });
    });
    final container = ProviderContainer(
      overrides: [
        firebaseAuthProvider.overrideWithValue(fixture.NotificationTestAuth()),
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
    await container.read(notificationsVmProvider.notifier).markAllRead();
    expect(marked, isTrue);
    expect(
      container.read(notificationsVmProvider).asData!.value.items.single.readAt,
      isNotNull,
    );
  });

  for (final mode in ['one', 'all', 'failure']) {
    test('알림 삭제 $mode 요청과 성공·실패 목록 처리', () async {
      final requests = <http.Request>[];
      final client = MockClient((r) async {
        requests.add(r);
        if (r.method == 'DELETE') {
          return response({}, mode == 'failure' ? 503 : 200);
        }
        return response({
          'results': [
            fixture.item(),
            {...fixture.item(), 'notification_id': '2'},
          ],
          'next_before_id': '2',
        });
      });
      final container = ProviderContainer(
        overrides: [
          firebaseAuthProvider.overrideWithValue(
            fixture.NotificationTestAuth(),
          ),
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
      final vm = container.read(notificationsVmProvider.notifier);
      if (mode == 'failure') {
        await expectLater(
          vm.deleteNotifications(id: '1'),
          throwsA(isA<NotificationsError>()),
        );
        expect(
          container.read(notificationsVmProvider).asData!.value.items.length,
          2,
        );
      } else {
        await vm.deleteNotifications(id: mode == 'one' ? '1' : null);
        final page = container.read(notificationsVmProvider).asData!.value;
        expect(requests.last.method, 'DELETE');
        expect(requests.last.headers['Authorization'], 'Bearer test-token');
        if (mode == 'one') {
          expect(page.items.single.id, '2');
          expect(page.nextBeforeId, '2');
        }
        if (mode == 'all') {
          expect(page.items, isEmpty);
          expect(page.nextBeforeId, isNull);
        }
      }
    });
  }

  test('삭제 중 추가 페이지 응답이 도착해도 삭제 알림이 되살아나지 않는다', () async {
    final page = Completer<http.Response>();
    final requested = Completer<void>();
    final client = MockClient((r) async {
      if (r.method == 'DELETE') return response({});
      if (r.url.queryParameters['before_id'] != null) {
        requested.complete();
        return page.future;
      }
      return response({
        'results': [fixture.item()],
        'next_before_id': '1',
      });
    });
    final container = ProviderContainer(
      overrides: [
        firebaseAuthProvider.overrideWithValue(fixture.NotificationTestAuth()),
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
    final vm = container.read(notificationsVmProvider.notifier);
    final loading = vm.loadMore();
    await requested.future;
    await vm.deleteNotifications();
    page.complete(
      response({
        'results': [fixture.item()],
        'next_before_id': null,
      }),
    );
    await loading;
    expect(
      container.read(notificationsVmProvider).asData!.value.items,
      isEmpty,
    );
  });
}
