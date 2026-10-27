import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ondolbom/model/auth/app_user.dart';
import 'package:ondolbom/model/auth/login_preferences.dart';
import 'package:ondolbom/model/auth/user_profile.dart';
import 'package:ondolbom/view/auth/personal_settings_view.dart';
import 'package:ondolbom/vm/auth/auth_vm.dart';
import 'package:ondolbom/vm/auth/user_profile_vm.dart';
import 'login_preferences_test.dart' show MemoryPreferences;
import 'vm/user_profile_vm_test.dart' show TestUser, TestAuth;

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

void main() {
  testWidgets('개인 설정에서 조회·수정·검증·중복 차단·실패 입력 보존·저장 후 갱신을 연결한다', (tester) async {
    var current = const UserProfile(
      userId: 'db',
      email: 'family@example.com',
      name: '가족',
      phone: '010-1111-2222',
    );
    var calls = 0;
    final pending = Completer<http.Response>();
    final client = MockClient((request) async {
      calls++;
      expect(request.method, 'PUT');
      expect(request.url.path, '/auth/profile');
      expect(jsonDecode(request.body), {
        'name': '새 이름',
        'phone': '01012345678',
      });
      if (calls == 1) return pending.future;
      current = const UserProfile(
        userId: 'db',
        email: 'family@example.com',
        name: '새 이름',
        phone: '010-1234-5678',
      );
      return updated();
    });
    addTearDown(client.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          firebaseAuthProvider.overrideWithValue(TestAuth(TestUser())),
          authUserProvider.overrideWith(
            (ref) => Stream.value(
              const AppUser(uid: 'uid', email: 'family@example.com'),
            ),
          ),
          userProfileProvider.overrideWith((ref) async => current),
          authHttpClientProvider.overrideWithValue(client),
          loginPreferencesProvider.overrideWithValue(MemoryPreferences()),
        ],
        child: const MaterialApp(home: PersonalSettingsView()),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('프로필 수정'));
    await tester.pumpAndSettle();
    expect(find.text('family@example.com'), findsOneWidget);
    expect(find.byType(TextFormField), findsNWidgets(2));
    await tester.enterText(find.byType(TextFormField).first, '');
    await tester.ensureVisible(find.text('변경사항 저장'));
    await tester.tap(find.text('변경사항 저장'));
    await tester.pumpAndSettle();
    expect(find.text('이름을 입력해 주세요.'), findsOneWidget);
    expect(calls, 0);
    await tester.enterText(find.byType(TextFormField).first, '새 이름');
    await tester.enterText(find.byType(TextFormField).last, '01012345678');
    await tester.ensureVisible(find.text('변경사항 저장'));
    await tester.tap(find.text('변경사항 저장'));
    await tester.pump();
    await tester.tap(find.text('저장 중…'));
    expect(calls, 1);
    pending.complete(http.Response('', 503));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextFormField>(find.byType(TextFormField).first)
          .controller!
          .text,
      '새 이름',
    );
    expect(find.textContaining('프로필을 다시 조회해 주세요.'), findsWidgets);
    await tester.ensureVisible(find.text('변경사항 저장'));
    await tester.tap(find.text('변경사항 저장'));
    await tester.pumpAndSettle();
    expect(find.text('개인 설정'), findsOneWidget);
    expect(find.text('새 이름'), findsOneWidget);
    expect(find.text('010-1234-5678'), findsOneWidget);
    expect(calls, 2);
    expect(tester.takeException(), isNull);
  });
}
