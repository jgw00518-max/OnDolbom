import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondolbom/model/family/family_room.dart';
import 'package:ondolbom/model/family/participate.dart';
import 'package:ondolbom/theme/app_theme.dart';
import 'package:ondolbom/view/family_room/family_room_home.dart';
import 'package:ondolbom/view/family_room/family_room_list.dart';
import 'package:ondolbom/vm/auth/auth_vm.dart';
import 'package:ondolbom/vm/family_room/family_room_notifier.dart';
import 'package:ondolbom/vm/family_room/family_room_state.dart';
import 'family_room_delete_test.dart' show DeleteRooms;

class SwitchRooms extends DeleteRooms {
  @override
  FamilyRoomState build() {
    final original = super.build();
    return original.copyWith(
      rooms: [
        ...original.rooms,
        const FamilyRoom(
          familyRoomId: 'ended',
          createdBy: 'user-a',
          careRecipientName: '참여 종료',
        ),
      ],
      participations: {
        ...original.participations,
        'ended': Participate(
          participateSeq: 3,
          userId: 'user-a',
          familyRoomId: 'ended',
          isRepresentative: false,
          joinedAt: DateTime(2026),
          leftAt: DateTime(2026, 10),
        ),
      },
    );
  }

  @override
  Future<void> fetchRooms() async {} // 실제 DB를 사용하지 않고 현재 참여 상태로 검증한다.
}

void main() {
  Future<ProviderContainer> mount(
    WidgetTester tester, {
    bool listRoot = false,
  }) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final container = ProviderContainer(
      overrides: [
        authUserProvider.overrideWith((ref) => Stream.value(null)),
        familyRoomProvider.overrideWith(SwitchRooms.new),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light,
          home: listRoot ? const FamilyRoomList() : const FamilyRoomHome(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  testWidgets('현재 공간 표시와 활성 공간 전환, 종료 공간 제외', (tester) async {
    final container = await mount(tester);
    await tester.tap(find.byTooltip('돌봄 공간 이동'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.textContaining('현재 공간'), findsOneWidget);
    expect(find.text('참여 종료 님의 돌봄 공간'), findsNothing);
    await tester.tap(find.text('이가족 님의 돌봄 공간'));
    await tester.pumpAndSettle();
    expect(container.read(familyRoomProvider).selectedRoomId, 'room-b');
    expect(find.text('이가족 님의 돌봄 공간'), findsOneWidget);
    expect(find.byType(FamilyRoomHome), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('목록으로 복귀해 기존 목록 경로를 재사용한다', (tester) async {
    await mount(tester, listRoot: true);
    await tester.tap(find.textContaining('김돌봄').first);
    await tester.pumpAndSettle();
    expect(find.byType(FamilyRoomHome), findsOneWidget);
    await tester.tap(find.byTooltip('돌봄 공간 이동'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('돌봄 공간 목록으로'));
    await tester.pumpAndSettle();
    expect(find.byType(FamilyRoomHome), findsNothing);
    expect(find.byType(FamilyRoomList), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('공간 이동 메뉴를 닫으면 선택 상태가 바뀌지 않는다', (tester) async {
    final container = await mount(tester);
    await tester.tap(find.byTooltip('돌봄 공간 이동'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('닫기'));
    await tester.pumpAndSettle();
    expect(container.read(familyRoomProvider).selectedRoomId, 'room-a');
    expect(tester.takeException(), isNull);
  });
}
