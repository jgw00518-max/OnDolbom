import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondolbom/model/invites/family_invite.dart';
import 'package:ondolbom/view/invites/received_invites.dart';
import 'package:ondolbom/vm/invites/invite_vm.dart';

FamilyInvite invite(String id, String status, {bool canResend = false}) =>
    FamilyInvite(
      inviteId: id,
      canResend: canResend,
      familyRoomId: 'room',
      inviteEmail: 'family@example.com',
      inviteAt: DateTime(2026, 10, 27, 14, 30),
      inviteStatus: status,
      recipientName: '가족',
      inviterName: '초대한 가족',
    );

class DesignInviteVm extends InviteVm {
  DesignInviteVm(super.ref);
  final cancelled = <String>[];
  final resent = <String>[];
  @override
  Future<bool> resendInvite(String inviteId) async {
    resent.add(inviteId);
    return true;
  }

  @override
  Future<void> cancelInvite(String inviteId) async {
    cancelled.add(inviteId);
  }
}

void main() {
  testWidgets('초대 탭과 실제 상태를 표시하고 수락 색상·취소 확인 동작을 유지한다', (tester) async {
    final container = ProviderContainer(
      overrides: [
        receivedInvitesProvider.overrideWith(
          (ref) async => [invite('received', '대기'), invite('expired', '만료')],
        ),
        sentInvitesProvider.overrideWith((ref) async => [invite('sent', '대기')]),
        inviteVmProvider.overrideWith((ref) => DesignInviteVm(ref)),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ReceivedInvites()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('2개의 초대가 있어요'), findsOneWidget);
    final accept = find.widgetWithText(FilledButton, '초대 수락');
    await tester.ensureVisible(accept);
    expect(
      tester.widget<FilledButton>(accept).style!.backgroundColor!.resolve({}),
      const Color(0xFFF6B08A),
    );
    await tester.tap(find.text('보낸 초대').first);
    await tester.pumpAndSettle();
    expect(find.text('1개의 초대가 있어요'), findsOneWidget);
    final cancel = find.widgetWithText(OutlinedButton, '초대 취소');
    await tester.ensureVisible(cancel);
    await tester.tap(cancel);
    await tester.pumpAndSettle();
    expect(find.text('초대를 취소할까요?'), findsOneWidget);
    expect(
      (container.read(inviteVmProvider) as DesignInviteVm).cancelled,
      isEmpty,
    );
    await tester.tap(find.widgetWithText(FilledButton, '초대 취소'));
    await tester.pumpAndSettle();
    expect((container.read(inviteVmProvider) as DesignInviteVm).cancelled, [
      'sent',
    ]);
    expect(tester.takeException(), isNull);
  });

  testWidgets('발신자용 만료 초대에서 재요청하고 새 이메일 발송 결과를 표시한다', (tester) async {
    final container = ProviderContainer(
      overrides: [
        receivedInvitesProvider.overrideWith((ref) async => []),
        sentInvitesProvider.overrideWith(
          (ref) async => [
            invite('own-expired', '만료', canResend: true),
            invite('other-expired', '만료'),
          ],
        ),
        inviteVmProvider.overrideWith((ref) => DesignInviteVm(ref)),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(home: ReceivedInvites()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('보낸 초대').first);
    await tester.pumpAndSettle();
    final button = find.widgetWithText(FilledButton, '재요청');
    expect(button, findsOneWidget);
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect((container.read(inviteVmProvider) as DesignInviteVm).resent, [
      'own-expired',
    ]);
    expect(find.textContaining('새 초대장을 이메일로 보냈습니다.'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('좁은 화면에서 만료 안내와 긴 이메일이 잘리지 않고 처리 버튼은 없다', (tester) async {
    tester.view.physicalSize = const Size(320, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          receivedInvitesProvider.overrideWith(
            (ref) async => [invite('expired', '만료')],
          ),
        ],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.3)),
            child: child!,
          ),
          home: const ReceivedInvites(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('만료'), findsOneWidget);
    expect(find.text('초대 수락'), findsNothing);
    expect(find.text('거절'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
