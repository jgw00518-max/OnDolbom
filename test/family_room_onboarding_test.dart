import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondolbom/model/auth/app_user.dart';
import 'package:ondolbom/model/family/family_room_onboarding_preferences.dart';
import 'package:ondolbom/model/family/family_room_onboarding_step.dart';
import 'package:ondolbom/theme/app_theme.dart';
import 'package:ondolbom/view/family_room/family_room_onboarding.dart';
import 'package:ondolbom/vm/auth/auth_vm.dart';
import 'package:ondolbom/vm/family_room/family_room_onboarding_vm.dart';

class MemoryOnboardingPreferences extends FamilyRoomOnboardingPreferences {
  bool completed = false, failRead = false, failWrite = false;
  int writes = 0;
  @override
  Future<bool> readCompleted() async {
    if (failRead) throw StateError('읽기 실패');
    return completed;
  }

  @override
  Future<void> complete() async {
    writes++;
    if (failWrite) throw StateError('저장 실패');
    completed = true;
  }
}

ProviderContainer containerFor(
  MemoryOnboardingPreferences preferences, {
  bool loggedIn = true,
  bool repeatOnLogin = false,
}) => ProviderContainer(
  overrides: [
    familyRoomOnboardingRepeatOnLoginProvider.overrideWithValue(repeatOnLogin),
    familyRoomOnboardingPreferencesProvider.overrideWithValue(preferences),
    authUserProvider.overrideWithValue(
      AsyncData(loggedIn ? const AppUser(uid: 'example-user') : null),
    ),
  ],
);

Future<void> mount(
  WidgetTester tester,
  ProviderContainer container, {
  double scale = 1,
  ThemeMode mode = ThemeMode.light,
  GlobalKey? preview,
}) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: mode,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: RepaintBoundary(
          key: preview,
          child: const FamilyRoomOnboardingGate(
            child: Scaffold(body: Center(child: Text('실제 돌봄 공간 목록'))),
          ),
        ),
      ),
    ),
  );
  // 이미지 파일 읽기·디코딩은 실제 비동기 구간에서 완료시킨다.
  await tester.runAsync(() async {
    await FamilyRoomOnboardingStep.load();
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await tester.pump();
    }
  });
  await tester.pumpAndSettle();
}

