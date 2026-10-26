import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'package:ondolbom/model/chats/chat_message.dart';
import 'package:ondolbom/vm/family_context.dart';

enum ChatStatus { connecting, connected, reconnecting, offline, blocked }

class PendingChat {
  const PendingChat(this.id, this.content, {this.failed = false});
  final String id;
  final String content;
  final bool failed;
}

class ChatState {
  const ChatState({
    this.messages = const [],
    this.pending = const [],
    this.status = ChatStatus.connecting,
    this.loadingHistory = true,
    this.loadingOlder = false,
    this.hasOlder = false,
    this.error,
  });
  final List<ChatMessage> messages;
  final List<PendingChat> pending;
  final ChatStatus status;
  final bool loadingHistory;
  final bool loadingOlder;
  final bool hasOlder;
  final String? error;
  bool get canSend =>
      status == ChatStatus.connected &&
      !loadingHistory &&
      !pending.any((message) => !message.failed);

  ChatState copyWith({
    List<ChatMessage>? messages,
    List<PendingChat>? pending,
    ChatStatus? status,
    bool? loadingHistory,
    bool? loadingOlder,
    bool? hasOlder,
    String? error,
    bool clearError = false,
  }) => ChatState(
    messages: messages ?? this.messages,
    pending: pending ?? this.pending,
    status: status ?? this.status,
    loadingHistory: loadingHistory ?? this.loadingHistory,
    loadingOlder: loadingOlder ?? this.loadingOlder,
    hasOlder: hasOlder ?? this.hasOlder,
    error: clearError ? null : error ?? this.error,
  );
}

class ChatFailure implements Exception {
  const ChatFailure(this.message, [this.status]);
  final String message;
  final int? status;
  @override
  String toString() => message;
}

final chatHttpClientProvider = Provider.autoDispose<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});
final chatSocketFactoryProvider = Provider<WebSocketChannel Function(Uri)>(
  (ref) =>
      (uri) => WebSocketChannel.connect(uri),
);

// 각 build의 자원을 따로 소유하여 이전 계정의 비동기 응답을 새 상태에 쓰지 않는다.
class _Session {
  bool alive = true;
  bool synced = false;
  bool paused = false;
  int retries = 0;
  int attempt = 0;
  WebSocketChannel? channel;
  StreamSubscription<dynamic>? subscription;
  Timer? reconnectTimer;
  Timer? authTimer;
  final Map<String, Timer> acknowledgements = {};

  void disconnect() {
    attempt++;
    authTimer?.cancel();
    authTimer = null;
    final subscription = this.subscription;
    this.subscription = null;
    if (subscription != null) unawaited(subscription.cancel());
    final channel = this.channel;
    this.channel = null;
    if (channel != null) {
      unawaited(
        channel.sink.close().then<void>((_) {}, onError: (Object _) {}),
      );
    }
  }

  void dispose() {
    alive = false;
    reconnectTimer?.cancel();
    for (final timer in acknowledgements.values) {
      timer.cancel();
    }
    acknowledgements.clear();
    disconnect();
  }
}

final chatVmProvider = NotifierProvider.autoDispose
    .family<ChatVm, ChatState, FamilyContext>(ChatVm.new);

class ChatVm extends Notifier<ChatState> {
  ChatVm(this.context);
  final FamilyContext context;
  _Session? _session;
  late http.Client _client;
  late Uri _base;
  late Future<String?> Function() _tokenLoader;
  late WebSocketChannel Function(Uri) _socketFactory;

  @override
  ChatState build() {
    _session?.dispose();
    _client = ref.watch(chatHttpClientProvider);
    _base = Uri.parse(ref.watch(apiBaseUrlProvider));
    _tokenLoader = ref.watch(apiTokenLoaderProvider);
    _socketFactory = ref.watch(chatSocketFactoryProvider);
    final session = _Session();
    _session = session;
    ref.onDispose(session.dispose);
    if (context.familyRoomId.isEmpty || context.userId.isEmpty) {
      return const ChatState(
        status: ChatStatus.blocked,
        loadingHistory: false,
        error: '로그인 후 가족 공간을 선택해 주세요.',
      );
    }
    unawaited(Future.microtask(() => _connect(session)));
    return const ChatState();
  }

