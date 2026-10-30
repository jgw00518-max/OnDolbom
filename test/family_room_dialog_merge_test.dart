import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondolbom/l10n/app_strings.dart';
import 'package:ondolbom/model/family/family_room.dart';
import 'package:ondolbom/theme/app_colors.dart';
import 'package:ondolbom/theme/app_theme.dart';
import 'package:ondolbom/view/family_room/family_room_delete_dialog.dart';
import 'package:ondolbom/view/family_room/space_settings_view.dart';
import 'package:ondolbom/vm/auth/auth_vm.dart';
import 'package:ondolbom/vm/family_room/family_room_notifier.dart';
import 'family_room_delete_test.dart' show DeleteRooms;

void main() {
  Future<void> mount(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(390, 1500);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          authUserProvider.overrideWith((ref) => Stream.value(null)),
          familyRoomProvider.overrideWith(DeleteRooms.new),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          locale: const Locale('en', 'US'),
          supportedLocales: AppStrings.supportedLocales,
          localizationsDelegates: const [
            AppStrings.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: child,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('공간 삭제 다이얼로그는 최신 다크 모드·영어 설정에서도 이름 확인을 유지한다', (tester) async {
    await mount(
      tester,
      const Scaffold(
        body: FamilyRoomDeleteDialog(
          room: FamilyRoom(
            familyRoomId: 'room-a',
            createdBy: 'owner',
            careRecipientName: '김돌봄',
          ),
        ),
      ),
    );
    expect(find.text('Delete this care space?'), findsOneWidget);
    expect(
      tester.widget<Dialog>(find.byType(Dialog)).backgroundColor,
      AppPalette.dark.background,
    );
    final confirm = find.byKey(const Key('family-room-delete-confirm'));
    expect(tester.widget<FilledButton>(confirm).onPressed, isNull);
    await tester.enterText(
      find.byKey(const Key('family-room-delete-name')),
      '김돌봄',
    );
    await tester.pump();
    expect(tester.widget<FilledButton>(confirm).onPressed, isNotNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('주보호자 이전 안내는 다크 모드·영어 설정에서도 Snackbar 대신 다이얼로그를 연다', (
    tester,
  ) async {
    await mount(tester, const SpaceSettingsView());
    final leave = find.byIcon(Icons.logout);
    await tester.ensureVisible(leave);
    await tester.pumpAndSettle();
    await tester.tap(leave);
    await tester.pumpAndSettle();
    expect(
      find.text('Transfer the primary guardian role first'),
      findsOneWidget,
    );
    expect(
      tester.widget<Dialog>(find.byType(Dialog)).backgroundColor,
      AppPalette.dark.background,
    );
    expect(find.byType(SnackBar), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
