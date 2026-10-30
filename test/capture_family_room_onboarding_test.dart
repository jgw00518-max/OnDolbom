// 실제 앱 위젯을 예시 데이터로 렌더링해 안내용 화면을 촬영한다.
// flutter test --dart-define=CAPTURE_ONBOARDING=true test/capture_family_room_onboarding_test.dart
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondolbom/model/auth/user_profile.dart';
import 'package:ondolbom/model/family/family_member.dart';
import 'package:ondolbom/model/family/family_room.dart';
import 'package:ondolbom/model/family/participate.dart';
import 'package:ondolbom/theme/app_theme.dart';
import 'package:ondolbom/view/family_room/family_room_list.dart';
import 'package:ondolbom/view/family_room/family_room_home.dart';
import 'package:ondolbom/vm/auth/auth_vm.dart';
import 'package:ondolbom/vm/auth/user_profile_vm.dart';
import 'package:ondolbom/vm/activity/activity_vm.dart';
import 'package:ondolbom/vm/chats/chat_notifications_vm.dart';
import 'package:ondolbom/vm/family_room/family_room_notifier.dart';
import 'package:ondolbom/vm/family_room/family_room_state.dart';
import 'package:ondolbom/vm/family_room/family_member_vm.dart';
import 'package:ondolbom/vm/schedules/schedule_vm.dart';

class CaptureRooms extends FamilyRoomNotifier {
  @override
  FamilyRoomState build() => FamilyRoomState(
    rooms: const [
      FamilyRoom(
        familyRoomId: 'example',
        createdBy: 'example',
        careRecipientName: '김온돌',
        careAddress: '서울시 · 예시 돌봄 공간',
      ),
    ],
    selectedRoomId: 'example',
    participations: {
      'example': Participate(
        participateSeq: 1,
        userId: 'example',
        familyRoomId: 'example',
        isRepresentative: true,
        joinedAt: DateTime(2026),
      ),
    },
  );
  @override
  Future<void> fetchRooms() async {}
}

class CaptureActivity extends ActivityVm {
  @override
  ActivityCounts build() => const ActivityCounts();
}

void main() {
  testWidgets('안내용 실제 돌봄 공간 화면 촬영', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final font = FontLoader('Pretendard')
      ..addFont(rootBundle.load('assets/fonts/Pretendard-Regular.otf'))
      ..addFont(rootBundle.load('assets/fonts/Pretendard-Bold.otf'));
    await font.load();
    // 위젯 테스트의 기본 사각 글꼴 대신 앱 글꼴을 사용하고 실제 아이콘도 로드한다.
    for (final family in ['Ahem', 'Roboto']) {
      await (FontLoader(family)
            ..addFont(rootBundle.load('assets/fonts/Pretendard-Regular.otf')))
          .load();
    }
    await (FontLoader(
      'MaterialIcons',
    )..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf'))).load();
    final today = DateTime.now();
    final container = ProviderContainer(
      overrides: [
        familyRoomProvider.overrideWith(CaptureRooms.new),
        authUserProvider.overrideWith((ref) => Stream.value(null)),
        userProfileProvider.overrideWith(
          (ref) async => const UserProfile(userId: 'example', name: '김가족'),
        ),
        activityProvider.overrideWith(CaptureActivity.new),
        chatUnreadProvider.overrideWith((ref) async => {}),
        scheduleListProvider((
          familyRoomId: 'example',
          year: today.year,
          month: today.month,
        )).overrideWith((ref) async => []),
        familyMembersProvider('example').overrideWith(
          (ref) async => [
            for (var i = 0; i < 3; i++)
              FamilyMember(
                participateSeq: i,
                userId: 'example-$i',
                isRepresentative: i == 0,
                joinedAt: DateTime(2026),
                name: ['김가족', '이가족', '박가족'][i],
              ),
          ],
        ),
      ],
    );
    addTearDown(container.dispose);
    final key = GlobalKey();
    final targets = <String, dynamic>{};
    Future<void> useAppFallbackFont() async {
      // 일부 기존 메뉴는 글꼴을 생략한다. 테스트 엔진의 사각 기본 글꼴만
      // 앱의 실제 Pretendard로 대체하며 위젯·문구·데이터·레이아웃 코드는 그대로 사용한다.
      for (final paragraph
          in tester.allRenderObjects.whereType<RenderParagraph>()) {
        final span = paragraph.text;
        if (span is TextSpan && span.style?.fontFamily == null) {
          paragraph.text = TextSpan(
            text: span.text,
            children: span.children,
            style: (span.style ?? const TextStyle()).copyWith(
              fontFamily: 'Pretendard',
            ),
            recognizer: span.recognizer,
            semanticsLabel: span.semanticsLabel,
          );
        }
      }
      await tester.pump();
    }

    Future<void> mount(Widget screen) async {
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light,
            home: RepaintBoundary(key: key, child: screen),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await useAppFallbackFont();
    }

    void target(String id, String image, Finder finder) {
      final rect = tester.getRect(finder.first);
      targets[id] = {
        'image': image,
        'rect': [
          rect.left / 390,
          rect.top / 844,
          rect.width / 390,
          rect.height / 844,
        ],
      };
    }

    Future<void> capture(String name) async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await tester.runAsync(() async {
        final image = await boundary.toImage(pixelRatio: 2);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        final file = File('assets/images/onboarding/$name.png');
        await file.parent.create(recursive: true);
        await file.writeAsBytes(data!.buffer.asUint8List());
        image.dispose();
      });
    }

    await mount(const FamilyRoomList());
    target('create', 'rooms', find.byType(FloatingActionButton));
    target(
      'enter',
      'rooms',
      find.ancestor(of: find.text('김온돌 돌봄 공간'), matching: find.byType(InkWell)),
    );
    target('menu', 'rooms', find.byType(IconButton));
    await capture('rooms');
    final scaffold = tester.state<ScaffoldState>(find.byType(Scaffold).first);
    scaffold.openDrawer();
    await tester.pumpAndSettle();
    await useAppFallbackFont();
    final first = tester.getRect(find.widgetWithText(ListTile, '초대'));
    final last = tester.getRect(find.widgetWithText(ListTile, '개인 설정'));
    final rect = first.expandToInclude(last);
    targets['drawer'] = {
      'image': 'drawer',
      'rect': [
        rect.left / 390,
        rect.top / 844,
        rect.width / 390,
        rect.height / 844,
      ],
    };
    await capture('drawer');
    scaffold.closeDrawer();
    await tester.pumpAndSettle();
    await mount(const FamilyRoomHome());
    await tester.drag(find.byType(ListView).first, const Offset(0, -200));
    await tester.pumpAndSettle();
    for (final name in ['투약일지', '실시간 채팅', '메모', '일정', '대상자 정보', '공간 설정']) {
      target(name, 'home', find.widgetWithText(OutlinedButton, name));
    }
    await capture('home');
    await tester.runAsync(
      () async => File(
        'assets/images/onboarding/targets.json',
      ).writeAsString(const JsonEncoder.withIndent('  ').convert(targets)),
    );
    expect(tester.takeException(), isNull);
  }, skip: !const bool.fromEnvironment('CAPTURE_ONBOARDING'));
}
