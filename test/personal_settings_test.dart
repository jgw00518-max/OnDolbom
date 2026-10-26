import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondolbom/model/auth/app_user.dart';
import 'package:ondolbom/model/auth/login_preferences.dart';
import 'package:ondolbom/model/auth/user_profile.dart';
import 'package:ondolbom/view/auth/personal_settings_view.dart';
import 'package:ondolbom/view/family_room/family_room_home.dart';
import 'package:ondolbom/vm/auth/auth_vm.dart';
import 'package:ondolbom/vm/auth/personal_settings_vm.dart';
import 'package:ondolbom/vm/auth/user_profile_vm.dart';
import 'package:ondolbom/vm/family_room/family_room_notifier.dart';
import 'family_care_connection_test.dart' show CareRooms;
import 'login_preferences_test.dart' show MemoryPreferences;
import 'widget_test.dart' show FakeAuth;

void main() {
  testWidgets('왼쪽 끝 메뉴·왼쪽 Drawer·다섯 메뉴와 로그아웃 경로 정리를 확인한다', (tester) async {
    final auth = FakeAuth();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          firebaseAuthProvider.overrideWithValue(auth),
          authUserProvider.overrideWith(
            (ref) => Stream.value(
              const AppUser(uid: 'uid', email: 'family@example.com'),
            ),
          ),
          userProfileProvider.overrideWith(
            (ref) async => const UserProfile(userId: 'db-user', name: '가족'),
          ),
          familyRoomProvider.overrideWith(CareRooms.new),
        ],
        child: MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: TextButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const FamilyRoomHome(),
                  ),
                ),
                child: const Text('공간 진입'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('공간 진입'));
    await tester.pumpAndSettle();
    expect(find.byType(BackButton), findsNothing);
    expect(tester.getCenter(find.byTooltip('계정 메뉴')).dx, lessThan(60));
    await tester.tap(find.byTooltip('계정 메뉴'));
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byType(Drawer)).left, closeTo(0, 1));
    for (final title in ['초대', '알림', '문의', '개인 설정', '로그아웃']) {
      expect(find.text(title), findsOneWidget);
    }
    await tester.ensureVisible(find.text('로그아웃'));
    await tester.tap(find.text('로그아웃'));
    await tester.pumpAndSettle();
    expect(auth.logouts, 1);
    expect(find.text('공간 진입'), findsOneWidget);
    expect(find.byType(FamilyRoomHome), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('개인 설정에서 로그인 옵션을 기존 저장소에 반영한다', (tester) async {
    final preferences = MemoryPreferences();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          loginPreferencesProvider.overrideWithValue(preferences),
          authUserProvider.overrideWith(
            (ref) => Stream.value(
              const AppUser(uid: 'uid', email: 'family@example.com'),
            ),
          ),
          userProfileProvider.overrideWith(
            (ref) async => const UserProfile(userId: 'user', name: '가족'),
          ),
        ],
        child: const MaterialApp(home: PersonalSettingsView()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('아이디 저장'));
    await tester.pumpAndSettle();
    expect(preferences.email, 'family@example.com');
    await tester.tap(find.text('자동 로그인'));
    await tester.pumpAndSettle();
    expect(preferences.autoLogin, true);
    await tester.tap(find.text('아이디 저장'));
    await tester.pumpAndSettle();
    expect(preferences.email, isNull);
  });

  test('로그인 계정 이메일을 확인할 수 없으면 아이디 저장을 허용하지 않는다', () async {
    final preferences = MemoryPreferences();
    final container = ProviderContainer(
      overrides: [
        loginPreferencesProvider.overrideWithValue(preferences),
        authUserProvider.overrideWith((ref) => Stream.value(null)),
      ],
    );
    addTearDown(container.dispose);
    final sub = container.listen(personalSettingsProvider, (_, _) {});
    addTearDown(sub.close);
    await container.read(authUserProvider.future);
    await container.read(personalSettingsProvider.future);
    await container
        .read(personalSettingsProvider.notifier)
        .save(rememberEmail: true);
    expect(preferences.email, isNull);
    expect(container.read(personalSettingsProvider).hasError, true);
  });
}
