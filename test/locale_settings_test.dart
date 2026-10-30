import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ondolbom/l10n/app_strings.dart';
import 'package:ondolbom/l10n/english_strings.dart';
import 'package:ondolbom/model/settings/locale_preferences.dart';
import 'package:ondolbom/vm/settings/locale_vm.dart';
import 'package:ondolbom/vm/settings/theme_vm.dart';
import 'package:ondolbom/theme/app_theme.dart';
import 'package:ondolbom/view/auth/personal_settings_view.dart';
import 'package:ondolbom/view/auth/login_view.dart';
import 'package:ondolbom/model/settings/text_size_preferences.dart';
import 'package:ondolbom/model/auth/login_preferences.dart';
import 'package:ondolbom/model/auth/app_user.dart';
import 'package:ondolbom/model/auth/user_profile.dart';
import 'package:ondolbom/vm/auth/auth_vm.dart';
import 'package:ondolbom/vm/auth/user_profile_vm.dart';
import 'package:ondolbom/vm/family_room/family_room_notifier.dart';
import 'package:ondolbom/vm/schedules/schedule_vm.dart';
import 'package:ondolbom/view/schedules/schedule_list.dart';
import 'text_size_test.dart' show MemoryTextSizePreferences;
import 'login_preferences_test.dart' show MemoryPreferences;
import 'schedule_list_test.dart' as calendar;

class MemoryLocalePreferences extends LocalePreferences {
  Locale locale = const Locale('ko', 'KR');
  bool fail = false;
  @override
  Future<Locale> read() async => locale;
  @override
  Future<void> write(String value) async {
    if (fail) throw StateError('offline');
    locale = value == 'en'
        ? const Locale('en', 'US')
        : const Locale('ko', 'KR');
  }
}