  bool _active(_Session session) =>
      ref.mounted && session.alive && identical(_session, session);
  Uri _uri(
    List<String> path, {
    bool socket = false,
    Map<String, String>? query,
  }) => _base.replace(
    scheme: socket ? (_base.scheme == 'https' ? 'wss' : 'ws') : _base.scheme,
    pathSegments: [
      ..._base.pathSegments.where((part) => part.isNotEmpty),
      'chats',
      ...path,
    ],
    queryParameters: query ?? {},
    fragment: '',
  );

  Future<void> _connect(_Session session) async {
    if (!_active(session) || session.paused) return;
    session.reconnectTimer?.cancel();
    session.disconnect();
    final attempt = session.attempt;
    state = state.copyWith(
      status: session.synced ? ChatStatus.reconnecting : ChatStatus.connecting,
      loadingHistory: true,
      clearError: true,
    );
    WebSocketChannel? channel;
    try {
      final token = await _tokenLoader().timeout(const Duration(seconds: 10));
      if (!_active(session) || session.paused || attempt != session.attempt) {
        return;
      }
      if (token == null || token.isEmpty) {
        _blocked(session, '로그인이 필요합니다. 다시 로그인해 주세요.');
        return;
      }
      channel = _socketFactory(
        _uri(['ws', context.familyRoomId], socket: true),
      );
      session.channel = channel;
      final current = channel;
      session.subscription = channel.stream.listen(
        (event) => _event(session, current, event),
        onError: (Object error) => _lost(session, current),
        onDone: () => _lost(session, current),
      );
      await channel.ready.timeout(const Duration(seconds: 10));
      if (!_active(session) || !identical(session.channel, current)) return;
      current.sink.add(jsonEncode({'type': 'auth', 'token': token}));
      session.authTimer = Timer(
        const Duration(seconds: 10),
        () => _lost(session, current),
      );
    } catch (_) {
      if (!_active(session) || attempt != session.attempt) return;
      if (channel == null) {
        _scheduleReconnect(session, '채팅 서버에 연결하지 못했습니다.');
      } else {
        _lost(session, channel);
      }
    }
  }

  void _event(_Session session, WebSocketChannel channel, dynamic event) {
    if (!_active(session) || !identical(session.channel, channel)) return;
    try {
      final data = jsonDecode(event as String) as Map<String, dynamic>;
      switch (data['type']) {
        case 'ready':
          if (state.status == ChatStatus.connected ||
              data['user_id'] != context.userId ||
              data['family_room_id'] != context.familyRoomId) {
            _blocked(session, '로그인 계정 또는 가족 공간이 일치하지 않습니다.');
            return;
          }
          session.authTimer?.cancel();
          state = state.copyWith(status: ChatStatus.connected);
          unawaited(_sync(session, channel));
        case 'message':
          if (state.status != ChatStatus.connected) {
            throw const FormatException();
          }
          _merge(session, [
            ChatMessage.fromJson(data['message'] as Map<String, dynamic>),
          ]);
        case 'ping':
          channel.sink.add(jsonEncode({'type': 'pong'}));
        case 'error':
          _failPending(session);
          state = state.copyWith(
            error: data['detail'] is String
                ? data['detail'] as String
                : '메시지를 보내지 못했습니다.',
          );
        default:
          throw const FormatException();
      }
    } catch (_) {
      _lost(session, channel, message: '채팅 서버 응답을 확인하지 못했습니다.');
    }
  }

