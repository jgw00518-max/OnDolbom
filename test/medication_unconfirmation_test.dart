import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ondolbom/vm/family_room/family_context.dart';
import 'package:ondolbom/vm/family_room/family_room_notifier.dart';
import 'package:ondolbom/vm/medications/medication_vm.dart';

import 'medication_confirmation_test.dart' show checked;
import 'medication_test.dart' as fixture;
import 'medication_edit_test.dart' show RoleRooms;
import 'memo_edit_test.dart' show testContextProvider;

Map<String, dynamic> row({int seq = 42, String? checker = 'user-a'}) => {
  ...fixture.medicationJson(seq, '완료된 약'),
  ...checked,
  'confirmed_by_user_id': checker,
};

http.Response cleared({int seq = 42, bool repeated = false}) => http.Response(
  jsonEncode({
    'result': 'OK',
    'medication_log_seq': seq,
    'already_unconfirmed': repeated,
    'medication_confirmed_at': null,
    'confirmed_by_user_id': null,
    'confirmed_by_name': null,
  }),
  200,
);

void main() {
  testWidgets('본인은 목록에서 확인 후 해제하며 취소는 요청하지 않는다', (tester) async {
    var deletes = 0;
    await fixture.mount(
      tester,
      MockClient((request) async {
        if (request.method == 'DELETE') {
          deletes++;
          expect(request.url.path, '/medications/confirm/42');
          expect(request.headers['Authorization'], 'Bearer test-token');
          expect(jsonDecode(request.body), {
            'family_room_id': 'room-a',
            'expected_confirmed_at': '2026-10-26T14:25:03.000',
            'expected_confirmed_by_user_id': 'user-a',
          });
          return cleared();
        }
        return fixture.response([row()]);
      }),
    );
    await tester.tap(find.byTooltip('복약 완료 체크 해제'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(deletes, 0);
    expect(find.text('1/1 완료'), findsOneWidget);
    await tester.tap(find.byTooltip('복약 완료 체크 해제'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('해제'));
    await tester.pumpAndSettle();
    expect(deletes, 1);
    expect(find.text('0/1 완료'), findsOneWidget);
    expect(find.textContaining('체크: 김확인'), findsNothing);
    expect(find.byTooltip('복약 완료 체크'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final checker in ['other-user', null]) {
    testWidgets('주보호자는 목록에서 타인·과거 기록을 해제한다 ($checker)', (tester) async {
      await fixture.mount(
        tester,
        MockClient((request) async {
          if (request.method == 'DELETE') {
            expect(
              jsonDecode(request.body)['expected_confirmed_by_user_id'],
              checker,
            );
            return cleared(repeated: true);
          }
          return fixture.response([row(checker: checker)]);
        }),
        primary: true,
      );
      await tester.tap(find.byTooltip('복약 완료 체크 해제'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('해제'));
      await tester.pumpAndSettle();
      expect(find.text('체크 해제'), findsNothing);
      expect(find.byTooltip('복약 완료 체크'), findsOneWidget);
      expect(find.text('0/1 완료'), findsOneWidget);
      expect(find.textContaining('체크: 김확인'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('일반 가족은 타인의 체크를 해제할 수 없다', (tester) async {
    await fixture.mount(
      tester,
      MockClient((_) async => fixture.response([row(checker: 'other')])),
    );
    expect(find.byTooltip('복약 완료 체크 해제'), findsNothing);
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
    await tester.tap(find.textContaining('완료된 약'));
    await tester.pumpAndSettle();
    expect(find.text('체크 해제'), findsNothing);
  });

  testWidgets('해제 중 중복 제출을 막고 실패 시 기존 완료 상태를 유지하며 재시도한다', (tester) async {
    final pending = Completer<http.Response>();
    var deletes = 0;
    await fixture.mount(
      tester,
      MockClient((request) async {
        if (request.method == 'DELETE') {
          return ++deletes == 1 ? pending.future : cleared();
        }
        return fixture.response([row()]);
      }),
    );
    await tester.tap(find.byTooltip('복약 완료 체크 해제'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('해제'));
    await tester.pump();
    expect(
      tester
          .widget<IconButton>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is IconButton && widget.tooltip == '복약 완료 체크 해제',
            ),
          )
          .onPressed,
      isNull,
    );
    expect(deletes, 1);
    pending.complete(
      http.Response(
        '{"detail":"해제 실패"}',
        500,
        headers: {'content-type': 'application/json; charset=utf-8'},
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('1/1 완료'), findsOneWidget);
    expect(find.byTooltip('복약 완료 체크 해제'), findsOneWidget);
    await tester.tap(find.byTooltip('복약 완료 체크 해제'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('해제'));
    await tester.pumpAndSettle();
    expect(deletes, 2);
    expect(find.text('0/1 완료'), findsOneWidget);
  });

  testWidgets('409 충돌은 최신 체크 기록을 조회하고 안내한다', (tester) async {
    var gets = 0;
    await fixture.mount(
      tester,
      MockClient((request) async {
        if (request.method == 'DELETE') {
          return http.Response(
            '{"detail":"체크 기록이 변경되었습니다."}',
            409,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        gets++;
        return fixture.response([
          {
            ...row(),
            if (gets > 1) 'confirmed_by_name': '새확인자',
            if (gets > 1) 'confirmed_by_user_id': 'new-user',
          },
        ]);
      }),
    );
    await tester.tap(find.byTooltip('복약 완료 체크 해제'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('해제'));
    await tester.pumpAndSettle();
    expect(gets, 2);
    expect(find.text('1/1 완료'), findsOneWidget);
    expect(find.textContaining('체크: 새확인자'), findsOneWidget);
    expect(find.text('체크 기록이 변경되었습니다.'), findsOneWidget);
    expect(find.byTooltip('복약 완료 체크 해제'), findsNothing);
  });

  test('늦은 페이지 응답이 해제 결과를 덮어쓰지 않고 다시 체크할 수 있다', () async {
    final page = Completer<http.Response>();
    final container = ProviderContainer(
      overrides: [
        familyContextProvider.overrideWithValue(fixture.family),
        apiTokenLoaderProvider.overrideWithValue(() async => 'test-token'),
        medicationHttpClientProvider.overrideWithValue(
          MockClient((request) async {
            if (request.method == 'DELETE') return cleared(seq: 1);
            if (request.method == 'POST') {
              return http.Response(
                jsonEncode({
                  'medication_log_seq': 1,
                  ...checked,
                  'confirmed_by_user_id': 'user-a',
                }),
                200,
                headers: {'content-type': 'application/json; charset=utf-8'},
              );
            }
            if (request.url.queryParameters['offset'] == '20') {
              return page.future;
            }
            return fixture.response(List.generate(20, (i) => row(seq: i + 1)));
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
    final feed = await container.read(provider.future);
    final vm = container.read(provider.notifier);
    final loading = vm.loadMore();
    await vm.unconfirmMedication(feed.items.first);
    page.complete(fixture.response([row(seq: 1), row(seq: 21)]));
    await loading;
    final result = container.read(provider).requireValue;
    expect(result.items.length, 21);
    expect(result.items.first.isConfirmed, isFalse);
    expect(result.items.first.confirmedByUserId, isNull);
    expect(result.items.first.authorName, '김가족');
    expect(result.confirming, isEmpty);
    await vm.confirmMedication(result.items.first);
    expect(
      container.read(provider).requireValue.items.first.isConfirmed,
      isTrue,
    );
  });

  test('토큰 대기 중 주보호자 권한을 잃으면 타인의 체크 해제 요청을 보내지 않는다', () async {
    final token = Completer<String?>();
    var waiting = false;
    var deletes = 0;
    final container = ProviderContainer(
      overrides: [
        familyContextProvider.overrideWithValue(fixture.family),
        familyRoomProvider.overrideWith(RoleRooms.new),
        apiTokenLoaderProvider.overrideWithValue(
          () => waiting ? token.future : Future.value('test-token'),
        ),
        medicationHttpClientProvider.overrideWithValue(
          MockClient((request) async {
            if (request.method == 'DELETE') deletes++;
            return fixture.response([row(checker: 'other-user')]);
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
    final feed = await container.read(provider.future);
    waiting = true;
    final pending = container
        .read(provider.notifier)
        .unconfirmMedication(feed.items.single);
    final assertion = expectLater(pending, throwsA(isA<MedicationFailure>()));
    (container.read(familyRoomProvider.notifier) as RoleRooms).changeRole();
    token.complete('test-token');
    await assertion;
    expect(deletes, 0);
    expect(
      container.read(provider).requireValue.items.single.isConfirmed,
      isTrue,
    );
  });

  test('토큰을 기다리는 동안 계정·공간이 바뀌면 해제 요청을 보내지 않는다', () async {
    final token = Completer<String?>();
    var waiting = false;
    var deletes = 0;
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
            if (request.method == 'DELETE') deletes++;
            return fixture.response([row()]);
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
        .unconfirmMedication(feed.items.single);
    final assertion = expectLater(pending, throwsA(isA<MedicationFailure>()));
    container.read(testContextProvider.notifier).change((
      familyRoomId: 'room-b',
      userId: 'user-b',
      roomName: '다른 공간',
    ));
    token.complete('test-token');
    await assertion;
    expect(deletes, 0);
  });
}
