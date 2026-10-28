import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:ondolbom/model/medications/medication.dart';
import 'package:ondolbom/vm/family_room/family_context.dart';
import 'package:ondolbom/vm/family_room/family_room_notifier.dart';

typedef MedicationQuery = ({FamilyContext context, String date});
final medicationEditAllowedProvider = Provider.family<bool, FamilyContext>((
  ref,
  context,
) {
  final state = ref.watch(familyRoomProvider);
  final member = state.selectedParticipation;
  return state.selectedRoomId == context.familyRoomId &&
      member != null &&
      member.userId == context.userId &&
      member.isActive &&
      member.isRepresentative;
});
// 작성과 수정은 동일한 주보호자·활성 참여 조건을 사용한다.
final medicationCreateAllowedProvider = medicationEditAllowedProvider;
final medicationHttpClientProvider = Provider.autoDispose<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

class MedicationFailure implements Exception {
  const MedicationFailure(this.message, {this.statusCode});
  final String message;
  final int? statusCode;
  @override
  String toString() => message;
}

class MedicationFeed {
  const MedicationFeed(
    this.items, {
    required this.hasMore,
    required this.offset,
    this.loadingMore = false,
    this.confirming = const {},
  });
  final List<Medication> items;
  final bool hasMore;
  final int offset;
  final bool loadingMore;
  final Set<int> confirming;

