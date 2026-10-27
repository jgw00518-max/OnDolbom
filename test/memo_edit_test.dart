import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ondolbom/model/memos/memo.dart';
import 'package:ondolbom/view/memos/memo_form_view.dart';
import 'package:ondolbom/view/memos/memo_list_view.dart';
import 'package:ondolbom/vm/family_room/family_context.dart';
import 'package:ondolbom/vm/memos/memo_vm.dart';

import 'memo_test.dart' as fixture;

Future<void> openDetail(WidgetTester tester) async {
  await tester.tap(find.text('기존 내용'));
  await tester.pumpAndSettle();
}

Future<void> openEdit(WidgetTester tester) async {
  await openDetail(tester);
  await tester.tap(find.text('수정'));
  await tester.pumpAndSettle();
}

Future<void> saveEdit(WidgetTester tester) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  await tester.ensureVisible(find.text('수정 저장'));
  await tester.tap(find.text('수정 저장'));
}

final testContextProvider = NotifierProvider<TestContext, MemoContext>(
  TestContext.new,
);

class TestContext extends Notifier<MemoContext> {
  @override
  MemoContext build() => fixture.selected;

  void change(MemoContext value) => state = value;
}

void main() {
  testWidgets('작성자는 수정 후 상세·목록과 재수정 입력창에서 저장한 내용을 본다', (tester) async {
    var content = '기존 내용';
    var patches = 0;
    await fixture.mount(
      tester,
      MockClient((request) async {
        expect(request.headers['Authorization'], 'Bearer test-token');
        if (request.method == 'PATCH') {
          patches++;
          expect(request.url.path, '/memos/update/memo-1');
          expect(jsonDecode(request.body), {
            'family_room_id': 'room-a',
            'memo_content': '수정된 내용',
          });
          content = '수정된 내용';
          return http.Response('{"result":"OK","memo_id":"memo-1"}', 200);
        }
        expect(request.method, 'GET');
        return fixture.listResponse([fixture.memoJson('memo-1', content)]);
      }),
    );
    await openEdit(tester);
    expect(
      tester.widget<TextFormField>(find.byType(TextFormField)).controller!.text,
      '기존 내용',
    );
    await tester.enterText(find.byType(TextFormField), '  수정된 내용  ');
    await saveEdit(tester);
    await tester.pumpAndSettle();
    expect(patches, 1);
    expect(find.byType(MemoFormView), findsNothing);
    expect(find.text('수정된 내용'), findsOneWidget);
    await tester.tap(find.text('수정'));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextFormField>(find.byType(TextFormField)).controller!.text,
      '수정된 내용',
    );
    // 변경하지 않고 뒤로 가면 취소 확인 없이 상세로 돌아간다.
    await tester.tap(find.byTooltip('이전 화면'));
    await tester.pumpAndSettle();
    expect(find.text('수정을 취소할까요?'), findsNothing);
    await tester.tap(find.byTooltip('이전 화면'));
    await tester.pumpAndSettle();
    expect(find.text('수정된 내용'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('다른 작성자의 메모에는 수정·삭제 버튼이 없다', (tester) async {
    await fixture.mount(
      tester,
      MockClient(
        (_) async => fixture.listResponse([
          {...fixture.memoJson('memo-1', '기존 내용'), 'user_id': 'other-user'},
        ]),
      ),
    );
    await openDetail(tester);
    expect(find.text('수정'), findsNothing);
    expect(find.text('삭제'), findsNothing);
  });

  testWidgets('수정은 빈 내용 검증·중복 저장 방지·실패 후 재시도를 지원한다', (tester) async {
    final pending = Completer<http.Response>();
    var patches = 0;
    await fixture.mount(
      tester,
      MockClient((request) async {
        if (request.method == 'PATCH') {
          patches++;
          if (patches == 1) return pending.future;
          return http.Response('{"result":"OK"}', 200);
        }
        return fixture.listResponse([fixture.memoJson('memo-1', '기존 내용')]);
      }),
    );
    await openEdit(tester);
    await tester.enterText(find.byType(TextFormField), '   ');
    await saveEdit(tester);
    await tester.pumpAndSettle();
    expect(find.text('메모 내용을 입력해 주세요.'), findsOneWidget);
    expect(patches, 0);
    await tester.enterText(find.byType(TextFormField), '변경한 내용');
    await saveEdit(tester);
    await tester.pump();
    await tester.tap(find.text('저장 중…'));
    expect(patches, 1);
    expect(
      tester.widget<TextFormField>(find.byType(TextFormField)).enabled,
      isFalse,
    );
    pending.complete(http.Response('{"detail":"server error"}', 500));
    await tester.pumpAndSettle();
    expect(find.text('변경한 내용'), findsOneWidget);
    expect(find.text('수정 저장'), findsOneWidget);
    await saveEdit(tester);
    await tester.pumpAndSettle();
    expect(patches, 2);
    expect(find.byType(MemoFormView), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('변경한 내용의 취소는 확인하며 원본을 유지한다', (tester) async {
    var mutations = 0;
    await fixture.mount(
      tester,
      MockClient((request) async {
        if (request.method != 'GET') mutations++;
        return fixture.listResponse([fixture.memoJson('memo-1', '기존 내용')]);
      }),
    );
    await openEdit(tester);
    await tester.enterText(find.byType(TextFormField), '수정 중');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('이전 화면'));
    await tester.pumpAndSettle();
    expect(find.text('수정을 취소할까요?'), findsOneWidget);
    await tester.tap(find.text('계속 수정'));
    await tester.pumpAndSettle();
    expect(find.text('수정 중'), findsOneWidget);
    await tester.tap(find.byTooltip('이전 화면'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('수정 취소'));
    await tester.pumpAndSettle();
    expect(find.text('기존 내용'), findsOneWidget);
    expect(mutations, 0);
  });

  testWidgets('삭제 취소는 요청하지 않고 삭제 성공 후 목록에서 제거한다', (tester) async {
    var deleted = false;
    var deletes = 0;
    await fixture.mount(
      tester,
      MockClient((request) async {
        if (request.method == 'DELETE') {
          deletes++;
          expect(request.url.path, '/memos/delete/memo-1');
          expect(request.url.queryParameters, {'family_room_id': 'room-a'});
          expect(request.headers['Authorization'], 'Bearer test-token');
          deleted = true;
          return http.Response('{"result":"OK"}', 200);
        }
        return fixture.listResponse(
          deleted ? [] : [fixture.memoJson('memo-1', '기존 내용')],
        );
      }),
    );
    await openDetail(tester);
    await tester.tap(find.text('삭제'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(deletes, 0);
    await tester.tap(find.text('삭제'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('삭제하기'));
    await tester.pumpAndSettle();
    expect(deletes, 1);
    expect(find.byType(MemoDetailView), findsNothing);
    expect(find.text('아직 작성된 메모가 없어요'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('삭제 실패 시 상세를 유지하고 재시도하며 중복 요청을 막는다', (tester) async {
    final pending = Completer<http.Response>();
    var deletes = 0;
    await fixture.mount(
      tester,
      MockClient((request) async {
        if (request.method == 'DELETE') {
          deletes++;
          if (deletes == 1) return pending.future;
          return http.Response('{"result":"OK"}', 200);
        }
        return fixture.listResponse([fixture.memoJson('memo-1', '기존 내용')]);
      }),
    );
    await openDetail(tester);
    await tester.tap(find.text('삭제'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('삭제하기'));
    await tester.pump();
    await tester.tap(find.text('삭제 중…'));
    expect(deletes, 1);
    pending.complete(http.Response('{"detail":"not found"}', 404));
    await tester.pumpAndSettle();
    expect(find.text('기존 내용'), findsOneWidget);
    expect(find.text('not found'), findsOneWidget);
    await tester.tap(find.text('삭제'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('삭제하기'));
    await tester.pumpAndSettle();
    expect(deletes, 2);
    expect(find.byType(MemoDetailView), findsNothing);
  });

  test('VM은 다른 작성자·공간과 토큰 로딩 중 공간 변경의 변경 요청을 차단한다', () async {
    final token = Completer<String?>();
    var mutations = 0;
    var waitToken = false;
    final container = ProviderContainer(
      overrides: [
        memoContextProvider.overrideWith(
          (ref) => ref.watch(testContextProvider),
        ),
        apiTokenLoaderProvider.overrideWithValue(
          () => waitToken ? token.future : Future.value('test-token'),
        ),
        memoHttpClientProvider.overrideWithValue(
          MockClient((request) async {
            if (request.method != 'GET') mutations++;
            return fixture.listResponse([]);
          }),
        ),
      ],
    );
    addTearDown(container.dispose);
    final provider = memoVmProvider(fixture.selected);
    final subscription = container.listen(provider, (_, _) {});
    addTearDown(subscription.close);
    await container.read(provider.future);
    final vm = container.read(provider.notifier);
    for (final fields in [
      {'user_id': 'other-user'},
      {'family_room_id': 'room-b'},
    ]) {
      final memo = Memo.fromJson({
        ...fixture.memoJson('memo-1', '내용'),
        ...fields,
      });
      await expectLater(vm.updateMemo(memo, '변경'), throwsA(isA<MemoFailure>()));
      await expectLater(vm.deleteMemo(memo), throwsA(isA<MemoFailure>()));
    }
    waitToken = true;
    final pending = vm.deleteMemo(
      Memo.fromJson(fixture.memoJson('memo-1', '내용')),
    );
    final assertion = expectLater(pending, throwsA(isA<MemoFailure>()));
    container.read(testContextProvider.notifier).change((
      familyRoomId: 'room-b',
      userId: 'user-b',
      roomName: '다른 공간',
    ));
    token.complete('test-token');
    await assertion;
    expect(mutations, 0);
  });
}
