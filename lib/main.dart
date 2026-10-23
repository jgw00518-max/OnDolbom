import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ondolbom/firebase_options.dart';
import 'package:ondolbom/view/auth/login_view.dart';
import 'package:ondolbom/vm/auth/auth_vm.dart';
import 'package:ondolbom/view/home.dart';

Future<void> main() async {
  // 네이티브 Firebase 호출 전에 Flutter 바인딩을 준비한다.
  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    // 앱 전체에서 같은 Riverpod 인증 상태를 읽도록 최상위에 둔다.
    runApp(const ProviderScope(child: MyApp()));
  } catch (_) {
    // 초기화 실패 상태에서 인증 화면을 실행하지 않고 재실행 안내를 표시한다.
    runApp(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Text(
              'Firebase 초기화에 실패했습니다.\n플랫폼 설정을 확인하고 앱을 다시 실행해 주세요.',
              textAlign: TextAlign.center,
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
      title: '온돌봄',
      theme: ThemeData(
        useMaterial3: true,

        colorScheme:
            ColorScheme.fromSeed(
              seedColor: const Color(0xFFAD5B32),
              brightness: Brightness.light,
            ).copyWith(
              primary: const Color(0xFFAD5B32),
              onPrimary: Colors.white,
              surface: const Color(0xFFFFFBF7),
              onSurface: const Color(0xFF333333),
              secondaryContainer: const Color(0xFFFFE9D8),
              onSecondaryContainer: const Color(0xFF875634),
              outline: const Color(0xFFD8C6BA),
            ),

        scaffoldBackgroundColor: const Color(0xFFFFFBF7),

        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFFFFBF7),
          foregroundColor: Color(0xFFAD5B32),
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          titleTextStyle: TextStyle(
            color: Color(0xFFAD5B32),
            fontSize: 28,
            fontWeight: FontWeight.bold,
          ),
        ),

        cardTheme: CardThemeData(
          color: const Color(0xFFFFF3E9),
          surfaceTintColor: Colors.transparent,
          elevation: 0,
          margin: const EdgeInsets.only(bottom: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: const BorderSide(color: Color(0xFFF1BE9E)),
          ),
        ),
      ),
      // 세션 복원 중에는 로그인 화면을 먼저 띄우지 않는다.
      // Firebase 로그인 성공 이후의 MySQL 등록 여부는 Home에서 별도로 확인한다.
      home: session.when(
        loading: () =>
            const Scaffold(body: Center(child: CircularProgressIndicator())),
        error: (_, _) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => ref.invalidate(authUserProvider),
              child: const Text('로그인 상태를 불러오지 못했습니다. 다시 시도'),
            ),
          ),
        ),
        data: (user) => user == null ? const LoginView() : const Home(),
      ),
    );
  }
}
