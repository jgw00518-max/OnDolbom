import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ondolbom/model/auth/app_user.dart';
import 'package:ondolbom/vm/auth/auth_vm.dart';
import 'package:ondolbom/vm/auth/user_profile_vm.dart';

// 토큰 발급·HTTP 응답을 대체하여 401 갱신과 등록 요청 내용을 검증한다.
class TestUser extends Fake implements User {
  final refreshes = <bool>[];
  @override
  String get uid => 'uid';
  @override
  Future<String?> getIdToken([bool forceRefresh = false]) async {
    refreshes.add(forceRefresh);
    return forceRefresh ? 'renewed-token' : 'first-token';
  }
}

class TestAuth extends Fake implements FirebaseAuth {
  TestAuth(this.user);
  final User user;
  @override
  User get currentUser => user;
}

void main() {
  test(
    'Profile registration sends only name and phone with Firebase token',
    () async {
      final client = MockClient((request) async {
        expect(request.method, 'POST');
        expect(request.url.path, '/auth/profile');
        expect(request.headers['Authorization'], 'Bearer first-token');
        expect(jsonDecode(request.body), {
          'name': '가족',
          'phone': '01012345678',
        });
        return http.Response(
          jsonEncode({
            'registered': true,
            'user': {
              'user_id': 'local',
              'user_email': 'family@example.com',
              'name': '가족',
              'phone': '010-1234-5678',
            },
          }),
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      });
      final container = ProviderContainer(
        overrides: [
          firebaseAuthProvider.overrideWithValue(TestAuth(TestUser())),
          authHttpClientProvider.overrideWithValue(client),
          userProfileProvider.overrideWith((ref) async => null),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(client.close);
      final subscription = container.listen(
        profileRegistrationProvider,
        (_, _) {},
      );
      addTearDown(subscription.close);
      await container
          .read(profileRegistrationProvider.notifier)
          .register(' 가족 ', '01012345678');
      expect(container.read(profileRegistrationProvider).hasError, false);
    },
  );

  test('Failed profile registration retains an error for retry', () async {
    final client = MockClient((_) async => http.Response('', 503));
    final container = ProviderContainer(
      overrides: [
        firebaseAuthProvider.overrideWithValue(TestAuth(TestUser())),
        authHttpClientProvider.overrideWithValue(client),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(client.close);
    final subscription = container.listen(
      profileRegistrationProvider,
      (_, _) {},
    );
    addTearDown(subscription.close);
    await container
        .read(profileRegistrationProvider.notifier)
        .register('가족', '010-1234-5678');
    expect(container.read(profileRegistrationProvider).hasError, true);
  });

  test(
    'Sends ID token, refreshes once on 401, then detects missing profile',
    () async {
      final user = TestUser();
      var calls = 0;
      final client = MockClient((request) async {
        calls++;
        expect(request.url.path, '/auth/me');
        expect(
          request.headers['Authorization'],
          'Bearer ${calls == 1 ? 'first-token' : 'renewed-token'}',
        );
        return calls == 1
            ? http.Response('', 401)
            : http.Response('{"registered":false,"user":null}', 200);
      });
      final container = ProviderContainer(
        overrides: [
          firebaseAuthProvider.overrideWithValue(TestAuth(user)),
          authUserProvider.overrideWith(
            (ref) => Stream.value(const AppUser(uid: 'uid')),
          ),
          authHttpClientProvider.overrideWithValue(client),
          apiBaseUrlProvider.overrideWithValue('http://localhost:8000'),
        ],
      );
      addTearDown(container.dispose);
      addTearDown(client.close);
      final subscription = container.listen(userProfileProvider, (_, _) {});
      addTearDown(subscription.close);
      expect(await container.read(userProfileProvider.future), isNull);
      expect(user.refreshes, [false, true]);
      expect(calls, 2);
    },
  );

  test('Server failure is an error rather than missing registration', () async {
    final client = MockClient(
      (_) async => http.Response(jsonEncode({'detail': 'private'}), 503),
    );
    final container = ProviderContainer(
      overrides: [
        firebaseAuthProvider.overrideWithValue(TestAuth(TestUser())),
        authUserProvider.overrideWith(
          (ref) => Stream.value(const AppUser(uid: 'uid')),
        ),
        authHttpClientProvider.overrideWithValue(client),
      ],
    );
    addTearDown(container.dispose);
    addTearDown(client.close);
    final subscription = container.listen(userProfileProvider, (_, _) {});
    addTearDown(subscription.close);
    await expectLater(
      container.read(userProfileProvider.future),
      throwsA(isA<ProfileLoadException>()),
    );
  });
}
