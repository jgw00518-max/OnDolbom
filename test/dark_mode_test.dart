import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondolbom/model/settings/theme_preferences.dart';
import 'package:ondolbom/vm/settings/theme_vm.dart';
import 'package:ondolbom/model/settings/text_size_preferences.dart';
import 'package:ondolbom/model/auth/login_preferences.dart';
import 'package:ondolbom/model/auth/app_user.dart';
import 'package:ondolbom/model/auth/user_profile.dart';
import 'package:ondolbom/theme/app_theme.dart';
import 'package:ondolbom/theme/app_colors.dart';
import 'package:ondolbom/view/auth/personal_settings_view.dart';
import 'package:ondolbom/view/auth/login_view.dart';
import 'package:ondolbom/vm/auth/auth_vm.dart';
import 'package:ondolbom/vm/auth/user_profile_vm.dart';
import 'text_size_test.dart' show MemoryTextSizePreferences;
import 'login_preferences_test.dart' show MemoryPreferences;

class MemoryThemePreferences extends ThemePreferences {
  ThemeMode mode = ThemeMode.light;
  bool fail = false;
  @override
  Future<ThemeMode> read() async => mode;
  @override
  Future<void> write(ThemeMode value) async {
    if (fail) throw StateError('disk');
    mode = value;
  }
}

class ThemeHarness extends ConsumerWidget {
  const ThemeHarness({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp(
    theme: AppTheme.light,
    darkTheme: AppTheme.dark,
    themeMode:
        ref.watch(themeModeProvider).asData?.value.mode ?? ThemeMode.light,
    home: child,
  );
}

void main() {
  test('다크 모드 선택은 저장되고 새 Provider에서도 복원한다', () async {
    final preferences = MemoryThemePreferences();
    final container = ProviderContainer(
      overrides: [themePreferencesProvider.overrideWithValue(preferences)],
    );
    addTearDown(container.dispose);
    await container.read(themeModeProvider.future);
    await container.read(themeModeProvider.notifier).select(true);
    expect(container.read(themeModeProvider).requireValue.mode, ThemeMode.dark);
    final restored = ProviderContainer(
      overrides: [themePreferencesProvider.overrideWithValue(preferences)],
    );
    addTearDown(restored.dispose);
    expect(
      (await restored.read(themeModeProvider.future)).mode,
      ThemeMode.dark,
    );
    await restored.read(themeModeProvider.notifier).select(false);
    expect(preferences.mode, ThemeMode.light);
  });
  test('저장 실패 시 이전 모드를 유지하고 오류를 안내한다', () async {
    final preferences = MemoryThemePreferences()..fail = true;
    final container = ProviderContainer(
      overrides: [themePreferencesProvider.overrideWithValue(preferences)],
    );
    addTearDown(container.dispose);
    await container.read(themeModeProvider.future);
    await container.read(themeModeProvider.notifier).select(true);
    final setting = container.read(themeModeProvider).requireValue;
    expect(setting.mode, ThemeMode.light);
    expect(setting.error, isNotNull);
    expect(setting.saving, false);
  });
  test('다크 테마 본문·보조 글씨와 버튼의 명암 대비를 확보한다', () {
    double contrast(Color a, Color b) {
      final x = a.computeLuminance(), y = b.computeLuminance();
      return ((x > y ? x : y) + .05) / ((x > y ? y : x) + .05);
    }

    expect(
      contrast(AppPalette.dark.textPrimary, AppPalette.dark.surface),
      greaterThan(7),
    );
    expect(
      contrast(AppPalette.dark.textSecondary, AppPalette.dark.surface),
      greaterThan(4.5),
    );
    expect(
      contrast(AppColors.textPrimary, AppColors.primary),
      greaterThan(4.5),
    );
  });
  testWidgets('이미 열린 팝업도 전역 모드 변경을 반영한다', (tester) async {
    final preferences = MemoryThemePreferences();
    final container = ProviderContainer(
      overrides: [themePreferencesProvider.overrideWithValue(preferences)],
    );
    addTearDown(container.dispose);
    await container.read(themeModeProvider.future);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: ThemeHarness(
          child: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => const AlertDialog(title: Text('열린 팝업')),
                ),
                child: const Text('팝업 열기'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('팝업 열기'));
    await tester.pumpAndSettle();
    await container.read(themeModeProvider.notifier).select(true);
    await tester.pumpAndSettle();
    final theme = Theme.of(tester.element(find.byType(AlertDialog)));
    expect(theme.brightness, Brightness.dark);
    expect(theme.dialogTheme.backgroundColor, AppPalette.dark.surface);
  });
  testWidgets('개인 설정 토글은 열린 화면 테마를 바꾸고 작은 화면에서도 유지된다', (tester) async {
    tester.view.physicalSize = const Size(390, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final preferences = MemoryThemePreferences();
    final boundary = GlobalKey();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          themePreferencesProvider.overrideWithValue(preferences),
          textSizePreferencesProvider.overrideWithValue(
            MemoryTextSizePreferences(),
          ),
          authUserProvider.overrideWith(
            (ref) => Stream.value(
              const AppUser(uid: 'test', email: 'family@example.com'),
            ),
          ),
          userProfileProvider.overrideWith(
            (ref) async => const UserProfile(
              userId: 'test',
              name: '가족 사용자',
              email: 'family@example.com',
              phone: '010-1234-5678',
            ),
          ),
        ],
        child: RepaintBoundary(
          key: boundary,
          child: const ThemeHarness(child: PersonalSettingsView()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('다크 모드'));
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    expect(preferences.mode, ThemeMode.dark);
    expect(
      Theme.of(tester.element(find.byType(PersonalSettingsView))).brightness,
      Brightness.dark,
    );
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
      AppPalette.dark.background,
    );
    expect(tester.takeException(), isNull);
    if (Platform.environment['CAPTURE_DARK_THEME'] == '1') {
      await tester.runAsync(() async {
        final render =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final png = await (await render.toImage(
          pixelRatio: 1,
        )).toByteData(format: ui.ImageByteFormat.png);
        File(
          '${Platform.environment['TEMP']}/ondolbom-dark-settings.png',
        ).writeAsBytesSync(png!.buffer.asUint8List());
      });
    }
    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    expect(preferences.mode, ThemeMode.light);
  });
  testWidgets('저장된 다크 모드는 로그인 화면에도 적용된다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          initialThemeModeProvider.overrideWithValue(ThemeMode.dark),
          loginPreferencesProvider.overrideWithValue(MemoryPreferences()),
        ],
        child: const ThemeHarness(child: LoginView()),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      Theme.of(tester.element(find.byType(LoginView))).brightness,
      Brightness.dark,
    );
    expect(
      tester.widget<Scaffold>(find.byType(Scaffold)).backgroundColor,
      AppPalette.dark.background,
    );
    expect(tester.takeException(), isNull);
  });
}