void main() {
  test('10개 페이지가 실제 스크린샷 안의 유효한 강조 영역을 가진다', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final steps = await FamilyRoomOnboardingStep.load();
    expect(steps.length, 10);
    for (final step in steps) {
      expect(step.target.left, greaterThanOrEqualTo(0));
      expect(step.target.top, greaterThanOrEqualTo(0));
      expect(step.target.right, lessThanOrEqualTo(1));
      expect(step.target.bottom, lessThanOrEqualTo(1));
      expect(step.target.width, greaterThan(0));
      expect(
        (await rootBundle.load(step.image)).lengthInBytes,
        greaterThan(1000),
      );
    }
  });

  test('동시 표시를 막고 완료 상태를 다음 앱 세션에서도 읽는다', () async {
    final preferences = MemoryOnboardingPreferences();
    final first = containerFor(preferences);
    final vm = first.read(familyRoomOnboardingProvider.notifier);
    expect(await vm.begin(), true);
    expect(await vm.begin(), false);
    await vm.finish();
    expect(preferences.completed, true);
    first.dispose();
    final next = containerFor(preferences);
    addTearDown(next.dispose);
    expect(
      await next.read(familyRoomOnboardingProvider.notifier).begin(),
      false,
    );
  });

  test('저장소 읽기 실패가 기존 화면을 차단하지 않는다', () async {
    final c = containerFor(MemoryOnboardingPreferences()..failRead = true);
    addTearDown(c.dispose);
    expect(await c.read(familyRoomOnboardingProvider.notifier).begin(), false);
    expect(c.read(familyRoomOnboardingProvider), false);
  });

  testWidgets('로그인 후 최초 표시, 건너뛰기 즉시 종료 및 재진입 시 미표시', (tester) async {
    final preferences = MemoryOnboardingPreferences();
    final c = containerFor(preferences);
    addTearDown(c.dispose);
    await mount(tester, c);
    expect(find.byType(FamilyRoomOnboarding), findsOneWidget);
    expect(find.text('1 / 10'), findsOneWidget);
    await tester.tap(find.text('건너뛰기'));
    await tester.pumpAndSettle();
    expect(find.byType(FamilyRoomOnboarding), findsNothing);
    expect(find.text('실제 돌봄 공간 목록'), findsOneWidget);
    expect(preferences.completed, true);
    await tester.pumpWidget(const SizedBox());
    await mount(tester, c);
    expect(find.byType(FamilyRoomOnboarding), findsNothing);
  });

  testWidgets('다음·양방향 스와이프·페이지 표시·마지막 시작하기', (tester) async {
    final preferences = MemoryOnboardingPreferences();
    final c = containerFor(preferences);
    addTearDown(c.dispose);
    await mount(tester, c);
    await tester.tap(find.text('다음'));
    await tester.pumpAndSettle();
    expect(find.text('2 / 10'), findsOneWidget);
    await tester.drag(find.byType(PageView), const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(find.text('3 / 10'), findsOneWidget);
    await tester.drag(find.byType(PageView), const Offset(600, 0));
    await tester.pumpAndSettle();
    expect(find.text('2 / 10'), findsOneWidget);
    for (var i = 0; i < 8; i++) {
      await tester.tap(find.text('다음'));
      await tester.pumpAndSettle();
    }
    expect(find.text('10 / 10'), findsOneWidget);
    expect(find.text('시작하기'), findsOneWidget);
    await tester.tap(find.text('시작하기'));
    await tester.pumpAndSettle();
    expect(find.byType(FamilyRoomOnboarding), findsNothing);
    expect(preferences.writes, 1);
  });

  testWidgets('핫 리로드 뒤 안내 데이터를 다시 읽어 화면을 유지한다', (tester) async {
    final c = containerFor(MemoryOnboardingPreferences());
    addTearDown(c.dispose);
    await mount(tester, c);
    tester.binding.buildOwner!.reassemble(tester.binding.rootElement!);
    await mount(tester, c);
    expect(find.byType(FamilyRoomOnboarding), findsOneWidget);
    expect(find.text('1 / 10'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('비로그인 상태에서는 온보딩을 띄우지 않는다', (tester) async {
    final c = containerFor(MemoryOnboardingPreferences(), loggedIn: false);
    addTearDown(c.dispose);
    await mount(tester, c);
    expect(find.byType(FamilyRoomOnboarding), findsNothing);
  });

  testWidgets('완료 저장 실패여도 건너뛰기 후 같은 실행에서 다시 표시하지 않는다', (tester) async {
    final preferences = MemoryOnboardingPreferences()..failWrite = true;
    final c = containerFor(preferences);
    addTearDown(c.dispose);
    await mount(tester, c);
    await tester.tap(find.text('건너뛰기'));
    await tester.pumpAndSettle();
    expect(find.byType(FamilyRoomOnboarding), findsNothing);
    expect(await c.read(familyRoomOnboardingProvider.notifier).begin(), false);
  });

  for (final size in [const Size(320, 568), const Size(844, 390)]) {
    testWidgets('작은 화면·가로 화면·큰 글씨·다크 모드에서 겹침 없이 이동: $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final c = containerFor(MemoryOnboardingPreferences());
      addTearDown(c.dispose);
      await mount(tester, c, scale: 2, mode: ThemeMode.dark);
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('다음'));
      await tester.pumpAndSettle();
      expect(find.text('2 / 10'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('사진 원본 비율과 전체 영역을 유지하고 주변 여백을 확보한다', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final c = containerFor(MemoryOnboardingPreferences());
    addTearDown(c.dispose);
    await mount(tester, c);
    final image = tester.getRect(
      find.byKey(const ValueKey('onboarding-image-0')),
    );
    final pages = tester.getRect(find.byType(PageView));
    expect(image.width / image.height, closeTo(390 / 844, 0.0001));
    expect(image.left, greaterThanOrEqualTo(pages.left + 24));
    expect(image.right, lessThanOrEqualTo(pages.right - 24));
    expect(image.top, greaterThanOrEqualTo(pages.top + 12));
    expect(844 - pages.bottom, lessThanOrEqualTo(48));
    expect(image.bottom, lessThanOrEqualTo(pages.bottom - 12));
    final firstStep = (await tester.runAsync(
      FamilyRoomOnboardingStep.load,
    ))!.first;
    expect(
      image.top + firstStep.target.bottom * image.height,
      lessThanOrEqualTo(pages.bottom - 3),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('개발 모드는 완료 기록이 있어도 로그인마다 다시 표시한다', (tester) async {
    final auth = StreamController<AppUser?>();
    final preferences = MemoryOnboardingPreferences()..completed = true;
    final c = ProviderContainer(
      overrides: [
        familyRoomOnboardingPreferencesProvider.overrideWithValue(preferences),
        familyRoomOnboardingRepeatOnLoginProvider.overrideWithValue(true),
        authUserProvider.overrideWith((ref) => auth.stream),
      ],
    );
    addTearDown(() async {
      c.dispose();
      await auth.close();
    });
    await mount(tester, c);
    auth.add(const AppUser(uid: 'same-user'));
    await mount(tester, c);
    expect(find.byType(FamilyRoomOnboarding), findsOneWidget);
    await tester.tap(find.text('건너뛰기'));
    await mount(tester, c);
    await tester.pumpWidget(const SizedBox());
    await mount(tester, c);
    expect(find.byType(FamilyRoomOnboarding), findsNothing);
    auth.add(null);
    await mount(tester, c);
    auth.add(const AppUser(uid: 'same-user'));
    await mount(tester, c);
    expect(find.byType(FamilyRoomOnboarding), findsOneWidget);
  });

  testWidgets('기본 설정에서는 완료 후 같은 계정으로 재로그인해도 다시 표시하지 않는다', (tester) async {
    final auth = StreamController<AppUser?>();
    final preferences = MemoryOnboardingPreferences();
    final c = ProviderContainer(
      overrides: [
        familyRoomOnboardingPreferencesProvider.overrideWithValue(preferences),
        authUserProvider.overrideWith((ref) => auth.stream),
      ],
    );
    addTearDown(() async {
      c.dispose();
      await auth.close();
    });
    await mount(tester, c);
    auth.add(const AppUser(uid: 'same-user'));
    await mount(tester, c);
    expect(find.byType(FamilyRoomOnboarding), findsOneWidget);
    await tester.tap(find.text('건너뛰기'));
    await mount(tester, c);
    await tester.pumpWidget(const SizedBox());
    await mount(tester, c);
    expect(find.byType(FamilyRoomOnboarding), findsNothing);
    auth.add(null);
    await mount(tester, c);
    auth.add(const AppUser(uid: 'same-user'));
    await mount(tester, c);
    expect(find.byType(FamilyRoomOnboarding), findsNothing);
  });

  testWidgets(
    '스크린샷 미리보기 저장',
    (tester) async {
      final directory = const String.fromEnvironment('ONBOARDING_PREVIEW_DIR');
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await (FontLoader('Pretendard')
            ..addFont(rootBundle.load('assets/fonts/Pretendard-Regular.otf')))
          .load();
      final c = containerFor(MemoryOnboardingPreferences());
      addTearDown(c.dispose);
      final key = GlobalKey();
      await mount(tester, c, preview: key);
      for (final (page, name) in [
        (0, 'onboarding-create'),
        (4, 'onboarding-medication'),
      ]) {
        if (page > 0) {
          for (var i = 0; i < page; i++) {
            await tester.tap(find.text('다음'));
            await tester.pumpAndSettle();
          }
        }
        // 페이지를 넘긴 뒤 해당 사진의 실제 디코딩이 끝난 후 촬영한다.
        await tester.runAsync(() async {
          final step = (await FamilyRoomOnboardingStep.load())[page];
          await precacheImage(AssetImage(step.image), key.currentContext!);
        });
        await tester.pumpAndSettle();
        final boundary =
            key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          await Directory(directory).create(recursive: true);
          await File(
            '$directory/$name.png',
          ).writeAsBytes(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
    },
    skip: const String.fromEnvironment('ONBOARDING_PREVIEW_DIR').isEmpty,
  );
}
