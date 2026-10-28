import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ondolbom/model/auth/app_user.dart';
import 'package:ondolbom/model/auth/user_profile.dart';
import 'package:ondolbom/model/notifications/push_service.dart';
import 'package:ondolbom/view/widgets/push_bridge.dart';
import 'package:ondolbom/view/notifications/notifications_view.dart';
import 'package:ondolbom/vm/auth/auth_vm.dart';
import 'package:ondolbom/vm/auth/user_profile_vm.dart';
import 'package:ondolbom/vm/notifications/notifications_vm.dart';
import 'push_service_test.dart'
    show PushAuth, TestPushPlatform, MemoryPushPrefs;
import 'view/notifications_view_test.dart' show EmptyNotifications;

void main() {
  testWidgets(
    'A push opens inbox only for its current authenticated recipient',
    (tester) async {
      final platform = TestPushPlatform();
      final auth = PushAuth();
      final client = MockClient((_) async => http.Response('{}', 200));
      addTearDown(client.close);
      final service = PushService(
        platform: platform,
        auth: auth,
        baseUrl: 'http://local',
        preferences: MemoryPushPrefs(),
        client: client,
      );
      final navigator = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            pushServiceProvider.overrideWithValue(service),
            authUserProvider.overrideWith(
              (ref) => Stream.value(const AppUser(uid: 'a')),
            ),
            userProfileProvider.overrideWith(
              (ref) async => const UserProfile(userId: 'mysql'),
            ),
            notificationsVmProvider.overrideWith(EmptyNotifications.new),
          ],
          child: MaterialApp(
            navigatorKey: navigator,
            builder: (context, child) =>
                PushBridge(navigatorKey: navigator, child: child!),
            home: const Scaffold(body: Text('home')),
          ),
        ),
      );
      await tester.pumpAndSettle();
      platform.tapController.add(
        const PushEvent({'user_uid': 'b', 'notification_id': '7'}),
      );
      await tester.pumpAndSettle();
      expect(find.byType(NotificationsView), findsNothing);
      platform.tapController.add(
        const PushEvent({'user_uid': 'a', 'notification_id': '7'}),
      );
      await tester.pumpAndSettle();
      expect(find.byType(NotificationsView), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
