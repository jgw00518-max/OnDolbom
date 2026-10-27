import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ondolbom/model/auth/app_user.dart';
import 'package:ondolbom/model/auth/user_profile.dart';
import 'package:ondolbom/view/family_room/family_room_home.dart';
import 'package:ondolbom/view/inquiries/inquiries_view.dart';
import 'package:ondolbom/view/inquiries/inquiry_form_view.dart';
import 'package:ondolbom/view/widgets/account_drawer.dart';
import 'package:ondolbom/vm/auth/auth_vm.dart';
import 'package:ondolbom/vm/auth/user_profile_vm.dart';
import 'package:ondolbom/vm/family_room/family_room_notifier.dart';
import 'package:ondolbom/vm/inquiries/inquiry_vm.dart';
import 'family_care_connection_test.dart' show CareRooms;

Map<String, dynamic> summary({bool detail = false}) => {
  'question_seq': 42,
  'question_title': '테스트 문의',
  'questioned_at': '2026-10-26T12:00:00',
  'family_room_id': null,
  'answered': 1,
  if (detail) 'question_content': '문의 본문',
  if (detail)
    'answers': [
      {'answer_content': '관리자 안내', 'answered_at': '2026-10-26T13:00:00'},
    ],
};

void main() {
  testWidgets('DB 연결 실패 시 로딩을 끝내고 자동 재요청 없이 오류와 재시도를 표시한다', (tester) async {
    var calls = 0;
    final api = InquiryApi(
      'http://localhost',
      MockClient((_) async {
        calls++;
        return http.Response('{"detail":"database unavailable"}', 503);
      }),
      () async => 'token',
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [inquiryApiProvider.overrideWithValue(api)],
        child: const MaterialApp(home: InquiriesView()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining('DB 연결'), findsOneWidget);
    expect(find.text('다시 시도'), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    expect(calls, 1);
    await tester.tap(find.text('다시 시도'));
    await tester.pumpAndSettle();
    expect(calls, 2);
  });

  testWidgets('Firebase 토큰 발급이 멈춰도 제한 시간 뒤 로딩을 해제한다', (tester) async {
    var httpCalls = 0;
    final token = Completer<String>();
    final api = InquiryApi(
      'http://localhost',
      MockClient((_) async {
        httpCalls++;
        return http.Response('{}', 200);
      }),
      () => token.future,
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [inquiryApiProvider.overrideWithValue(api)],
        child: const MaterialApp(home: InquiriesView()),
      ),
    );
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pump(const Duration(seconds: 11));
    await tester.pumpAndSettle();
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining('로그인 정보를 확인하는 시간이 초과'), findsOneWidget);
    expect(httpCalls, 0);
    token.complete('late-token');
    await tester.pump();
    expect(httpCalls, 0);
  });
  testWidgets('공간 선택 전과 공간 내부에서 같은 계정 Drawer와 문의를 연다', (tester) async {
    final api = InquiryApi(
      'http://localhost',
      MockClient(
        (_) async => http.Response('{"items":[],"next_cursor":null}', 200),
      ),
      () async => 'token',
    );
    for (final inside in [false, true]) {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            authUserProvider.overrideWith(
              (ref) => Stream.value(
                const AppUser(uid: 'uid', email: 'family@example.com'),
              ),
            ),
            userProfileProvider.overrideWith(
              (ref) async => const UserProfile(
                userId: 'user',
                name: '가족 이름',
                email: 'family@example.com',
                phone: '010-1234-5678',
              ),
            ),
            inquiryApiProvider.overrideWithValue(api),
            familyRoomProvider.overrideWith(CareRooms.new),
          ],
          child: MaterialApp(
            home: inside
                ? const FamilyRoomHome()
                : Scaffold(
                    drawer: const AccountDrawer(),
                    appBar: AppBar(
                      title: const Text('가족 공간'),
                      leading: const AccountMenuButton(),
                    ),
                  ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('계정 메뉴'));
      await tester.pumpAndSettle();
      expect(find.text('가족 이름 님'), findsOneWidget);
      expect(find.text('family@example.com'), findsOneWidget);
      expect(find.text('010-1234-5678'), findsOneWidget);
      await tester.tap(find.text('문의'));
      await tester.pumpAndSettle();
      expect(find.byType(InquiriesView), findsOneWidget);
      expect(find.text('등록한 문의가 없습니다.'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    }
  });

  testWidgets('내 문의 목록·상세·관리자 답변과 새로고침을 연결한다', (tester) async {
    var reads = 0;
    final api = InquiryApi(
      'http://localhost',
      MockClient((request) async {
        expect(request.headers['Authorization'], 'Bearer token');
        reads++;
        return http.Response(
          jsonEncode(
            request.url.path.endsWith('/42')
                ? summary(detail: true)
                : {
                    'items': [summary()],
                    'next_cursor': null,
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
        overrides: [inquiryApiProvider.overrideWithValue(api)],
        child: const MaterialApp(home: InquiriesView()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('테스트 문의'));
    await tester.pumpAndSettle();
    expect(find.text('문의 본문'), findsOneWidget);
    expect(find.text('관리자 안내'), findsOneWidget);
    await tester.tap(find.byTooltip('답변 새로고침'));
    await tester.pumpAndSettle();
    expect(reads, 3);
  });

  testWidgets('작성 입력 검증·공간 선택·중복 방지·실패 입력 보존', (tester) async {
    final pending = Completer<http.Response>();
    var calls = 0;
    final api = InquiryApi(
      'http://localhost',
      MockClient((request) {
        calls++;
        final body = jsonDecode(request.body);
        expect(body['family_room_id'], isNull);
        expect(body.containsKey('user_id'), false);
        return pending.future;
      }),
      () async => 'token',
    );
    await tester.pumpWidget(
      ProviderScope(
        overrides: [inquiryApiProvider.overrideWithValue(api)],
        child: const MaterialApp(home: InquiryFormView(familyRoomId: 'room-a')),
      ),
    );
    await tester.ensureVisible(find.text('문의 등록'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('문의 등록'));
    await tester.pump();
    expect(calls, 0);
    await tester.enterText(find.byType(TextFormField).first, '제목');
    await tester.enterText(find.byType(TextFormField).last, '내용');
    await tester.ensureVisible(find.text('현재 가족 공간과 관련된 문의'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('현재 가족 공간과 관련된 문의'));
    await tester.ensureVisible(find.text('문의 등록'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('문의 등록'));
    await tester.pump();
    await tester.tap(find.text('등록 중…'));
    await tester.pump();
    expect(calls, 1);
    pending.complete(http.Response('private error', 503));
    await tester.pumpAndSettle();
    expect(find.text('제목'), findsWidgets);
    expect(
      tester
          .widget<TextFormField>(find.byType(TextFormField).last)
          .controller!
          .text,
      '내용',
    );
    expect(find.textContaining('목록을 확인한 후'), findsOneWidget);
  });

  test('정상 등록 후 목록을 갱신하고 서버 반환 ID를 사용한다', () async {
    final api = InquiryApi(
      'http://localhost',
      MockClient((_) async => http.Response('{"question_seq":42}', 201)),
      () async => 'token',
    );
    final container = ProviderContainer(
      overrides: [inquiryApiProvider.overrideWithValue(api)],
    );
    addTearDown(container.dispose);
    final sub = container.listen(inquiryCreateProvider, (_, _) {});
    addTearDown(sub.close);
    await container.read(inquiryCreateProvider.notifier).create('제목', '내용');
    expect(container.read(inquiryCreateProvider).requireValue, 42);
  });

  test('계정 전환 후 도착한 이전 계정의 저장 결과는 노출하지 않는다', () async {
    final pending = Completer<http.Response>();
    final firstApi = InquiryApi(
      'http://localhost',
      MockClient((_) => pending.future),
      () async => 'old',
    );
    final secondApi = InquiryApi(
      'http://localhost',
      MockClient((_) async => http.Response('{}', 200)),
      () async => 'new',
    );
    final container = ProviderContainer(
      overrides: [inquiryApiProvider.overrideWithValue(firstApi)],
    );
    addTearDown(container.dispose);
    final sub = container.listen(inquiryCreateProvider, (_, _) {});
    addTearDown(sub.close);
    final request = container
        .read(inquiryCreateProvider.notifier)
        .create('제목', '내용');
    await Future<void>.delayed(Duration.zero);
    container.updateOverrides([
      inquiryApiProvider.overrideWithValue(secondApi),
    ]);
    container.read(inquiryCreateProvider);
    pending.complete(http.Response('{"question_seq":42}', 201));
    await request;
    expect(container.read(inquiryCreateProvider).asData?.value, isNull);
  });
}
