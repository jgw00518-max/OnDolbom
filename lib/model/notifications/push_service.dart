import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

final pushServiceProvider = Provider<PushService?>((ref) => null);

class PushError implements Exception {
  const PushError(this.message);
  final String message;
}

class PushEvent {
  const PushEvent(this.data, {this.title, this.body});
  final Map<String, dynamic> data;
  final String? title;
  final String? body;
}

// 네이티브 SDK를 분리해 실제 Firebase 연결 없이 계정 전환 등을 테스트한다.
abstract class PushPlatform {
  Stream<PushEvent> get messages;
  Stream<PushEvent> get taps;
  Stream<String> get tokenChanges;
  Future<void> initialize();
  Future<bool> permission();
  Future<String?> token();
  Future<void> deleteToken();
  Future<void> show(PushEvent event);
  Future<void> clear();
}

class AndroidPushPlatform implements PushPlatform {
  final _messaging = FirebaseMessaging.instance;
  final _registrations = StreamController<String>.broadcast();
  String? _fid;
  Completer<String>? _registering;
  bool _wired = false;
  final _local = FlutterLocalNotificationsPlugin();
  final _localTaps = StreamController<PushEvent>.broadcast();
  final _taps = StreamController<PushEvent>.broadcast();
  PushEvent _event(RemoteMessage message) => PushEvent(
    message.data,
    title: message.notification?.title,
    body: message.notification?.body,
  );
  @override
  Stream<PushEvent> get messages => FirebaseMessaging.onMessage.map(_event);
  @override
  Stream<PushEvent> get taps => _taps.stream;
  @override
  Stream<String> get tokenChanges => _registrations.stream;
  @override
  // 채널과 구독을 준비하고 앱 종료 상태에서 누른 알림도 복원한다.
  Future<void> initialize() async {
    await _local.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings('ic_stat_notification'),
      ),
      onDidReceiveNotificationResponse: (response) {
        try {
          _localTaps.add(
            PushEvent(jsonDecode(response.payload!) as Map<String, dynamic>),
          );
        } catch (_) {
          /* payload가 없는 콘솔 알림은 화면 이동 없이 앱만 연다. */
        }
      },
    );
    await _local
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(
          const AndroidNotificationChannel(
            'ondolbom_updates',
            '온돌봄 소식',
            importance: Importance.high,
          ),
        );
    if (!_wired) {
      _wired = true;
      _messaging.onRegistered.listen((fid) {
        final changed = _fid != fid;
        _fid = fid;
        if (_registering?.isCompleted == false) _registering!.complete(fid);
        if (changed) _registrations.add(fid);
      });
      _messaging.onUnregistered.listen((fid) {
        if (_fid == fid) _fid = null;
      });
      _localTaps.stream.listen(_taps.add);
      FirebaseMessaging.onMessageOpenedApp.map(_event).listen(_taps.add);
    }
    final initial = await _messaging.getInitialMessage();
    if (initial != null) _taps.add(_event(initial));
    final launch = await _local.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp == true) {
      try {
        _taps.add(
          PushEvent(
            jsonDecode(launch!.notificationResponse!.payload!)
                as Map<String, dynamic>,
          ),
        );
      } catch (_) {}
    }
  }

  @override
  Future<bool> permission() async {
    final result = await _messaging.requestPermission();
    return result.authorizationStatus == AuthorizationStatus.authorized ||
        result.authorizationStatus == AuthorizationStatus.provisional;
  }

  @override
  Future<String?> token() async {
    await _messaging.setAutoInitEnabled(true);
    _registering = Completer<String>();
    await _messaging.register();
    // SDK 17은 FCM 토큰 대신 onRegistered의 FID로 발송 대상을 식별한다.
    return _fid ??
        await _registering!.future.timeout(const Duration(seconds: 15));
  }

  @override
  Future<void> deleteToken() async {
    await _messaging.setAutoInitEnabled(false);
    await _messaging.unregister();
    _fid = null;
  }

  @override
  Future<void> clear() => _local.cancelAll();
  @override
  Future<void> show(PushEvent event) {
    final chat = event.data['type'] == 'chat_message';
    final group = chat
        ? 'chat_${event.data['family_room_id']}'
        : event.data['notification_id']?.toString() ?? event.title ?? 'push';
    final tag = sha256.convert(utf8.encode(group)).toString();
    // 같은 공간의 채팅은 하나의 기기 알림으로 갱신한다. 숫자는 서버의 미읽음 수를 사용한다.
    return _local.show(
      int.parse(tag.substring(0, 8), radix: 16) & 0x7fffffff,
      event.title ?? '온돌봄',
      event.body ?? '새 소식이 있습니다. 앱에서 확인해 주세요.',
      NotificationDetails(
        android: AndroidNotificationDetails(
          'ondolbom_updates',
          '온돌봄 소식',
          icon: 'ic_stat_notification',
          importance: Importance.high,
          priority: Priority.high,
          tag: tag,
        ),
      ),
      payload: jsonEncode(event.data),
    );
  }
}

