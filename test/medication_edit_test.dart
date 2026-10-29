import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ondolbom/model/family/participate.dart';
import 'package:ondolbom/view/medications/medication_list_view.dart';
import 'package:ondolbom/vm/family_room/family_context.dart';
import 'package:ondolbom/vm/family_room/family_room_notifier.dart';
import 'package:ondolbom/vm/family_room/family_room_state.dart';
import 'package:ondolbom/vm/medications/medication_vm.dart';
import 'medication_test.dart' as fixture;

class RoleRooms extends FamilyRoomNotifier {
  @override
  FamilyRoomState build() => FamilyRoomState(
    selectedRoomId: 'room-a',
    participations: {
      'room-a': Participate(
        participateSeq: 1,
        userId: 'user-a',
        familyRoomId: 'room-a',
        isRepresentative: true,
        joinedAt: DateTime(2026, 1, 1),
      ),
    },
  );
  void changeRole({bool primary = false, bool left = false}) {
    state = state.copyWith(
      participations: {
        'room-a': Participate(
          participateSeq: 1,
          userId: 'user-a',
          familyRoomId: 'room-a',
          isRepresentative: primary,
          joinedAt: DateTime(2026, 1, 1),
          leftAt: left ? DateTime(2026, 10, 26) : null,
        ),
      },
    );
  }
}

Future<void> openEdit(WidgetTester tester) async {
  await tester.tap(find.textContaining('기존 약').first);
  await tester.pumpAndSettle();
  await tester.tap(find.text('수정'));
  await tester.pumpAndSettle();
}

Future<void> editField(WidgetTester tester, String field, String value) async {
  final finder = find.byKey(ValueKey('medication-edit-$field'));
  await tester.ensureVisible(finder);
  await tester.enterText(finder, value);
  await tester.pumpAndSettle();
}

