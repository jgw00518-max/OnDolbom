import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondolbom/theme/app_theme.dart';
import 'package:ondolbom/view/widgets/app_empty_state.dart';

void main() {
  testWidgets('빈 화면은 메모와 같은 원형 아이콘·제목·설명을 표시한다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light,
        home: const Scaffold(
          body: AppEmptyState(
            icon: Icons.mail_outline,
            title: '받은 가족 초대가 없습니다.',
            description: '초대가 도착하면 이곳에서 확인할 수 있어요.',
          ),
        ),
      ),
    );
    expect(find.byIcon(Icons.mail_outline), findsOneWidget);
    expect(find.text('받은 가족 초대가 없습니다.'), findsOneWidget);
    final decorations = tester
        .widgetList<Container>(find.byType(Container))
        .map((w) => w.decoration)
        .whereType<BoxDecoration>();
    expect(decorations.any((d) => d.shape == BoxShape.circle), isTrue);
  });
  testWidgets('작은 빈 영역·큰 글씨·다크 모드에서 안내를 스크롤할 수 있다', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.dark,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: const Scaffold(
          body: SizedBox(
            width: 240,
            height: 180,
            child: AppEmptyState(
              icon: Icons.notifications_none,
              title: '확인할 알림이 없습니다.',
              description: '새로운 소식이 도착하면 이곳에서 알려드릴게요.',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('새로운 소식이 도착하면 이곳에서 알려드릴게요.'));
    expect(tester.takeException(), isNull);
  });
}
