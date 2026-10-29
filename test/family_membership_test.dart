import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ondolbom/model/auth/app_user.dart';
import 'package:ondolbom/model/family/family_member.dart';
import 'package:ondolbom/view/family_room/membership_exit_dialog.dart';
import 'package:ondolbom/vm/auth/auth_vm.dart';
import 'package:ondolbom/vm/family_room/family_room_notifier.dart';
import 'family_room_delete_test.dart'
    show DeleteRooms, DeleteAuth, guardianProvider;

void main() {
  ProviderContainer setup(
    http.Client client, {
    bool guardian = false,
    DeleteAuth? auth,
  }) {
    final container = ProviderContainer(
      overrides: [
        firebaseAuthProvider.overrideWithValue(auth ?? DeleteAuth()),
        authUserProvider.overrideWith(
          (ref) => Stream.value(const AppUser(uid: 'firebase-user')),
        ),
        guardianProvider.overrideWithValue(guardian),
        familyRoomProvider.overrideWith(DeleteRooms.new),
        familyRoomHttpClientProvider.overrideWithValue(client),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(client.close);
    return container;
  }

  http.Response response({int? seq}) => http.Response(
    jsonEncode({
      'result': 'OK',
      'family_room_id': 'room-a',
      'user_id': 'user-a',
      'participate_seq': seq ?? 1,
    }),
    200,
  );

  test('일반 가족 탈퇴는 인증 POST 후 해당 공간만 로컬에서 제거한다', () async {
    final container = setup(
      MockClient((request) async {
        expect(request.url.path, '/family-room/room-a/leave');
        expect(request.method, 'POST');
        expect(request.headers['Authorization'], 'Bearer verified-token');
        return response();
      }),
    );
    await container
        .read(familyRoomProvider.notifier)
        .endMembership(familyRoomId: 'room-a');
    final state = container.read(familyRoomProvider);
    expect(state.rooms.map((room) => room.familyRoomId), ['room-b']);
    expect(state.participations.containsKey('room-a'), isFalse);
    expect(state.selectedRoomId, isNull);
  });

  test('주보호자 강퇴는 대상 참여 번호를 보내고 자신의 공간은 유지한다', () async {
    final container = setup(
      MockClient((request) async {
        expect(request.url.path, '/family-room/room-a/members/2/remove');
        return response(seq: 2);
      }),
      guardian: true,
    );
    await container
        .read(familyRoomProvider.notifier)
        .endMembership(familyRoomId: 'room-a', participateSeq: 2);
    expect(container.read(familyRoomProvider).selectedRoomId, 'room-a');
    expect(container.read(familyRoomProvider).isLoading, isFalse);
  });

  test('주보호자 탈퇴와 일반 가족의 강퇴는 요청 전에 차단한다', () async {
    var calls = 0;
    for (final guardian in [true, false]) {
      final container = setup(
        MockClient((_) async {
          calls++;
          return response();
        }),
        guardian: guardian,
      );
      await expectLater(
        container
            .read(familyRoomProvider.notifier)
            .endMembership(
              familyRoomId: 'room-a',
              participateSeq: guardian ? null : 2,
            ),
        throwsA(isA<FamilyRoomMembershipFailure>()),
      );
    }
    expect(calls, 0);
  });

  test('서버 오류·시간 초과 시 공간을 제거하지 않는다', () async {
    for (final timeout in [true, false]) {
      final container = setup(
        MockClient((_) async {
          if (timeout) throw TimeoutException('offline');
          return http.Response('{}', 503);
        }),
      );
      await expectLater(
        container
            .read(familyRoomProvider.notifier)
            .endMembership(familyRoomId: 'room-a'),
        throwsA(isA<FamilyRoomMembershipFailure>()),
      );
      expect(container.read(familyRoomProvider).selectedRoomId, 'room-a');
      expect(container.read(familyRoomProvider).isLoading, isFalse);
    }
  });

  test('응답 전에 계정이 바뀌면 이전 공간 상태를 갱신하지 않는다', () async {
    final auth = DeleteAuth();
    final pending = Completer<http.Response>();
    final requested = Completer<void>();
    final container = setup(
      MockClient((_) {
        requested.complete();
        return pending.future;
      }),
      auth: auth,
    );
    final future = container
        .read(familyRoomProvider.notifier)
        .endMembership(familyRoomId: 'room-a');
    final assertion = expectLater(
      future,
      throwsA(isA<FamilyRoomMembershipFailure>()),
    );
    await requested.future;
    auth.user = null;
    pending.complete(response());
    await assertion;
    expect(container.read(familyRoomProvider).rooms.length, 2);
  });

  testWidgets('강퇴 확인창은 취소 시 요청하지 않고 제출 중 중복 작업을 막는다', (tester) async {
    var calls = 0;
    final pending = Completer<http.Response>();
    final container = setup(
      MockClient((_) {
        calls++;
        return pending.future;
      }),
      guardian: true,
    );
    final target = FamilyMember(
      participateSeq: 2,
      userId: 'member',
      isRepresentative: false,
      joinedAt: DateTime(2026),
      name: '가족',
    );
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => showDialog<bool>(
                  context: context,
                  barrierDismissible: false,
                  builder: (_) => MembershipExitDialog(
                    familyRoomId: 'room-a',
                    target: target,
                  ),
                ),
                child: const Text('열기'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(calls, 0);
    await tester.tap(find.text('열기'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '강퇴'));
    await tester.pump();
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    pending.complete(response(seq: 2));
    await tester.pumpAndSettle();
    expect(calls, 1);
    expect(find.byType(AlertDialog), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
