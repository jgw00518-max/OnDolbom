import 'package:ondolbom/model/auth/user_profile.dart';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ondolbom/model/auth/app_user.dart';
import 'package:ondolbom/model/family/family_room.dart';
import 'package:ondolbom/model/family/participate.dart';
import 'package:ondolbom/view/family_room/family_room_home.dart';
import 'package:ondolbom/view/schedules/schedule_list.dart';
import 'package:ondolbom/view/schedules/schedule_create.dart';
import 'package:ondolbom/vm/auth/auth_vm.dart';
import 'package:ondolbom/vm/auth/user_profile_vm.dart';
import 'package:ondolbom/vm/family_room_notifier.dart';
import 'package:ondolbom/vm/family_room_state.dart';
import 'package:ondolbom/vm/schedules/schedule_vm.dart';

class CalendarUser extends Fake implements User {
  @override
  String get uid => 'firebase-user';
  @override
  Future<String?> getIdToken([bool forceRefresh = false]) async => 'id-token';
}

class CalendarAuth extends Fake implements FirebaseAuth {
  @override
  User? get currentUser => CalendarUser();
}

class CalendarRooms extends FamilyRoomNotifier {
  CalendarRooms(this.representative);
  final bool representative;
  @override
  FamilyRoomState build() => FamilyRoomState(
    selectedRoomId: 'room-a',
    rooms: const [
      FamilyRoom(
        familyRoomId: 'room-a',
        createdBy: 'family-user',
        careRecipientName: '가족 A',
      ),
    ],
    participations: {
      'room-a': Participate(
        participateSeq: 1,
        userId: 'family-user',
        familyRoomId: 'room-a',
        isRepresentative: representative,
        joinedAt: DateTime(2026, 1, 1),
      ),
    },
  );
}

Map<String, Object?> event(int day, String name) => {
  'schedule_seq': day,
  'schedule_date': '2026-10-${day.toString().padLeft(2, '0')}',
  'start_time': '09:00:00',
  'end_time': '10:00:00',
  'schedule_state': '미완료',
  'schedule_name': name,
  'schedule_memo': '식사 챙기기',
  'creator_name': '주보호자',
};

