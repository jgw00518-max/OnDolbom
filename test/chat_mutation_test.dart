import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ondolbom/model/chats/chat_message.dart';
import 'package:ondolbom/view/chats/chat_image_view.dart';
import 'package:ondolbom/vm/chats/chat_vm.dart';

import 'chat_test.dart' as fixture;
import 'chat_image_test.dart' as images;
import 'memo_image_test.dart' show photo;

Map<String, dynamic> edited({int seq = 7, bool image = false}) => {
  ...fixture.message(seq, content: '수정한 내용'),
  'has_image': image ? 1 : 0,
  'live_chat_updated_at': '2026-10-26T18:01:00',
};

Map<String, dynamic> deleted({int seq = 7}) => {
  ...fixture.message(seq, content: '삭제된 메시지입니다.'),
  'has_image': 0,
  'is_deleted': true,
  'live_chat_deleted_at': '2026-10-26T18:02:00',
};

http.Response changed(Map<String, dynamic> message) => http.Response(
  jsonEncode({'type': 'message', 'message': message}),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Future<void> menu(WidgetTester tester, String action) async {
  await tester.tap(find.byTooltip('메시지 메뉴').first);
  await tester.pumpAndSettle();
  await tester.tap(find.text(action));
  await tester.pumpAndSettle();
}

void main() {
  test('삭제 모델은 원문과 사진을 숨기며 수정·삭제 시각을 파싱한다', () {
    final message = ChatMessage.fromJson({
      ...deleted(),
      'chat_content': '숨겨야 할 원문',
      'has_image': 1,
    });
    expect(message.content, '삭제된 메시지입니다.');
    expect(message.hasImage, isFalse);
    expect(message.isDeleted, isTrue);
    expect(message.deletedAt, isNotNull);
    expect(ChatMessage.fromJson(edited()).updatedAt, isNotNull);
  });

  testWidgets('본인 메시지를 길게 눌러 수정하면 PATCH와 수정됨 표시를 반영한다', (tester) async {
    var patches = 0;
    await images.mountImages(
      tester,
      MockClient((request) async {
        if (request.method == 'PATCH') {
          patches++;
          expect(request.url.path, '/chats/messages/7');
          expect(request.headers['Authorization'], 'Bearer id-token');
          expect(jsonDecode(request.body), {
            'family_room_id': 'room-a',
            'content': '수정한 내용',
          });
          return changed(edited());
        }
        return fixture.page([fixture.message(7, content: '기존 내용')]);
      }),
    );
    await tester.longPress(find.text('기존 내용'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('수정'));
    await tester.pumpAndSettle();
    expect(find.text('기존 내용'), findsNWidgets(2));
    await tester.enterText(
      find.byKey(const ValueKey('chat-edit-input')),
      '수정한 내용',
    );
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();
    expect(patches, 1);
    expect(find.text('수정한 내용'), findsOneWidget);
    expect(find.textContaining('수정됨'), findsOneWidget);
    expect(find.text('나'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('삭제 확인 취소는 요청하지 않고 전체 삭제는 텍스트·사진·메뉴를 숨긴다', (tester) async {
    var deletes = 0;
    await images.mountImages(
      tester,
      MockClient((request) async {
        if (request.method == 'DELETE') {
          deletes++;
          expect(request.url.queryParameters, {'family_room_id': 'room-a'});
          expect(request.headers['Authorization'], 'Bearer id-token');
          return changed(deleted());
        }
        if (request.url.path.endsWith('/image')) {
          return http.Response.bytes(photo, 200);
        }
        return fixture.page([images.imageMessage(null, content: '사진 설명')]);
      }),
    );
    await menu(tester, '삭제');
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(deletes, 0);
    expect(find.text('사진 설명'), findsOneWidget);
    await menu(tester, '삭제');
    await tester.tap(find.text('삭제').last);
    await tester.pumpAndSettle();
    expect(deletes, 1);
    expect(find.text('삭제된 메시지입니다.'), findsOneWidget);
    expect(find.text('사진 설명'), findsNothing);
    expect(find.byType(ChatImageView), findsNothing);
    expect(find.byTooltip('메시지 메뉴'), findsNothing);
  });

  testWidgets('다른 가족·삭제된 메시지에는 수정·삭제 메뉴가 없다', (tester) async {
    await images.mountImages(
      tester,
      MockClient(
        (_) async =>
            fixture.page([fixture.message(6, user: 'other-user'), deleted()]),
      ),
    );
    expect(find.byTooltip('메시지 메뉴'), findsNothing);
    expect(find.text('삭제된 메시지입니다.'), findsOneWidget);
  });

  testWidgets('텍스트를 비우는 수정은 거절하지만 이미지 설명은 비울 수 있다', (tester) async {
    var patches = 0;
    final socket = await images.mountImages(
      tester,
      MockClient((request) async {
        if (request.method == 'PATCH') {
          patches++;
          expect(jsonDecode(request.body)['content'], '');
          return changed({...edited(image: true), 'chat_content': ''});
        }
        if (request.url.path.endsWith('/image')) {
          return http.Response.bytes(photo, 200);
        }
        return fixture.page([fixture.message(7)]);
      }),
    );
    await menu(tester, '수정');
    await tester.enterText(find.byKey(const ValueKey('chat-edit-input')), ' ');
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();
    expect(find.text('텍스트 메시지 내용은 비울 수 없습니다.'), findsOneWidget);
    expect(patches, 0);
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    socket.emit({
      'type': 'message',
      'message': {...fixture.message(7), 'has_image': 1},
    });
    await tester.pumpAndSettle();
    await menu(tester, '수정');
    expect(find.text('첨부 사진은 유지되며 설명만 수정합니다.'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('chat-edit-input')), '');
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();
    expect(patches, 1);
    expect(find.byType(ChatImageView), findsOneWidget);
  });

  testWidgets('수정 중 중복 제출을 차단하고 실패 후 입력을 유지하며 재시도한다', (tester) async {
    final pending = Completer<http.Response>();
    var patches = 0;
    await images.mountImages(
      tester,
      MockClient((request) async {
        if (request.method == 'PATCH') {
          return ++patches == 1 ? pending.future : changed(edited());
        }
        return fixture.page([fixture.message(7)]);
      }),
    );
    await menu(tester, '수정');
    await tester.enterText(
      find.byKey(const ValueKey('chat-edit-input')),
      '수정한 내용',
    );
    await tester.tap(find.text('저장'));
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '저장 중…'))
          .onPressed,
      isNull,
    );
    pending.complete(http.Response('{"detail":"failed"}', 503));
    await tester.pumpAndSettle();
    expect(find.text('메시지의 최신 상태가 요청한 결과와 다릅니다. 내용을 확인해 주세요.'), findsOneWidget);
    expect(find.text('수정한 내용'), findsOneWidget);
    expect(patches, 1);
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();
    expect(patches, 2);
    expect(find.textContaining('수정됨'), findsOneWidget);
  });

  testWidgets('사진 확대 중 삭제 이벤트를 받으면 확대 창에서도 사진을 숨긴다', (tester) async {
    final socket = await images.mountImages(
      tester,
      MockClient((request) async {
        if (request.url.path.endsWith('/refresh')) {
          return fixture.page([deleted()]);
        }
        if (request.url.path.endsWith('/image')) {
          return http.Response.bytes(photo, 200);
        }
        return fixture.page([images.imageMessage(null)]);
      }),
    );
    await tester.tap(
      find.descendant(
        of: find.byType(ChatImageView),
        matching: find.byType(InkWell),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsOneWidget);
    socket.emit({'type': 'message', 'action': 'deleted', 'message': deleted()});
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsNothing);
    expect(
      find.descendant(
        of: find.byType(Dialog),
        matching: find.text('삭제된 메시지입니다.'),
      ),
      findsOneWidget,
    );
  });

  test('재연결 시 이미 조회한 ID를 refresh로 갱신하고 새 메시지도 복구한다', () async {
    var refreshes = 0;
    final harness = fixture.Harness(
      client: MockClient((request) async {
        if (request.url.path.endsWith('/refresh')) {
          refreshes++;
          expect(jsonDecode(request.body), {
            'family_room_id': 'room-a',
            'message_ids': [1, 2],
          });
          return fixture.page([edited(seq: 1), deleted(seq: 2)]);
        }
        if (request.url.queryParameters['after_id'] == '2') {
          return fixture.page([fixture.message(3)]);
        }
        return fixture.page([fixture.message(2), fixture.message(1)]);
      }),
    );
    addTearDown(harness.dispose);
    await harness.connected();
    harness.vm.reconnect();
    await harness.connected();
    expect(refreshes, 1);
    expect(harness.state.messages.map((item) => item.seq), [1, 2, 3]);
    expect(harness.state.messages[0].content, '수정한 내용');
    expect(harness.state.messages[1].isDeleted, isTrue);
  });

  test('늦은 수정 HTTP 응답과 과거 페이지가 삭제된 메시지를 복원하지 않는다', () async {
    final patch = Completer<http.Response>();
    final started = Completer<void>();
    final older = Completer<http.Response>();
    final harness = fixture.Harness(
      imageContext: true,
      client: MockClient((request) async {
        if (request.method == 'PATCH') {
          started.complete();
          return patch.future;
        }
        if (request.url.path.endsWith('/refresh')) {
          return fixture.page([deleted()]);
        }
        if (request.url.queryParameters.containsKey('before_id')) {
          return older.future;
        }
        return fixture.page([fixture.message(7)], more: true);
      }),
    );
    addTearDown(harness.dispose);
    await harness.connected();
    final first = harness.state.messages.single;
    final changing = harness.vm.updateMessage(first, '수정한 내용');
    await started.future;
    final loading = harness.vm.loadOlder();
    harness.sockets.single.emit({
      'type': 'message',
      'action': 'deleted',
      'message': deleted(),
    });
    await harness.waitFor(() => harness.state.messages.single.isDeleted);
    patch.complete(changed(edited()));
    older.complete(fixture.page([fixture.message(7), fixture.message(6)]));
    await changing;
    await loading;
    expect(harness.state.messages.last.isDeleted, isTrue);
    expect(harness.state.messages.last.content, '삭제된 메시지입니다.');
    expect(harness.state.changing, isEmpty);
  });

  test('변경 요청 토큰 대기 중 계정이 바뀌면 전송하지 않는다', () async {
    final token = Completer<String?>();
    var waiting = false;
    var patches = 0;
    final harness = fixture.Harness(
      imageContext: true,
      token: () => waiting ? token.future : Future.value('id-token'),
      client: MockClient((request) async {
        if (request.method == 'PATCH') patches++;
        return fixture.page([fixture.message(7)]);
      }),
    );
    addTearDown(harness.dispose);
    await harness.connected();
    waiting = true;
    final saving = harness.vm.updateMessage(
      harness.state.messages.single,
      '수정한 내용',
    );
    final assertion = expectLater(saving, throwsA(isA<ChatFailure>()));
    harness.container
        .read(fixture.testTokenProvider.notifier)
        .setToken('new-token');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    token.complete('id-token');
    await assertion;
    expect(patches, 0);
  });

  test('재연결 시 기존 메시지는 최대 100개씩 나누어 갱신한다', () async {
    final sizes = <int>[];
    final harness = fixture.Harness(
      client: MockClient((request) async {
        if (request.url.path.endsWith('/refresh')) {
          final ids = (jsonDecode(request.body)['message_ids'] as List)
              .cast<int>();
          sizes.add(ids.length);
          return fixture.page(ids.map((id) => fixture.message(id)).toList());
        }
        if (request.url.queryParameters.containsKey('after_id')) {
          return fixture.page([]);
        }
        return fixture.page(List.generate(205, (i) => fixture.message(i + 1)));
      }),
    );
    addTearDown(harness.dispose);
    await harness.connected();
    harness.vm.reconnect();
    await harness.connected();
    expect(sizes, [100, 100, 5]);
    expect(harness.state.messages.length, 205);
  });
}
