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
import 'package:ondolbom/view/family_room_home.dart';
import 'package:ondolbom/vm/auth/auth_vm.dart';
import 'package:ondolbom/vm/auth/user_profile_vm.dart' as profile;
import 'package:ondolbom/vm/family_context.dart';
import 'package:ondolbom/vm/family_room_notifier.dart';
import 'package:ondolbom/vm/family_room_state.dart';
import 'package:ondolbom/vm/memos/memo_vm.dart';
import 'package:ondolbom/vm/medications/medication_vm.dart';

class CareUser extends Fake implements User {
  @override
  String get uid => 'firebase-uid';
  @override
  Future<String?> getIdToken([bool forceRefresh = false]) async => 'id-token';
}

class CareAuth extends Fake implements FirebaseAuth {
  User? user = CareUser();
  @override
  User? get currentUser => user;
}

class CareRooms extends FamilyRoomNotifier {
  @override
  FamilyRoomState build() => const FamilyRoomState(
    selectedRoomId: 'room-a',
    rooms: [
      FamilyRoom(
        familyRoomId: 'room-a',
        createdBy: 'db-user',
        careRecipientName: '가족 A',
      ),
      FamilyRoom(
        familyRoomId: 'room-b',
        createdBy: 'db-user',
        careRecipientName: '가족 B',
      ),
    ],
  );
}

void main() {
  for (final menu in ['메모', '투약일지']) {
    testWidgets('$menu 메뉴는 선택 공간과 로그인 토큰으로 조회한다', (tester) async {
      final calls = <String>[];
      final client = MockClient((request) async {
        expect(request.url.host, 'localhost');
        expect(request.url.queryParameters['family_room_id'], 'room-a');
        expect(request.headers['Authorization'], 'Bearer id-token');
        calls.add(request.url.path);
        return http.Response(jsonEncode({'results': []}), 200);
      });
      addTearDown(client.close);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            firebaseAuthProvider.overrideWithValue(CareAuth()),
            authUserProvider.overrideWith(
              (ref) => Stream.value(const AppUser(uid: 'firebase-uid')),
            ),
            profile.userProfileProvider.overrideWith(
              (ref) async => const UserProfile(userId: 'db-user'),
            ),
            profile.apiBaseUrlProvider.overrideWithValue(
              'http://localhost:8000',
            ),
            familyRoomProvider.overrideWith(CareRooms.new),
            memoHttpClientProvider.overrideWithValue(client),
            medicationHttpClientProvider.overrideWithValue(client),
          ],
          child: const MaterialApp(home: FamilyRoomHome()),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text(menu));
      await tester.tap(find.text(menu));
      await tester.pumpAndSettle();
      expect(
        calls,
        contains(menu == '메모' ? '/memos/select' : '/medications/select'),
      );
      expect(find.text('가족 A 님의 돌봄 공간'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  test('공간 변경은 실제 선택 상태를 따르고 로그아웃 후 이전 토큰을 사용하지 않는다', () async {
    final auth = CareAuth();
    final container = ProviderContainer(
      overrides: [
        firebaseAuthProvider.overrideWithValue(auth),
        authUserProvider.overrideWith(
          (ref) => Stream.value(const AppUser(uid: 'firebase-uid')),
        ),
        profile.userProfileProvider.overrideWith(
          (ref) async => const UserProfile(userId: 'db-user'),
        ),
        familyRoomProvider.overrideWith(CareRooms.new),
      ],
    );
    addTearDown(container.dispose);
    final sessionSub = container.listen(authUserProvider, (_, _) {});
    final profileSub = container.listen(profile.userProfileProvider, (_, _) {});
    addTearDown(sessionSub.close);
    addTearDown(profileSub.close);
    await container.read(authUserProvider.future);
    await container.read(profile.userProfileProvider.future);
    expect(container.read(familyContextProvider).userId, 'db-user');
    container.read(familyRoomProvider.notifier).selectRoom('room-b');
    expect(container.read(familyContextProvider).familyRoomId, 'room-b');
    final loadToken = container.read(apiTokenLoaderProvider);
    expect(await loadToken(), 'id-token');
    auth.user = null;
    expect(await loadToken(), isNull);
  });

  test('토큰이 없으면 두 기능 모두 API 요청을 보내지 않는다', () async {
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return http.Response('{"results":[]}', 200);
    });
    addTearDown(client.close);
    final container = ProviderContainer(
      overrides: [
        apiTokenLoaderProvider.overrideWithValue(() async => null),
        memoHttpClientProvider.overrideWithValue(client),
        medicationHttpClientProvider.overrideWithValue(client),
      ],
    );
    addTearDown(container.dispose);
    const context = (
      familyRoomId: 'room-a',
      userId: 'db-user',
      roomName: '가족 A',
    );
    final memoSub = container.listen(memoVmProvider(context), (_, _) {});
    final medSub = container.listen(
      medicationVmProvider((context: context, date: '2026-10-24')),
      (_, _) {},
    );
    addTearDown(memoSub.close);
    addTearDown(medSub.close);
    await expectLater(
      container.read(memoVmProvider(context).future),
      throwsA(isA<MemoFailure>()),
    );
    await expectLater(
      container.read(
        medicationVmProvider((context: context, date: '2026-10-24')).future,
      ),
      throwsA(isA<MedicationFailure>()),
    );
    expect(calls, 0);
  });
}
