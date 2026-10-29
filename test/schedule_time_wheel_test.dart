import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondolbom/theme/app_theme.dart';
import 'package:ondolbom/view/schedules/schedule_time_wheel.dart';

Future<void> openPicker(
  WidgetTester tester, {
  bool isStart = false,
  TimeOfDay initial = const TimeOfDay(hour: 14, minute: 30),
  TimeOfDay start = const TimeOfDay(hour: 14, minute: 30),
}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () async {
                final result = await showModalBottomSheet<TimeOfDay>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => ScheduleTimeWheel(
                    isStart: isStart,
                    initialTime: initial,
                    startTime: start,
                  ),
                );
                if (!context.mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      result == null
                          ? '선택 취소'
                          : '결과 ${result.hour}:${result.minute}',
                    ),
                  ),
                );
              },
              child: const Text('시간 열기'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('시간 열기'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('종료시간 빠른 설정은 시작 기준이며 적용 후에만 반환한다', (tester) async {
    await openPicker(tester);
    await tester.tap(find.text('+4시간'));
    await tester.pumpAndSettle();
    expect(find.text('18:30'), findsOneWidget);
    expect(find.text('결과 18:30'), findsNothing);
    await tester.tap(find.text('시간 적용'));
    await tester.pumpAndSettle();
    expect(find.text('결과 18:30'), findsOneWidget);
  });

  testWidgets('휠에서 변경해도 취소하면 선택값을 반환하지 않는다', (tester) async {
    await openPicker(tester);
    await tester.drag(
      find.byKey(const ValueKey('hour-wheel')),
      const Offset(0, -48),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(find.text('선택 취소'), findsOneWidget);
  });

  testWidgets('기존 5분 단위가 아닌 시간도 그대로 유지한다', (tester) async {
    await openPicker(
      tester,
      isStart: true,
      initial: const TimeOfDay(hour: 14, minute: 17),
    );
    expect(find.text('14:17'), findsOneWidget);
    expect(find.text('+4시간'), findsNothing);
    await tester.tap(find.text('시간 적용'));
    await tester.pumpAndSettle();
    expect(find.text('결과 14:17'), findsOneWidget);
  });

  testWidgets('자정을 넘는 빠른 설정은 비활성화한다', (tester) async {
    await openPicker(
      tester,
      initial: const TimeOfDay(hour: 23, minute: 40),
      start: const TimeOfDay(hour: 23, minute: 40),
    );
    for (final label in ['+2시간', '+4시간', '+8시간']) {
      expect(
        tester
            .widget<ChoiceChip>(find.widgetWithText(ChoiceChip, label))
            .onSelected,
        isNull,
      );
    }
    expect(tester.takeException(), isNull);
  });
}
