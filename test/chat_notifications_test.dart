import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ondolbom/model/auth/app_user.dart';
import 'package:ondolbom/view/chats/chat_view.dart';
import 'package:ondolbom/view/family_room/family_room_home.dart';
import 'package:ondolbom/vm/auth/auth_vm.dart';
import 'package:ondolbom/vm/chats/chat_notifications_vm.dart';
import 'package:ondolbom/vm/chats/chat_vm.dart';
import 'package:ondolbom/vm/family_room/family_context.dart';
import 'package:ondolbom/vm/family_room/family_room_notifier.dart';
import 'family_room_delete_test.dart' show DeleteRooms;
import 'chat_test.dart' as fixture;

void main() {
  test('미읽음 숫자와 읽음 API는 인증하고 실제 읽음 위치를 반환한다', () async {
    final calls = <http.Request>[];
    final client = MockClient((request) async {
      calls.add(request);
      expect(request.headers['Authorization'], 'Bearer token');
      return http.Response(
        jsonEncode(
          request.method == 'GET'
              ? {
                  'counts': {'room-a': 3},
                }
              : {'last_read_chat_seq': 9},
        ),
        200,
      );
    });
    final container = ProviderContainer(
      overrides: [
        authUserProvider.overrideWith(
          (ref) => Stream.value(const AppUser(uid: 'uid')),
        ),
        apiTokenLoaderProvider.overrideWithValue(() async => 'token'),
        chatHttpClientProvider.overrideWithValue(client),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(client.close);
    final subscription = container.listen(chatUnreadProvider, (_, _) {});
    addTearDown(subscription.close);
    expect(await container.read(chatUnreadProvider.future), {'room-a': 3});
    expect(
      await container.read(chatNotificationsApiProvider).markRead('room-a', 7),
      9,
    );
    expect(jsonDecode(calls.last.body), {
      'family_room_id': 'room-a',
      'chat_seq': 7,
    });
  });

  test('계정 전환 후 늦은 읽음 응답을 적용하지 않는다', () async {
    var active = true;
    final requested = Completer<void>();
    final pending = Completer<http.Response>();
    final client = MockClient((request) {
      requested.complete();
      return pending.future;
    });
    final container = ProviderContainer(
      overrides: [
        apiTokenLoaderProvider.overrideWithValue(
          () async => active ? 'token' : null,
        ),
        chatHttpClientProvider.overrideWithValue(client),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(client.close);
    final future = container
        .read(chatNotificationsApiProvider)
        .markRead('room-a', 7);
    final assertion = expectLater(future, throwsA(isA<ChatFailure>()));
    await requested.future;
    active = false;
    pending.complete(http.Response('{"last_read_chat_seq":7}', 200));
    await assertion;
  });

  testWidgets('미읽음 숫자가 생겨도 채팅 아이콘의 크기와 위치를 유지한다', (tester) async {
    var count = 0;
    final container = ProviderContainer(
      overrides: [
        authUserProvider.overrideWith((ref) => Stream.value(null)),
        familyRoomProvider.overrideWith(DeleteRooms.new),
        chatUnreadProvider.overrideWith((ref) async => {'room-a': count}),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: FamilyRoomHome()),
      ),
    );
    await tester.pumpAndSettle();
    final icon = find.byIcon(Icons.chat_bubble_outline);
    final original = tester.getRect(icon);
    for (final value in [1, 3, 100]) {
      count = value;
      container.invalidate(chatUnreadProvider);
      await tester.pumpAndSettle();
      expect(find.text(value > 99 ? '99+' : '$value'), findsOneWidget);
      expect(tester.getRect(icon), original);
    }
    expect(tester.takeException(), isNull);
  });

  testWidgets('읽음 실패는 자동 반복하지 않고 사용자 재시도 때 복구한다', (tester) async {
    var reads = 0;
    final socket = fixture.TestSocket();
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/read')) {
        reads++;
        return reads == 1
            ? http.Response('{}', 503)
            : http.Response('{"last_read_chat_seq":7}', 200);
      }
      return fixture.page([fixture.message(7)]);
    });
    addTearDown(client.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          familyContextProvider.overrideWithValue(fixture.room),
          apiTokenLoaderProvider.overrideWithValue(() async => 'token'),
          chatHttpClientProvider.overrideWithValue(client),
          chatSocketFactoryProvider.overrideWithValue((uri) => socket),
        ],
        child: const MaterialApp(home: ChatView()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(reads, 1);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(reads, 1);
    await tester.tap(find.text('읽음 처리 실패 · 다시 시도'));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(reads, 2);
    expect(find.text('읽음 처리 실패 · 다시 시도'), findsNothing);
  });

  testWidgets('화면에 반영한 메시지만 읽고 다른 화면에 가려지면 읽지 않는다', (tester) async {
    final reads = <int>[];
    final socket = fixture.TestSocket();
    final client = MockClient((request) async {
      if (request.url.path.endsWith('/read')) {
        final seq = jsonDecode(request.body)['chat_seq'] as int;
        reads.add(seq);
        return http.Response(jsonEncode({'last_read_chat_seq': seq}), 200);
      }
      return fixture.page([fixture.message(7, user: 'other')]);
    });
    addTearDown(client.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          familyContextProvider.overrideWithValue(fixture.room),
          apiTokenLoaderProvider.overrideWithValue(() async => 'token'),
          chatHttpClientProvider.overrideWithValue(client),
          chatSocketFactoryProvider.overrideWithValue((uri) => socket),
        ],
        child: const MaterialApp(home: ChatView()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(reads.last, 7);
    final context = tester.element(find.byType(ChatView));
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('cover')),
      ),
    );
    await tester.pumpAndSettle();
    socket.emit({
      'type': 'message',
      'message': fixture.message(8, user: 'other'),
    });
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 400));
    expect(reads.last, 7);
    Navigator.of(context).pop();
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(reads.last, 8);
    expect(tester.takeException(), isNull);
  });
}
