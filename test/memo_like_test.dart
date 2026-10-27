import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ondolbom/model/memos/memo.dart';
import 'package:ondolbom/view/memos/memo_list_view.dart';
import 'package:ondolbom/vm/family_room/family_context.dart';
import 'package:ondolbom/vm/memos/memo_vm.dart';

import 'memo_test.dart' as fixture;
import 'memo_edit_test.dart' show testContextProvider;

Map<String, dynamic> memo({bool liked = false}) => {
  ...fixture.memoJson('memo-1', '가족 메모'),
  'user_id': 'author-a',
  'likes': 2,
  'is_liked': liked ? 1 : 0,
};

http.Response success({bool repeated = false}) => http.Response(
  jsonEncode({
    'result': 'OK',
    'memo_id': 'memo-1',
    'likes': 3,
    'is_liked': true,
    'already_liked': repeated,
  }),
  200,
);

void main() {
  testWidgets('목록에서 좋아요를 누르면 상세 이동 없이 등록하고 상세·목록이 같은 상태를 표시한다', (tester) async {
    var posts = 0;
    await fixture.mount(
      tester,
      MockClient((request) async {
        if (request.method == 'POST') {
          posts++;
          expect(request.url.path, '/memos/like/memo-1');
          expect(request.headers['Authorization'], 'Bearer test-token');
          expect(jsonDecode(request.body), {
            'family_room_id': 'room-a',
            'author_user_id': 'author-a',
          });
          return success();
        }
        return fixture.listResponse([memo()]);
      }),
    );
    await tester.tap(find.text('좋아요 2'));
    await tester.pumpAndSettle();
    expect(posts, 1);
    expect(find.byType(MemoDetailView), findsNothing);
    expect(find.text('좋아요 3'), findsOneWidget);
    expect(find.byIcon(Icons.favorite), findsOneWidget);
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, '좋아요 3'))
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('가족 메모'));
    await tester.pumpAndSettle();
    expect(find.text('좋아요 3'), findsOneWidget);
    await tester.tap(find.text('좋아요 3'));
    await tester.pumpAndSettle();
    expect(posts, 1);
    expect(tester.takeException(), isNull);
  });

  testWidgets('상세에서 등록한 좋아요는 뒤로 돌아간 목록에도 반영된다', (tester) async {
    var posts = 0;
    await fixture.mount(
      tester,
      MockClient((request) async {
        if (request.method == 'POST') {
          posts++;
          return success();
        }
        return fixture.listResponse([memo()]);
      }),
    );
    await tester.tap(find.text('가족 메모'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('좋아요 2'));
    await tester.pumpAndSettle();
    expect(find.text('좋아요 3'), findsOneWidget);
    await tester.tap(find.byTooltip('이전 화면'));
    await tester.pumpAndSettle();
    expect(find.text('좋아요 3'), findsOneWidget);
    expect(posts, 1);
  });

  testWidgets('조회 시 이미 누른 메모는 채운 하트와 비활성 버튼을 표시한다', (tester) async {
    var posts = 0;
    await fixture.mount(
      tester,
      MockClient((request) async {
        if (request.method != 'GET') posts++;
        return fixture.listResponse([memo(liked: true)]);
      }),
    );
    expect(find.byIcon(Icons.favorite), findsOneWidget);
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, '좋아요 2'))
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('가족 메모'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, '좋아요 2'))
          .onPressed,
      isNull,
    );
    expect(posts, 0);
  });

  testWidgets('요청 중 중복 클릭을 막고 실패 시 개수를 유지하며 재시도한다', (tester) async {
    final pending = Completer<http.Response>();
    var posts = 0;
    await fixture.mount(
      tester,
      MockClient((request) async {
        if (request.method == 'POST') {
          return ++posts == 1 ? pending.future : success(repeated: true);
        }
        return fixture.listResponse([memo()]);
      }),
    );
    await tester.tap(find.text('가족 메모'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('좋아요 2'));
    await tester.pump();
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, '좋아요 2'))
          .onPressed,
      isNull,
    );
    await tester.tap(find.text('좋아요 2'));
    expect(posts, 1);
    pending.complete(http.Response('{"detail":"save failed"}', 500));
    await tester.pumpAndSettle();
    expect(find.text('좋아요 2'), findsOneWidget);
    expect(find.text('save failed'), findsOneWidget);
    await tester.tap(find.text('좋아요 2'));
    await tester.pumpAndSettle();
    expect(posts, 2);
    expect(find.text('좋아요 3'), findsOneWidget);
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, '좋아요 3'))
          .onPressed,
      isNull,
    );
  });

  test('토큰 대기 중 공간·계정이 바뀌면 좋아요 요청을 전송하지 않는다', () async {
    final token = Completer<String?>();
    var wait = false;
    var posts = 0;
    final container = ProviderContainer(
      overrides: [
        memoContextProvider.overrideWith(
          (ref) => ref.watch(testContextProvider),
        ),
        apiTokenLoaderProvider.overrideWithValue(
          () => wait ? token.future : Future.value('test-token'),
        ),
        memoHttpClientProvider.overrideWithValue(
          MockClient((request) async {
            if (request.method == 'POST') posts++;
            return fixture.listResponse([memo()]);
          }),
        ),
      ],
    );
    addTearDown(container.dispose);
    final provider = memoVmProvider(fixture.selected);
    final subscription = container.listen(provider, (_, _) {});
    addTearDown(subscription.close);
    await container.read(provider.future);
    wait = true;
    final pending = container
        .read(provider.notifier)
        .likeMemo(Memo.fromJson(memo()));
    final assertion = expectLater(pending, throwsA(isA<MemoFailure>()));
    container.read(testContextProvider.notifier).change((
      familyRoomId: 'room-b',
      userId: 'user-b',
      roomName: '다른 공간',
    ));
    token.complete('test-token');
    await assertion;
    expect(posts, 0);
  });

  test('모델은 기존 응답·정수·bool 좋아요 상태를 처리한다', () {
    expect(Memo.fromJson(fixture.memoJson('memo-1', '내용')).isLiked, isFalse);
    for (final value in [true, 1]) {
      final model = Memo.fromJson({...memo(), 'is_liked': value});
      expect(model.isLiked, isTrue);
      expect(model.toJson()['is_liked'], isTrue);
    }
  });
}
