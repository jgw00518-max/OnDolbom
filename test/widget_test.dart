import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:ondolbom/main.dart';
import 'package:ondolbom/model/auth/app_user.dart';
import 'package:ondolbom/vm/auth/auth_vm.dart';
import 'package:ondolbom/vm/auth/user_profile_vm.dart';

// 실제 계정을 생성하지 않고 Firebase 호출 결과와 화면 전환을 검증한다.
class FakeCredential extends Fake implements UserCredential {}

class FakeAuth extends Fake implements FirebaseAuth {
  String? email;
  String? password;
  int registrations = 0;
  int logouts = 0;
  FirebaseAuthException? failure;

  @override
  Future<UserCredential> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    if (failure != null) throw failure!;
    this.email = email;
    this.password = password;
    return FakeCredential();
  }

  @override
  Future<UserCredential> createUserWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    registrations++;
    return signInWithEmailAndPassword(email: email, password: password);
  }

  @override
  Future<void> signOut() async {
    logouts++;
  }
}

void main() {
  testWidgets('Session changes switch screens and logout calls Firebase', (
    tester,
  ) async {
    final controller = StreamController<AppUser?>();
    addTearDown(controller.close);
    final auth = FakeAuth();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          firebaseAuthProvider.overrideWithValue(auth),
          authUserProvider.overrideWith((ref) => controller.stream),
          userProfileProvider.overrideWith((ref) async => null),
        ],
        child: const MyApp(),
      ),
    );
    controller.add(const AppUser(uid: 'test', email: 'family@example.com'));
    await tester.pumpAndSettle();
    expect(find.text('family@example.com'), findsOneWidget);
    await tester.tap(find.text('로그아웃'));
    await tester.pumpAndSettle();
    expect(auth.logouts, 1);
    controller.add(null);
    await tester.pumpAndSettle();
    expect(find.text('온돌봄 로그인'), findsOneWidget);
  });
}