class PushPreferences {
  SharedPreferencesAsync get _prefs => SharedPreferencesAsync();
  String random(int bytes) => List.generate(
    bytes,
    (_) => Random.secure().nextInt(256).toRadixString(16).padLeft(2, '0'),
  ).join();
  // 계정이 바뀌어도 설치 식별자를 유지해 서버의 연결 계정을 교체한다.
  Future<Map<String, dynamic>> installation() async {
    var id = await _prefs.getString('push.installation');
    var secret = await _prefs.getString('push.secret');
    if (id == null || secret == null) {
      id = random(16);
      secret = random(32);
      await _prefs.setString('push.installation', id);
      await _prefs.setString('push.secret', secret);
    }
    return {'installation_id': id, 'secret': secret};
  }

  // 등록·해제 순서를 앱 재실행 후에도 유지한다.
  Future<int> nextGeneration() async {
    final value = (await _prefs.getInt('push.generation') ?? 0) + 1;
    await _prefs.setInt('push.generation', value);
    return value;
  }
}

/// 등록·갱신·로그아웃을 직렬 처리해 늦은 요청이 새 계정 연결을 덮어쓰지 않게 한다.
class PushService {
  PushService({
    required this.platform,
    required this.auth,
    required this.baseUrl,
    PushPreferences? preferences,
    http.Client? client,
  }) : preferences = preferences ?? PushPreferences(),
       client = client ?? http.Client();
  final PushPlatform platform;
  final FirebaseAuth auth;
  final String baseUrl;
  final PushPreferences preferences;
  final http.Client client;
  final status = ValueNotifier<String>('푸시 연결 준비 중');
  final taps = StreamController<PushEvent>.broadcast();
  final received = StreamController<PushEvent>.broadcast();
  bool Function(PushEvent)? suppressForeground;
  Future<void> _queue = Future.value();
  Future<void>? _initializing;
  String? _sessionKey;
  int _revision = 0;
  bool _ready = false;
  bool _listening = false;
  String? _uid;
  Map<String, dynamic>? _binding;

  Future<void> start() => _initializing ??= _start().catchError((Object error) {
    _initializing = null;
    throw error;
  });
  Future<void> _start() async {
    if (!_listening) {
      _listening = true;
      platform.messages.listen((event) async {
        final uid = auth.currentUser?.uid;
        if (uid == null ||
            (event.data['user_uid'] != null && event.data['user_uid'] != uid)) {
          return;
        }
        received.add(event);
        try {
          if (event.data['type'] == 'chat_message') {
            // 웹소켓 메시지가 화면에 반영될 짧은 여유 후 실제 표시 여부를 확인한다.
            await Future<void>.delayed(const Duration(milliseconds: 300));
          }
          if (auth.currentUser?.uid == uid &&
              suppressForeground?.call(event) != true) {
            await platform.show(event);
          }
        } catch (_) {
          status.value = '기기 알림 표시 설정을 확인해 주세요.';
        }
      });
      platform.taps.listen(taps.add);
      platform.tokenChanges.listen((_) {
        reconnect();
      });
    }
    await platform.initialize();
  }

