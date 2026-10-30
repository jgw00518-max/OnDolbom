import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ondolbom/model/medications/medication.dart';
import 'package:ondolbom/vm/family_room/family_context.dart';
import 'package:ondolbom/vm/medications/medication_vm.dart';

import 'medication_test.dart' as fixture;
import 'memo_edit_test.dart' show testContextProvider;

const checked = {
  'medication_confirmed_at': '2026-10-26T14:25:03',
  'confirmed_by_user_id': 'checker-a',
  'confirmed_by_name': '김확인',
};
http.Response confirmation({int seq = 42, bool repeated = false}) =>
    http.Response(
      jsonEncode({
        'result': 'OK',
        'medication_log_seq': seq,
        'already_confirmed': repeated,
        ...checked,
      }),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

void main() {
  testWidgets('목록은 체크 이름만 표시하고 상세에서 체크 시간을 확인한다', (tester) async {
    var posts = 0;
    await fixture.mount(
      tester,
      MockClient((request) async {
        if (request.method == 'POST') {
          posts++;
          expect(request.url.path, '/medications/confirm/42');
          expect(request.headers['Authorization'], 'Bearer test-token');
          expect(jsonDecode(request.body), {'family_room_id': 'room-a'});
          return confirmation();
        }
        return fixture.response([fixture.medicationJson(42, '체크할 약')]);
      }),
    );
    expect(find.byTooltip('약 추가'), findsNothing);
    expect(find.text('0/1 완료'), findsOneWidget);
    await tester.tap(find.byTooltip('복약 완료 체크'));
    await tester.pumpAndSettle();
    expect(posts, 1);
    expect(find.text('1/1 완료'), findsOneWidget);
    expect(find.textContaining('체크: 김확인'), findsOneWidget);
    expect(find.textContaining('체크 시간: 오후 2시 25분'), findsNothing);
    expect(
      tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (widget) => widget is IconButton && widget.tooltip == '복약 완료',
            ),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.textContaining('체크할 약'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.textContaining('체크: 김확인'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.textContaining('체크 시간: 오후 2시 25분'),
      ),
      findsOneWidget,
    );
    expect(find.text('복약 완료 체크'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('목록에서 체크한 뒤 상세에서 최초 체크 정보를 확인하며 추가 체크 버튼은 없다', (tester) async {
    await fixture.mount(
      tester,
      MockClient((request) async {
        if (request.method == 'POST') return confirmation(repeated: true);
        return fixture.response([fixture.medicationJson(42, '체크할 약')]);
      }),
    );
    await tester.tap(find.byTooltip('복약 완료 체크'));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('체크할 약'));
    await tester.pumpAndSettle();
    expect(find.text('복약 완료 체크'), findsNothing);
    expect(
      find.descendant(
        of: find.byType(AlertDialog),
        matching: find.textContaining('체크: 김확인'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.text('닫기'));
    await tester.pumpAndSettle();
    expect(find.text('1/1 완료'), findsOneWidget);
    expect(find.textContaining('체크: 김확인'), findsOneWidget);
  });

  testWidgets('체크 중 중복 제출을 막고 실패 시 미완료 상태를 유지하며 재시도한다', (tester) async {
    final pending = Completer<http.Response>();
    var posts = 0;
    await fixture.mount(
      tester,
      MockClient((request) async {
        if (request.method == 'POST') {
          return ++posts == 1 ? pending.future : confirmation();
        }
        return fixture.response([fixture.medicationJson(42, '체크할 약')]);
      }),
    );
    await tester.tap(
      find.byWidgetPredicate(
        (widget) => widget is IconButton && widget.tooltip == '복약 완료 체크',
      ),
    );
    await tester.pump();
    expect(posts, 1);
    expect(
      tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (widget) => widget is IconButton && widget.tooltip == '복약 완료 체크',
            ),
          )
          .onPressed,
      isNull,
    );
    pending.complete(http.Response('{"detail":"check failed"}', 500));
    await tester.pumpAndSettle();
    expect(find.text('0/1 완료'), findsOneWidget);
    expect(find.text('check failed'), findsOneWidget);
    await tester.tap(
      find.byWidgetPredicate(
        (widget) => widget is IconButton && widget.tooltip == '복약 완료 체크',
      ),
    );
    await tester.pumpAndSettle();
    expect(posts, 2);
    expect(find.text('1/1 완료'), findsOneWidget);
  });

  testWidgets('다른 가족이 체크한 기록은 해제할 수 없고 저장된 확인자를 표시한다', (tester) async {
    var posts = 0;
    await fixture.mount(
      tester,
      MockClient((request) async {
        if (request.method != 'GET') posts++;
        return fixture.response([
          {...fixture.medicationJson(42, '완료된 약'), ...checked},
        ]);
      }),
    );
    expect(find.byTooltip('복약 완료 체크'), findsNothing);
    expect(find.textContaining('체크: 김확인'), findsOneWidget);
    expect(posts, 0);
  });

  test('추가 페이지 응답이 늦게 와도 체크 성공 결과와 완료 상태를 유지한다', () async {
    final page = Completer<http.Response>();
    final container = ProviderContainer(
      overrides: [
        familyContextProvider.overrideWithValue(fixture.family),
        apiTokenLoaderProvider.overrideWithValue(() async => 'test-token'),
        medicationHttpClientProvider.overrideWithValue(
          MockClient((request) async {
            if (request.method == 'POST') return confirmation(seq: 1);
            if (request.url.queryParameters['offset'] == '20') {
              return page.future;
            }
            return fixture.response(
              List.generate(20, (i) => fixture.medicationJson(i + 1, '약 $i')),
            );
          }),
        ),
      ],
    );
    addTearDown(container.dispose);
    final provider = medicationVmProvider((
      context: fixture.family,
      date: fixture.day,
    ));
    final subscription = container.listen(provider, (_, _) {});
    addTearDown(subscription.close);
    final first = await container.read(provider.future);
    final vm = container.read(provider.notifier);
    final loading = vm.loadMore();
    await vm.confirmMedication(first.items.first);
    page.complete(
      fixture.response([
        fixture.medicationJson(1, '이전 응답'),
        fixture.medicationJson(21, '추가 약'),
      ]),
    );
    await loading;
    final result = container.read(provider).requireValue;
    expect(result.items.first.isConfirmed, isTrue);
    expect(result.items.first.confirmedByName, '김확인');
    expect(result.items.length, 21);
    expect(result.confirming, isEmpty);
  });

  test('체크 토큰을 기다리는 동안 계정·공간이 바뀌면 요청을 전송하지 않는다', () async {
    final token = Completer<String?>();
    var waiting = false;
    var posts = 0;
    final container = ProviderContainer(
      overrides: [
        familyContextProvider.overrideWith(
          (ref) => ref.watch(testContextProvider),
        ),
        apiTokenLoaderProvider.overrideWithValue(
          () => waiting ? token.future : Future.value('test-token'),
        ),
        medicationHttpClientProvider.overrideWithValue(
          MockClient((request) async {
            if (request.method == 'POST') posts++;
            return fixture.response([fixture.medicationJson(42, '체크할 약')]);
          }),
        ),
      ],
    );
    addTearDown(container.dispose);
    container.read(testContextProvider.notifier).change(fixture.family);
    final provider = medicationVmProvider((
      context: fixture.family,
      date: fixture.day,
    ));
    final subscription = container.listen(provider, (_, _) {});
    addTearDown(subscription.close);
    final feed = await container.read(provider.future);
    waiting = true;
    final pending = container
        .read(provider.notifier)
        .confirmMedication(feed.items.single);
    final assertion = expectLater(pending, throwsA(isA<MedicationFailure>()));
    container.read(testContextProvider.notifier).change((
      familyRoomId: 'room-b',
      userId: 'user-b',
      roomName: '다른 공간',
    ));
    token.complete('test-token');
    await assertion;
    expect(posts, 0);
  });

  test('확인자 이름 누락과 기존 체크 기록을 ID 노출 없이 표시한다', () {
    final legacy = Medication.fromJson(
      fixture.medicationJson(42, '약', confirmed: true),
    );
    expect(legacy.confirmedByLabel, '확인자 정보 없음');
    final unnamed = Medication.fromJson({
      ...fixture.medicationJson(42, '약'),
      ...checked,
      'confirmed_by_name': '  ',
    });
    expect(unnamed.confirmedByLabel, '이름 없는 가족');
    expect(medicationConfirmationLabel(unnamed), isNot(contains('checker-a')));
  });
}
