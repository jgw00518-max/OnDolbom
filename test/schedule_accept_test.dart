import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'schedule_list_test.dart' as calendar;

http.Response jsonResponse(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

// 요약 정보와 이름이 중복되더라도 아바타가 있는 담당 가족 카드만 검증한다.
Finder assigneeCard() => find.byWidgetPredicate(
  (widget) =>
      widget is Row && widget.children.any((child) => child is CircleAvatar),
);

void main() {
  testWidgets('일반 가족 수락 성공 후 상세·목록을 갱신하고 미완료를 유지한다', (tester) async {
    var accepted = false;
    var posts = 0;
    final client = MockClient((request) async {
      if (request.method == 'POST') {
        expect(request.url.path, '/schedules/25/accept');
        expect(request.headers['Authorization'], 'Bearer id-token');
        expect(request.body, isEmpty);
        posts++;
        accepted = true;
        return jsonResponse({'result': 'OK'});
      }
      return jsonResponse({
        'results': [
          {
            ...calendar.event(25, '수락할 돌봄'),
            if (accepted) 'accepted_by': 'family-user',
            if (accepted) 'accepted_name': '테스트 가족',
          },
        ],
      });
    });
    addTearDown(client.close);
    await calendar.mountCalendar(tester, client, representative: false);
    await tester.tap(find.text('수락할 돌봄'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('schedule-accept')));
    await tester.pumpAndSettle();
    expect(posts, 1);
    // 상세의 요약 정보와 담당 가족 카드에 이름이 각각 표시되므로 카드만 검증한다.
    expect(find.text('담당 중'), findsOneWidget);
    expect(
      find.descendant(of: assigneeCard(), matching: find.text('테스트 가족')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: find.byType(Dialog), matching: find.text('미완료')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('schedule-accept')), findsNothing);
    await tester.tap(find.byTooltip('닫기'));
    await tester.pumpAndSettle();
    expect(find.text('담당자 등록 완료'), findsOneWidget);
  });

  testWidgets('수락 처리 중 중복 클릭과 닫기를 막는다', (tester) async {
    final pending = Completer<http.Response>();
    var posts = 0;
    final client = MockClient((request) async {
      if (request.method == 'POST') {
        posts++;
        return pending.future;
      }
      return jsonResponse({
        'results': [calendar.event(25, '대기 돌봄')],
      });
    });
    addTearDown(client.close);
    await calendar.mountCalendar(tester, client, representative: false);
    await tester.tap(find.text('대기 돌봄'));
    await tester.pumpAndSettle();
    final button = find.byKey(const ValueKey('schedule-accept'));
    await tester.tap(button);
    await tester.pump();
    await tester.tap(button);
    await tester.pump();
    expect(posts, 1);
    expect(tester.widget<FilledButton>(button).onPressed, isNull);
    expect(
      tester
          .widget<IconButton>(
            find.byKey(const ValueKey('schedule-detail-close')),
          )
          .onPressed,
      isNull,
    );
    pending.complete(jsonResponse({'result': 'OK'}));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('schedule-accept')), findsNothing);
  });

  testWidgets('다른 가족의 선행 수락은 오류와 최신 담당자를 표시한다', (tester) async {
    var conflict = false;
    final client = MockClient((request) async {
      if (request.method == 'POST') {
        conflict = true;
        return jsonResponse({'detail': '이미 담당 가족이 등록된 일정입니다.'}, 409);
      }
      return jsonResponse({
        'results': [
          {
            ...calendar.event(25, '동시 요청 돌봄'),
            if (conflict) 'accepted_by': 'other-family',
            if (conflict) 'accepted_name': '다른 가족',
          },
        ],
      });
    });
    addTearDown(client.close);
    await calendar.mountCalendar(tester, client, representative: false);
    await tester.tap(find.text('동시 요청 돌봄'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('schedule-accept')));
    await tester.pumpAndSettle();
    expect(find.text('이미 담당 가족이 등록된 일정입니다.'), findsOneWidget);
    expect(
      find.descendant(of: assigneeCard(), matching: find.text('다른 가족')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('schedule-accept')), findsNothing);
  });

  for (final kind in ['주보호자', '완료', '담당자 있음']) {
    testWidgets('$kind 일정에는 수락 버튼이 없다', (tester) async {
      final client = MockClient(
        (request) async => jsonResponse({
          'results': [
            {
              ...calendar.event(25, '조회 돌봄'),
              if (kind == '완료') 'schedule_state': '완료',
              if (kind == '담당자 있음') 'accepted_by': 'other-family',
            },
          ],
        }),
      );
      addTearDown(client.close);
      await calendar.mountCalendar(
        tester,
        client,
        representative: kind == '주보호자',
      );
      await tester.tap(find.text('조회 돌봄'));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('schedule-accept')), findsNothing);
    });
  }

  testWidgets('수락 후 조회 실패는 저장 실패로 표시하거나 중복 수락하지 않는다', (tester) async {
    var accepted = false;
    final client = MockClient((request) async {
      if (request.method == 'POST') {
        accepted = true;
        return jsonResponse({'result': 'OK'});
      }
      if (accepted) return jsonResponse({'detail': '연결 오류'}, 503);
      return jsonResponse({
        'results': [calendar.event(25, '조회 실패 돌봄')],
      });
    });
    addTearDown(client.close);
    await calendar.mountCalendar(tester, client, representative: false);
    await tester.tap(find.text('조회 실패 돌봄'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('schedule-accept')));
    await tester.pumpAndSettle();
    expect(find.text('수락은 완료되었습니다. 최신 일정 정보를 다시 조회해 주세요.'), findsOneWidget);
    expect(find.byKey(const ValueKey('schedule-accept')), findsNothing);
  });

  for (final viewer in ['주보호자', '수락자', '다른 가족']) {
    testWidgets('$viewer 관점에서 실제 수락자에게만 나 배지를 표시한다', (tester) async {
      final client = MockClient(
        (request) async => jsonResponse({
          'results': [
            {
              ...calendar.event(25, 'test4가 수락한 일정'),
              'accepted_by': 'test4-user',
              'accepted_name': 'test4',
            },
          ],
        }),
      );
      addTearDown(client.close);
      await calendar.mountCalendar(
        tester,
        client,
        representative: viewer == '주보호자',
        profileUserId: viewer == '수락자' ? 'test4-user' : 'test1-user',
      );
      await tester.tap(find.text('test4가 수락한 일정'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(of: assigneeCard(), matching: find.text('test4')),
        findsOneWidget,
      );
      expect(find.text('나'), viewer == '수락자' ? findsOneWidget : findsNothing);
      expect(
        find.text('담당 중'),
        viewer == '수락자' ? findsOneWidget : findsNothing,
      );
      expect(find.text('담당 가족'), findsOneWidget);
      expect(assigneeCard(), findsOneWidget);
    });
  }
}