Future<void> mountCalendar(
  WidgetTester tester,
  http.Client client, {
  bool representative = true,
  Widget? home,
  String profileUserId = 'family-user',
}) async {
  await tester.binding.setSurfaceSize(const Size(430, 950));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        firebaseAuthProvider.overrideWithValue(CalendarAuth()),
        authUserProvider.overrideWith(
          (ref) => Stream.value(const AppUser(uid: 'firebase-user')),
        ),
        apiBaseUrlProvider.overrideWithValue('http://localhost:8000'),
        userProfileProvider.overrideWith(
          (ref) async => UserProfile(userId: profileUserId),
        ),
        familyRoomProvider.overrideWith(() => CalendarRooms(representative)),
        scheduleHttpClientProvider.overrideWithValue(client),
      ],
      child: MaterialApp(
        home:
            home ??
            ScheduleList(
              familyRoomId: 'room-a',
              initialDate: DateTime(2026, 10, 25),
            ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('선택 날짜 일정·상세와 월 이동을 실제 요청 형식으로 확인한다', (tester) async {
    final months = <String>[];
    final client = MockClient((request) async {
      expect(request.headers['Authorization'], 'Bearer id-token');
      expect(request.url.queryParameters['family_room_id'], 'room-a');
      months.add(request.url.queryParameters['month']!);
      return http.Response(
        jsonEncode({
          'results': request.url.queryParameters['month'] == '10'
              ? [event(25, '오전 돌봄'), event(26, '다음 날 돌봄')]
              : [],
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    addTearDown(client.close);
    await mountCalendar(tester, client);
    expect(find.text('오전 돌봄'), findsOneWidget);
    expect(find.text('다음 날 돌봄'), findsNothing);
    await tester.tap(find.text('오전 돌봄'));
    await tester.pumpAndSettle();
    expect(find.text('식사 챙기기'), findsOneWidget);
    await tester.tap(find.byTooltip('닫기'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('schedule-day-26')));
    await tester.pumpAndSettle();
    expect(find.text('다음 날 돌봄'), findsOneWidget);
    await tester.tap(find.byTooltip('다음 달'));
    await tester.pumpAndSettle();
    expect(find.text('2026년 11월'), findsOneWidget);
    expect(find.text('등록된 돌봄 일정이 없어요'), findsOneWidget);
    expect(months, containsAll(['10', '11']));
    expect(tester.takeException(), isNull);
  });

  testWidgets('일반 가족도 목록을 조회하고 등록 버튼은 보이지 않는다', (tester) async {
    final client = MockClient(
      (request) async => http.Response('{"results":[]}', 200),
    );
    addTearDown(client.close);
    await mountCalendar(tester, client, representative: false);
    expect(find.text('돌봄 일정'), findsOneWidget);
    expect(find.byKey(const ValueKey('schedule-add')), findsNothing);
  });

  testWidgets('일반 가족의 홈 일정 메뉴도 달력으로 이동한다', (tester) async {
    final client = MockClient(
      (request) async => http.Response('{"results":[]}', 200),
    );
    addTearDown(client.close);
    await mountCalendar(
      tester,
      client,
      representative: false,
      home: const FamilyRoomHome(),
    );
    await tester.ensureVisible(find.text('일정'));
    await tester.tap(find.text('일정'));
    await tester.pumpAndSettle();
    expect(find.text('돌봄 일정'), findsOneWidget);
    expect(find.byKey(const ValueKey('schedule-add')), findsNothing);
  });

  testWidgets('조회 실패는 빈 일정으로 숨기지 않고 재시도한다', (tester) async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return calls == 1
          ? http.Response(
              '{"detail":"서버 연결 오류"}',
              503,
              headers: {'content-type': 'application/json; charset=utf-8'},
            )
          : http.Response(
              '{"results":[]}',
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
    });
    addTearDown(client.close);
    await mountCalendar(tester, client);
    expect(find.text('서버 연결 오류'), findsOneWidget);
    await tester.tap(find.text('다시 조회'));
    await tester.pumpAndSettle();
    expect(find.text('등록된 돌봄 일정이 없어요'), findsOneWidget);
  });

  testWidgets('등록 화면이 달력 선택 날짜를 이어받는다', (tester) async {
    final client = MockClient(
      (request) async => http.Response('{"results":[]}', 200),
    );
    addTearDown(client.close);
    await mountCalendar(tester, client);
    await tester.tap(find.byKey(const ValueKey('schedule-add')));
    await tester.pumpAndSettle();
    expect(find.text('2026-10-25'), findsOneWidget);
    expect(find.text('일정명 (선택)'), findsOneWidget);
  });

  testWidgets('등록 후 등록한 월과 날짜를 선택하고 목록을 다시 조회한다', (tester) async {
    final months = <String>[];
    final client = MockClient((request) async {
      months.add(request.url.queryParameters['month']!);
      return http.Response('{"results":[]}', 200);
    });
    addTearDown(client.close);
    await mountCalendar(tester, client);
    await tester.tap(find.byKey(const ValueKey('schedule-add')));
    await tester.pumpAndSettle();
    // 저장 API는 별도로 검증하고 여기서는 등록 화면의 반환 계약을 확인한다.
    Navigator.of(
      tester.element(find.byType(ScheduleCreate)),
    ).pop((date: DateTime(2026, 11, 3), published: false));
    await tester.pumpAndSettle();
    expect(find.text('2026년 11월'), findsOneWidget);
    expect(find.text('11월 3일'), findsOneWidget);
    expect(months.last, '11');
    expect(find.text('일정이 등록되었습니다. 가족 알림은 발행 대기 중입니다.'), findsOneWidget);
  });

  testWidgets('좁은 화면의 여섯 주 달력과 오늘 버튼이 정상 동작한다', (tester) async {
    final client = MockClient(
      (request) async => http.Response('{"results":[]}', 200),
    );
    addTearDown(client.close);
    await mountCalendar(
      tester,
      client,
      home: ScheduleList(
        familyRoomId: 'room-a',
        initialDate: DateTime(2026, 8, 31),
      ),
    );
    await tester.binding.setSurfaceSize(const Size(360, 640));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('schedule-day-31')), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('오늘'));
    await tester.pumpAndSettle();
    final now = DateTime.now();
    expect(find.text('${now.year}년 ${now.month}월'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
