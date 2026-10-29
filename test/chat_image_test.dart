import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ondolbom/model/chats/chat_message.dart';
import 'package:ondolbom/view/chats/chat_view.dart';
import 'package:ondolbom/view/chats/chat_image_view.dart';
import 'package:ondolbom/vm/chats/chat_vm.dart';
import 'package:ondolbom/vm/chats/chat_image_vm.dart';
import 'package:ondolbom/vm/family_room/family_context.dart';

import 'chat_test.dart' as fixture;
import 'memo_image_test.dart' show photo;
import 'memo_edit_test.dart' show testContextProvider;

// 읽음 요청은 사진 업로드 횟수·응답을 검증하는 핸들러와 분리한다.
MockClient _chatMockClient(
  Future<http.Response> Function(http.Request) handler,
) => MockClient((request) async {
  if (request.url.path.endsWith('/chats/read')) {
    return http.Response(
      jsonEncode({'last_read_chat_seq': jsonDecode(request.body)['chat_seq']}),
      200,
    );
  }
  return handler(request);
});

String requestId(http.Request request) => RegExp(
  r'name="client_message_id"\r\n\r\n([^\r]+)',
).firstMatch(latin1.decode(request.bodyBytes))!.group(1)!;

Map<String, dynamic> imageMessage(String? id, {String content = '사진 설명'}) => {
  ...fixture.message(7, clientId: id, content: content),
  'author_name': '김가족',
  'has_image': 1,
};

http.Response uploaded(
  String id, {
  int status = 201,
  String content = '사진 설명',
}) => http.Response(
  jsonEncode({
    'type': 'message',
    'message': imageMessage(id, content: content),
    'duplicate': status == 200,
  }),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Future<fixture.TestSocket> mountImages(
  WidgetTester tester,
  http.Client client, {
  Future<Uint8List?> Function()? picker,
  double width = 390,
}) async {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final socket = fixture.TestSocket();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        familyContextProvider.overrideWithValue(fixture.room),
        apiTokenLoaderProvider.overrideWithValue(() async => 'id-token'),
        chatHttpClientProvider.overrideWithValue(client),
        chatSocketFactoryProvider.overrideWithValue((_) => socket),
        chatImagePickerProvider.overrideWithValue(picker ?? () async => photo),
      ],
      child: const MaterialApp(home: ChatView()),
    ),
  );
  await tester.pumpAndSettle();
  return socket;
}