void main() {
  test('주보호자 UI 권한은 공간·사용자·역할·참여 종료를 구분한다', () {
    final container = ProviderContainer(
      overrides: [familyRoomProvider.overrideWith(RoleRooms.new)],
    );
    addTearDown(container.dispose);
    expect(
      container.read(medicationEditAllowedProvider(fixture.family)),
      isTrue,
    );
    expect(
      container.read(
        medicationEditAllowedProvider((
          familyRoomId: 'other',
          userId: 'user-a',
          roomName: '',
        )),
      ),
      isFalse,
    );
    expect(
      container.read(
        medicationEditAllowedProvider((
          familyRoomId: 'room-a',
          userId: 'other',
          roomName: '',
        )),
      ),
      isFalse,
    );
    (container.read(familyRoomProvider.notifier) as RoleRooms).changeRole();
    expect(
      container.read(medicationEditAllowedProvider(fixture.family)),
      isFalse,
    );
    (container.read(familyRoomProvider.notifier) as RoleRooms).changeRole(
      primary: true,
      left: true,
    );
    expect(
      container.read(medicationEditAllowedProvider(fixture.family)),
      isFalse,
    );
  });

  testWidgets('일반 가족은 상세에서 수정 버튼을 볼 수 없다', (tester) async {
    await fixture.mount(
      tester,
      MockClient(
        (_) async => fixture.response([fixture.medicationJson(42, '기존 약')]),
      ),
    );
    await tester.tap(find.textContaining('기존 약').first);
    await tester.pumpAndSettle();
    expect(find.text('투약 정보'), findsOneWidget);
    expect(find.text('수정'), findsNothing);
  });

  testWidgets('주보호자는 기존 값을 불러와 PATCH로 수정하고 목록을 갱신한다', (tester) async {
    var saved = false;
    var patches = 0;
    final client = MockClient((request) async {
      if (request.method == 'PATCH') {
        patches++;
        expect(request.url.path, '/medications/update/42');
        expect(request.headers['Authorization'], 'Bearer test-token');
        expect(jsonDecode(request.body), {
          'family_room_id': 'room-a',
          'medication_info': '변경된 약',
          'medication_date': fixture.day,
          'medication_time': '점심 식전 15분',
          'dosage': '1.25',
          'dosage_unit': '정',
        });
        saved = true;
        return http.Response('{"result":"OK","medication_log_seq":42}', 200);
      }
      return fixture.response([
        {
          ...fixture.medicationJson(
            42,
            saved ? '변경된 약' : '기존 약',
            confirmed: true,
          ),
          'user_id': 'other-author',
          'medication_time': '점심 식전 15분',
          'dosage': saved ? 1.25 : 0.5,
        },
      ]);
    });
    await fixture.mount(tester, client, primary: true);
    await openEdit(tester);
    expect(find.text('투약 정보 수정'), findsOneWidget);
    final field = tester.widget<TextFormField>(
      find.byKey(const ValueKey('medication-edit-minutes')),
    );
    expect(field.controller!.text, '15');
    expect(
      tester
          .widget<DropdownButtonFormField<String>>(
            find.byKey(const ValueKey('medication-edit-meal')),
          )
          .initialValue,
      '점심',
    );
    expect(
      tester
          .widget<DropdownButtonFormField<String>>(
            find.byKey(const ValueKey('medication-edit-timing')),
          )
          .initialValue,
      '식전',
    );
    await editField(tester, 'info', '변경된 약');
    await editField(tester, 'dosage', '1.25');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.tap(find.text('수정 저장'));
    await tester.pumpAndSettle();
    expect(patches, 1);
    expect(find.textContaining('변경된 약'), findsOneWidget);
    expect(find.text('복약 완료'), findsWidgets);
    expect(find.text('투약 정보를 수정했어요.'), findsOneWidget);
  });

  testWidgets('기존 자유 형식 시간은 명시적으로 선택하고 세 입력을 조합해 저장한다', (tester) async {
    String? savedTime;
    await fixture.mount(
      tester,
      MockClient((request) async {
        if (request.method == 'PATCH') {
          savedTime =
              (jsonDecode(request.body) as Map)['medication_time'] as String;
          return http.Response('{"result":"OK","medication_log_seq":42}', 200);
        }
        return fixture.response([
          {...fixture.medicationJson(42, '기존 약'), 'medication_time': '09:15'},
        ]);
      }),
      primary: true,
      width: 320,
    );
    await openEdit(tester);
    expect(find.textContaining('기존 복약 시간: 09:15'), findsOneWidget);
    await tester.tap(find.text('수정 저장'));
    await tester.pumpAndSettle();
    expect(savedTime, isNull);
    expect(find.text('식사를 선택해 주세요.'), findsOneWidget);
    expect(find.text('시점을 선택해 주세요.'), findsOneWidget);
    expect(find.text('0~9999분 입력'), findsOneWidget);
    final meal = find.byKey(const ValueKey('medication-edit-meal'));
    await tester.ensureVisible(meal);
    await tester.tap(meal);
    await tester.pumpAndSettle();
    await tester.tap(find.text('저녁').last);
    await tester.pumpAndSettle();
    final timing = find.byKey(const ValueKey('medication-edit-timing'));
    await tester.ensureVisible(timing);
    await tester.tap(timing);
    await tester.pumpAndSettle();
    await tester.tap(find.text('식전').last);
    await tester.pumpAndSettle();
    await editField(tester, 'minutes', '10000');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.tap(find.text('수정 저장'));
    await tester.pumpAndSettle();
    expect(savedTime, isNull);
    await editField(tester, 'minutes', '45');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.tap(find.text('수정 저장'));
    await tester.pumpAndSettle();
    expect(savedTime, '저녁 식전 45분');
    expect(tester.takeException(), isNull);
  });

  testWidgets('날짜를 수정하면 변경된 날짜의 목록으로 이동한다', (tester) async {
    String? patchedDate;
    final requestedDates = <String?>[];
    await fixture.mount(
      tester,
      MockClient((request) async {
        if (request.method == 'PATCH') {
          patchedDate =
              (jsonDecode(request.body) as Map)['medication_date'] as String;
          return http.Response('{"result":"OK","medication_log_seq":42}', 200);
        }
        final date = request.url.queryParameters['medication_date'];
        requestedDates.add(date);
        return fixture.response(
          date == fixture.day && patchedDate == null || date == patchedDate
              ? [fixture.medicationJson(42, '기존 약', date: date!)]
              : [],
        );
      }),
      primary: true,
    );
    await openEdit(tester);
    await tester.tap(find.byKey(const ValueKey('medication-edit-date')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('24').last);
    await tester.tap(find.byKey(const ValueKey('date-picker-apply')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('수정 저장'));
    await tester.pumpAndSettle();
    expect(patchedDate, '2026-10-24');
    expect(requestedDates.last, '2026-10-24');
    expect(find.text('2026-10-24'), findsOneWidget);
    expect(find.textContaining('기존 약'), findsOneWidget);
  });

  testWidgets('입력을 검증하고 403 실패 시 내용을 보존하며 중복 저장을 막는다', (tester) async {
    var patches = 0;
    final result = Completer<http.Response>();
    await fixture.mount(
      tester,
      MockClient((request) async {
        if (request.method == 'PATCH') {
          patches++;
          return result.future;
        }
        return fixture.response([fixture.medicationJson(42, '기존 약')]);
      }),
      primary: true,
      width: 320,
    );
    await openEdit(tester);
    await editField(tester, 'dosage', '0');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.tap(find.text('수정 저장'));
    await tester.pumpAndSettle();
    expect(patches, 0);
    await editField(tester, 'dosage', '2');
    await editField(tester, 'info', '실패해도 유지할 약');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.tap(find.text('수정 저장'));
    await tester.pump();
    await tester.tap(find.text('저장 중…'));
    await tester.pump();
    expect(patches, 1);
    result.complete(
      http.Response(
        '{"detail":"주보호자만 수정 가능"}',
        403,
        headers: {'content-type': 'application/json; charset=utf-8'},
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('현재 공간의 주보호자만 투약 정보를 수정할 수 있어요.'), findsOneWidget);
    final field = tester.widget<TextFormField>(
      find.byKey(const ValueKey('medication-edit-info')),
    );
    expect(field.controller!.text, '실패해도 유지할 약');
    expect(find.text('수정 저장'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('편집 중 주보호자 권한이 해제되면 저장을 막는다', (tester) async {
    var patches = 0;
    final container = ProviderContainer(
      overrides: [
        familyContextProvider.overrideWithValue(fixture.family),
        familyRoomProvider.overrideWith(RoleRooms.new),
        apiTokenLoaderProvider.overrideWithValue(() async => 'test-token'),
        medicationHttpClientProvider.overrideWithValue(
          MockClient((request) async {
            if (request.method == 'PATCH') patches++;
            return fixture.response([fixture.medicationJson(42, '기존 약')]);
          }),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: MedicationListView(initialDate: DateTime(2026, 10, 23)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await openEdit(tester);
    (container.read(familyRoomProvider.notifier) as RoleRooms).changeRole();
    await tester.pumpAndSettle();
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '수정 저장'),
    );
    expect(button.onPressed, isNull);
    expect(find.text('현재 공간의 주보호자만 수정할 수 있어요.'), findsOneWidget);
    expect(patches, 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('수정 취소는 확인을 받고 기존 내용을 보존한다', (tester) async {
    var patches = 0;
    await fixture.mount(
      tester,
      MockClient((request) async {
        if (request.method == 'PATCH') patches++;
        return fixture.response([fixture.medicationJson(42, '기존 약')]);
      }),
      primary: true,
    );
    await openEdit(tester);
    await editField(tester, 'info', '버릴 변경');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(find.text('수정을 취소할까요?'), findsOneWidget);
    await tester.tap(find.text('수정 취소'));
    await tester.pumpAndSettle();
    expect(find.text('투약 정보 수정'), findsNothing);
    expect(find.textContaining('기존 약'), findsOneWidget);
    expect(patches, 0);
  });
}
