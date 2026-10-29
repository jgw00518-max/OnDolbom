import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ondolbom/model/auth/app_user.dart';
import 'package:ondolbom/theme/app_theme.dart';
import 'package:ondolbom/view/family_room/family_member_list.dart';
import 'package:ondolbom/view/family_room/representative_transfer_dialog.dart';
import 'package:ondolbom/vm/auth/auth_vm.dart';
import 'package:ondolbom/vm/family_room/family_member_vm.dart';
import 'package:ondolbom/vm/family_room/family_room_notifier.dart';

import 'family_room_delete_test.dart' as fixture;

http.Response response(Map<String, dynamic> body, [int status = 200]) =>
    http.Response(
      jsonEncode(body),
      status,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );

http.Response transferredResponse() => response({
  'result': 'OK',
  'family_room_id': 'room-a',
  'previous_representative_user_id': 'user-a',
  'representative_user_id': 'user-b',
});

Future<void> transfer(
  ProviderContainer container, {
  String target = 'user-b',
}) => container
    .read(familyRoomProvider.notifier)
    .transferRepresentative(familyRoomId: 'room-a', targetUserId: target);

void main() {
  ProviderContainer setup(
    http.Client client, {
    bool representative = true,
    fixture.DeleteAuth? auth,
  }) {
    final container = ProviderContainer(
      overrides: [
        firebaseAuthProvider.overrideWithValue(auth ?? fixture.DeleteAuth()),
        authUserProvider.overrideWith(
          (ref) => Stream.value(const AppUser(uid: 'firebase-user')),
        ),
        fixture.guardianProvider.overrideWithValue(representative),
        familyRoomProvider.overrideWith(fixture.DeleteRooms.new),
        familyRoomHttpClientProvider.overrideWithValue(client),
        familyMemberHttpClientProvider.overrideWithValue(client),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(client.close);
    return container;
  }

  Future<void> mount(WidgetTester tester, ProviderContainer container) async {
    tester.view.physicalSize = const Size(320, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(1.2)),
            child: child!,
          ),
          home: const FamilyMemberList(familyRoomId: 'room-a'),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  http.Response membersResponse({bool transferred = false}) => response({
    'results': [
      {
        'participate_seq': 1,
        'user_id': 'user-a',
        'is_representative': transferred ? 0 : 1,
        'joined_at': '2026-10-01',
        'name': '기존 주보호자',
      },
      {
        'participate_seq': 3,
        'user_id': 'user-b',
        'is_representative': transferred ? 1 : 0,
        'joined_at': '2026-10-01',
        'name': '새 가족',
        'user_email': 'family@example.test',
      },
    ],
  });

  http.Response roomsResponse() => response({
    'results': [
      for (final id in ['room-a', 'room-b'])
        {
          'family_room': {
            'family_room_id': id,
            'created_by': 'original-creator',
            'care_recipient_name': id == 'room-a' ? '김돌봄' : '이가족',
          },
          'participate': {
            'participate_seq': id == 'room-a' ? 1 : 2,
            'user_id': 'user-a',
            'family_room_id': id,
            'is_representative': 0,
            'joined_at': '2026-10-01',
            'left_at': null,
          },
        },
    ],
  });

  test('인증된 이전 POST 후 해당 공간의 권한만 일반 가족으로 바꾸고 참여를 보존한다', () async {
    final container = setup(
      MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/family-room/room-a/transfer-representative');
        expect(request.headers['Authorization'], 'Bearer verified-token');
        expect(jsonDecode(request.body), {'target_user_id': 'user-b'});
        return transferredResponse();
      }),
    );
    final previous = container.read(familyRoomProvider);
    await transfer(container);
    final state = container.read(familyRoomProvider);
    expect(state.selectedParticipation!.isRepresentative, isFalse);
    expect(state.selectedParticipation!.isActive, isTrue);
    expect(
      state.selectedParticipation!.joinedAt,
      previous.selectedParticipation!.joinedAt,
    );
    expect(state.rooms, same(previous.rooms));
    expect(
      state.participations['room-b'],
      same(previous.participations['room-b']),
    );
    expect(state.isLoading, isFalse);
    await expectLater(
      transfer(container),
      throwsA(isA<RepresentativeTransferFailure>()),
    );
  });

  test('일반 가족·자기 자신·빈 대상은 요청 전에 거절한다', () async {
    var posts = 0;
    for (final scenario in [(false, 'user-b'), (true, 'user-a'), (true, '')]) {
      final container = setup(
        MockClient((_) async {
          posts++;
          return transferredResponse();
        }),
        representative: scenario.$1,
      );
      await expectLater(
        transfer(container, target: scenario.$2),
        throwsA(isA<RepresentativeTransferFailure>()),
      );
    }
    expect(posts, 0);
  });

  test('서버 거절·통신 시간 초과·다른 대상 성공 응답은 권한을 변경하지 않는다', () async {
    for (final failure in ['403', '409', 'timeout', 'malformed']) {
      final container = setup(
        MockClient((_) async {
          if (failure == 'timeout') throw TimeoutException('offline');
          if (failure == 'malformed') {
            return response({
              'result': 'OK',
              'family_room_id': 'room-a',
              'previous_representative_user_id': 'user-a',
              'representative_user_id': 'someone-else',
            });
          }
          return response({'detail': '가족 정보가 변경되었습니다.'}, int.parse(failure));
        }),
      );
      await expectLater(
        transfer(container),
        throwsA(isA<RepresentativeTransferFailure>()),
      );
      expect(
        container
            .read(familyRoomProvider)
            .selectedParticipation!
            .isRepresentative,
        isTrue,
      );
      expect(container.read(familyRoomProvider).isLoading, isFalse);
    }
  });

  test('처리 중 다른 이전 요청은 전송하지 않는다', () async {
    final pending = Completer<http.Response>();
    final requested = Completer<void>();
    var posts = 0;
    final container = setup(
      MockClient((_) {
        posts++;
        requested.complete();
        return pending.future;
      }),
    );
    final first = transfer(container);
    await requested.future;
    await expectLater(
      transfer(container),
      throwsA(isA<RepresentativeTransferFailure>()),
    );
    expect(posts, 1);
    pending.complete(transferredResponse());
    await first;
  });

  test('토큰을 기다리는 동안 공간이 바뀌면 이전 요청을 보내지 않는다', () async {
    final auth = fixture.DeleteAuth();
    final pending = Completer<String?>();
    (auth.user as fixture.DeleteUser).token = () => pending.future;
    var posts = 0;
    final container = setup(
      MockClient((_) async {
        posts++;
        return transferredResponse();
      }),
      auth: auth,
    );
    final future = transfer(container);
    final assertion = expectLater(
      future,
      throwsA(isA<RepresentativeTransferFailure>()),
    );
    container.read(familyRoomProvider.notifier).selectRoom('room-b');
    pending.complete('verified-token');
    await assertion;
    expect(posts, 0);
    expect(container.read(familyRoomProvider).selectedRoomId, 'room-b');
  });

  test('응답 대기 중 계정·공간이 바뀌면 이전 결과를 반영하지 않는다', () async {
    for (final changeAccount in [true, false]) {
      final auth = fixture.DeleteAuth();
      final pending = Completer<http.Response>();
      final requested = Completer<void>();
      final container = setup(
        MockClient((_) {
          requested.complete();
          return pending.future;
        }),
        auth: auth,
      );
      final future = transfer(container);
      final assertion = expectLater(
        future,
        throwsA(isA<RepresentativeTransferFailure>()),
      );
      await requested.future;
      if (changeAccount) {
        auth.user = null;
      } else {
        container.read(familyRoomProvider.notifier).selectRoom('room-b');
      }
      pending.complete(transferredResponse());
      await assertion;
      expect(
        container
            .read(familyRoomProvider)
            .participations['room-a']!
            .isRepresentative,
        isTrue,
      );
    }
  });

  test('이전 성공 후 재조회가 실패해도 일반 가족 권한과 공간을 유지한다', () async {
    final container = setup(
      MockClient(
        (request) async => request.method == 'POST'
            ? transferredResponse()
            : response({}, 503),
      ),
    );
    await transfer(container);
    await container
        .read(familyRoomProvider.notifier)
        .refreshRoomsPreservingState();
    final state = container.read(familyRoomProvider);
    expect(state.selectedRoomId, 'room-a');
    expect(state.rooms.length, 2);
    expect(state.selectedParticipation!.isRepresentative, isFalse);
    expect(state.errorMessage, isNotNull);
    expect(state.isLoading, isFalse);
  });

  testWidgets('이전 확인창은 대상과 영향을 표시하며 취소 시 요청하지 않는다', (tester) async {
    var posts = 0;
    final container = setup(
      MockClient((request) async {
        if (request.method == 'POST') posts++;
        return membersResponse();
      }),
    );
    await mount(tester, container);
    await tester.tap(find.byTooltip('주보호자 이전'));
    await tester.pumpAndSettle();
    expect(find.text('새 가족 님에게 주보호자를 이전합니다.'), findsOneWidget);
    expect(find.text('family@example.test'), findsNWidgets(2));
    expect(find.textContaining('나는 일반 가족으로 계속 참여'), findsOneWidget);
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(posts, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('이전 성공 후 공간·가족을 재조회하고 관리 버튼을 숨긴다', (tester) async {
    var transferred = false;
    var spaceReads = 0;
    var memberReads = 0;
    final container = setup(
      MockClient((request) async {
        if (request.method == 'POST') {
          transferred = true;
          return transferredResponse();
        }
        if (request.url.path.endsWith('/members')) {
          memberReads++;
          return membersResponse(transferred: transferred);
        }
        spaceReads++;
        return roomsResponse();
      }),
    );
    await mount(tester, container);
    await tester.tap(find.byTooltip('주보호자 이전'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('주보호자 이전'));
    await tester.pumpAndSettle();
    expect(find.byType(RepresentativeTransferDialog), findsNothing);
    expect(find.byTooltip('주보호자 이전'), findsNothing);
    expect(find.byTooltip('가족 강퇴'), findsNothing);
    expect(memberReads, greaterThanOrEqualTo(2));
    expect(spaceReads, 1);
    expect(container.read(familyRoomProvider).selectedRoomId, 'room-a');
    expect(
      container
          .read(familyRoomProvider)
          .selectedParticipation!
          .isRepresentative,
      isFalse,
    );
    expect(find.text('주보호자를 이전했습니다. 이제 일반 가족으로 참여합니다.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('이전 실패 시 확인창을 유지하며 처리 중 중복 제출·취소를 막는다', (tester) async {
    final pending = Completer<http.Response>();
    var posts = 0;
    final container = setup(
      MockClient((request) {
        if (request.method == 'POST') {
          posts++;
          return pending.future;
        }
        return Future.value(membersResponse());
      }),
    );
    await mount(tester, container);
    await tester.tap(find.byTooltip('주보호자 이전'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('주보호자 이전'));
    await tester.pump();
    await tester.tap(find.text('이전 중…'));
    expect(
      tester
          .widget<TextButton>(find.widgetWithText(TextButton, '취소'))
          .onPressed,
      isNull,
    );
    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(find.byType(RepresentativeTransferDialog), findsOneWidget);
    expect(posts, 1);
    pending.complete(response({'detail': '대상 가족이 나갔습니다.'}, 409));
    await tester.pumpAndSettle();
    expect(find.text('대상 가족이 나갔습니다.'), findsOneWidget);
    expect(find.byType(RepresentativeTransferDialog), findsOneWidget);
    expect(
      container
          .read(familyRoomProvider)
          .selectedParticipation!
          .isRepresentative,
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('확인창을 연 뒤 계정이 바뀌면 새 계정으로 요청하지 않는다', (tester) async {
    final auth = fixture.DeleteAuth();
    var posts = 0;
    final container = setup(
      MockClient((request) async {
        if (request.method == 'POST') posts++;
        return membersResponse();
      }),
      auth: auth,
    );
    await mount(tester, container);
    await tester.tap(find.byTooltip('주보호자 이전'));
    await tester.pumpAndSettle();
    auth.user = null;
    await tester.tap(find.text('주보호자 이전'));
    await tester.pumpAndSettle();
    expect(posts, 0);
    expect(find.text('로그인 상태가 변경됐어요. 화면을 다시 열어 주세요.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('일반 가족에게 이전 버튼을 표시하지 않는다', (tester) async {
    final container = setup(
      MockClient((_) async => membersResponse()),
      representative: false,
    );
    await mount(tester, container);
    expect(find.byTooltip('주보호자 이전'), findsNothing);
    expect(find.byTooltip('가족 강퇴'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
