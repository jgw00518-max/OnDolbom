import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ondolbom/main.dart';
import 'package:ondolbom/model/memos/memo.dart';
import 'package:ondolbom/vm/auth/auth_vm.dart';
import 'package:ondolbom/vm/family_room/family_context.dart';
import 'package:ondolbom/view/memos/memo_list_view.dart';
import 'package:ondolbom/view/memos/memo_form_view.dart';
import 'package:ondolbom/vm/memos/memo_vm.dart';

const selected = (
  familyRoomId: 'room-a',
  userId: 'user-a',
  roomName: '김정희 님의 돌봄 공간',
);
Map<String, dynamic> memoJson(String id, String text) => {
  'memo_id': id,
  'family_room_id': 'room-a',
  'user_id': 'user-a',
  'memo_content': text,
  'likes': 0,
  'written_at': '2026-10-23T18:30:00',
  'memo_updated_at': null,
};
http.Response listResponse(List<Map<String, dynamic>> memos) => http.Response(
  jsonEncode({'results': memos}),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Future<void> mount(WidgetTester tester, http.Client client) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        apiTokenLoaderProvider.overrideWithValue(() async => 'test-token'),
        authUserProvider.overrideWith((ref) => Stream.value(null)),
        memoContextProvider.overrideWithValue(selected),
        memoHttpClientProvider.overrideWithValue(client),
      ],
      child: Consumer(
        builder: (context, ref, _) {
          final app = const MyApp().build(context, ref) as MaterialApp;
          return MaterialApp(theme: app.theme, home: const MemoListView());
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('줄바꿈으로 3줄을 넘는 메모는 말줄임표를 표시하고 상세는 원문을 유지한다', (tester) async {
    const content = '1\n2\n3\n4\n5';
    await mount(
      tester,
      MockClient((_) async => listResponse([memoJson('multiline', content)])),
    );
    expect(find.text('1\n2\n3…'), findsOneWidget);
    await tester.tap(find.text('1\n2\n3…'));
    await tester.pumpAndSettle();
    expect(find.text(content), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('정확히 3줄인 메모에는 말줄임표를 붙이지 않는다', (tester) async {
    const content = '1\n2\n3';
    await mount(
      tester,
      MockClient((_) async => listResponse([memoJson('three-lines', content)])),
    );
    expect(find.text(content), findsOneWidget);
    expect(find.text('1\n2\n3…'), findsNothing);
  });

  test('작성자 이름은 공백을 제거하고 없는 경우 ID 대신 기본 문구를 사용한다', () {
    for (final name in [null, '', '   ']) {
      final memo = Memo.fromJson({...memoJson('1', '내용'), 'author_name': name});
      expect(memo.authorLabel, '이름 없는 가족');
      expect(memo.userId, 'user-a');
    }
    final memo = Memo.fromJson({
      ...memoJson('1', '내용'),
      'author_name': '  김가족  ',
    });
    expect(memo.authorLabel, '김가족');
    expect(memo.toJson()['author_name'], '  김가족  ');
  });

  testWidgets('내 메모와 다른 가족 메모의 목록·상세에 작성자 이름을 표시한다', (tester) async {
    await mount(
      tester,
      MockClient(
        (_) async => listResponse([
          {...memoJson('mine', '내 메모'), 'author_name': '김본인'},
          {
            ...memoJson('other', '가족 메모'),
            'user_id': 'other-user-id',
            'author_name': '이가족',
          },
        ]),
      ),
    );
    expect(find.text('김본인'), findsOneWidget);
    expect(find.text('이가족'), findsOneWidget);
    expect(find.textContaining('other-user-id'), findsNothing);
    await tester.tap(find.text('가족 메모'));
    await tester.pumpAndSettle();
    expect(find.text('메모 상세'), findsOneWidget);
    expect(find.text('이가족'), findsOneWidget);
    expect(find.textContaining('other-user-id'), findsNothing);
  });

  testWidgets('목록에서 상세를 열고 메모를 작성하면 목록을 다시 조회한다', (tester) async {
    var saved = false;
    var posts = 0;
    final client = MockClient((request) async {
      expect(request.headers['Authorization'], 'Bearer test-token');
      if (request.method == 'POST') {
        posts++;
        expect(jsonDecode(request.body), {
          'family_room_id': 'room-a',
          'memo_content': '오늘도 함께 돌봐요.',
        });
        saved = true;
        return http.Response('{"result":"OK","memo_id":"new"}', 201);
      }
      expect(request.url.queryParameters['family_room_id'], 'room-a');
      return listResponse([
        if (saved) memoJson('new', '오늘도 함께 돌봐요.'),
        memoJson('old', '따뜻한 보리차를 좋아하세요. 식사 후 한 잔 부탁드려요.'),
      ]);
    });
    await mount(tester, client);
    expect(find.textContaining('따뜻한 보리차'), findsOneWidget);

    await tester.tap(find.textContaining('따뜻한 보리차'));
    await tester.pumpAndSettle();
    expect(find.text('메모 상세'), findsOneWidget);

    await tester.tap(find.byTooltip('이전 화면'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('메모 쓰기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('메모 등록'));
    await tester.pumpAndSettle();
    expect(find.text('메모 내용을 입력해 주세요.'), findsOneWidget);
    expect(posts, 0);
    await tester.enterText(find.byType(TextFormField), '오늘도 함께 돌봐요.');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();

    await tester.tap(find.text('메모 등록'));
    await tester.pumpAndSettle();
    expect(posts, 1);
    expect(find.byType(MemoFormView), findsNothing);
    expect(find.text('오늘도 함께 돌봐요.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('작성 실패 시 내용을 보존하고 다시 등록할 수 있다', (tester) async {
    final result = Completer<http.Response>();
    var posts = 0;
    await mount(
      tester,
      MockClient((request) async {
        if (request.method == 'GET') return listResponse([]);
        posts++;
        return result.future;
      }),
    );
    await tester.tap(find.byTooltip('메모 쓰기'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '저장할 내용');
    await tester.tap(find.text('메모 등록'));
    await tester.pump();
    await tester.tap(find.text('등록 중…'));
    expect(posts, 1);
    result.complete(
      http.Response(
        jsonEncode({'detail': '작성 권한이 없습니다.'}),
        403,
        headers: {'content-type': 'application/json; charset=utf-8'},
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('이 공간의 메모에 접근할 수 없어요.'), findsOneWidget);
    expect(find.text('저장할 내용'), findsOneWidget);
    expect(find.text('메모 등록'), findsOneWidget);
  });

  testWidgets('목록 연결 실패 후 재시도한다', (tester) async {
    var fail = true;
    await mount(
      tester,
      MockClient((_) async {
        if (fail) throw http.ClientException('offline');
        return listResponse([]);
      }),
    );
    expect(find.text('메모를 불러오지 못했어요'), findsOneWidget);
    fail = false;
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();
    expect(find.text('아직 작성된 메모가 없어요'), findsOneWidget);
  });

  testWidgets('작은 화면에서 작성 취소 시 입력 유실을 확인한다', (tester) async {
    await mount(tester, MockClient((_) async => listResponse([])));
    tester.view.physicalSize = const Size(320, 640);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('메모 쓰기'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField), '작성 중인 내용');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('취소'));
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(find.text('작성을 취소할까요?'), findsOneWidget);
    await tester.tap(find.text('계속 작성'));
    await tester.pumpAndSettle();
    expect(find.text('작성 중인 내용'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  test('서로 다른 공간의 메모 상태는 분리된다', () async {
    const other = (familyRoomId: 'room-b', userId: 'user-a', roomName: '다른 공간');
    final container = ProviderContainer(
      overrides: [
        apiTokenLoaderProvider.overrideWithValue(() async => 'test-token'),
        authUserProvider.overrideWith((ref) => Stream.value(null)),
        memoHttpClientProvider.overrideWithValue(
          MockClient((request) async {
            final room = request.url.queryParameters['family_room_id']!;
            return listResponse([
              {...memoJson(room, room), 'family_room_id': room},
            ]);
          }),
        ),
      ],
    );
    addTearDown(container.dispose);
    final a = container.listen(memoVmProvider(selected), (_, _) {});
    final b = container.listen(memoVmProvider(other), (_, _) {});
    addTearDown(a.close);
    addTearDown(b.close);
    final first = await container.read(memoVmProvider(selected).future);
    final second = await container.read(memoVmProvider(other).future);
    expect(first.items.single.familyRoomId, 'room-a');
    expect(second.items.single.familyRoomId, 'room-b');
  });

  test('페이지 추가 조회는 공간 ID와 다음 offset을 전달한다', () async {
    final offsets = <String?>[];
    final container = ProviderContainer(
      overrides: [
        apiTokenLoaderProvider.overrideWithValue(() async => 'test-token'),
        authUserProvider.overrideWith((ref) => Stream.value(null)),
        memoHttpClientProvider.overrideWithValue(
          MockClient((request) async {
            offsets.add(request.url.queryParameters['offset']);
            expect(request.url.queryParameters['family_room_id'], 'room-a');
            return listResponse(
              offsets.length == 1
                  ? List.generate(20, (i) => memoJson('$i', '메모 $i'))
                  : [memoJson('20', '이전 메모')],
            );
          }),
        ),
      ],
    );
    addTearDown(container.dispose);
    final provider = memoVmProvider(selected);
    final subscription = container.listen(provider, (_, _) {});
    addTearDown(subscription.close);
    await container.read(provider.future);
    await container.read(provider.notifier).loadMore();
    expect(offsets, ['0', '20']);
    expect(container.read(provider).requireValue.items.length, 21);
    expect(container.read(provider).requireValue.hasMore, false);
  });
}
