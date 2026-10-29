import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ondolbom/view/medications/medication_form_view.dart';
import 'medication_test.dart' as fixture;

void main() {
  testWidgets('기간 선택과 직접 입력은 상호 배타적이며 입력 일수를 전송한다', (tester) async {
    Map<String, dynamic>? saved;
    await fixture.mount(
      tester,
      MockClient((request) async {
        if (request.method == 'GET') return fixture.response([]);
        saved = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response('{"result":"OK","medication_log_seq":1}', 201);
      }),
      primary: true,
    );
    await tester.tap(find.text('약 추가'));
    await tester.pumpAndSettle();
    final period = find.byKey(const ValueKey('medication-period'));
    final days = find.byKey(const ValueKey('medication-period-days'));
    expect(
      tester.widget<DropdownButtonFormField<int>>(period).onChanged,
      isNotNull,
    );
    expect(days, findsNothing);
    await tester.ensureVisible(find.text('직접 입력'));
    await tester.tap(find.text('직접 입력'));
    await tester.pumpAndSettle();
    expect(period, findsNothing);
    expect(tester.widget<TextFormField>(days).enabled, isTrue);
    await tester.enterText(days, '0');
    await tester.ensureVisible(find.text('약 추가하기'));
    await tester.tap(find.text('약 추가하기'));
    await tester.pumpAndSettle();
    expect(find.text('1~365일 입력'), findsOneWidget);
    await tester.ensureVisible(days);
    await tester.pumpAndSettle();
    await tester.enterText(days, '365');
    await fixture.fill(tester, 'info', '기간 약');
    await fixture.fill(tester, 'dosage', '1');
    await fixture.fill(tester, 'unit', '정');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('약 추가하기'));
    await tester.tap(find.text('약 추가하기'));
    await tester.pumpAndSettle();
    expect(saved?['duration_days'], 365);
    expect(find.byType(MedicationFormView), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('삭제 안내 후 같은 공간 ID와 함께 기간 삭제 API를 호출한다', (tester) async {
    http.Request? deleted;
    await fixture.mount(
      tester,
      MockClient((request) async {
        if (request.method == 'DELETE') {
          deleted = request;
          return http.Response('{"result":"OK","deleted_count":3}', 200);
        }
        return fixture.response(
          deleted == null ? [fixture.medicationJson(1, '기간 약')] : [],
        );
      }),
      primary: true,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('약 삭제'));
    await tester.pumpAndSettle();
    expect(find.textContaining('오늘 체크한 항목도 삭제'), findsOneWidget);
    await tester.tap(find.text('삭제'));
    await tester.pumpAndSettle();
    expect(deleted?.url.path, '/medications/delete/1');
    expect(jsonDecode(deleted!.body), {'family_room_id': 'room-a'});
    expect(find.text('오늘 이후의 투약 항목 3개를 삭제했어요.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