  void _merge(_Session session, List<ChatMessage> incoming) {
    if (!_active(session)) return;
    if (incoming.any((message) => message.roomId != context.familyRoomId)) {
      throw const FormatException();
    }
    final byId = {
      for (final message in [...state.messages, ...incoming])
        message.seq: message,
    };
    final messages = byId.values.toList()
      ..sort((a, b) => a.seq.compareTo(b.seq));
    final confirmed = messages
        .where((message) => message.userId == context.userId)
        .map((message) => message.clientId)
        .toSet();
    for (final id in confirmed) {
      session.acknowledgements.remove(id)?.cancel();
    }
    state = state.copyWith(
      messages: messages,
      pending: state.pending
          .where((message) => !confirmed.contains(message.id))
          .toList(),
    );
  }

  Future<Map<String, dynamic>> _history(
    _Session session,
    Map<String, String> cursor,
  ) async {
    final token = await _tokenLoader().timeout(const Duration(seconds: 15));
    if (!_active(session)) throw const ChatFailure('로그인 상태가 변경되었습니다.');
    if (token == null || token.isEmpty) {
      throw const ChatFailure('다시 로그인해 주세요.', 401);
    }
    final response = await _client
        .get(
          _uri(
            ['messages'],
            query: {
              'family_room_id': context.familyRoomId,
              'limit': '30',
              ...cursor,
            },
          ),
          headers: {
            'Authorization': 'Bearer $token',
            'Accept': 'application/json',
          },
        )
        .timeout(const Duration(seconds: 15));
    if (!_active(session)) throw const ChatFailure('로그인 상태가 변경되었습니다.');
    if (response.statusCode == 401) {
      throw const ChatFailure('다시 로그인해 주세요.', 401);
    }
    if (response.statusCode == 403) {
      throw const ChatFailure('이 공간의 채팅에 접근할 수 없습니다.', 403);
    }
    if (response.statusCode != 200) {
      throw const ChatFailure('이전 대화를 불러오지 못했습니다. 서버 설정을 확인해 주세요.');
    }
    return jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;
  }

  List<ChatMessage> _rows(Map<String, dynamic> page) =>
      (page['results'] as List)
          .map((item) => ChatMessage.fromJson(item as Map<String, dynamic>))
          .toList();

  Future<void> _sync(_Session session, WebSocketChannel channel) async {
    // 재연결 당시 마지막 ID를 고정한다. 복구 도중 들어오는 실시간 메시지와 합친다.
    var after = state.messages.isEmpty ? 0 : state.messages.last.seq;
    final reconnecting = session.synced;
    try {
      do {
        final page = await _history(
          session,
          reconnecting ? {'after_id': '$after'} : {},
        );
        if (!_active(session) || !identical(session.channel, channel)) return;
        _merge(session, _rows(page));
        if (!reconnecting) {
          state = state.copyWith(hasOlder: page['has_more'] == true);
          break;
        }
        final next = page['next_after_id'] as int?;
        if (next == null) break;
        if (next <= after) throw const FormatException();
        after = next;
      } while (true);
      session.synced = true;
      session.retries = 0;
      state = state.copyWith(loadingHistory: false, clearError: true);
    } catch (error) {
      if (!_active(session) || !identical(session.channel, channel)) return;
      if (error is ChatFailure &&
          (error.status == 401 || error.status == 403)) {
        _blocked(session, error.message);
      } else {
        state = state.copyWith(
          loadingHistory: false,
          error: error is ChatFailure
              ? error.message
              : '이전 대화를 불러오지 못했습니다. 다시 연결해 주세요.',
        );
      }
    }
  }

  Future<void> loadOlder() async {
    final session = _session;
    if (session == null ||
        !state.hasOlder ||
        state.loadingOlder ||
        state.loadingHistory ||
        state.messages.isEmpty) {
      return;
    }
    state = state.copyWith(loadingOlder: true);
    try {
      final page = await _history(session, {
        'before_id': '${state.messages.first.seq}',
      });
      if (!_active(session)) return;
      _merge(session, _rows(page));
      state = state.copyWith(
        loadingOlder: false,
        hasOlder: page['has_more'] == true,
        clearError: true,
      );
    } catch (error) {
      if (!_active(session)) return;
      if (error is ChatFailure &&
          (error.status == 401 || error.status == 403)) {
        _blocked(session, error.message);
      } else {
        state = state.copyWith(
          loadingOlder: false,
          error: '이전 대화를 불러오지 못했습니다. 다시 시도해 주세요.',
        );
      }
    }
  }

