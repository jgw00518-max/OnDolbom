import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondolbom/model/family/family_member.dart';
import 'package:ondolbom/view/family_room/family_room_member_summary.dart';
import 'package:ondolbom/vm/family_room/family_member_vm.dart';

void main() {
  testWidgets('실제 전체 인원과 세 가족 미리보기를 표시한다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          familyMembersProvider('room').overrideWith(
            (ref) async => [
              for (var i = 0; i < 4; i++)
                FamilyMember(
                  participateSeq: i,
                  userId: 'user-$i',
                  isRepresentative: i == 0,
                  joinedAt: DateTime(2026),
                  name: ['김가족', '이가족', '박가족', '최가족'][i],
                ),
            ],
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(body: FamilyRoomMemberSummary(familyRoomId: 'room')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('4명이 함께하고 있어요'), findsOneWidget);
    expect(find.byTooltip('김가족'), findsOneWidget);
    expect(find.byTooltip('박가족'), findsOneWidget);
    expect(find.byTooltip('최가족'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('조회 실패를 임의의 인원으로 표시하지 않는다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          familyMembersProvider(
            'room',
          ).overrideWith((ref) async => throw Exception('offline')),
        ],
        child: const MaterialApp(
          home: Scaffold(body: FamilyRoomMemberSummary(familyRoomId: 'room')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('참여 가족 다시 조회'), findsOneWidget);
    expect(find.text('0명이 함께하고 있어요'), findsNothing);
  });
}
