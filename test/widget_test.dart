import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondolbom/main.dart';
import 'package:ondolbom/model/auth/app_user.dart';
import 'package:ondolbom/vm/auth/auth_vm.dart';
import 'package:ondolbom/vm/auth/user_profile_vm.dart';

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
  test('VM trims email, preserves password, signs up and signs out', () async {
    final auth = FakeAuth();
    final container = ProviderContainer(
      overrides: [firebaseAuthProvider.overrideWithValue(auth)],
    );
    addTearDown(container.dispose);
    final vm = container.read(authVmProvider.notifier);
    await vm.signUp(' family@example.com ', ' pass word ');
    expect(auth.email, 'family@example.com');
    expect(auth.password, ' pass word ');
    expect(auth.registrations, 1);
    expect(container.read(authVmProvider).hasError, false);
    await vm.signOut();
    expect(auth.logouts, 1);
  });

  test('VM exposes authentication failure without raw error text', () async {
    final auth = FakeAuth()
      ..failure = FirebaseAuthException(
        code: 'invalid-credential',
        message: 'private',
      );
    final container = ProviderContainer(
      overrides: [firebaseAuthProvider.overrideWithValue(auth)],
    );
    addTearDown(container.dispose);
    await container
        .read(authVmProvider.notifier)
        .signIn('family@example.com', 'incorrect');
    final result = container.read(authVmProvider);
    expect(result.hasError, true);
    expect(authErrorMessage(result.error!), '이메일 또는 비밀번호를 확인해 주세요.');
    expect(authErrorMessage(result.error!), isNot(contains('private')));
  });

  testWidgets('Signed-out user sees login and signup validation', (
    tester,
  ) async {
    final auth = FakeAuth();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          firebaseAuthProvider.overrideWithValue(auth),
          authUserProvider.overrideWith((ref) => Stream.value(null)),
        ],
        child: const MyApp(),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('온돌봄 로그인'), findsOneWidget);
    await tester.tap(find.text('로그인'));
    await tester.pump();
    expect(find.text('이메일을 입력해 주세요.'), findsOneWidget);
    await tester.tap(find.text('이메일로 회원가입'));
    await tester.pumpAndSettle();
    expect(find.text('비밀번호 확인'), findsOneWidget);
    await tester.enterText(
      find.byType(TextFormField).at(0),
      'family@example.com',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'password1');
    await tester.enterText(find.byType(TextFormField).at(2), 'different');
    await tester.tap(find.text('이메일로 가입'));
    await tester.pump();
    expect(find.text('비밀번호가 일치하지 않습니다.'), findsOneWidget);
    expect(auth.registrations, 0);
  });

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
