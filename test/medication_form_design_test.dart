import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ondolbom/theme/app_colors.dart';
import 'package:ondolbom/theme/app_theme.dart';
import 'package:ondolbom/view/medications/medication_form_view.dart';
import 'package:ondolbom/vm/family_room/family_context.dart';
import 'package:ondolbom/vm/medications/medication_vm.dart';
import 'medication_test.dart' as fixture;

void main() {
  testWidgets('약 추가는 다이얼로그 대신 화면으로 열리고 입력 중 뒤로 가기는 확인한다', (tester) async {
    var posts = 0;
    await fixture.mount(
      tester,
      MockClient((request) async {
        if (request.method == 'POST') posts++;
        return fixture.response([]);
      }),
      primary: true,
    );
    await tester.tap(find.text('약 추가'));
    await tester.pumpAndSettle();
    expect(find.byType(MedicationFormView), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
    expect(find.text('MEDICATION'), findsOneWidget);
    await fixture.fill(tester, 'info', '취소할 약');
    await tester.tap(find.byTooltip('이전 화면'));
    await tester.pumpAndSettle();
    expect(find.text('작성을 취소할까요?'), findsOneWidget);
    await tester.tap(find.text('계속 작성'));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextFormField>(find.byKey(const ValueKey('medication-info')))
          .controller!
          .text,
      '취소할 약',
    );
    await tester.tap(find.byTooltip('이전 화면'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('작성 취소'));
    await tester.pumpAndSettle();
    expect(find.byType(MedicationFormView), findsNothing);
    expect(posts, 0);
  });

  testWidgets('시작일을 바꿔 저장하면 그 날짜로 전송하고 목록도 같은 날짜로 돌아온다', (tester) async {
    Map<String, dynamic>? saved;
    await fixture.mount(
      tester,
      MockClient((request) async {
        if (request.method == 'POST') {
          saved = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response('{"result":"OK","medication_log_seq":1}', 201);
        }
        return fixture.response([]);
      }),
      primary: true,
    );
    await tester.tap(find.text('약 추가'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('medication-start-date')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('24').last);
    final dateContext = tester.element(find.byType(DatePickerDialog));
    await tester.tap(
      find.text(MaterialLocalizations.of(dateContext).okButtonLabel),
    );
    await tester.pumpAndSettle();
    expect(find.text('2026-10-24'), findsOneWidget);
    await fixture.fill(tester, 'info', '날짜 변경 약');
    await fixture.fill(tester, 'dosage', '1');
    await fixture.fill(tester, 'unit', '정');
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('약 추가하기'));
    await tester.tap(find.text('약 추가하기'));
    await tester.pumpAndSettle();
    expect(saved?['medication_date'], '2026-10-24');
    expect(saved?['duration_days'], 2);
    expect(find.byType(MedicationFormView), findsNothing);
    expect(find.text('2026-10-24'), findsOneWidget);
  });

  testWidgets('320px 큰 글씨에서도 카드·입력·저장 버튼이 넘치지 않는다', (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          familyContextProvider.overrideWithValue(fixture.family),
          medicationCreateAllowedProvider(
            fixture.family,
          ).overrideWithValue(true),
          medicationHttpClientProvider.overrideWithValue(
            MockClient((_) async => fixture.response([])),
          ),
          apiTokenLoaderProvider.overrideWithValue(() async => 'token'),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!,
          ),
          home: const MedicationFormView(
            query: (context: fixture.family, date: fixture.day),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.ensureVisible(find.text('약 추가하기'));
    await tester.pumpAndSettle();
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '약 추가하기'),
    );
    expect(button.style!.backgroundColor!.resolve({}), AppColors.primary);
    expect(button.style!.foregroundColor!.resolve({}), AppColors.textPrimary);
    expect(tester.takeException(), isNull);
  });
}
