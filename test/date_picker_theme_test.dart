import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondolbom/theme/app_theme.dart';

void main() {
  for (final scale in [1.0, 1.2]) {
    testWidgets('한국어 달력에서 날짜 선택과 입력 모드 전환 ($scale)', (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      DateTime? selected;
      late MaterialLocalizations labels;
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light,
          locale: const Locale('ko', 'KR'),
          supportedLocales: const [Locale('ko', 'KR')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!,
          ),
          home: Scaffold(
            body: Builder(
              builder: (context) {
                labels = MaterialLocalizations.of(context);
                return TextButton(
                  onPressed: () async {
                    selected = await showDatePicker(
                      context: context,
                      initialDate: DateTime(2026, 10, 20),
                      currentDate: DateTime(2026, 10, 28),
                      firstDate: DateTime(2026, 10),
                      lastDate: DateTime(2026, 10, 28),
                    );
                  },
                  child: const Text('날짜 선택'),
                );
              },
            ),
          ),
        ),
      );
      await tester.tap(find.text('날짜 선택'));
      await tester.pumpAndSettle();
      expect(find.text(labels.cancelButtonLabel), findsOneWidget);
      expect(find.text(labels.okButtonLabel), findsOneWidget);
      final dialog = tester.getRect(find.byType(Dialog));
      final confirm = tester.getRect(
        find.byKey(const ValueKey('date-picker-confirm-background')),
      );
      expect(dialog.right - confirm.right, greaterThanOrEqualTo(16));
      expect(dialog.bottom - confirm.bottom, greaterThanOrEqualTo(12));
      final cancel = tester.getRect(find.text(labels.cancelButtonLabel));
      expect(dialog.bottom - cancel.bottom, greaterThanOrEqualTo(12));
      await tester.tap(find.byTooltip(labels.inputDateModeButtonLabel));
      await tester.pumpAndSettle();
      expect(find.byType(TextField), findsOneWidget);
      await tester.tap(find.byTooltip(labels.calendarModeButtonLabel));
      await tester.pumpAndSettle();
      await tester.tap(find.text('25'));
      await tester.tap(find.text(labels.okButtonLabel));
      await tester.pumpAndSettle();
      expect(selected, DateTime(2026, 10, 25));
      expect(tester.takeException(), isNull);
    });
  }
}
