import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ondolbom/main.dart';
import 'package:ondolbom/vm/auth/auth_vm.dart';
import 'package:ondolbom/model/medications/medication.dart';
import 'package:ondolbom/view/medications/medication_form_view.dart';
import 'package:ondolbom/view/medications/medication_list_view.dart';
import 'package:ondolbom/vm/family_room/family_context.dart';
import 'package:ondolbom/vm/medications/medication_vm.dart';

const family = (familyRoomId: 'room-a', userId: 'user-a', roomName: '가족 돌봄 공간');
const day = '2026-10-23';
Map<String, dynamic> medicationJson(
  int seq,
  String name, {
  String date = day,
  bool confirmed = false,
}) => {
  'medication_log_seq': seq,
  'family_room_id': 'room-a',
  'user_id': 'user-a',
  'author_name': '김가족',
  'medication_info': name,
  'medication_date': date,
  'medication_time': '아침 식후 30분',
  'dosage': 0.5,
  'dosage_unit': '정',
  'medication_confirmed_at': confirmed ? '${date}T09:00:00' : null,
  'recorded_at': '${date}T08:00:00',
  'record_updated_at': null,
};
http.Response response(List<Map<String, dynamic>> rows) => http.Response(
  jsonEncode({'results': rows}),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

Future<void> mount(
  WidgetTester tester,
  http.Client client, {
  double width = 390,
  bool primary = false,
}) async {
  tester.view.physicalSize = Size(width, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authUserProvider.overrideWith((ref) => Stream.value(null)),
        familyContextProvider.overrideWithValue(family),
        medicationEditAllowedProvider(family).overrideWithValue(primary),
        medicationHttpClientProvider.overrideWithValue(client),
        apiTokenLoaderProvider.overrideWithValue(() async => 'test-token'),
      ],
      child: Consumer(
        builder: (context, ref, _) {
          final app = const MyApp().build(context, ref) as MaterialApp;
          return MaterialApp(
            theme: app.theme,
            home: MedicationListView(initialDate: DateTime(2026, 10, 23)),
          );
        },
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> fill(WidgetTester tester, String name, String value) async {
  final field = find.byKey(ValueKey('medication-$name'));
  await tester.ensureVisible(field);
  await tester.enterText(field, value);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('등록 순서와 무관하게 아침·점심·저녁 안에서 식전·식후 순서로 표시한다', (tester) async {
    await mount(
      tester,
      MockClient(
        (_) async => response([
          {...medicationJson(4, '기타 약'), 'medication_time': '취침 전'},
          {...medicationJson(3, '저녁 약'), 'medication_time': '저녁 식후 30분'},
          {...medicationJson(2, '점심 약'), 'medication_time': '점심 식후 30분'},
          medicationJson(1, '아침 약'),
          {...medicationJson(5, '저녁 식전 약'), 'medication_time': '저녁 식전 30분'},
          {...medicationJson(6, '점심 식전 약'), 'medication_time': '점심 식전 30분'},
          {...medicationJson(7, '아침 식전 약'), 'medication_time': '아침 식전 30분'},
        ]),
      ),
    );
    tester.view.physicalSize = const Size(390, 2800);
    await tester.pumpAndSettle();
    final names = [
      '아침 식전 약',
      '아침 약',
      '점심 식전 약',
      '점심 약',
      '저녁 식전 약',
      '저녁 약',
      '기타 약',
    ];
    for (var i = 0; i < names.length - 1; i++) {
      expect(
        tester.getTopLeft(find.textContaining(names[i])).dy,
        lessThan(tester.getTopLeft(find.textContaining(names[i + 1])).dy),
      );
    }
    expect(tester.takeException(), isNull);
  });

  test('모델은 숫자·문자열 용량과 null을 처리한다', () {
    final numeric = Medication.fromJson(medicationJson(1, '테스트 약'));
    expect(numeric.doseLabel, '0.5정');
    final nullable = Medication.fromJson({
      ...medicationJson(2, '테스트 약'),
      'dosage': null,
      'medication_time': null,
      'dosage_unit': null,
      'recorded_at': null,
    });
    expect(nullable.doseLabel, '');
    expect(nullable.isConfirmed, false);
    final text = Medication.fromJson({
      ...medicationJson(3, '테스트 약'),
      'dosage': '1.000',
    });
    expect(text.doseLabel, '1정');
    for (final value in ['0', '-1', '0.0001', '10000000', 'NaN']) {
      expect(isValidMedicationDosage(value), false);
    }
    expect(isValidMedicationDosage('0.001'), true);
  });

  testWidgets('시간별 목록·상태·상세를 표시하고 공통 테마를 사용한다', (tester) async {
    await mount(
      tester,
      MockClient((request) async {
        expect(request.headers['Authorization'], 'Bearer test-token');
        expect(request.url.queryParameters['family_room_id'], 'room-a');
        return response([
          medicationJson(1, '테스트 약 A'),
          medicationJson(2, '테스트 약 B', confirmed: true),
        ]);
      }),
    );
    expect(find.text('아침 식후 30분'), findsOneWidget);
    expect(find.text('1/2 완료'), findsOneWidget);
    expect(find.text('테스트 약 A 0.5정'), findsOneWidget);
    final card = tester.element(find.byType(Card).last);
    expect(Theme.of(card).cardTheme.color, Colors.white);
    expect(Theme.of(card).colorScheme.primary, const Color(0xFFF6B08A));

    await tester.tap(find.text('테스트 약 A 0.5정'));
    await tester.pumpAndSettle();
    expect(find.text('투약 정보'), findsOneWidget);
    expect(find.textContaining('작성자: 김가족'), findsOneWidget);
    expect(find.text('수정 저장'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('입력을 검증하고 작성 성공 후 목록을 갱신한다', (tester) async {
    var saved = false;
    var posts = 0;
    String? date;
    await mount(
      tester,
      MockClient((request) async {
        if (request.method == 'POST') {
          posts++;
          expect(jsonDecode(request.body), {
            'family_room_id': 'room-a',
            'medication_info': '새 테스트 약',
            'medication_date': date,
            'medication_time': '아침 식후 30분',
            'dosage': '0.500',
            'dosage_unit': '정',
          });
          saved = true;
          return http.Response('{"result":"OK","medication_log_seq":3}', 201);
        }
        date = request.url.queryParameters['medication_date'];
        return response(
          saved ? [medicationJson(3, '새 테스트 약', date: date!)] : [],
        );
      }),
      primary: true,
    );
    await tester.tap(find.text('약 추가'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('추가'));
    await tester.pumpAndSettle();
    expect(posts, 0);
    await fill(tester, 'info', '새 테스트 약');
    await fill(tester, 'dosage', '0.500');
    await fill(tester, 'unit', '정');
    expect(find.text('약 정보를 입력해 주세요.'), findsNothing);
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();

    await tester.tap(find.text('추가'));
    await tester.pumpAndSettle();
    expect(posts, 1);
    expect(find.byType(MedicationFormDialog), findsNothing);
    expect(find.text('새 테스트 약 0.5정'), findsOneWidget);
  });

  testWidgets('작은 화면에서 저장 중 중복 제출을 막고 실패하면 입력을 유지한다', (tester) async {
    var posts = 0;
    final pending = Completer<http.Response>();
    await mount(
      tester,
      MockClient((request) async {
        if (request.method == 'GET') return response([]);
        posts++;
        return pending.future;
      }),
      width: 320,
      primary: true,
    );
    await tester.tap(find.text('약 추가'));
    await tester.pumpAndSettle();
    await fill(tester, 'info', '저장할 약');
    await fill(tester, 'dosage', '1');
    await fill(tester, 'unit', '포');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.tap(find.text('추가'));
    await tester.pump();
    await tester.tap(find.text('등록 중…'));
    expect(posts, 1);
    pending.complete(http.Response('{"detail":"error"}', 500));
    await tester.pumpAndSettle();
    expect(find.byType(MedicationFormDialog), findsOneWidget);
    final info = tester.widget<TextFormField>(
      find.byKey(const ValueKey('medication-info')),
    );
    expect(info.controller!.text, '저장할 약');
    expect(find.text('추가'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('인증 오류를 표시하고 재시도 및 날짜 변경 시 다시 조회한다', (tester) async {
    var denied = true;
    final dates = <String>[];
    await mount(
      tester,
      MockClient((request) async {
        dates.add(request.url.queryParameters['medication_date']!);
        if (denied) return http.Response('{}', 401);
        return response([]);
      }),
    );
    expect(find.textContaining('로그인이 필요해요'), findsOneWidget);
    denied = false;
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();
    expect(find.textContaining('이 날짜에 등록된 약이 없어요.'), findsOneWidget);
    await tester.tap(find.byTooltip('다음 날짜'));
    await tester.pumpAndSettle();
    expect(dates.last, isNot(dates.first));
  });

  test('공간·날짜별 상태를 분리하고 다음 페이지를 조회한다', () async {
    final requests = <Uri>[];
    final container = ProviderContainer(
      overrides: [
        authUserProvider.overrideWith((ref) => Stream.value(null)),
        apiTokenLoaderProvider.overrideWithValue(() async => 'test-token'),
        medicationHttpClientProvider.overrideWithValue(
          MockClient((request) async {
            requests.add(request.url);
            final room = request.url.queryParameters['family_room_id']!;
            final date = request.url.queryParameters['medication_date']!;
            final offset = int.parse(request.url.queryParameters['offset']!);
            return response(
              List.generate(
                offset == 0 ? 20 : 1,
                (i) => {
                  ...medicationJson(offset + i, room, date: date),
                  'family_room_id': room,
                },
              ),
            );
          }),
        ),
      ],
    );
    addTearDown(container.dispose);
    final first = medicationVmProvider((context: family, date: day));
    const another = (
      familyRoomId: 'room-b',
      userId: 'user-a',
      roomName: '다른 공간',
    );
    final second = medicationVmProvider((context: another, date: '2026-10-24'));
    final a = container.listen(first, (_, _) {});
    final b = container.listen(second, (_, _) {});
    addTearDown(a.close);
    addTearDown(b.close);
    await container.read(first.future);
    await container.read(second.future);
    await container.read(first.notifier).loadMore();
    expect(container.read(first).requireValue.items.length, 21);
    expect(
      container
          .read(second)
          .requireValue
          .items
          .singleWhere((item) => item.seq == 0)
          .familyRoomId,
      'room-b',
    );
    expect(requests.last.queryParameters['offset'], '20');
    expect(requests.last.queryParameters['medication_date'], day);
  });
}