  MedicationFeed copyWith({
    List<Medication>? items,
    bool? loadingMore,
    Set<int>? confirming,
  }) => MedicationFeed(
    items ?? this.items,
    hasMore: hasMore,
    offset: offset,
    loadingMore: loadingMore ?? this.loadingMore,
    confirming: confirming ?? this.confirming,
  );
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
  final _confirming = <int>{};
  final _confirmationVersions = <int, int>{};

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
      confirming: Set.unmodifiable(_confirming),
    );
  }

  Future<Map<String, dynamic>> _request(
    String path, {
    Map<String, String>? params,
    Map<String, dynamic>? body,
    bool patch = false,
    bool delete = false,
    void Function()? beforeSend,
    int? expectedStatus,
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
      if (path == 'insert') _ensureCanCreate();
      if (path.startsWith('confirm/')) _ensureConfirmationContext();
      beforeSend?.call();
      final headers = <String, String>{
        'Accept': 'application/json',
        if (body != null) 'Content-Type': 'application/json; charset=utf-8',
        'Authorization': 'Bearer $token',
      };
      final uri = Uri.parse(
        '${_base.replaceFirst(RegExp(r'/+$'), '')}/medications/$path',
      ).replace(queryParameters: params);
      final response =
          await (delete
                  ? _client.delete(
                      uri,
                      headers: headers,
                      body: jsonEncode(body),
                    )
                  : patch
                  ? _client.patch(uri, headers: headers, body: jsonEncode(body))
                  : body == null
                  ? _client.get(uri, headers: headers)
                  : _client.post(uri, headers: headers, body: jsonEncode(body)))
              .timeout(const Duration(seconds: 15));
      if (!ref.mounted || generation != _generation) {
        throw const MedicationFailure('로그인 상태가 변경되었습니다.');
      }
      if (path.startsWith('confirm/')) _ensureConfirmationContext();
      if (response.statusCode == 401) {
        throw const MedicationFailure('로그인이 필요해요. 로그인 상태를 확인해 주세요.');
      }
      if (response.statusCode == 403) {
        throw MedicationFailure(
          path.startsWith('delete/')
              ? '현재 공간의 주보호자만 약을 삭제할 수 있어요.'
              : delete
              ? '체크한 본인 또는 현재 주보호자만 체크를 해제할 수 있어요.'
              : patch
              ? '현재 공간의 주보호자만 투약 정보를 수정할 수 있어요.'
              : path == 'insert'
              ? '현재 공간의 주보호자만 투약일지를 작성할 수 있어요.'
              : '이 공간의 투약일지에 접근할 수 없어요.',
        );
      }
      final decoded = jsonDecode(utf8.decode(response.bodyBytes));
      if (decoded is! Map<String, dynamic>) throw const FormatException();
      if (response.statusCode !=
          (expectedStatus ?? (patch || body == null ? 200 : 201))) {
        throw MedicationFailure(
          decoded['detail'] is String
              ? decoded['detail'] as String
              : '요청을 처리하지 못했어요. 입력 내용을 확인해 주세요.',
          statusCode: response.statusCode,
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
    final versions = Map<int, int>.of(_confirmationVersions);
    state = AsyncData(
      MedicationFeed(
        before.items,
        hasMore: true,
        offset: before.offset,
        loadingMore: true,
        confirming: Set.unmodifiable(_confirming),
      ),
    );
    try {
      final next = await _fetch(before.offset);
      if (!ref.mounted || generation != _generation) return;
      final current = state.asData?.value ?? before;
      final unique = {for (final item in current.items) item.seq: item};
      for (final item in next) {
        if (unique.containsKey(item.seq) &&
            (_confirming.contains(item.seq) ||
                versions[item.seq] != _confirmationVersions[item.seq])) {
          continue;
        }
        if (unique[item.seq]?.isConfirmed == true && !item.isConfirmed) {
          continue;
        }
        unique[item.seq] = item;
      }
      state = AsyncData(
        MedicationFeed(
          unique.values.toList(),
          hasMore: next.length == pageSize,
          offset: before.offset + next.length,
          confirming: Set.unmodifiable(_confirming),
        ),
      );
    } catch (_) {
      if (ref.mounted && generation == _generation) {
        state = AsyncData(
          (state.asData?.value ?? before).copyWith(loadingMore: false),
        );
      }
      rethrow;
    }
  }

  void _ensureConfirmationContext() {
    if (ref.read(familyContextProvider) != query.context ||
        query.context.userId.isEmpty ||
        query.context.familyRoomId.isEmpty) {
      throw const MedicationFailure('선택한 공간과 로그인 상태를 확인해 주세요.');
    }
  }

  Future<void> confirmMedication(Medication item) => _changeConfirmation(item);

  Future<void> unconfirmMedication(Medication item) =>
      _changeConfirmation(item, undo: true);

  void _ensureCanUnconfirm(Medication item) {
    _ensureConfirmationContext();
    if (item.confirmedByUserId != query.context.userId &&
        !ref.read(medicationEditAllowedProvider(query.context))) {
      throw const MedicationFailure('체크한 본인 또는 현재 주보호자만 체크를 해제할 수 있어요.');
    }
  }

  Future<void> _changeConfirmation(Medication item, {bool undo = false}) async {
    _ensureConfirmationContext();
    if (item.familyRoomId != query.context.familyRoomId) {
      throw const MedicationFailure('다른 공간의 투약일지는 체크할 수 없어요.');
    }
    final feed = state.asData?.value;
    if (feed == null) throw const MedicationFailure('목록을 불러온 후 다시 시도해 주세요.');
    final target = feed.items
        .where((record) => record.seq == item.seq)
        .firstOrNull;
    if (target == null) throw const MedicationFailure('투약일지를 다시 조회해 주세요.');
    if (undo) {
      if (!target.isConfirmed) return;
      _ensureCanUnconfirm(target);
      if (target.confirmedAt != item.confirmedAt ||
          target.confirmedByUserId != item.confirmedByUserId) {
        throw const MedicationFailure('체크 기록이 변경되었습니다. 다시 확인해 주세요.');
      }
    } else if (target.isConfirmed) {
      return;
    }
    if (!_confirming.add(item.seq)) return;
    state = AsyncData(feed.copyWith(confirming: Set.unmodifiable(_confirming)));
    try {
      final result = await _request(
        'confirm/${item.seq}',
        delete: undo,
        beforeSend: undo ? () => _ensureCanUnconfirm(target) : null,
        body: {
          'family_room_id': query.context.familyRoomId,
          if (undo) ...{
            'expected_confirmed_at': target.confirmedAt!.toIso8601String(),
            'expected_confirmed_by_user_id': target.confirmedByUserId,
          },
        },
        expectedStatus: 200,
      );
      final at = DateTime.tryParse(
        result['medication_confirmed_at'] as String? ?? '',
      );
      if ((!undo && at == null) ||
          (undo &&
              (at != null ||
                  result['confirmed_by_user_id'] != null ||
                  result['confirmed_by_name'] != null)) ||
          result['medication_log_seq'] != item.seq) {
        throw const MedicationFailure('체크 결과를 확인하지 못했어요. 다시 시도해 주세요.');
      }
      final current = state.asData?.value;
      if (ref.mounted && current != null) {
        _confirmationVersions[item.seq] =
            (_confirmationVersions[item.seq] ?? 0) + 1;
        state = AsyncData(
          current.copyWith(
            items: [
              for (final record in current.items)
                if (record.seq == item.seq)
                  record.withConfirmation(
                    at,
                    result['confirmed_by_user_id'] as String?,
                    result['confirmed_by_name'] as String?,
                  )
                else
                  record,
            ],
          ),
        );
      }
    } on MedicationFailure catch (error) {
      if (undo && error.statusCode == 409 && ref.mounted) {
        ref.invalidateSelf();
        try {
          await future;
        } catch (_) {
          // 조회 실패는 목록의 오류 상태로 표시하고 원래 충돌 안내도 유지한다.
        }
      }
      rethrow;
    } finally {
      _confirming.remove(item.seq);
      if (ref.mounted) {
        final current = state.asData?.value;
        if (current != null) {
          state = AsyncData(
            current.copyWith(confirming: Set.unmodifiable(_confirming)),
          );
        }
      }
    }
  }

  Future<void> create({
    required String info,
    required String time,
    required String dosage,
    required String unit,
    int durationDays = 1,
  }) async {
    _ensureCanCreate();
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
    if (durationDays < 1 || durationDays > 365) {
      throw const MedicationFailure('복용 기간은 1~365일로 입력해 주세요.');
    }
    await _request(
      'insert',
      body: {
        'family_room_id': query.context.familyRoomId,
        'medication_info': info.trim(),
        'medication_date': query.date,
        'duration_days': durationDays,
        'medication_time': time.trim(),
        'dosage': dosage.trim(),
        'dosage_unit': unit.trim(),
      },
    );
    // 기간에 포함된 다른 날짜 화면도 다음 조회에서 새 항목을 받도록 무효화한다.
    if (ref.mounted) ref.invalidate(medicationVmProvider);
  }

  Future<int> deletePeriod(Medication item) async {
    _ensureCanCreate();
    if (item.familyRoomId != query.context.familyRoomId) {
      throw const MedicationFailure('선택한 공간이 변경되었습니다.');
    }
    final result = await _request(
      'delete/${item.seq}',
      delete: true,
      expectedStatus: 200,
      beforeSend: _ensureCanCreate,
      body: {'family_room_id': query.context.familyRoomId},
    );
    final count = result['deleted_count'] as int;
    if (ref.mounted) ref.invalidate(medicationVmProvider);
    return count;
  }

  void _ensureCanCreate() {
    if (ref.read(familyContextProvider) != query.context) {
      throw const MedicationFailure('선택한 공간이 변경됐어요. 닫은 후 다시 작성해 주세요.');
    }
    if (!ref.read(medicationCreateAllowedProvider(query.context))) {
      throw const MedicationFailure('현재 공간의 주보호자만 투약일지를 작성할 수 있어요.');
    }
  }

  Future<void> updateMedication({
    required Medication item,
    required DateTime date,
    required String info,
    required String time,
    required String dosage,
    required String unit,
  }) async {
    if (ref.read(familyContextProvider) != query.context ||
        item.familyRoomId != query.context.familyRoomId) {
      throw const MedicationFailure('선택한 공간이 변경됐어요. 닫은 후 다시 조회해 주세요.');
    }
    if (!ref.read(medicationEditAllowedProvider(query.context))) {
      throw const MedicationFailure('현재 공간의 주보호자만 투약 정보를 수정할 수 있어요.');
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
    final generation = _generation;
    await _request(
      'update/${item.seq}',
      patch: true,
      body: {
        'family_room_id': query.context.familyRoomId,
        'medication_info': info.trim(),
        'medication_date': medicationDateKey(date),
        'medication_time': time.trim(),
        'dosage': dosage.trim(),
        'dosage_unit': unit.trim(),
      },
    );
    if (!ref.mounted ||
        generation != _generation ||
        ref.read(familyContextProvider) != query.context) {
      throw const MedicationFailure('선택한 공간이 변경됐어요. 다시 조회해 주세요.');
    }
    final target = (context: query.context, date: medicationDateKey(date));
    if (target != query) ref.invalidate(medicationVmProvider(target));
    ref.invalidateSelf();
  }
}
