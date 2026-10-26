import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:ondolbom/model/chats/chat_message.dart';
import 'package:ondolbom/view/chats/chat_view.dart';
import 'package:ondolbom/view/family_room/family_room_home.dart';
import 'package:ondolbom/vm/chats/chat_vm.dart';
import 'package:ondolbom/vm/family_room/family_context.dart';
import 'package:ondolbom/vm/family_room/family_room_notifier.dart';
import 'family_care_connection_test.dart' show CareRooms;

const room = (familyRoomId: 'room-a', userId: 'db-user', roomName: '가족 A');

Map<String, dynamic> message(
  int id, {
  String? clientId,
  String content = '저장된 대화',
  String user = 'db-user',
}) => {
  'chat_seq': id,
  'family_room_id': 'room-a',
  'user_id': user,
  'chat_content': content,
  'sent_at': '2026-10-25T18:01:00',
  'client_message_id': clientId,
  'live_chat_updated_at': null,
};
http.Response page(
  List<Map<String, dynamic>> rows, {
  bool more = false,
  int? after,
}) => http.Response(
  jsonEncode({'results': rows, 'has_more': more, 'next_after_id': after}),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

class TestSink extends Fake implements WebSocketSink {
  TestSink(this.socket);
  final TestSocket socket;
  @override
  void add(dynamic event) {
    final frame = jsonDecode(event as String) as Map<String, dynamic>;
    socket.sent.add(frame);
    if (frame['type'] == 'auth' && socket.autoReady) {
      socket.emit({
        'type': 'ready',
        'user_id': 'db-user',
        'family_room_id': 'room-a',
      });
    }
    socket.onFrame?.call(frame);
  }

  @override
  Future<void> close([int? closeCode, String? closeReason]) async {
    socket.closed = true;
    unawaited(socket.controller.close());
  }
}

class TestSocket extends Fake implements WebSocketChannel {
  final controller = StreamController<dynamic>();
  final sent = <Map<String, dynamic>>[];
  bool autoReady = true;
  bool closed = false;
  int? code;
  void Function(Map<String, dynamic>)? onFrame;
  @override
  Stream<dynamic> get stream => controller.stream;
  @override
  late final WebSocketSink sink = TestSink(this);
  @override
  Future<void> get ready async {}
  @override
  int? get closeCode => code;
  void emit(Map<String, dynamic> frame) {
    if (!controller.isClosed) controller.add(jsonEncode(frame));
  }

  void disconnect(int closeCode) {
    code = closeCode;
    unawaited(controller.close());
  }
}

final testTokenProvider = NotifierProvider<TestToken, String?>(TestToken.new);

class TestToken extends Notifier<String?> {
  @override
  String? build() => 'id-token';
  void setToken(String? value) {
    state = value;
  }
}

class Harness {
  Harness({http.Client? client, Future<String?> Function()? token}) {
    container = ProviderContainer(
      overrides: [
        apiBaseUrlProvider.overrideWithValue('https://example.test/api'),
        apiTokenLoaderProvider.overrideWith((ref) {
          final value = ref.watch(testTokenProvider);
          return token ?? () async => value;
        }),
        chatHttpClientProvider.overrideWithValue(
          client ?? MockClient((_) async => page([])),
        ),
        chatSocketFactoryProvider.overrideWithValue((uri) {
          urls.add(uri);
          final socket = TestSocket();
          sockets.add(socket);
          return socket;
        }),
      ],
    );
    subscription = container.listen(chatVmProvider(room), (_, _) {});
  }
  late ProviderContainer container;
  late ProviderSubscription<ChatState> subscription;
  final sockets = <TestSocket>[];
  final urls = <Uri>[];
  ChatState get state => container.read(chatVmProvider(room));
  ChatVm get vm => container.read(chatVmProvider(room).notifier);
  Future<void> waitFor(bool Function() done) async {
    for (var i = 0; i < 200 && !done(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 2));
    }
    expect(done(), isTrue, reason: 'Expected chat state was not reached');
  }

  Future<void> connected() => waitFor(
    () => state.status == ChatStatus.connected && !state.loadingHistory,
  );
  void dispose() {
    subscription.close();
    container.dispose();
  }
}

