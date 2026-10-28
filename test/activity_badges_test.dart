import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ondolbom/model/auth/app_user.dart';
import 'package:ondolbom/model/auth/user_profile.dart';
import 'package:ondolbom/view/widgets/account_drawer.dart';
import 'package:ondolbom/view/widgets/activity_read_marker.dart';
import 'package:ondolbom/vm/activity/activity_vm.dart';
import 'package:ondolbom/vm/auth/auth_vm.dart';
import 'package:ondolbom/vm/auth/user_profile_vm.dart';
import 'vm/notifications_vm_test.dart' show NotificationTestAuth;

class VisibleActivity extends ActivityVm {
  @override
  ActivityCounts build() => const ActivityCounts(
    invites: 2,
    notifications: 4,
    notices: 120,
    inquiries: 1,
  );
  @override
  Future<void> refresh({bool force = false}) async {}
  void clear() => state = const ActivityCounts();
}

class MarkingActivity extends VisibleActivity {
  final seen = <String>[];
  bool fail = false;
  @override
  Future<void> markRead(String path, String token) async {
    if (fail) throw StateError('offline');
    seen.add('$path:$token');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('상세 표시 후 해당 버전을 읽음 처리하고 실패 시 재시도한다', (tester) async {
    final container = ProviderContainer(
      overrides: [activityProvider.overrideWith(MarkingActivity.new)],
    );
    addTearDown(container.dispose);
    final vm = container.read(activityProvider.notifier) as MarkingActivity;
    Widget detail(String token) => UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Scaffold(
          body: ActivityReadMarker(
            path: '/inquiries/4',
            token: token,
            child: const Text('관리자 답변'),
          ),
        ),
      ),
    );
    await tester.pumpWidget(detail('version-one'));
    await tester.pumpAndSettle();
    expect(vm.seen, ['/inquiries/4:version-one']);
    vm.fail = true;
    await tester.pumpWidget(detail('version-two'));
    await tester.pumpAndSettle();
    expect(find.text('읽음 상태 저장 실패 · 다시 시도'), findsOneWidget);
    vm.fail = false;
    await tester.tap(find.text('읽음 상태 저장 실패 · 다시 시도'));
    await tester.pumpAndSettle();
    expect(vm.seen.last, '/inquiries/4:version-two');
    expect(find.text('읽음 상태 저장 실패 · 다시 시도'), findsNothing);
  });
  testWidgets('메뉴 빨간 점과 Drawer 숫자를 표시하고 0건이면 숨긴다', (tester) async {
    final container = ProviderContainer(
      overrides: [
        activityProvider.overrideWith(VisibleActivity.new),
        authUserProvider.overrideWith((ref) => Stream.value(null)),
        userProfileProvider.overrideWith(
          (ref) async => const UserProfile(userId: 'db', name: '가족'),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(
            appBar: null,
            drawer: AccountDrawer(),
            body: AccountMenuButton(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('account-news-dot')), findsOneWidget);
    await tester.tap(find.byTooltip('계정 메뉴'));
    await tester.pumpAndSettle();
    for (final label in ['2', '4', '99+', '1']) {
      expect(find.text(label), findsOneWidget);
    }
    // Drawer를 열었어도 읽음 숫자를 지우지 않는다.
    expect(container.read(activityProvider).hasNews, isTrue);
    (container.read(activityProvider.notifier) as VisibleActivity).clear();
    await tester.pumpAndSettle();
    expect(find.text('99+'), findsNothing);
    expect(find.byKey(const ValueKey('account-news-dot')), findsNothing);
  });

  test('조회 실패는 기존 숫자를 유지하고 읽음 POST 후 갱신하며 계정 전환 응답은 무시한다', () async {
    var body = <String, dynamic>{
      'invites': 2,
      'notifications': 3,
      'notices': 1,
      'inquiries': 1,
    };
    var fail = false;
    Completer<http.Response>? delayed;
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      if (request.method == 'POST') return http.Response('{"read":true}', 200);
      if (delayed != null) return delayed.future;
      return http.Response(jsonEncode(body), fail ? 503 : 200);
    });
    final session = StreamController<AppUser?>();
    final container = ProviderContainer(
      overrides: [
        firebaseAuthProvider.overrideWithValue(NotificationTestAuth()),
        authUserProvider.overrideWith((ref) => session.stream),
        userProfileProvider.overrideWith(
          (ref) async => const UserProfile(userId: 'db'),
        ),
        authHttpClientProvider.overrideWithValue(client),
      ],
    );
    final sub = container.listen(activityProvider, (_, _) {});
    addTearDown(() {
      sub.close();
      container.dispose();
      client.close();
      session.close();
    });
    session.add(const AppUser(uid: 'verified'));
    for (
      var i = 0;
      i < 30 && container.read(activityProvider).invites != 2;
      i++
    ) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
    expect(container.read(activityProvider).notifications, 3);
    expect(requests.last.url.queryParameters['force'], 'true');
    fail = true;
    await container.read(activityProvider.notifier).refresh();
    expect(requests.last.url.queryParameters['force'], isNull);
    expect(container.read(activityProvider).notifications, 3);
    fail = false;
    body = {'invites': null, 'notifications': 0, 'notices': 0, 'inquiries': 0};
    await container
        .read(activityProvider.notifier)
        .markRead('/notices/a/n', 'a' * 64);
    expect(container.read(activityProvider).invites, 2);
    expect(container.read(activityProvider).notices, 0);
    expect(requests.last.url.queryParameters['force'], 'true');
    expect(
      requests.where((r) => r.method == 'POST').single.url.path,
      '/activity/notices/a/n/read',
    );
    expect(
      jsonDecode(
        requests.where((r) => r.method == 'POST').single.body,
      )['token'],
      'a' * 64,
    );
    delayed = Completer<http.Response>();
    final refresh = container.read(activityProvider.notifier).refresh();
    await Future<void>.delayed(const Duration(milliseconds: 5));
    session.add(null);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    expect(container.read(activityProvider).hasNews, isFalse);
    delayed.complete(http.Response('{"invites":99}', 200));
    await refresh;
    expect(container.read(activityProvider).hasNews, isFalse);
  });
}
