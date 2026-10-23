import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:ondolbom/view/family_room_list.dart';

void main() {
  runApp(const ProviderScope(
    child : MyApp(),
  )
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Flutter Demo',
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
      home: const FamilyRoomList(),
    );
  }
}