void main() {
  test('모델은 기존 NULL 요청 ID와 서버 DATETIME을 처리한다', () {
    final item = ChatMessage.fromJson(message(1));
    expect(item.clientId, isNull);
    expect(item.sentAt!.hour, 18);
    expect(item.sentAt!.isUtc, isFalse);
  });

  test('WSS 주소와 첫 인증 메시지, HTTP 인증 헤더를 연결한다', () async {
    final harness = Harness(
      client: MockClient((request) async {
        expect(request.headers['Authorization'], 'Bearer id-token');
        expect(request.url.path, '/api/chats/messages');
        expect(request.url.queryParameters['family_room_id'], 'room-a');
        return page([message(2), message(1)], more: true);
      }),
    );
    addTearDown(harness.dispose);
    await harness.connected();
    expect(harness.urls.single.scheme, 'wss');
    expect(harness.urls.single.path, '/api/chats/ws/room-a');
    expect(harness.urls.single.queryParameters, isEmpty);
    expect(harness.sockets.single.sent.first, {
      'type': 'auth',
      'token': 'id-token',
    });
    expect(harness.state.messages.map((item) => item.seq), [1, 2]);
    expect(harness.state.hasOlder, isTrue);
  });

  test('토큰이 없으면 소켓과 HTTP에 접근하지 않는다', () async {
    var requests = 0;
    final harness = Harness(
      token: () async => null,
      client: MockClient((_) async {
        requests++;
        return page([]);
      }),
    );
    addTearDown(harness.dispose);
    await harness.waitFor(() => harness.state.status == ChatStatus.blocked);
    expect(harness.sockets, isEmpty);
    expect(requests, 0);
  });

  test('서버 응답 전에는 전송 중이며 동일 메시지는 한 번만 표시한다', () async {
    final harness = Harness();
    addTearDown(harness.dispose);
    await harness.connected();
    expect(harness.vm.send('  안녕하세요 😀  '), isTrue);
    final socket = harness.sockets.single;
    final frame = socket.sent.last;
    expect(frame['content'], '안녕하세요 😀');
    expect(frame.containsKey('user_id'), isFalse);
    expect(
      frame['client_message_id'],
      matches(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ),
      ),
    );
    expect(harness.state.messages, isEmpty);
    expect(harness.state.pending.single.failed, isFalse);
    expect(harness.vm.send('중복 클릭'), isFalse);
    final stored = message(
      1,
      clientId: frame['client_message_id'] as String,
      content: frame['content'] as String,
    );
    socket.emit({'type': 'message', 'message': stored});
    socket.emit({'type': 'message', 'message': stored, 'duplicate': true});
    await harness.waitFor(() => harness.state.pending.isEmpty);
    expect(harness.state.messages.length, 1);
    socket.emit({'type': 'ping'});
    await harness.waitFor(() => socket.sent.last['type'] == 'pong');
  });

  test('전송 실패 재시도는 같은 UUID를 사용한다', () async {
    final harness = Harness();
    addTearDown(harness.dispose);
    await harness.connected();
    harness.vm.send('재시도할 내용');
    final socket = harness.sockets.single;
    final id = socket.sent.last['client_message_id'] as String;
    socket.emit({'type': 'error', 'status': 422, 'detail': '입력 오류'});
    await harness.waitFor(() => harness.state.pending.single.failed);
    harness.vm.retry(id);
    expect(socket.sent.last['client_message_id'], id);
    expect(harness.state.pending.single.failed, isFalse);
  });

  test('이전 대화는 before_id로 조회하고 실시간 중복과 합친다', () async {
    final harness = Harness(
      client: MockClient((request) async {
        if (request.url.queryParameters['before_id'] == '2') {
          return page([message(1)]);
        }
        return page([message(3), message(2)], more: true);
      }),
    );
    addTearDown(harness.dispose);
    await harness.connected();
    harness.sockets.single.emit({'type': 'message', 'message': message(3)});
    await harness.vm.loadOlder();
    expect(harness.state.messages.map((item) => item.seq), [1, 2, 3]);
    expect(harness.state.hasOlder, isFalse);
  });

  test('재연결은 누락 페이지를 복구하고 HTTP·실시간 메시지를 중복 제거한다', () async {
    final cursors = <String?>[];
    final harness = Harness(
      client: MockClient((request) async {
        final after = request.url.queryParameters['after_id'];
        cursors.add(after);
        if (after == '1') return page([message(2)], more: true, after: 2);
        if (after == '2') return page([message(3)]);
        return page([message(1)]);
      }),
    );
    addTearDown(harness.dispose);
    await harness.connected();
    final old = harness.sockets.single;
    harness.vm.reconnect();
    await harness.waitFor(() => harness.sockets.length == 2);
    await harness.connected();
    expect(old.closed, isTrue);
    expect(cursors, [null, '1', '2']);
    expect(harness.state.messages.map((item) => item.seq), [1, 2, 3]);
  });

  test('접근 거절은 자동 재연결하지 않는다', () async {
    final harness = Harness();
    addTearDown(harness.dispose);
    await harness.connected();
    harness.sockets.single.disconnect(4403);
    await harness.waitFor(() => harness.state.status == ChatStatus.blocked);
    expect(harness.sockets.length, 1);
    expect(harness.state.messages, isEmpty);
  });

  test('다른 공간의 실시간 메시지는 상태에 들어가지 않는다', () async {
    final harness = Harness();
    addTearDown(harness.dispose);
    await harness.connected();
    harness.sockets.single.emit({
      'type': 'message',
      'message': {...message(7), 'family_room_id': 'other-room'},
    });
    await harness.waitFor(
      () => harness.state.status == ChatStatus.reconnecting,
    );
    expect(harness.state.messages, isEmpty);
  });

  test('로그인 토큰 상태가 바뀌면 기존 연결과 대화를 폐기한다', () async {
    final harness = Harness(
      client: MockClient((_) async => page([message(1)])),
    );
    addTearDown(harness.dispose);
    await harness.connected();
    final old = harness.sockets.single;
    harness.container.read(testTokenProvider.notifier).setToken(null);
    await harness.container.pump();
    await harness.waitFor(() => harness.state.status == ChatStatus.blocked);
    expect(old.closed, isTrue);
    expect(harness.state.messages, isEmpty);
    expect(harness.state.pending, isEmpty);
  });

  testWidgets('일시 단절 후 자동 재연결하고 작은 화면의 키보드에서도 입력한다', (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final sockets = <TestSocket>[];
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          familyContextProvider.overrideWithValue(room),
          apiTokenLoaderProvider.overrideWithValue(() async => 'id-token'),
          chatHttpClientProvider.overrideWithValue(
            MockClient((_) async => page([])),
          ),
          chatSocketFactoryProvider.overrideWithValue((uri) {
            final socket = TestSocket();
            sockets.add(socket);
            return socket;
          }),
        ],
        child: const MaterialApp(home: ChatView()),
      ),
    );
    await tester.pumpAndSettle();
    expect(sockets.length, 1);
    sockets.first.disconnect(1006);
    await tester.pumpAndSettle();
    expect(find.text('다시 연결 중…'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();
    expect(sockets.length, 2);
    expect(find.text('연결됨'), findsOneWidget);
    tester.view.viewInsets = FakeViewPadding(bottom: 240);
    addTearDown(tester.view.resetViewInsets);
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('chat-input')),
      '작은 화면에서 메시지 보내기',
    );
    await tester.pump();
    await tester.tap(find.byTooltip('메시지 전송'));
    await tester.pump();
    expect(find.text('전송 중…'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
    expect(sockets.last.closed, isTrue);
  });

  test('폐기 후 늦은 HTTP 응답은 상태에 반영하지 않는다', () async {
    final response = Completer<http.Response>();
    final harness = Harness(client: MockClient((_) => response.future));
    await harness.waitFor(() => harness.state.status == ChatStatus.connected);
    final socket = harness.sockets.single;
    harness.dispose();
    response.complete(page([message(1)]));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(socket.closed, isTrue);
  });

  testWidgets('공간 홈에서 채팅에 진입해 입력·전송·서버 확인을 표시한다', (tester) async {
    final socket = TestSocket();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          familyContextProvider.overrideWithValue(room),
          familyRoomProvider.overrideWith(CareRooms.new),
          apiTokenLoaderProvider.overrideWithValue(() async => 'id-token'),
          chatHttpClientProvider.overrideWithValue(
            MockClient((_) async => page([])),
          ),
          chatSocketFactoryProvider.overrideWithValue((uri) => socket),
        ],
        child: MaterialApp(
          theme: ThemeData(colorSchemeSeed: const Color(0xFFAD5B32)),
          home: const FamilyRoomHome(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('실시간 채팅'));
    await tester.tap(find.text('실시간 채팅'));
    await tester.pumpAndSettle();
    expect(find.text('가족 채팅'), findsOneWidget);
    expect(find.text('연결됨'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('chat-input')),
      '오늘도 함께 돌봐요',
    );
    await tester.pump();
    await tester.tap(find.byTooltip('메시지 전송'));
    await tester.pump();
    expect(find.text('전송 중…'), findsOneWidget);
    expect(socket.sent.last['content'], '오늘도 함께 돌봐요');
    socket.emit({
      'type': 'message',
      'message': message(
        7,
        clientId: socket.sent.last['client_message_id'] as String,
        content: '오늘도 함께 돌봐요',
      ),
    });
    await tester.pumpAndSettle();
    expect(find.text('전송 중…'), findsNothing);
    expect(find.text('오늘도 함께 돌봐요'), findsOneWidget);
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(socket.closed, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('선택 공간이 없으면 연결하지 않고 안내한다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          familyContextProvider.overrideWithValue((
            familyRoomId: '',
            userId: '',
            roomName: '',
          )),
          chatSocketFactoryProvider.overrideWithValue(
            (uri) => throw StateError('must not connect'),
          ),
        ],
        child: const MaterialApp(home: ChatView()),
      ),
    );
    expect(find.text('로그인 후 가족 공간을 선택해 주세요.'), findsOneWidget);
  });
}
