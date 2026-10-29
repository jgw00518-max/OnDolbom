import 'dart:async';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ondolbom/model/auth/app_user.dart';
import 'package:ondolbom/vm/auth/auth_vm.dart';
import 'package:ondolbom/vm/auth/profile_edit_vm.dart';
import 'package:ondolbom/vm/auth/user_profile_vm.dart';
import 'user_profile_vm_test.dart' show TestUser, TestAuth;

http.Response updated() => http.Response(
  jsonEncode({
    'registered': true,
    'user': {
      'user_id': 'db',
      'user_email': 'family@example.com',
      'name': '새 이름',
      'phone': '010-1234-5678',
    },
  }),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

class MutableEditAuth extends Fake implements FirebaseAuth {
  User? user;
  @override
  User? get currentUser => user;
}

class DeferredEditUser extends TestUser {
  final token = Completer<String?>();
  @override
  Future<String?> getIdToken([bool forceRefresh = false]) => token.future;
}

void main() {
  test('401일 때만 토큰을 한 번 갱신하고 수정 결과를 반영한다', () async {
    final user = TestUser();
    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      expect(
        request.headers['Authorization'],
        calls == 1 ? 'Bearer first-token' : 'Bearer renewed-token',
      );
      return calls == 1 ? http.Response('', 401) : updated();
    });
    final container = ProviderContainer(
      overrides: [
        firebaseAuthProvider.overrideWithValue(TestAuth(user)),
        authUserProvider.overrideWith(
          (ref) => Stream.value(const AppUser(uid: 'uid')),
        ),
        authHttpClientProvider.overrideWithValue(client),
        userProfileProvider.overrideWith((ref) async => null),
      ],
    );
    addTearDown(() {
      container.dispose();
      client.close();
    });
    final sub = container.listen(profileEditProvider, (_, _) {});
    addTearDown(sub.close);
    await container.read(authUserProvider.future);
    expect(
      await container
          .read(profileEditProvider.notifier)
          .save('새 이름', '01012345678'),
      isTrue,
    );
    expect(user.refreshes, [false, true]);
    expect(
      container.read(profileEditProvider).requireValue!.phone,
      '010-1234-5678',
    );
  });

  for (final afterRequest in [false, true]) {
    test('계정 전환 후 늦은 ${afterRequest ? '수정 응답' : '토큰'}은 반영하지 않는다', () async {
      final user = DeferredEditUser();
      final auth = MutableEditAuth()..user = user;
      final sessions = StreamController<AppUser?>();
      final sent = Completer<void>();
      final response = Completer<http.Response>();
      var calls = 0;
      final client = MockClient((request) {
        calls++;
        sent.complete();
        return response.future;
      });
      final container = ProviderContainer(
        overrides: [
          firebaseAuthProvider.overrideWithValue(auth),
          authUserProvider.overrideWith((ref) => sessions.stream),
          authHttpClientProvider.overrideWithValue(client),
        ],
      );
      addTearDown(() {
        container.dispose();
        client.close();
        sessions.close();
      });
      final sub = container.listen(profileEditProvider, (_, _) {});
      addTearDown(sub.close);
      final session = container.read(authUserProvider.future);
      sessions.add(const AppUser(uid: 'uid'));
      await session;
      final result = container
          .read(profileEditProvider.notifier)
          .save('새 이름', '01012345678');
      if (afterRequest) {
        user.token.complete('token');
        await sent.future;
      }
      auth.user = null;
      sessions.add(null);
      await Future<void>.delayed(Duration.zero);
      container.read(profileEditProvider);
      if (afterRequest) {
        response.complete(updated());
      } else {
        user.token.complete('token');
      }
      expect(await result, isFalse);
      expect(calls, afterRequest ? 1 : 0);
      expect(container.read(profileEditProvider).asData?.value, isNull);
    });
  }
}
