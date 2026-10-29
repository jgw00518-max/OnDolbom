import 'dart:convert';
import 'package:ondolbom/view/chats/chat_view.dart';
import 'package:ondolbom/vm/chats/chat_vm.dart';
import 'package:ondolbom/vm/family_room/family_context.dart';
import 'package:ondolbom/vm/family_room/family_room_notifier.dart';
import 'family_room_delete_test.dart' show DeleteRooms;
import 'chat_test.dart' as chat_fixture;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ondolbom/model/auth/app_user.dart';
import 'package:ondolbom/model/auth/user_profile.dart';
import 'package:ondolbom/model/notifications/push_service.dart';
import 'package:ondolbom/view/widgets/push_bridge.dart';
import 'package:ondolbom/view/notifications/notifications_view.dart';
import 'package:ondolbom/vm/auth/auth_vm.dart';
import 'package:ondolbom/vm/auth/user_profile_vm.dart';
import 'package:ondolbom/vm/notifications/notifications_vm.dart';
import 'push_service_test.dart'
    show PushAuth, TestPushPlatform, MemoryPushPrefs;
import 'view/notifications_view_test.dart' show EmptyNotifications;

class ChatPushRooms extends DeleteRooms {
  @override
  Future<void> fetchRooms() async {}
}

void main() {
  testWidgets('채팅 푸시는 권한 확인 후 해당 공간을 선택하고 채팅방을 연다', (tester) async {
    final platform = TestPushPlatform();
    final auth = PushAuth();
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/read')) {
        return http.Response(
          jsonEncode({
            'last_read_chat_seq': jsonDecode(request.body)['chat_seq'],
          }),
          200,
        );
      }
      return chat_fixture.page([]);
    });
    addTearDown(client.close);
    final socket = chat_fixture.TestSocket()..autoReady = false;
    socket.onFrame = (frame) {
      if (frame['type'] == 'auth') {
        socket.emit({
          'type': 'ready',
          'user_id': 'user-a',
          'family_room_id': 'room-b',
        });
      }
    };
    final service = PushService(
      platform: platform,
      auth: auth,
      baseUrl: 'http://local',
      preferences: MemoryPushPrefs(),
      client: client,
    );
    final container = ProviderContainer(
      overrides: [
        pushServiceProvider.overrideWithValue(service),
        authUserProvider.overrideWith(
          (ref) => Stream.value(const AppUser(uid: 'a')),
        ),
        userProfileProvider.overrideWith(
          (ref) async => const UserProfile(userId: 'user-a'),
        ),
        familyRoomProvider.overrideWith(ChatPushRooms.new),
        apiTokenLoaderProvider.overrideWithValue(() async => 'token'),
        chatHttpClientProvider.overrideWithValue(client),
        chatSocketFactoryProvider.overrideWithValue((uri) => socket),
      ],
    );
    addTearDown(container.dispose);
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          navigatorKey: navigator,
          builder: (context, child) =>
              PushBridge(navigatorKey: navigator, child: child!),
          home: const Scaffold(body: Text('home')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    platform.tapController.add(
      const PushEvent({
        'type': 'chat_message',
        'user_uid': 'a',
        'family_room_id': 'room-b',
        'chat_seq': '7',
      }),
    );
    await tester.pumpAndSettle();
    expect(container.read(familyRoomProvider).selectedRoomId, 'room-b');
    expect(find.byType(ChatView), findsOneWidget);
    expect(find.byType(NotificationsView), findsNothing);
    platform.tapController.add(
      const PushEvent({
        'type': 'chat_message',
        'user_uid': 'a',
        'family_room_id': 'foreign',
        'chat_seq': '8',
      }),
    );
    await tester.pumpAndSettle();
    expect(container.read(familyRoomProvider).selectedRoomId, 'room-b');
    expect(find.byType(ChatView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final kind in [
    'schedule_created',
    'schedule_reconfirm_expired',
    'schedule_reconfirm_unanswered',
    'schedule_recruitment',
    'schedule_reconfirm_unverified',
  ]) {
    testWidgets(
      '$kind push opens inbox only for its current authenticated recipient',
      (tester) async {
        final platform = TestPushPlatform();
        final auth = PushAuth();
        final client = MockClient((_) async => http.Response('{}', 200));
        addTearDown(client.close);
        final service = PushService(
          platform: platform,
          auth: auth,
          baseUrl: 'http://local',
          preferences: MemoryPushPrefs(),
          client: client,
        );
        final navigator = GlobalKey<NavigatorState>();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              pushServiceProvider.overrideWithValue(service),
              authUserProvider.overrideWith(
                (ref) => Stream.value(const AppUser(uid: 'a')),
              ),
              userProfileProvider.overrideWith(
                (ref) async => const UserProfile(userId: 'mysql'),
              ),
              notificationsVmProvider.overrideWith(EmptyNotifications.new),
            ],
            child: MaterialApp(
              navigatorKey: navigator,
              builder: (context, child) =>
                  PushBridge(navigatorKey: navigator, child: child!),
              home: const Scaffold(body: Text('home')),
            ),
          ),
        );
        await tester.pumpAndSettle();
        platform.tapController.add(
          PushEvent({'type': kind, 'user_uid': 'b', 'notification_id': '7'}),
        );
        await tester.pumpAndSettle();
        expect(find.byType(NotificationsView), findsNothing);
        platform.tapController.add(
          PushEvent({'type': kind, 'user_uid': 'a', 'notification_id': '7'}),
        );
        await tester.pumpAndSettle();
        expect(find.byType(NotificationsView), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }
}