  // 등록과 로그아웃 해제를 직렬 처리해 이전 요청이 새 연결을 덮어쓰지 않게 한다.
  Future<void> _serial(Future<void> Function() action) {
    final operation = _queue.then((_) => action());
    _queue = operation.catchError((Object error) {
      // 메시지에는 기기 식별자가 포함될 수 있어 안전한 오류 코드만 표시한다.
      String safeCode(String code) =>
          RegExp(r'^[a-zA-Z0-9_/-]{1,80}$').hasMatch(code) ? code : 'unknown';
      status.value = switch (error) {
        PushError() => error.message,
        FirebaseException() =>
          '푸시 연결 실패 · ${safeCode(error.plugin)}/${safeCode(error.code)}',
        PlatformException() => '기기 푸시 연결 실패 · ${safeCode(error.code)}',
        TimeoutException() => '푸시 등록 응답 지연 · 다시 연결해 주세요.',
        _ => '푸시 연결 실패 · 다시 연결해 주세요.',
      };
    });
    return _queue;
  }

  // 인증과 MySQL 프로필 등록이 준비된 계정만 기기에 연결한다.
  void setSession(String? uid, bool ready) {
    final key = '$uid:$ready';
    if (_sessionKey == key) return;
    _sessionKey = key;
    _ready = ready;
    _revision++;
    final changedAccount = _uid != null && _uid != uid;
    _uid = uid;
    if (uid == null || changedAccount) {
      detach();
    }
    if (uid != null && ready) {
      reconnect();
    }
  }

  Future<Map<String, dynamic>> _post(
    String path,
    Map<String, dynamic> body,
    String uid,
  ) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      final user = auth.currentUser;
      if (user == null || user.uid != uid) throw StateError('계정 변경');
      final token = await user
          .getIdToken(attempt == 1)
          .timeout(const Duration(seconds: 10));
      if (auth.currentUser?.uid != uid || token == null) {
        throw StateError('계정 변경');
      }
      final response = await client
          .post(
            Uri.parse('${baseUrl.replaceAll(RegExp(r'/+$'), '')}$path'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 401 && attempt == 0) continue;
      if (response.statusCode != 200) {
        try {
          final detail =
              (jsonDecode(utf8.decode(response.bodyBytes)) as Map)['detail'];
          if (detail is String && detail.length < 200) throw PushError(detail);
        } on PushError {
          rethrow;
        } catch (_) {}
        throw const PushError('푸시 연결 실패 · 다시 연결해 주세요.');
      }
      if (auth.currentUser?.uid != uid) throw StateError('계정 변경');
      return jsonDecode(utf8.decode(response.bodyBytes))
          as Map<String, dynamic>;
    }
    throw StateError('인증 실패');
  }

  // 비동기 등록 중 계정이 바뀌면 이전 계정으로 연결하지 않는다.
  Future<void> reconnect() {
    final revision = _revision;
    return _serial(() async {
      await start();
      final uid = auth.currentUser?.uid;
      if (uid == null || !_ready || revision != _revision) return;
      status.value = '푸시 연결 중';
      if (!await platform.permission()) {
        status.value = '휴대폰 설정에서 알림을 허용해 주세요.';
        return;
      }
      final token = await platform.token().timeout(const Duration(seconds: 15));
      if (token == null ||
          auth.currentUser?.uid != uid ||
          revision != _revision) {
        return;
      }
      final binding = {
        ...await preferences.installation(),
        'generation': await preferences.nextGeneration(),
      };
      await _post('/push/devices', {...binding, 'fid': token}, uid);
      _binding = binding;
      status.value = '푸시 알림 연결됨';
    });
  }

  // 로그아웃 전에 현재 계정 인증으로 서버 연결 해제를 시도한다.
  Future<void> detach() {
    _revision++;
    return _serial(() async {
      final uid = auth.currentUser?.uid;
      try {
        if (uid != null) {
          final body = {
            ...await preferences.installation(),
            'generation': await preferences.nextGeneration(),
          };
          await _post('/push/devices/unregister', body, uid);
        }
      } catch (_) {
        /* 서버 해제 실패 시에도 FCM 토큰 삭제를 시도하고 로그아웃은 유지한다. */
      }
      try {
        await platform.deleteToken().timeout(const Duration(seconds: 8));
      } catch (_) {}
      try {
        await platform.clear();
      } catch (_) {}
      _binding = null;
      status.value = '로그인 후 푸시 연결';
    });
  }

  Future<void> sendTest() => _serial(() async {
    final uid = auth.currentUser?.uid;
    if (uid == null || _binding == null) {
      status.value = '먼저 푸시를 다시 연결해 주세요.';
      return;
    }
    await _post('/push/test', _binding!, uid);
    status.value = '테스트 발송 요청 완료 · 휴대폰 알림을 확인해 주세요.';
  });
}
