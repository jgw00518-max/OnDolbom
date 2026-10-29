import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ondolbom/view/notices/notices_view.dart';
import 'package:ondolbom/vm/notices/notice_vm.dart';

void main() {
  testWidgets('공지 목록에서 복합 키로 상세를 열고 수정 본문을 표시한다', (tester) async {
    final notice = {
      'admin_id': 'admin-a',
      'notice_id': 'notice-a',
      'notice_title': '서비스 안내',
      'notice_content': '공지 본문',
      'notice_created_at': '2026-10-26T12:00:00',
      'notice_updated_at': '2026-10-26T13:00:00',
    };
    final api = NoticeApi(
      'http://localhost',
      MockClient((request) async {
        expect(request.headers['Authorization'], 'Bearer token');
        final detail = request.url.path.endsWith('/admin-a/notice-a');
        return http.Response(
          jsonEncode(
            detail
                ? notice
                : {
                    'items': [notice],
                    'has_more': false,
                  },
          ),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
      () async => 'token',
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [noticeApiProvider.overrideWithValue(api)],
        child: const MaterialApp(home: NoticesView()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('서비스 안내'));
    await tester.pumpAndSettle();
    expect(find.text('공지 본문'), findsOneWidget);
    expect(find.text('수정 2026-10-26 13:00'), findsOneWidget);
    final backToList = find.widgetWithText(FilledButton, '목록으로 돌아가기');
    await tester.ensureVisible(backToList);
    expect(
      tester
          .widget<FilledButton>(backToList)
          .style!
          .backgroundColor!
          .resolve({}),
      const Color(0xFFF6B08A),
    );
    await tester.tap(backToList);
    await tester.pumpAndSettle();
    expect(find.text('꼭 확인해 주세요'), findsOneWidget);
  });

  testWidgets('오류를 자동 재요청하지 않고 수동 재시도 후 빈 목록을 표시한다', (tester) async {
    var calls = 0;
    final api = NoticeApi(
      'http://localhost',
      MockClient((_) async {
        calls++;
        return calls == 1
            ? http.Response('private', 503)
            : http.Response('{"items":[],"has_more":false}', 200);
      }),
      () async => 'token',
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [noticeApiProvider.overrideWithValue(api)],
        child: const MaterialApp(home: NoticesView()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 5));
    expect(calls, 1);
    expect(find.textContaining('서버와 DB'), findsOneWidget);
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();
    expect(find.text('등록된 공지사항이 없습니다.'), findsOneWidget);
  });
}