class LanguageHarness extends ConsumerWidget {
  const LanguageHarness({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context, WidgetRef ref) => MaterialApp(
    locale:
        ref.watch(localeSettingProvider).asData?.value.locale ??
        const Locale('ko', 'KR'),
    supportedLocales: AppStrings.supportedLocales,
    localizationsDelegates: const [
      AppStrings.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    theme: AppTheme.light,
    darkTheme: AppTheme.dark,
    themeMode:
        ref.watch(themeModeProvider).asData?.value.mode ?? ThemeMode.light,
    home: child,
  );
}

void main() {
  test('언어는 저장·복원되고 실패 시 이전 언어를 유지한다', () async {
    final preferences = MemoryLocalePreferences();
    final first = ProviderContainer(
      overrides: [localePreferencesProvider.overrideWithValue(preferences)],
    );
    addTearDown(first.dispose);
    await first.read(localeSettingProvider.future);
    await first.read(localeSettingProvider.notifier).select('en');
    expect(
      first.read(localeSettingProvider).requireValue.locale.languageCode,
      'en',
    );
    final restored = ProviderContainer(
      overrides: [localePreferencesProvider.overrideWithValue(preferences)],
    );
    addTearDown(restored.dispose);
    expect(
      (await restored.read(localeSettingProvider.future)).locale.languageCode,
      'en',
    );
    preferences.fail = true;
    await restored.read(localeSettingProvider.notifier).select('ko');
    expect(
      restored.read(localeSettingProvider).requireValue.locale.languageCode,
      'en',
    );
    expect(restored.read(localeSettingProvider).requireValue.error, isNotNull);
  });
  test('번역의 자리표시자는 원문의 인자를 보존한다', () {
    final pattern = RegExp(r'\{(\d+)\}');
    for (final entry in englishStrings.entries) {
      final source = pattern
          .allMatches(entry.key)
          .map((m) => m.group(1))
          .toSet();
      final translated = pattern
          .allMatches(entry.value)
          .map((m) => m.group(1))
          .toSet();
      expect(translated, source, reason: entry.key);
    }
  });
  testWidgets('설정에서 영어와 한국어를 전환하고 다크 모드·사용자 이름은 유지한다', (tester) async {
    tester.view.physicalSize = const Size(390, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final preferences = MemoryLocalePreferences();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localePreferencesProvider.overrideWithValue(preferences),
          initialThemeModeProvider.overrideWithValue(ThemeMode.dark),
          textSizePreferencesProvider.overrideWithValue(
            MemoryTextSizePreferences(),
          ),
          authUserProvider.overrideWith(
            (ref) => Stream.value(const AppUser(uid: 'user')),
          ),
          userProfileProvider.overrideWith(
            (ref) async => const UserProfile(userId: 'user', name: '테스트 가족'),
          ),
        ],
        child: const LanguageHarness(child: PersonalSettingsView()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byType(DropdownButton<String>));
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('English').last);
    await tester.pumpAndSettle();
    expect(find.text('Personal settings'), findsOneWidget);
    expect(find.text('Language'), findsOneWidget);
    expect(find.text('Dark mode'), findsOneWidget);
    expect(find.text('테스트 가족'), findsOneWidget);
    expect(preferences.locale.languageCode, 'en');
    expect(
      Theme.of(tester.element(find.byType(PersonalSettingsView))).brightness,
      Brightness.dark,
    );
    await tester.tap(find.byType(DropdownButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('한국어').last);
    await tester.pumpAndSettle();
    expect(find.text('개인 설정'), findsOneWidget);
    expect(preferences.locale.languageCode, 'ko');
    expect(tester.takeException(), isNull);
  });
  testWidgets('영어 로그인 화면은 작은 화면에서도 표시된다', (tester) async {
    tester.view.physicalSize = const Size(320, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          initialLocaleProvider.overrideWithValue(const Locale('en', 'US')),
          initialThemeModeProvider.overrideWithValue(ThemeMode.light),
          loginPreferencesProvider.overrideWithValue(MemoryPreferences()),
        ],
        child: const LanguageHarness(child: LoginView()),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Sign in'), findsWidgets);
    expect(find.text('Password'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('영어 달력은 요일을 번역하고 사용자 일정명과 API 값은 유지한다', (tester) async {
    tester.view.physicalSize = const Size(430, 1100);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final client = MockClient((request) async {
      expect(request.url.queryParameters['family_room_id'], 'room-a');
      return http.Response(
        jsonEncode({
          'results': [calendar.event(25, '내가 쓴 일정')],
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    });
    addTearDown(client.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          initialLocaleProvider.overrideWithValue(const Locale('en', 'US')),
          initialThemeModeProvider.overrideWithValue(ThemeMode.light),
          firebaseAuthProvider.overrideWithValue(calendar.CalendarAuth()),
          authUserProvider.overrideWith(
            (ref) => Stream.value(const AppUser(uid: 'firebase-user')),
          ),
          userProfileProvider.overrideWith(
            (ref) async => const UserProfile(userId: 'family-user'),
          ),
          familyRoomProvider.overrideWith(() => calendar.CalendarRooms(true)),
          scheduleHttpClientProvider.overrideWithValue(client),
        ],
        child: LanguageHarness(
          child: ScheduleList(
            familyRoomId: 'room-a',
            initialDate: DateTime(2026, 10, 25),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Sun'), findsOneWidget);
    expect(find.text('Mon'), findsOneWidget);
    expect(find.text('내가 쓴 일정'), findsOneWidget);
    expect(find.text('Incomplete'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('번역 인자에 포함된 사용자 문자열은 재번역하거나 다시 치환하지 않는다', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          initialLocaleProvider.overrideWithValue(const Locale('en', 'US')),
          initialThemeModeProvider.overrideWithValue(ThemeMode.light),
        ],
        child: LanguageHarness(
          child: Builder(
            builder: (context) => Scaffold(
              body: Text(AppStrings.format(context, '{0} 님', ['온돌봄 {1}'])),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('온돌봄 {1}'), findsOneWidget);
  });
}
