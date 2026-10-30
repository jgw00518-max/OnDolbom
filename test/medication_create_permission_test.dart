import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:ondolbom/view/medications/medication_list_view.dart';
import 'package:ondolbom/vm/family_room/family_context.dart';
import 'package:ondolbom/vm/family_room/family_room_notifier.dart';
import 'package:ondolbom/vm/medications/medication_vm.dart';

import 'medication_edit_test.dart' show RoleRooms;
import 'medication_test.dart' as fixture;

void main() {
  testWidgets('일반 참여자는 목록·상세를 볼 수 있지만 약 추가 버튼은 없다', (tester) async {
    await fixture.mount(
      tester,
      MockClient(
        (_) async => fixture.response([fixture.medicationJson(1, '가족 약')]),
      ),
    );
    expect(find.byTooltip('약 추가'), findsNothing);
    await tester.tap(find.textContaining('가족 약'));
    await tester.pumpAndSettle();
    expect(find.text('투약 정보'), findsOneWidget);
  });

  testWidgets('작성 중 주보호자 권한이 해제되면 등록 버튼을 비활성화한다', (tester) async {
    var posts = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          familyContextProvider.overrideWithValue(fixture.family),
          familyRoomProvider.overrideWith(RoleRooms.new),
          apiTokenLoaderProvider.overrideWithValue(() async => 'test-token'),
          medicationHttpClientProvider.overrideWithValue(
            MockClient((request) async {
              if (request.method == 'POST') posts++;
              return fixture.response([]);
            }),
          ),
        ],
        child: MaterialApp(
          home: MedicationListView(initialDate: DateTime(2026, 10, 23)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MedicationListView)),
    );
    await tester.tap(find.byTooltip('약 추가'));
    await tester.pumpAndSettle();
    await fixture.fill(tester, 'info', '입력할 약');
    await fixture.fill(tester, 'dosage', '1');
    await fixture.fill(tester, 'unit', '정');
    FocusManager.instance.primaryFocus?.unfocus();
    (container.read(familyRoomProvider.notifier) as RoleRooms).changeRole();
    await tester.pumpAndSettle();
    expect(find.text('현재 공간의 주보호자만 투약일지를 작성할 수 있어요.'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, '약 추가하기'))
          .onPressed,
      isNull,
    );
    expect(posts, 0);
    expect(tester.takeException(), isNull);
  });

  test('VM은 일반 참여자와 토큰 로딩 중 주보호자 권한 해제의 작성을 차단한다', () async {
    final token = Completer<String?>();
    var waitToken = false;
    var posts = 0;
    final container = ProviderContainer(
      overrides: [
        familyContextProvider.overrideWithValue(fixture.family),
        familyRoomProvider.overrideWith(RoleRooms.new),
        apiTokenLoaderProvider.overrideWithValue(
          () => waitToken ? token.future : Future.value('test-token'),
        ),
        medicationHttpClientProvider.overrideWithValue(
          MockClient((request) async {
            if (request.method == 'POST') posts++;
            return fixture.response([]);
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
    await container.read(provider.future);
    final rooms = container.read(familyRoomProvider.notifier) as RoleRooms;
    final vm = container.read(provider.notifier);
    rooms.changeRole();
    await expectLater(
      vm.create(info: '약', time: '아침 식후 30분', dosage: '1', unit: '정'),
      throwsA(isA<MedicationFailure>()),
    );
    rooms.changeRole(primary: true);
    waitToken = true;
    final pending = vm.create(
      info: '약',
      time: '아침 식후 30분',
      dosage: '1',
      unit: '정',
    );
    final assertion = expectLater(pending, throwsA(isA<MedicationFailure>()));
    rooms.changeRole();
    token.complete('test-token');
    await assertion;
    expect(posts, 0);
  });
}
