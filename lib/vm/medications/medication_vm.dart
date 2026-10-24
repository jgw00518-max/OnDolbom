import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:ondolbom/model/medications/medication.dart';
import 'package:ondolbom/vm/family_context.dart';

typedef MedicationQuery = ({FamilyContext context, String date});
final medicationHttpClientProvider = Provider.autoDispose<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

class MedicationFailure implements Exception {
  const MedicationFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

class MedicationFeed {
  const MedicationFeed(
    this.items, {
    required this.hasMore,
    required this.offset,
    this.loadingMore = false,
  });
  final List<Medication> items;
  final bool hasMore;
  final int offset;
  final bool loadingMore;
}

final medicationVmProvider = AsyncNotifierProvider.autoDispose
    .family<MedicationVm, MedicationFeed, MedicationQuery>(
      MedicationVm.new,
      retry: (_, _) => null,
    );

class MedicationVm extends AsyncNotifier<MedicationFeed> {
  MedicationVm(this.query);
  final MedicationQuery query;
  static const pageSize = 20;
  late http.Client _client;
  late String _base;
  late Future<String?> Function() _tokenLoader;
  int _generation = 0;

  @override
  Future<MedicationFeed> build() async {
    _generation++;
    _client = ref.watch(medicationHttpClientProvider);
    _base = ref.watch(apiBaseUrlProvider);
    _tokenLoader = ref.watch(apiTokenLoaderProvider);
    if (query.context.familyRoomId.isEmpty) {
      return const MedicationFeed([], hasMore: false, offset: 0);
    }
    final items = await _fetch(0);
    return MedicationFeed(
      items,
      hasMore: items.length == pageSize,
      offset: items.length,
    );
  }

  Future<Map<String, dynamic>> _request(
    String path, {
    Map<String, String>? params,
    Map<String, dynamic>? body,
  }) async {
    final generation = _generation;
    try {
      final token = await _tokenLoader().timeout(const Duration(seconds: 15));
      if (token == null || token.isEmpty) {
        throw const MedicationFailure('로그인이 필요해요. 로그인 상태를 확인해 주세요.');
      }
      if (!ref.mounted || generation != _generation) {
        throw const MedicationFailure('로그인 상태가 변경되었습니다.');
      }
      final headers = <String, String>{
        'Accept': 'application/json',
        if (body != null) 'Content-Type': 'application/json; charset=utf-8',
        'Authorization': 'Bearer $token',
      };
      final uri = Uri.parse(
        '${_base.replaceFirst(RegExp(r'/+$'), '')}/medications/$path',
      ).replace(queryParameters: params);
      final response =
          await (body == null
                  ? _client.get(uri, headers: headers)
                  : _client.post(uri, headers: headers, body: jsonEncode(body)))
              .timeout(const Duration(seconds: 15));
      if (!ref.mounted || generation != _generation) {
        throw const MedicationFailure('로그인 상태가 변경되었습니다.');
      }
      if (response.statusCode == 401) {
        throw const MedicationFailure('로그인이 필요해요. 로그인 상태를 확인해 주세요.');
      }
      if (response.statusCode == 403) {
        throw const MedicationFailure('이 공간의 투약일지에 접근할 수 없어요.');
      }
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic>) throw const FormatException();
      if (response.statusCode != (body == null ? 200 : 201)) {
        throw MedicationFailure(
          decoded['detail'] is String
              ? decoded['detail'] as String
              : '요청을 처리하지 못했어요. 입력 내용을 확인해 주세요.',
        );
      }
      return decoded;
    } on TimeoutException {
      throw const MedicationFailure('응답이 지연되고 있어요. 잠시 후 다시 시도해 주세요.');
    } on http.ClientException {
      throw const MedicationFailure('서버에 연결할 수 없어요. 연결 상태를 확인해 주세요.');
    } on FormatException {
      throw const MedicationFailure('서버 응답을 읽지 못했어요. 다시 시도해 주세요.');
    }
  }

  Future<List<Medication>> _fetch(int offset) async {
    final result = await _request(
      'select',
      params: {
        'family_room_id': query.context.familyRoomId,
        'medication_date': query.date,
        'limit': '$pageSize',
        'offset': '$offset',
      },
    );
    return (result['results'] as List<dynamic>)
        .map((item) => Medication.fromJson(item as Map<String, dynamic>))
        .toList();
  }

  Future<void> loadMore() async {
    final before = state.asData?.value;
    if (before == null || before.loadingMore || !before.hasMore) return;
    final generation = _generation;
    state = AsyncData(
      MedicationFeed(
        before.items,
        hasMore: true,
        offset: before.offset,
        loadingMore: true,
      ),
    );
    try {
      final next = await _fetch(before.offset);
      if (!ref.mounted || generation != _generation) return;
      final unique = {
        for (final item in [...before.items, ...next]) item.seq: item,
      };
      state = AsyncData(
        MedicationFeed(
          unique.values.toList(),
          hasMore: next.length == pageSize,
          offset: before.offset + next.length,
        ),
      );
    } catch (_) {
      if (ref.mounted && generation == _generation) state = AsyncData(before);
      rethrow;
    }
  }

  Future<void> create({
    required String info,
    required String time,
    required String dosage,
    required String unit,
  }) async {
    if (query.context.familyRoomId.isEmpty || query.context.userId.isEmpty) {
      throw const MedicationFailure('사용자와 돌봄 공간을 먼저 선택해 주세요.');
    }
    if (info.trim().isEmpty ||
        info.trim().runes.length > 100 ||
        time.trim().isEmpty ||
        time.trim().runes.length > 20 ||
        unit.trim().isEmpty ||
        unit.trim().runes.length > 20 ||
        !isValidMedicationDosage(dosage)) {
      throw const MedicationFailure('약 정보와 용량을 확인해 주세요.');
    }
    await _request(
      'insert',
      body: {
        'family_room_id': query.context.familyRoomId,
        'medication_info': info.trim(),
        'medication_date': query.date,
        'medication_time': time.trim(),
        'dosage': dosage.trim(),
        'dosage_unit': unit.trim(),
      },
    );
    if (ref.mounted) ref.invalidateSelf();
  }
}
