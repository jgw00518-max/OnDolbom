import 'package:ondolbom/vm/family_room/family_room_onboarding_vm.dart';
import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ondolbom/model/auth/app_user.dart';
import 'package:ondolbom/model/auth/user_profile.dart';
import 'package:ondolbom/model/family/family_room.dart';
import 'package:ondolbom/model/family/participate.dart';
import 'package:ondolbom/theme/app_theme.dart';
import 'package:ondolbom/view/family_room/family_room_delete_dialog.dart';
import 'package:ondolbom/view/family_room/family_room_home.dart';
import 'package:ondolbom/view/family_room/family_room_list.dart';
import 'package:ondolbom/vm/auth/auth_vm.dart';
import 'package:ondolbom/vm/auth/user_profile_vm.dart' as profile;
import 'package:ondolbom/vm/family_room/family_room_notifier.dart';
import 'package:ondolbom/vm/family_room/family_room_state.dart';

// 공간 삭제 검사는 개발용 온보딩 표시와 분리한다.
class DeleteTestOnboarding extends FamilyRoomOnboardingVm {
  @override
  Future<bool> begin() async => false;
}

class DeleteUser extends Fake implements User {
  Future<String?> Function() token = () async => 'verified-token';
  @override
  String get uid => 'firebase-user';
  @override
  Future<String?> getIdToken([bool forceRefresh = false]) => token();
}

class DeleteAuth extends Fake implements FirebaseAuth {
  User? user = DeleteUser();
  @override
  User? get currentUser => user;
}

final guardianProvider = Provider<bool>((ref) => true);

class DeleteRooms extends FamilyRoomNotifier {
  @override
  FamilyRoomState build() {
    super.build();
    return FamilyRoomState(
      selectedRoomId: 'room-a',
      rooms: const [
        FamilyRoom(
          familyRoomId: 'room-a',
          createdBy: 'someone-else',
          careRecipientName: '김돌봄',
        ),
        FamilyRoom(
          familyRoomId: 'room-b',
          createdBy: 'user-a',
          careRecipientName: '이가족',
        ),
      ],
      participations: {
        'room-b': Participate(
          participateSeq: 2,
          userId: 'user-a',
          familyRoomId: 'room-b',
          isRepresentative: false,
          joinedAt: DateTime(2026, 10, 1),
        ),
        'room-a': Participate(
          participateSeq: 1,
          userId: 'user-a',
          familyRoomId: 'room-a',
          isRepresentative: ref.watch(guardianProvider),
          joinedAt: DateTime(2026, 10, 1),
        ),
      },
    );
  }
}

http.Response deletedResponse() => http.Response(
  jsonEncode({
    'result': 'OK',
    'family_room_id': 'room-a',
    'family_room_deleted_at': '2026-10-27T17:30:00',
    'already_deleted': false,
  }),
  200,
);

Future<void> deleteRoom(ProviderContainer container, {String name = '김돌봄'}) =>
    container
        .read(familyRoomProvider.notifier)
        .deleteRoom(
          familyRoomId: 'room-a',
          recipientName: '김돌봄',
          confirmationName: name,
        );

