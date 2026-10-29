import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondolbom/model/family/family_member.dart';
import 'package:ondolbom/theme/app_theme.dart';
import 'package:ondolbom/view/family_room/space_settings_view.dart';
import 'package:ondolbom/view/family_room/family_room_home.dart';
import 'package:ondolbom/vm/family_room/family_room_notifier.dart';
import 'package:ondolbom/vm/family_room/family_member_vm.dart';
import 'package:ondolbom/vm/auth/auth_vm.dart';
import 'family_room_delete_test.dart' show DeleteRooms, guardianProvider;

void main() {
  for (final guardian in [true, false]) {
    testWidgets('공간 설정의 역할별 관리 버튼과 종료 확인: $guardian', (tester) async {
      await tester.binding.setSurfaceSize(Size(guardian ? 390 : 320, 1900));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final container = ProviderContainer(
        overrides: [
          guardianProvider.overrideWithValue(guardian),
          authUserProvider.overrideWith((ref) => Stream.value(null)),
          familyRoomProvider.overrideWith(DeleteRooms.new),
          familyMembersProvider('room-a').overrideWith(
            (ref) async => [
              FamilyMember(
                participateSeq: 1,
                userId: 'owner',
                isRepresentative: true,
                joinedAt: DateTime(2026),
                name: '주보호자',
              ),
              FamilyMember(
                participateSeq: 2,
                userId: 'member',
                isRepresentative: false,
                joinedAt: DateTime(2026),
                name: '테스트 가족',
              ),
            ],
          ),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light,
            home: const SpaceSettingsView(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('테스트 가족'), findsNothing);
      expect(
        tester.getTopLeft(find.text('메모 및 채팅 내보내기')).dy,
        greaterThan(tester.getTopLeft(find.text('공간 관리')).dy),
      );
      expect(find.text('가족 초대'), guardian ? findsOneWidget : findsNothing);
      expect(find.text('돌봄 공간 삭제'), guardian ? findsOneWidget : findsNothing);
      await tester.tap(find.text('함께하는 가족'));
      await tester.pumpAndSettle();
      expect(find.text('테스트 가족'), findsOneWidget);
      expect(
        find.byTooltip('주보호자 이전'),
        guardian ? findsOneWidget : findsNothing,
      );
      expect(find.byTooltip('가족 강퇴'), guardian ? findsOneWidget : findsNothing);
      if (guardian) {
        await tester.tap(find.byTooltip('가족 강퇴'));
        await tester.pumpAndSettle();
        expect(find.text('가족을 강퇴할까요?'), findsOneWidget);
        await tester.tap(find.text('취소'));
        await tester.pumpAndSettle();
      }
      await tester.tap(find.byTooltip('이전 화면'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('공간에서 나가기'));
      await tester.tap(find.text('공간에서 나가기'));
      await tester.pumpAndSettle();
      expect(
        find.textContaining(guardian ? '먼저 주보호자 이전' : '공간에서 나갈까요?'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('일반 돌봄 공간 메인에 설정이 있고 이전 관리 진입점은 없다', (tester) async {
    final container = ProviderContainer(
      overrides: [
        guardianProvider.overrideWithValue(false),
        authUserProvider.overrideWith((ref) => Stream.value(null)),
        familyRoomProvider.overrideWith(DeleteRooms.new),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(theme: AppTheme.light, home: const FamilyRoomHome()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('공간 설정'), findsOneWidget);
    expect(find.text('함께하는 가족'), findsNothing);
    expect(find.byType(PopupMenuButton<String>), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
