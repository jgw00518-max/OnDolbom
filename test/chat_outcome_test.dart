import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ondolbom/vm/chats/chat_vm.dart';

import 'chat_test.dart' as fixture;
import 'chat_image_test.dart' as images;
import 'chat_mutation_test.dart' as mutations;

void main() {
  for (final deleting in [false, true]) {
    final name = deleting ? '삭제' : '수정';
    final desired = deleting ? mutations.deleted() : mutations.edited();

    test('$name 완료 이벤트를 받은 뒤 HTTP 응답이 유실돼도 성공 처리한다', () async {
      final response = Completer<http.Response>();
      final started = Completer<void>();
      var writes = 0;
      final harness = fixture.Harness(
        imageContext: true,
        client: MockClient((request) async {
          if (request.method == 'PATCH' || request.method == 'DELETE') {
            writes++;
            started.complete();
            return response.future;
          }
          if (request.url.path.endsWith('/refresh')) {
            return fixture.page([desired]);
          }
          return fixture.page([fixture.message(7)]);
        }),
      );
      addTearDown(harness.dispose);
      await harness.connected();
      final original = harness.state.messages.single;
      final saving = deleting
          ? harness.vm.deleteMessage(original)
          : harness.vm.updateMessage(original, '수정한 내용');
      await started.future;
      harness.sockets.single.emit({
        'type': 'message',
        'action': deleting ? 'deleted' : 'updated',
        'message': desired,
      });
      await harness.waitFor(
        () => deleting
            ? harness.state.messages.single.isDeleted
            : harness.state.messages.single.content == '수정한 내용',
      );
      response.completeError(http.ClientException('HTTP response lost'));
      await saving;
      expect(writes, 1);
      expect(harness.state.changing, isEmpty);
      expect(harness.state.messages.single.content, desired['chat_content']);
    });

    test('$name 이벤트가 없어도 refresh로 요청한 최종 상태를 확인하면 성공 처리한다', () async {
      var writes = 0;
      var reads = 0;
      final harness = fixture.Harness(
        imageContext: true,
        client: MockClient((request) async {
          if (request.method == 'PATCH' || request.method == 'DELETE') {
            writes++;
            throw TimeoutException('HTTP response timed out');
          }
          if (request.url.path.endsWith('/refresh')) {
            reads++;
            expect(jsonDecode(request.body), {
              'family_room_id': 'room-a',
              'message_ids': [7],
            });
            return fixture.page([desired]);
          }
          return fixture.page([fixture.message(7)]);
        }),
      );
      addTearDown(harness.dispose);
      await harness.connected();
      final original = harness.state.messages.single;
      await (deleting
          ? harness.vm.deleteMessage(original)
          : harness.vm.updateMessage(original, '수정한 내용'));
      expect(writes, 1);
      expect(reads, 1);
      expect(harness.state.messages.single.content, desired['chat_content']);
    });

    test('$name 요청과 재조회가 모두 실패하면 결과 불확실로 구분하고 자동 재전송하지 않는다', () async {
      var writes = 0;
      var reads = 0;
      final harness = fixture.Harness(
        imageContext: true,
        client: MockClient((request) async {
          if (request.method == 'PATCH' || request.method == 'DELETE') {
            writes++;
            throw http.ClientException('write response lost');
          }
          if (request.url.path.endsWith('/refresh')) {
            reads++;
            throw http.ClientException('read unavailable');
          }
          return fixture.page([fixture.message(7)]);
        }),
      );
      addTearDown(harness.dispose);
      await harness.connected();
      final original = harness.state.messages.single;
      await expectLater(
        deleting
            ? harness.vm.deleteMessage(original)
            : harness.vm.updateMessage(original, '수정한 내용'),
        throwsA(isA<ChatOutcomeUnknown>()),
      );
      expect(writes, 1);
      expect(reads, 1);
      expect(harness.state.messages.single.content, original.content);
      expect(harness.state.messages.single.isDeleted, isFalse);
      expect(harness.state.changing, isEmpty);
    });
  }

  test('재조회한 상태가 요청한 수정과 다르면 최신 상태를 반영하고 성공 처리하지 않는다', () async {
    final harness = fixture.Harness(
      imageContext: true,
      client: MockClient((request) async {
        if (request.method == 'PATCH') throw http.ClientException('lost');
        if (request.url.path.endsWith('/refresh')) {
          return fixture.page([
            {...mutations.edited(), 'chat_content': '다른 기기에서 수정한 내용'},
          ]);
        }
        return fixture.page([fixture.message(7)]);
      }),
    );
    addTearDown(harness.dispose);
    await harness.connected();
    await expectLater(
      harness.vm.updateMessage(harness.state.messages.single, '수정한 내용'),
      throwsA(
        isA<ChatFailure>().having(
          (error) => error.message,
          'message',
          contains('최신 상태'),
        ),
      ),
    );
    expect(harness.state.messages.single.content, '다른 기기에서 수정한 내용');
  });

  for (final status in [401, 403, 422]) {
    test('$status 응답은 재조회하거나 성공으로 바꾸지 않고 그대로 안내한다', () async {
      final response = Completer<http.Response>();
      final started = Completer<void>();
      var reads = 0;
      final harness = fixture.Harness(
        imageContext: true,
        client: MockClient((request) async {
          if (request.method == 'PATCH') {
            started.complete();
            return response.future;
          }
          if (request.url.path.endsWith('/refresh')) {
            reads++;
            return fixture.page([mutations.edited()]);
          }
          return fixture.page([fixture.message(7)]);
        }),
      );
      addTearDown(harness.dispose);
      await harness.connected();
      final saving = harness.vm.updateMessage(
        harness.state.messages.single,
        '수정한 내용',
      );
      final assertion = expectLater(
        saving,
        throwsA(isA<ChatFailure>().having((e) => e.status, 'status', status)),
      );
      await started.future;
      harness.sockets.single.emit({
        'type': 'message',
        'message': mutations.edited(),
      });
      await harness.waitFor(
        () => harness.state.messages.single.updatedAt != null,
      );
      response.complete(http.Response('non-JSON error', status));
      await assertion;
      expect(reads, 0);
    });
  }

  test('재조회가 권한 오류면 이전 이벤트로 성공 처리하지 않는다', () async {
    final pending = Completer<http.Response>();
    final started = Completer<void>();
    final harness = fixture.Harness(
      imageContext: true,
      client: MockClient((request) async {
        if (request.method == 'PATCH') throw http.ClientException('lost');
        if (request.url.path.endsWith('/refresh')) {
          started.complete();
          return pending.future;
        }
        return fixture.page([fixture.message(7)]);
      }),
    );
    addTearDown(harness.dispose);
    await harness.connected();
    final saving = harness.vm.updateMessage(
      harness.state.messages.single,
      '수정한 내용',
    );
    final assertion = expectLater(
      saving,
      throwsA(isA<ChatFailure>().having((e) => e.status, 'status', 403)),
    );
    await started.future;
    harness.sockets.single.emit({
      'type': 'message',
      'message': mutations.edited(),
    });
    await harness.waitFor(
      () => harness.state.messages.single.updatedAt != null,
    );
    pending.complete(http.Response('denied', 403));
    await assertion;
    expect(harness.state.status, ChatStatus.blocked);
  });

  test('재조회도 실패했지만 대기 중 도착한 실시간 결과가 일치하면 성공 처리한다', () async {
    final pending = Completer<http.Response>();
    final started = Completer<void>();
    final harness = fixture.Harness(
      imageContext: true,
      client: MockClient((request) async {
        if (request.method == 'PATCH') throw http.ClientException('lost');
        if (request.url.path.endsWith('/refresh')) {
          started.complete();
          return pending.future;
        }
        return fixture.page([fixture.message(7)]);
      }),
    );
    addTearDown(harness.dispose);
    await harness.connected();
    final saving = harness.vm.updateMessage(
      harness.state.messages.single,
      '수정한 내용',
    );
    await started.future;
    harness.sockets.single.emit({
      'type': 'message',
      'message': mutations.edited(),
    });
    await harness.waitFor(
      () => harness.state.messages.single.updatedAt != null,
    );
    pending.completeError(http.ClientException('read failed'));
    await saving;
    expect(harness.state.changing, isEmpty);
  });

  test('결과 확인 중 계정이 바뀌면 이전 계정의 성공 결과를 적용하지 않는다', () async {
    final pending = Completer<http.Response>();
    final started = Completer<void>();
    final harness = fixture.Harness(
      imageContext: true,
      client: MockClient((request) async {
        if (request.method == 'PATCH') throw http.ClientException('lost');
        if (request.url.path.endsWith('/refresh')) {
          started.complete();
          return pending.future;
        }
        return fixture.page([fixture.message(7)]);
      }),
    );
    addTearDown(harness.dispose);
    await harness.connected();
    final saving = harness.vm.updateMessage(
      harness.state.messages.single,
      '수정한 내용',
    );
    final assertion = expectLater(saving, throwsA(isA<ChatFailure>()));
    await started.future;
    harness.container
        .read(fixture.testTokenProvider.notifier)
        .setToken('new-token');
    await Future<void>.delayed(const Duration(milliseconds: 5));
    pending.complete(fixture.page([mutations.edited()]));
    await assertion;
    await harness.connected();
    expect(harness.state.messages.single.content, '저장된 대화');
  });

  for (final response in [
    http.Response('proxy error', 502),
    http.Response('{}', 200),
  ]) {
    test('불확실한 HTTP ${response.statusCode} 응답도 재조회로 성공 여부를 확인한다', () async {
      final harness = fixture.Harness(
        imageContext: true,
        client: MockClient((request) async {
          if (request.method == 'PATCH') return response;
          if (request.url.path.endsWith('/refresh')) {
            return fixture.page([mutations.edited()]);
          }
          return fixture.page([fixture.message(7)]);
        }),
      );
      addTearDown(harness.dispose);
      await harness.connected();
      await harness.vm.updateMessage(harness.state.messages.single, '수정한 내용');
      expect(harness.state.messages.single.content, '수정한 내용');
    });
  }

  testWidgets('결과를 확인할 수 없으면 수정창과 입력 내용을 유지한다', (tester) async {
    var writes = 0;
    await images.mountImages(
      tester,
      MockClient((request) async {
        if (request.method == 'PATCH') {
          writes++;
          throw http.ClientException('lost');
        }
        if (request.url.path.endsWith('/refresh')) {
          throw http.ClientException('read failed');
        }
        return fixture.page([fixture.message(7)]);
      }),
    );
    await mutations.menu(tester, '수정');
    await tester.enterText(
      find.byKey(const ValueKey('chat-edit-input')),
      '유지할 수정 내용',
    );
    await tester.tap(find.text('저장'));
    await tester.pumpAndSettle();
    expect(find.text('변경 결과를 확인하지 못했습니다. 다시 연결해 확인해 주세요.'), findsOneWidget);
    expect(find.text('유지할 수정 내용'), findsOneWidget);
    expect(find.text('메시지 수정'), findsOneWidget);
    expect(writes, 1);
  });

  testWidgets('수정 완료 이벤트 뒤 응답이 유실되어도 수정창을 정상적으로 닫는다', (tester) async {
    final pending = Completer<http.Response>();
    final started = Completer<void>();
    final socket = await images.mountImages(
      tester,
      MockClient((request) async {
        if (request.method == 'PATCH') {
          started.complete();
          return pending.future;
        }
        if (request.url.path.endsWith('/refresh')) {
          return fixture.page([mutations.edited()]);
        }
        return fixture.page([fixture.message(7)]);
      }),
    );
    await mutations.menu(tester, '수정');
    await tester.enterText(
      find.byKey(const ValueKey('chat-edit-input')),
      '수정한 내용',
    );
    await tester.tap(find.text('저장'));
    await tester.pump();
    await started.future;
    socket.emit({'type': 'message', 'message': mutations.edited()});
    await tester.pump();
    pending.completeError(http.ClientException('lost'));
    await tester.pumpAndSettle();
    expect(find.text('메시지 수정'), findsNothing);
    expect(find.text('수정한 내용'), findsOneWidget);
    expect(find.textContaining('수정됨'), findsOneWidget);
  });

  test('요청 전 캐시가 같은 내용이어도 서버 확인이 없으면 성공으로 추정하지 않는다', () async {
    final harness = fixture.Harness(
      imageContext: true,
      client: MockClient((request) async {
        if (request.method != 'GET') throw http.ClientException('unavailable');
        return fixture.page([fixture.message(7)]);
      }),
    );
    addTearDown(harness.dispose);
    await harness.connected();
    final original = harness.state.messages.single;
    await expectLater(
      harness.vm.updateMessage(original, original.content),
      throwsA(isA<ChatOutcomeUnknown>()),
    );
  });

  test('요청을 보내기 전 토큰 로딩이 실패하면 저장 결과 확인을 시도하지 않는다', () async {
    var tokenFails = false;
    var requests = 0;
    final harness = fixture.Harness(
      imageContext: true,
      token: () async {
        if (tokenFails) throw TimeoutException('token unavailable');
        return 'id-token';
      },
      client: MockClient((request) async {
        requests++;
        return fixture.page([fixture.message(7)]);
      }),
    );
    addTearDown(harness.dispose);
    await harness.connected();
    final before = requests;
    tokenFails = true;
    await expectLater(
      harness.vm.updateMessage(harness.state.messages.single, '수정한 내용'),
      throwsA(isA<ChatFailure>()),
    );
    expect(requests, before);
  });
}
