import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondolbom/theme/app_theme.dart';
import 'package:ondolbom/view/widgets/app_date_picker.dart';

void main() {
  for (final scale in [1.0, 1.2]) {
    testWidgets('오늘 이동은 달력 선택만 바꾸고 확인 후 반영한다 ($scale)', (tester) async {
      tester.view.physicalSize = const Size(320, 740);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      DateTime? result;
      final today = DateUtils.dateOnly(DateTime.now());
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
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () async {
                  result = await showAppDatePicker(
                    context: context,
                    initialDate: today.add(const Duration(days: 90)),
                    firstDate: DateTime(1900),
                    lastDate: DateTime(2100, 12, 31),
                  );
                },
                child: const Text('열기'),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('열기'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('date-picker-today')));
      await tester.pumpAndSettle();
      expect(result, isNull);
      expect(
        tester
            .widget<CalendarDatePicker>(find.byType(CalendarDatePicker))
            .initialDate,
        today,
      );
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(
        find.byKey(const ValueKey('date-picker-apply')),
      );
      await tester.tap(find.byKey(const ValueKey('date-picker-apply')));
      await tester.pumpAndSettle();
      expect(result, today);
    });
  }
}