  String _newId() {
    final random = Random.secure();
    final bytes = List.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final hex = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  bool send(String text) {
    if (!state.canSend) return false;
    final content = text.trim();
    if (content.isEmpty || content.runes.length > 4000) {
      state = state.copyWith(error: '메시지는 1~4,000자로 입력해 주세요.');
      return false;
    }
    final message = PendingChat(_newId(), content);
    state = state.copyWith(
      pending: [...state.pending, message],
      clearError: true,
    );
    _transmit(message);
    return true;
  }

  void retry(String id) {
    if (!state.canSend) return;
    final matches = state.pending.where(
      (message) => message.id == id && message.failed,
    );
    if (matches.isEmpty) return;
    final message = PendingChat(id, matches.first.content);
    state = state.copyWith(
      pending: [
        for (final item in state.pending) item.id == id ? message : item,
      ],
      clearError: true,
    );
    _transmit(message);
  }

  void _transmit(PendingChat message) {
    final session = _session!;
    try {
      session.channel!.sink.add(
        jsonEncode({
          'type': 'message',
          'client_message_id': message.id,
          'content': message.content,
        }),
      );
      session.acknowledgements[message.id] = Timer(
        const Duration(seconds: 15),
        () {
          if (!_active(session)) return;
          _failPending(session);
          state = state.copyWith(
            error: '전송 확인이 지연되고 있습니다. 재시도하면 중복 저장을 확인합니다.',
          );
        },
      );
    } catch (_) {
      _failPending(session);
      state = state.copyWith(error: '메시지를 전송하지 못했습니다. 다시 연결해 주세요.');
    }
  }

  void _failPending(_Session session) {
    for (final timer in session.acknowledgements.values) {
      timer.cancel();
    }
    session.acknowledgements.clear();
    state = state.copyWith(
      pending: [
        for (final item in state.pending)
          PendingChat(item.id, item.content, failed: true),
      ],
    );
  }

  void _blocked(_Session session, String message) {
    if (!_active(session)) return;
    session.reconnectTimer?.cancel();
    session.disconnect();
    _failPending(session);
    state = state.copyWith(
      status: ChatStatus.blocked,
      loadingHistory: false,
      loadingOlder: false,
      error: message,
    );
  }

  void _lost(_Session session, WebSocketChannel channel, {String? message}) {
    if (!_active(session) || !identical(session.channel, channel)) return;
    final code = channel.closeCode;
    session.disconnect();
    _failPending(session);
    if (code == 4403 || code == 4400 || code == 1009) {
      _blocked(
        session,
        code == 4403 ? '이 공간의 채팅에 접근할 수 없습니다.' : '채팅 연결 요청을 확인해 주세요.',
      );
      return;
    }
    _scheduleReconnect(session, message ?? '채팅 연결이 끊겼습니다.');
  }

  void _scheduleReconnect(_Session session, String message) {
    if (!_active(session) || session.paused) return;
    final retry = session.retries++;
    state = state.copyWith(
      status: retry < 5 ? ChatStatus.reconnecting : ChatStatus.offline,
      loadingHistory: false,
      loadingOlder: false,
      error: message,
    );
    if (retry < 5) {
      session.reconnectTimer?.cancel();
      session.reconnectTimer = Timer(
        Duration(seconds: 1 << retry),
        () => _connect(session),
      );
    }
  }

  void reconnect() {
    final session = _session;
    if (session == null || !_active(session)) return;
    session.paused = false;
    session.retries = 0;
    _failPending(session);
    unawaited(_connect(session));
  }

  void pause() {
    final session = _session;
    if (session == null || !_active(session)) return;
    session.paused = true;
    session.reconnectTimer?.cancel();
    session.disconnect();
    _failPending(session);
    state = state.copyWith(
      status: ChatStatus.offline,
      loadingHistory: false,
      loadingOlder: false,
    );
  }
}
