import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:ondolbom/firebase_options.dart';
import 'package:ondolbom/view/auth/login_view.dart';
import 'package:ondolbom/view/home.dart';
import 'package:ondolbom/vm/auth/auth_vm.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    runApp(
      const ProviderScope(
        child: MyApp(),
      ),
    );
  } catch (_) {
    runApp(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: Text(
              'Firebase 초기화에 실패했습니다.\n'
              '플랫폼 설정을 확인하고 앱을 다시 실행해 주세요.',
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
    final session = ref.watch(authUserProvider);

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: '온돌봄',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
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
            side: const BorderSide(
              color: Color(0xFFF1BE9E),
            ),
          ),
        ),
      ),
      home: session.when(
        loading: () => const Scaffold(
          body: Center(
            child: CircularProgressIndicator(),
          ),
        ),
        error: (_, _) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () {
                ref.invalidate(authUserProvider);
              },
              child: const Text(
                '로그인 상태를 불러오지 못했습니다. 다시 시도',
              ),
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