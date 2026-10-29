import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondolbom/model/settings/text_size_preferences.dart';
import 'package:ondolbom/model/auth/app_user.dart';
import 'package:ondolbom/model/auth/login_preferences.dart';
import 'package:ondolbom/model/auth/user_profile.dart';
import 'package:ondolbom/view/auth/personal_settings_view.dart';
import 'package:ondolbom/view/widgets/app_text_scale.dart';
import 'package:ondolbom/vm/auth/auth_vm.dart';
import 'package:ondolbom/vm/auth/user_profile_vm.dart';
import 'package:ondolbom/vm/settings/text_size_vm.dart';
import 'login_preferences_test.dart' show MemoryPreferences;

class MemoryTextSizePreferences extends TextSizePreferences {
  AppTextSize size = AppTextSize.medium;
  bool fail = false;
  int writes = 0;
  Completer<void>? pending;
  @override
  Future<AppTextSize> read() async => size;
  @override
  Future<void> write(AppTextSize value) async {
    writes++;
    if (pending != null) await pending!.future;
    if (fail) throw StateError('storage unavailable');
    size = value;
  }
}

class NonlinearTestScaler extends TextScaler {
  const NonlinearTestScaler();
  @override
  double scale(double fontSize) =>
      fontSize < 20 ? fontSize * 1.5 : fontSize * 1.2;
  @override
  double get textScaleFactor => 1.5;
}

void main() {
  test('저장 실패 시 현재 크기를 유지하고 중복 저장을 차단하며 재실행 시 복원한다', () async {
    final preferences = MemoryTextSizePreferences();
    final container = ProviderContainer(
      overrides: [textSizePreferencesProvider.overrideWithValue(preferences)],
    );
    final sub = container.listen(textSizeProvider, (_, _) {});
    addTearDown(() {
      sub.close();
      container.dispose();
    });
    expect(
      (await container.read(textSizeProvider.future)).size,
      AppTextSize.medium,
    );
    preferences.pending = Completer<void>();
    preferences.fail = true;
    final saved = container
        .read(textSizeProvider.notifier)
        .select(AppTextSize.large);
    await container.read(textSizeProvider.notifier).select(AppTextSize.small);
    expect(preferences.writes, 1);
    expect(
      container.read(textSizeProvider).requireValue.size,
      AppTextSize.medium,
    );
    preferences.pending!.complete();
    await saved;
    expect(container.read(textSizeProvider).requireValue.error, isNotNull);
    preferences.fail = false;
    await container.read(textSizeProvider.notifier).select(AppTextSize.large);
    expect(
      container.read(textSizeProvider).requireValue.size,
      AppTextSize.large,
    );
    final restarted = ProviderContainer(
      overrides: [textSizePreferencesProvider.overrideWithValue(preferences)],
    );
    final restartedSub = restarted.listen(textSizeProvider, (_, _) {});
    addTearDown(() {
      restartedSub.close();
      restarted.dispose();
    });
    expect(
      (await restarted.read(textSizeProvider.future)).size,
      AppTextSize.large,
    );
  });

  test('시스템의 비선형 글씨 배율을 덮어쓰지 않고 앱 배율을 추가 적용한다', () {
    const system = NonlinearTestScaler();
    const scaler = AppTextScaler(system, 1.2);
    expect(scaler.scale(12), closeTo(system.scale(12) * 1.2, 0.001));
    expect(scaler.scale(28), closeTo(system.scale(28) * 1.2, 0.001));
    expect(scaler, const AppTextScaler(system, 1.2));
  });

  testWidgets('설정에서 선택한 크기를 기존 화면·새 화면·팝업에 같은 배율로 전달한다', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final preferences = MemoryTextSizePreferences();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          textSizePreferencesProvider.overrideWithValue(preferences),
          loginPreferencesProvider.overrideWithValue(MemoryPreferences()),
          authUserProvider.overrideWith(
            (ref) => Stream.value(
              const AppUser(uid: 'uid', email: 'family@example.com'),
            ),
          ),
          userProfileProvider.overrideWith(
            (ref) async => const UserProfile(userId: 'db', name: '가족'),
          ),
        ],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(1.3)),
            child: AppTextScale(child: child!),
          ),
          home: const PersonalSettingsView(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('크게'), 180);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(OutlinedButton, '크게'));
    await tester.pumpAndSettle();
    expect(preferences.size, AppTextSize.large);
    expect(
      MediaQuery.textScalerOf(tester.element(find.text('크게'))).scale(16),
      closeTo(16 * 1.3 * 1.2, 0.001),
    );
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    unawaited(
      navigator.push(
        MaterialPageRoute<void>(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => const AlertDialog(content: Text('팝업 크기 확인')),
                ),
                child: const Text('새 화면'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(
      MediaQuery.textScalerOf(tester.element(find.text('새 화면'))).scale(16),
      closeTo(16 * 1.3 * 1.2, 0.001),
    );
    await tester.tap(find.text('새 화면'));
    await tester.pumpAndSettle();
    expect(
      MediaQuery.textScalerOf(tester.element(find.text('팝업 크기 확인'))).scale(16),
      closeTo(16 * 1.3 * 1.2, 0.001),
    );
    expect(tester.takeException(), isNull);
  });
}
