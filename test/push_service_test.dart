import 'dart:async';
import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ondolbom/model/notifications/push_service.dart';

class PushUser extends Fake implements User {
  PushUser(this.id);
  final String id;
  @override
  String get uid => id;
  @override
  Future<String?> getIdToken([bool forceRefresh = false]) async => id;
}

class PushAuth extends Fake implements FirebaseAuth {
  User? user = PushUser('a');
  @override
  User? get currentUser => user;
}

class MemoryPushPrefs extends PushPreferences {
  int generation = 0;
  @override
  Future<Map<String, dynamic>> installation() async => {
    'installation_id': 'a' * 32,
    'secret': 'b' * 64,
  };
  @override
  Future<int> nextGeneration() async => ++generation;
}

class TestPushPlatform implements PushPlatform {
  final messageController = StreamController<PushEvent>.broadcast();
  final tapController = StreamController<PushEvent>.broadcast();
  final tokenController = StreamController<String>.broadcast();
  bool allowed = true;
  int deleted = 0;
  int shown = 0;
  Completer<bool>? gate;
  @override
  Stream<PushEvent> get messages => messageController.stream;
  @override
  Stream<PushEvent> get taps => tapController.stream;
  @override
  Stream<String> get tokenChanges => tokenController.stream;
  @override
  Future<void> initialize() async {}
  @override
  Future<bool> permission() async =>
      gate == null ? allowed : await gate!.future;
  @override
  Future<String?> token() async => 'device-token-long-enough';
  @override
  Future<void> deleteToken() async {
    deleted++;
  }

  @override
  Future<void> clear() async {}
  @override
  Future<void> show(PushEvent event) async {
    shown++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('Permission denial does not register or fail authentication', () async {
    final platform = TestPushPlatform()..allowed = false;
    var calls = 0;
    final service = PushService(
      platform: platform,
      auth: PushAuth(),
      baseUrl: 'http://local',
      preferences: MemoryPushPrefs(),
      client: MockClient((_) async {
        calls++;
        return http.Response('{}', 200);
      }),
    );
    service.setSession('a', true);
    await service.reconnect();
    expect(calls, 0);
    expect(service.status.value, contains('허용'));
  });
  test(
    'Registration and logout use monotonic generations; token deletion survives offline server',
    () async {
      final platform = TestPushPlatform();
      final requests = <http.Request>[];
      final service = PushService(
        platform: platform,
        auth: PushAuth(),
        baseUrl: 'http://local',
        preferences: MemoryPushPrefs(),
        client: MockClient((request) async {
          requests.add(request);
          return http.Response(
            '{}',
            request.url.path.endsWith('unregister') ? 503 : 200,
          );
        }),
      );
      service.setSession('a', true);
      await service.reconnect();
      await service.detach();
      final generations = requests
          .map((r) => (jsonDecode(r.body) as Map)['generation'] as int)
          .toList();
      expect(generations, orderedEquals([...generations]..sort()));
      expect(platform.deleted, 1);
      expect(requests.last.url.path, '/push/devices/unregister');
    },
  );
  test('Late permission result cannot register the previous account', () async {
    final auth = PushAuth();
    final platform = TestPushPlatform()..gate = Completer<bool>();
    final headers = <String?>[];
    final service = PushService(
      platform: platform,
      auth: auth,
      baseUrl: 'http://local',
      preferences: MemoryPushPrefs(),
      client: MockClient((r) async {
        if (r.url.path == '/push/devices') {
          headers.add(r.headers['Authorization']);
        }
        return http.Response('{}', 200);
      }),
    );
    service.setSession('a', true);
    await Future<void>.delayed(Duration.zero);
    auth.user = PushUser('b');
    service.setSession('b', true);
    platform.gate!.complete(true);
    await service.reconnect();
    expect(headers, isNotEmpty);
    expect(headers.every((header) => header == 'Bearer b'), isTrue);
  });
  test(
    'Foreground messages for another account and logged out sessions are ignored',
    () async {
      final platform = TestPushPlatform();
      final auth = PushAuth();
      final service = PushService(
        platform: platform,
        auth: auth,
        baseUrl: 'http://local',
        preferences: MemoryPushPrefs(),
      );
      await service.start();
      platform.messageController.add(
        const PushEvent({'user_uid': 'b', 'notification_id': '7'}),
      );
      platform.messageController.add(
        const PushEvent({'user_uid': 'a', 'notification_id': '8'}),
      );
      await Future<void>.delayed(Duration.zero);
      expect(platform.shown, 1);
      auth.user = null;
      platform.messageController.add(
        const PushEvent({'user_uid': 'a', 'notification_id': '9'}),
      );
      await Future<void>.delayed(Duration.zero);
      expect(platform.shown, 1);
    },
  );
}
