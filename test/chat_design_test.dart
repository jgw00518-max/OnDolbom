import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ondolbom/view/chats/chat_view.dart';
import 'package:ondolbom/vm/chats/chat_vm.dart';
import 'package:ondolbom/vm/family_room/family_context.dart';

import 'chat_test.dart' as fixture;

Map<String, dynamic> dated(int seq, int day) => {
  ...fixture.message(seq, user: 'family', content: '가족의 대화 $seq'),
  'author_name': '김민지',
  'sent_at': '2026-10-${day}T14:18:00',
};

Future<void> mount(WidgetTester tester, {double scale = 1}) async {
  tester.view.physicalSize = const Size(320, 740);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final socket = fixture.TestSocket();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        familyContextProvider.overrideWithValue(fixture.room),
        apiTokenLoaderProvider.overrideWithValue(() async => 'token'),
        chatSocketFactoryProvider.overrideWithValue((_) => socket),
        chatHttpClientProvider.overrideWithValue(
          MockClient((request) async {
            if (request.url.path.endsWith('/read')) {
              return http.Response(
                jsonEncode({
                  'last_read_chat_seq': jsonDecode(request.body)['chat_seq'],
                }),
                200,
              );
            }
            if (request.url.queryParameters.containsKey('before_id')) {
              return fixture.page([dated(2, 29), dated(1, 28)]);
            }
            return fixture.page([dated(3, 29)], more: true);
          }),
        ),
      ],
      child: MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: const ChatView(),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('이전 대화를 불러오면 같은 날 구분선을 합치고 다른 날은 나눈다', (tester) async {
    await mount(tester);
    // 상태 텍스트의 실제 경계가 화면 오른쪽 여백에 맞는지 확인한다.
    expect(tester.getRect(find.text('연결됨')).right, closeTo(320 - 16, 1));
    expect(find.text('2026년 10월 29일 목요일'), findsOneWidget);
    await tester.tap(find.text('이전 대화 더 보기'));
    await tester.pumpAndSettle();
    expect(find.text('2026년 10월 29일 목요일'), findsOneWidget);
    expect(find.text('2026년 10월 28일 수요일'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('작은 화면의 큰 글씨에서도 날짜와 작성자 및 입력창이 넘치지 않는다', (tester) async {
    await mount(tester, scale: 2);
    expect(find.text('김민지'), findsOneWidget);
    expect(find.text('2026년 10월 29일 목요일'), findsOneWidget);
    expect(find.byKey(const ValueKey('chat-input')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