void main() {
  test('모델은 기존 응답과 숫자·bool 이미지 플래그를 처리한다', () {
    expect(ChatMessage.fromJson(fixture.message(7)).hasImage, isFalse);
    expect(ChatMessage.fromJson(imageMessage(null)).hasImage, isTrue);
    expect(
      ChatMessage.fromJson({...imageMessage(null), 'has_image': true}).hasImage,
      isTrue,
    );
  });

  test('이미지와 텍스트를 단일 multipart로 전송하고 HTTP 응답과 소켓 이벤트를 합친다', () async {
    final pending = Completer<http.Response>();
    http.Request? upload;
    final harness = fixture.Harness(
      imageContext: true,
      client: _chatMockClient((request) async {
        if (request.method == 'POST') {
          upload = request;
          return pending.future;
        }
        return fixture.page([]);
      }),
    );
    addTearDown(harness.dispose);
    await harness.connected();
    expect(harness.vm.send(' 사진 설명 ', image: photo), isTrue);
    expect(harness.vm.send('중복', image: photo), isFalse);
    await harness.waitFor(() => upload != null);
    final request = upload!;
    expect(request.url.path, '/api/chats/messages/with-image');
    expect(request.headers['Authorization'], 'Bearer id-token');
    expect(
      request.headers['content-type'],
      startsWith('multipart/form-data; boundary='),
    );
    final body = latin1.decode(request.bodyBytes);
    expect(body, contains('name="family_room_id"\r\n\r\nroom-a'));
    expect(RegExp('name="image"').allMatches(body).length, 1);
    expect(body, contains(latin1.decode(photo)));
    final id = requestId(request);
    harness.sockets.single.emit({
      'type': 'message',
      'message': imageMessage(id),
    });
    await harness.waitFor(() => harness.state.pending.isEmpty);
    pending.complete(uploaded(id));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(harness.state.messages.length, 1);
    expect(harness.state.messages.single.hasImage, isTrue);
    expect(
      harness.sockets.single.sent.where((frame) => frame['type'] == 'message'),
      isEmpty,
    );
  });

  test('실패 후 같은 UUID·이미지·내용으로 재전송하고 200 중복 응답을 성공 처리한다', () async {
    final uploads = <http.Request>[];
    final harness = fixture.Harness(
      imageContext: true,
      client: _chatMockClient((request) async {
        if (request.method == 'POST') {
          uploads.add(request);
          if (uploads.length == 1) {
            return http.Response('{"detail":"failed"}', 500);
          }
          return uploaded(requestId(request), status: 200);
        }
        return fixture.page([]);
      }),
    );
    addTearDown(harness.dispose);
    await harness.connected();
    harness.vm.send('사진 설명', image: photo);
    await harness.waitFor(() => harness.state.pending.single.failed);
    final id = harness.state.pending.single.id;
    expect(harness.state.pending.single.image, photo);
    harness.vm.retry(id);
    await harness.waitFor(() => harness.state.pending.isEmpty);
    expect(uploads.length, 2);
    expect(requestId(uploads[0]), requestId(uploads[1]));
    for (final request in uploads) {
      expect(latin1.decode(request.bodyBytes), contains(latin1.decode(photo)));
    }
    expect(harness.state.messages.single.clientId, id);
  });

  test('업로드 중 소켓 연결이 바뀌어도 동일 이미지의 중복 업로드를 시작하지 않는다', () async {
    final pending = Completer<http.Response>();
    http.Request? upload;
    var count = 0;
    final harness = fixture.Harness(
      imageContext: true,
      client: _chatMockClient((request) async {
        if (request.method == 'POST') {
          count++;
          upload = request;
          return pending.future;
        }
        return fixture.page([]);
      }),
    );
    addTearDown(harness.dispose);
    await harness.connected();
    harness.vm.send('', image: photo);
    await harness.waitFor(() => upload != null);
    final id = harness.state.pending.single.id;
    harness.vm.reconnect();
    await harness.connected();
    harness.vm.retry(id);
    expect(count, 1);
    pending.complete(uploaded(id, content: ''));
    await harness.waitFor(() => harness.state.pending.isEmpty);
    expect(harness.state.messages.single.content, '');
  });

  test('토큰 대기 중 계정이 바뀌면 이전 업로드를 전송하지 않는다', () async {
    final token = Completer<String?>();
    var waiting = false;
    var posts = 0;
    final harness = fixture.Harness(
      imageContext: true,
      token: () => waiting ? token.future : Future.value('id-token'),
      client: _chatMockClient((request) async {
        if (request.method == 'POST') posts++;
        return fixture.page([]);
      }),
    );
    addTearDown(harness.dispose);
    await harness.connected();
    waiting = true;
    harness.vm.send('', image: photo);
    harness.container
        .read(fixture.testTokenProvider.notifier)
        .setToken('new-token');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    token.complete('id-token');
    await harness.connected();
    expect(posts, 0);
    expect(harness.state.pending, isEmpty);
  });

  test('계정 변경 전의 늦은 업로드 응답을 새 채팅 상태에 표시하지 않는다', () async {
    final pending = Completer<http.Response>();
    http.Request? upload;
    final harness = fixture.Harness(
      imageContext: true,
      client: _chatMockClient((request) async {
        if (request.method == 'POST') {
          upload = request;
          return pending.future;
        }
        return fixture.page([]);
      }),
    );
    addTearDown(harness.dispose);
    await harness.connected();
    harness.vm.send('', image: photo);
    await harness.waitFor(() => upload != null);
    harness.container
        .read(fixture.testTokenProvider.notifier)
        .setToken('new-token');
    await harness.connected();
    pending.complete(uploaded(requestId(upload!), content: ''));
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(harness.state.messages, isEmpty);
    expect(harness.state.pending, isEmpty);
  });

  testWidgets('사진 선택·교체·제거 후 이미지 단독 전송과 확대를 지원한다', (tester) async {
    var posts = 0;
    await mountImages(
      tester,
      _chatMockClient((request) async {
        if (request.method == 'POST') {
          posts++;
          return uploaded(requestId(request), content: '');
        }
        if (request.url.path.endsWith('/image')) {
          expect(request.headers['Authorization'], 'Bearer id-token');
          expect(request.url.queryParameters['family_room_id'], 'room-a');
          return http.Response.bytes(photo, 200);
        }
        return fixture.page([]);
      }),
      width: 320,
    );
    await tester.tap(find.byTooltip('사진 첨부'));
    await tester.pumpAndSettle();
    expect(find.text('첨부 사진 1장'), findsOneWidget);
    await tester.tap(find.byTooltip('첨부 사진 변경'));
    await tester.pumpAndSettle();
    expect(find.text('첨부 사진 1장'), findsOneWidget);
    await tester.tap(find.byTooltip('첨부 사진 제거'));
    await tester.pumpAndSettle();
    expect(find.text('첨부 사진 1장'), findsNothing);
    expect(posts, 0);
    await tester.tap(find.byTooltip('사진 첨부'));
    await tester.pumpAndSettle();
    tester.view.viewInsets = FakeViewPadding(bottom: 240);
    addTearDown(tester.view.resetViewInsets);
    await tester.pump();
    await tester.tap(find.byTooltip('메시지 전송'));
    await tester.pumpAndSettle();
    expect(posts, 1);
    expect(find.text('첨부 사진 1장'), findsNothing);
    final state = ProviderScope.containerOf(
      tester.element(find.byType(ChatView)),
    ).read(chatVmProvider(fixture.room));
    expect(state.pending, isEmpty, reason: state.error);
    expect(state.messages.single.hasImage, isTrue);
    expect(find.byType(ChatImageView), findsOneWidget);
    await tester.ensureVisible(find.byType(ChatImageView));
    await tester.pumpAndSettle();
    final imageProvider = ProviderScope.containerOf(
      tester.element(find.byType(ChatView)),
    ).read(chatImageProvider((context: fixture.room, seq: 7)));
    expect(imageProvider.hasError, isFalse, reason: '${imageProvider.error}');
    expect(imageProvider.hasValue, isTrue);
    await tester.tap(
      find.descendant(
        of: find.byType(ChatImageView),
        matching: find.byType(InkWell),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsOneWidget);
    await tester.tap(find.byTooltip('사진 닫기'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('사진 선택 취소와 크기 초과는 입력을 유지하고 전송하지 않는다', (tester) async {
    var picks = 0;
    var posts = 0;
    await mountImages(
      tester,
      _chatMockClient((request) async {
        if (request.method == 'POST') posts++;
        return fixture.page([]);
      }),
      picker: () async =>
          ++picks == 1 ? null : Uint8List(maxChatImageBytes + 1),
    );
    await tester.enterText(find.byKey(const ValueKey('chat-input')), '남길 내용');
    await tester.tap(find.byTooltip('사진 첨부'));
    await tester.pumpAndSettle();
    expect(find.text('첨부 사진 1장'), findsNothing);
    await tester.tap(find.byTooltip('사진 첨부'));
    await tester.pumpAndSettle();
    expect(find.textContaining('5MB 이하'), findsOneWidget);
    expect(find.text('남길 내용'), findsOneWidget);
    expect(posts, 0);
  });

  testWidgets('이미지 로딩 실패는 사진 다시 불러오기로 복구한다', (tester) async {
    var images = 0;
    await mountImages(
      tester,
      _chatMockClient((request) async {
        if (request.url.path.endsWith('/image')) {
          return ++images == 1
              ? http.Response('failed', 503)
              : http.Response.bytes(photo, 200);
        }
        return fixture.page([imageMessage(null)]);
      }),
    );
    expect(find.text('사진 다시 불러오기'), findsOneWidget);
    await tester.tap(find.text('사진 다시 불러오기'));
    await tester.pumpAndSettle();
    expect(images, 2);
    expect(find.text('사진 다시 불러오기'), findsNothing);
    expect(
      find.descendant(
        of: find.byType(ChatImageView),
        matching: find.byType(InkWell),
      ),
      findsOneWidget,
    );
  });

  test('이미지 업로드 권한이 거절되면 연결을 차단하고 재전송용 원본을 보존한다', () async {
    final harness = fixture.Harness(
      imageContext: true,
      client: _chatMockClient((request) async {
        if (request.method == 'POST') return http.Response('denied', 403);
        return fixture.page([]);
      }),
    );
    addTearDown(harness.dispose);
    await harness.connected();
    harness.vm.send('사진 설명', image: photo);
    await harness.waitFor(() => harness.state.status == ChatStatus.blocked);
    expect(harness.state.pending.single.failed, isTrue);
    expect(harness.state.pending.single.image, photo);
  });

  test('이미지 조회는 인증 토큰이 없으면 HTTP에 접근하지 않는다', () async {
    var requests = 0;
    final container = ProviderContainer(
      overrides: [
        familyContextProvider.overrideWithValue(fixture.room),
        apiBaseUrlProvider.overrideWithValue('https://example.test/api'),
        apiTokenLoaderProvider.overrideWithValue(() async => null),
        chatHttpClientProvider.overrideWithValue(
          _chatMockClient((request) async {
            requests++;
            return http.Response.bytes(photo, 200);
          }),
        ),
      ],
    );
    addTearDown(container.dispose);
    await expectLater(
      container.read(chatImageProvider((context: fixture.room, seq: 7)).future),
      throwsA(isA<ChatFailure>()),
    );
    expect(requests, 0);
  });

  test('이미지 조회 중 공간이 바뀌면 이전 공간의 늦은 이미지 응답을 표시하지 않는다', () async {
    final pending = Completer<http.Response>();
    final started = Completer<void>();
    final container = ProviderContainer(
      overrides: [
        familyContextProvider.overrideWith(
          (ref) => ref.watch(testContextProvider),
        ),
        apiBaseUrlProvider.overrideWithValue('https://example.test/api'),
        apiTokenLoaderProvider.overrideWithValue(() async => 'id-token'),
        chatHttpClientProvider.overrideWithValue(
          _chatMockClient((request) async {
            expect(request.url.path, '/api/chats/messages/7/image');
            expect(request.headers['Authorization'], 'Bearer id-token');
            started.complete();
            return pending.future;
          }),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.read(testContextProvider.notifier).change(fixture.room);
    final provider = chatImageProvider((context: fixture.room, seq: 7));
    final subscription = container.listen(provider, (_, _) {});
    addTearDown(subscription.close);
    final loading = container.read(provider.future);
    final assertion = expectLater(loading, throwsA(isA<ChatFailure>()));
    await started.future;
    container.read(testContextProvider.notifier).change((
      familyRoomId: 'room-b',
      userId: 'other-user',
      roomName: '다른 가족',
    ));
    pending.complete(http.Response.bytes(photo, 200));
    await assertion;
    expect(container.read(provider).asData, isNull);
  });
}
