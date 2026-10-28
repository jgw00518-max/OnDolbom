import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:ondolbom/theme/app_theme.dart';
import 'package:ondolbom/view/widgets/app_text_scale.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ondolbom/firebase_options.dart';
import 'package:ondolbom/view/auth/login_view.dart';
import 'package:ondolbom/view/auth/widgets/login_loading_view.dart';
import 'package:ondolbom/view/home.dart';
import 'package:ondolbom/vm/auth/auth_vm.dart';
import 'package:ondolbom/model/auth/login_preferences.dart';
import 'package:ondolbom/model/auth/kakao_login.dart';
import 'package:flutter/foundation.dart';
import 'package:ondolbom/model/notifications/push_service.dart';
import 'package:ondolbom/view/widgets/push_bridge.dart';

final _pushNavigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  // 네이티브 Firebase 호출 전에 Flutter 바인딩을 준비한다.
  WidgetsFlutterBinding.ensureInitialized();
  KakaoLogin.initialize();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    // 자동 로그인 옵션을 앱 화면 표시 전에 적용한다.
    final push = !kIsWeb && defaultTargetPlatform == TargetPlatform.android
        ? PushService(
            platform: AndroidPushPlatform(),
            auth: FirebaseAuth.instance,
            baseUrl: const String.fromEnvironment(
              'API_BASE_URL',
              defaultValue: 'http://10.0.2.2:8000',
            ),
          )
        : null;
    await restoreLoginSession(
      FirebaseAuth.instance,
      LoginPreferences(),
      beforeSignOut: push?.detach,
    );
    // 앱 전체에서 같은 Riverpod 인증 상태를 읽도록 최상위에 둔다.
    runApp(
      ProviderScope(
        overrides: [
          pushServiceProvider.overrideWithValue(push),
          beforeSignOutProvider.overrideWithValue(push?.detach ?? () async {}),
        ],
        child: const MyApp(),
      ),
    );
  } catch (_) {
    // 초기화 실패 상태에서 인증 화면을 실행하지 않고 재실행 안내를 표시한다.
    runApp(
      ProviderScope(
        child: MaterialApp(
          theme: AppTheme.light,
          builder: (context, child) =>
              AppTextScale(child: child ?? const SizedBox.shrink()),
          home: const Scaffold(
            body: Center(
              child: Text(
                '로그인 초기화에 실패했습니다.\n'
                '앱 설정을 확인하고 다시 실행해 주세요.',
                textAlign: TextAlign.center,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // 앱 재실행 시 복원된 세션과 이후 로그인·로그아웃 변화를 함께 감시한다.
    final session = ref.watch(authUserProvider);

    return MaterialApp(
      locale: const Locale('ko', 'KR'),
      supportedLocales: const [
        Locale('ko', 'KR')
      ],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate
      ],
      debugShowCheckedModeBanner: false,
      title: '온돌봄',
      navigatorKey: _pushNavigatorKey,
      theme: AppTheme.light,
      // Navigator 바깥에 적용해 열린 화면과 팝업에도 같은 글씨 크기를 전달한다.
      builder: (context, child) => PushBridge(
        navigatorKey: _pushNavigatorKey,
        child: AppTextScale(child: child ?? const SizedBox.shrink()),
      ),
      // 세션 복원 중에는 로그인 화면을 먼저 띄우지 않는다.
      // Firebase 로그인 성공 이후의 MySQL 등록 여부는 Home에서 별도로 확인한다.
      home: session.when(
        loading: () => const LoginLoadingView(),
        error: (_, _) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () {
                ref.invalidate(authUserProvider);
              },
              child: const Text('로그인 상태를 불러오지 못했습니다. 다시 시도'),
            ),
          ),
        ),
        data: (user) {
          if (user == null) {
            return const LoginView();
          }

          return const Home();
        },
      ),
    );
  }
}