void main() {
  ProviderContainer setup(
    http.Client client, {
    bool guardian = true,
    DeleteAuth? auth,
  }) {
    final container = ProviderContainer(
      overrides: [
        familyRoomOnboardingProvider.overrideWith(DeleteTestOnboarding.new),
        firebaseAuthProvider.overrideWithValue(auth ?? DeleteAuth()),
        authUserProvider.overrideWith(
          (ref) => Stream.value(const AppUser(uid: 'firebase-user')),
        ),
        guardianProvider.overrideWithValue(guardian),
        familyRoomProvider.overrideWith(DeleteRooms.new),
        familyRoomHttpClientProvider.overrideWithValue(client),
        profile.apiBaseUrlProvider.overrideWithValue('http://localhost:8000'),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(client.close);
    return container;
  }

  test('현재 주보호자가 인증 DELETE를 보내고 삭제 공간만 로컬 목록에서 제거한다', () async {
    final container = setup(
      MockClient((request) async {
        expect(request.method, 'DELETE');
        expect(
          request.url.toString(),
          'http://localhost:8000/family-room/room-a',
        );
        expect(request.headers['Authorization'], 'Bearer verified-token');
        expect(request.body, isEmpty);
        return deletedResponse();
      }),
    );
    await deleteRoom(container);
    final state = container.read(familyRoomProvider);
    expect(state.rooms.map((room) => room.familyRoomId), ['room-b']);
    expect(state.selectedRoomId, isNull);
    expect(state.participations.containsKey('room-a'), isFalse);
    expect(state.isLoading, isFalse);
  });

  test('이름 불일치와 일반 가족은 HTTP 요청 전에 차단한다', () async {
    var requests = 0;
    for (final guardian in [true, false]) {
      final container = setup(
        MockClient((_) async {
          requests++;
          return deletedResponse();
        }),
        guardian: guardian,
      );
      await expectLater(
        deleteRoom(container, name: guardian ? '다른 이름' : '김돌봄'),
        throwsA(isA<FamilyRoomDeleteFailure>()),
      );
    }
    expect(requests, 0);
  });

  test('서버 실패·타임아웃 시 공간을 지우지 않고 다시 시도할 수 있다', () async {
    for (final timeout in [false, true]) {
      var calls = 0;
      final container = setup(
        MockClient((_) async {
          if (++calls == 1) {
            if (timeout) throw TimeoutException('pending');
            return http.Response(
              jsonEncode({'detail': '현재 주보호자만 삭제할 수 있습니다.'}),
              403,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }
          return deletedResponse();
        }),
      );
      await expectLater(
        deleteRoom(container),
        throwsA(isA<FamilyRoomDeleteFailure>()),
      );
      expect(container.read(familyRoomProvider).rooms.length, 2);
      expect(container.read(familyRoomProvider).isLoading, isFalse);
      await deleteRoom(container);
      expect(container.read(familyRoomProvider).rooms.length, 1);
    }
  });

  test('토큰 대기 중 계정·공간이 바뀌면 삭제 요청을 보내지 않는다', () async {
    for (final changeAccount in [true, false]) {
      final pending = Completer<String?>();
      final auth = DeleteAuth();
      (auth.user as DeleteUser).token = () => pending.future;
      var calls = 0;
      final container = setup(
        MockClient((_) async {
          calls++;
          return deletedResponse();
        }),
        auth: auth,
      );
      final task = deleteRoom(container);
      if (changeAccount) {
        auth.user = null;
      } else {
        container.read(familyRoomProvider.notifier).selectRoom('room-b');
      }
      pending.complete('token');
      await expectLater(task, throwsA(isA<FamilyRoomDeleteFailure>()));
      expect(calls, 0);
    }
  });

  Future<void> mount(
    WidgetTester tester,
    http.Client client, {
    bool guardian = true,
    bool list = false,
    Size size = const Size(390, 844),
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(client.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          familyRoomOnboardingProvider.overrideWith(DeleteTestOnboarding.new),
          firebaseAuthProvider.overrideWithValue(DeleteAuth()),
          authUserProvider.overrideWith(
            (ref) => Stream.value(const AppUser(uid: 'firebase-user')),
          ),
          profile.userProfileProvider.overrideWith(
            (ref) async => const UserProfile(userId: 'user-a'),
          ),
          profile.apiBaseUrlProvider.overrideWithValue('http://localhost:8000'),
          guardianProvider.overrideWithValue(guardian),
          familyRoomProvider.overrideWith(DeleteRooms.new),
          familyRoomHttpClientProvider.overrideWithValue(client),
        ],
        child: MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: list ? const FamilyRoomList() : const FamilyRoomHome(),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openDialog(WidgetTester tester) async {
    await tester.ensureVisible(find.text('공간 설정'));
    await tester.tap(find.text('공간 설정'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('돌봄 공간 삭제'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('돌봄 공간 삭제'));
    await tester.pumpAndSettle();
  }

  testWidgets('일반 가족에게 삭제 메뉴를 표시하지 않는다', (tester) async {
    await mount(
      tester,
      MockClient((_) async => deletedResponse()),
      guardian: false,
    );
    await tester.ensureVisible(find.text('공간 설정'));
    await tester.tap(find.text('공간 설정'));
    await tester.pumpAndSettle();
    expect(find.text('메모 및 채팅 내보내기'), findsOneWidget);
    expect(find.text('돌봄 공간 삭제'), findsNothing);
  });

  testWidgets('대상자 이름이 일치해야 활성화되고 취소하면 요청하지 않는다', (tester) async {
    var calls = 0;
    await mount(
      tester,
      MockClient((_) async {
        calls++;
        return deletedResponse();
      }),
    );
    await openDialog(tester);
    expect(find.text('돌봄 공간을 삭제할까요?'), findsOneWidget);
    expect(find.text('모든 가족이 이 공간을 이용할 수 없게 됩니다.'), findsOneWidget);
    final button = find.byKey(const Key('family-room-delete-confirm'));
    expect(tester.widget<FilledButton>(button).onPressed, isNull);
    await tester.enterText(find.byType(TextField), '김돌');
    await tester.pump();
    expect(tester.widget<FilledButton>(button).onPressed, isNull);
    await tester.enterText(find.byType(TextField), '김돌봄');
    await tester.pump();
    expect(tester.widget<FilledButton>(button).onPressed, isNotNull);
    await tester.tap(find.text('취소'));
    await tester.pumpAndSettle();
    expect(find.byType(FamilyRoomDeleteDialog), findsNothing);
    expect(calls, 0);
  });

  testWidgets('삭제 실패는 입력을 보존하고 처리 중에는 중복 요청과 취소를 막는다', (tester) async {
    final pending = Completer<http.Response>();
    var calls = 0;
    await mount(
      tester,
      MockClient((_) {
        calls++;
        return pending.future;
      }),
    );
    await openDialog(tester);
    await tester.enterText(find.byType(TextField), '김돌봄');
    await tester.pump();
    await tester.tap(find.byKey(const Key('family-room-delete-confirm')));
    await tester.pump();
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const Key('family-room-delete-confirm')),
          )
          .onPressed,
      isNull,
    );
    expect(
      tester
          .widget<OutlinedButton>(find.widgetWithText(OutlinedButton, '취소'))
          .onPressed,
      isNull,
    );
    pending.complete(
      http.Response(
        jsonEncode({'detail': '삭제를 처리하지 못했습니다.'}),
        503,
        headers: {'content-type': 'application/json; charset=utf-8'},
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('삭제를 처리하지 못했습니다.'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '김돌봄',
    );
    expect(calls, 1);
  });

  testWidgets('작은 화면·큰 글씨·키보드가 열린 상태에서도 이름 확인과 취소에 접근한다', (tester) async {
    var calls = 0;
    await mount(
      tester,
      MockClient((_) async {
        calls++;
        return deletedResponse();
      }),
      size: const Size(320, 640),
      textScale: 1.5,
    );
    unawaited(
      showDialog<bool>(
        context: tester.element(find.byType(FamilyRoomHome)),
        barrierDismissible: false,
        builder: (_) => const FamilyRoomDeleteDialog(
          room: FamilyRoom(
            familyRoomId: 'room-a',
            createdBy: 'someone-else',
            careRecipientName: '김돌봄',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    tester.view.viewInsets = const FakeViewPadding(bottom: 240);
    addTearDown(tester.view.resetViewInsets);
    await tester.pumpAndSettle();
    final field = find.byKey(const Key('family-room-delete-name'));
    await tester.ensureVisible(field);
    await tester.pumpAndSettle();
    await tester.enterText(field, '김돌봄');
    await tester.pumpAndSettle();
    final confirm = find.byKey(const Key('family-room-delete-confirm'));
    await tester.ensureVisible(confirm);
    await tester.pumpAndSettle();
    expect(confirm.hitTestable(), findsOneWidget);
    expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
    final cancel = find.widgetWithText(OutlinedButton, '취소');
    await tester.ensureVisible(cancel);
    await tester.pumpAndSettle();
    await tester.tap(cancel);
    await tester.pumpAndSettle();
    expect(find.byType(FamilyRoomDeleteDialog), findsNothing);
    expect(calls, 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('삭제 성공 후 목록으로 복귀해 새 목록을 조회한다', (tester) async {
    var deleted = false;
    var gets = 0;
    await mount(
      tester,
      MockClient((request) async {
        if (request.method == 'DELETE') {
          deleted = true;
          return deletedResponse();
        }
        gets++;
        return http.Response(
          jsonEncode({
            'results': [
              for (final id in [if (!deleted) 'room-a', 'room-b'])
                {
                  'family_room': {
                    'family_room_id': id,
                    'created_by': 'user-a',
                    'care_recipient_name': id == 'room-a' ? '김돌봄' : '이가족',
                  },
                  'participate': {
                    'participate_seq': 1,
                    'user_id': 'user-a',
                    'family_room_id': id,
                    'is_representative': 1,
                    'joined_at': '2026-10-01T00:00:00',
                  },
                },
            ],
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
      list: true,
    );
    await tester.ensureVisible(find.text('김돌봄 돌봄 공간'));
    await tester.tap(find.text('김돌봄 돌봄 공간'));
    await tester.pumpAndSettle();
    await openDialog(tester);
    await tester.enterText(find.byType(TextField), '김돌봄');
    await tester.pump();
    await tester.tap(find.byKey(const Key('family-room-delete-confirm')));
    await tester.pumpAndSettle();
    expect(find.byType(FamilyRoomHome), findsNothing);
    expect(find.text('김돌봄 돌봄 공간'), findsNothing);
    expect(
      find.text('이가족 돌봄 공간'),
      findsOneWidget,
      reason: tester
          .widgetList<Text>(find.byType(Text))
          .map((text) => text.data)
          .join('\n'),
    );
    expect(gets, 2);
    expect(tester.takeException(), isNull);
  });
}
