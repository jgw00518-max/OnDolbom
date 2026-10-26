import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:ondolbom/model/chats/chat_message.dart';
import 'package:ondolbom/model/medications/medication.dart';
import 'package:ondolbom/view/chats/chat_view.dart';
import 'package:ondolbom/vm/chats/chat_vm.dart';
import 'package:ondolbom/vm/family_context.dart';

import 'chat_test.dart' as chat;
import 'medication_test.dart' as medication;

void main() {
  test('투약일지·채팅은 작성자 이름을 다듬고 없는 이름은 기본 문구로 표시한다', () {
    for (final name in [null, '', '   ', '  김가족  ']) {
      final expected = name == '  김가족  ' ? '김가족' : '이름 없는 가족';
      final log = Medication.fromJson({
        ...medication.medicationJson(1, '약'),
        'author_name': name,
      });
      final message = ChatMessage.fromJson({
        ...chat.message(1),
        'author_name': name,
      });
      expect(log.authorLabel, expected);
      expect(message.authorLabel, expected);
      expect(log.userId, 'user-a');
      expect(message.userId, 'db-user');
    }
  });

  testWidgets('다른 가족의 투약일지 상세는 ID 대신 이름을 표시한다', (tester) async {
    await medication.mount(
      tester,
      MockClient(
        (_) async => medication.response([
          {
            ...medication.medicationJson(1, '가족 약'),
            'user_id': 'other-user-id',
            'author_name': '이가족',
          },
        ]),
      ),
    );
    await tester.tap(find.textContaining('가족 약'));
    await tester.pumpAndSettle();
    expect(find.textContaining('작성자: 이가족'), findsOneWidget);
    expect(find.textContaining('other-user-id'), findsNothing);
  });

  testWidgets('채팅은 본인·가족의 과거 대화와 실시간 메시지에 이름을 표시한다', (tester) async {
    final socket = chat.TestSocket();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          familyContextProvider.overrideWithValue(chat.room),
          apiTokenLoaderProvider.overrideWithValue(() async => 'id-token'),
          chatSocketFactoryProvider.overrideWithValue((_) => socket),
          chatHttpClientProvider.overrideWithValue(
            MockClient(
              (_) async => chat.page([
                {...chat.message(1, content: '본인 대화'), 'author_name': '김본인'},
                {
                  ...chat.message(2, user: 'other-user-id', content: '가족 대화'),
                  'author_name': '이가족',
                },
              ]),
            ),
          ),
        ],
        child: const MaterialApp(home: ChatView()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('김본인'), findsOneWidget);
    expect(find.text('이가족'), findsOneWidget);
    expect(find.text('other-user-id'), findsNothing);
    expect(find.text('db-user'), findsNothing);
    socket.emit({
      'type': 'message',
      'message': {
        ...chat.message(3, user: 'another-user-id', content: '실시간 가족 대화'),
        'author_name': '최가족',
      },
    });
    await tester.pumpAndSettle();
    expect(find.text('최가족'), findsOneWidget);
    expect(find.text('another-user-id'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });
}
