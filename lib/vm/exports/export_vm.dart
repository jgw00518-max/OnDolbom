import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:ondolbom/model/exports/export_options.dart';
import 'package:ondolbom/vm/exports/export_save_failure.dart';
import 'package:ondolbom/vm/family_room/family_context.dart';

final exportTodayProvider = Provider<DateTime>((ref) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
});

final exportHttpClientProvider = Provider.autoDispose<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

// 취소는 false, 저장 완료는 true. 저장 실패 시 생성한 파일은 재사용한다.
final exportFileSaverProvider = Provider<Future<bool> Function(ExportFile)>((
  ref,
) {
  return (file) async {
    final path = await FilePicker.platform.saveFile(
      dialogTitle: '메모·채팅 파일 저장',
      fileName: file.name,
      type: FileType.custom,
      allowedExtensions: [file.format.extension],
      bytes: file.bytes,
    );
    // Web 구현은 다운로드를 시작한 뒤에도 null을 반환한다.
    return kIsWeb || path != null;
  };
});

// 네이티브 메시지·details에는 경로 등이 들어갈 수 있어 로그에 그대로 남기지 않는다.
final exportSaveLoggerProvider =
    Provider<void Function(ExportSaveFailure, Object, StackTrace)>((ref) {
      return (failure, error, stack) {
        developer.log(
          'problem=${failure.problem.name} exception=${error.runtimeType} code=${failure.code}',
          name: 'ondolbom.exports.save',
          level: 1000,
          stackTrace: stack,
        );
      };
    });

enum ExportPhase { idle, generating, saving }

class ExportState {
  const ExportState({
    this.phase = ExportPhase.idle,
    this.file,
    this.error,
    this.message,
    this.saveProblem,
  });
  final ExportPhase phase;
  final ExportFile? file;
  final String? error;
  final String? message;
  final ExportSaveProblem? saveProblem;
  bool get busy => phase != ExportPhase.idle;
}

class ExportFailure implements Exception {
  const ExportFailure(this.message);
  final String message;
}

final exportVmProvider = NotifierProvider.autoDispose
    .family<ExportVm, ExportState, FamilyContext>(ExportVm.new);

class ExportVm extends Notifier<ExportState> {
  ExportVm(this.selected);
  final FamilyContext selected;
  late http.Client _client;
  late String _baseUrl;
  late Future<String?> Function() _tokenLoader;
  late Future<bool> Function(ExportFile) _saveFile;
  int _generation = 0;

  @override
  ExportState build() {
    _generation++;
    _client = ref.watch(exportHttpClientProvider);
    _baseUrl = ref.watch(apiBaseUrlProvider).replaceFirst(RegExp(r'/+$'), '');
    _tokenLoader = ref.watch(apiTokenLoaderProvider);
    _saveFile = ref.watch(exportFileSaverProvider);
    return const ExportState();
  }

  void clear() {
    if (!state.busy) state = const ExportState();
  }

  void _checkContext() {
    if (!ref.mounted || ref.read(familyContextProvider) != selected) {
      throw const ExportFailure('계정 또는 가족 공간이 변경됐어요. 화면을 다시 열어 주세요.');
    }
    if (selected.familyRoomId.isEmpty || selected.userId.isEmpty) {
      throw const ExportFailure('로그인 후 가족 공간을 선택해 주세요.');
    }
  }

  bool _active(int generation) => ref.mounted && generation == _generation;

  Future<void> generate(ExportOptions options) async {
    if (state.busy) return;
    final generation = _generation;
    state = const ExportState(phase: ExportPhase.generating);
    try {
      _checkContext();
      final today = ref.read(exportTodayProvider);
      if ((!options.memos && !options.chats) ||
          options.startDate.isAfter(options.endDate) ||
          options.endDate.isAfter(today)) {
        throw const ExportFailure('기간과 내보낼 범위를 확인해 주세요.');
      }
      final token = await _tokenLoader().timeout(const Duration(seconds: 15));
      if (!_active(generation)) return;
      _checkContext();
      if (token == null || token.isEmpty) {
        throw const ExportFailure('로그인이 필요해요. 다시 로그인해 주세요.');
      }
      final response = await _client
          .post(
            Uri.parse('$_baseUrl/exports/download'),
            headers: {
              'Authorization': 'Bearer $token',
              'Content-Type': 'application/json',
              'Accept': options.format.contentType,
            },
            body: jsonEncode(options.toJson(selected.familyRoomId)),
          )
          .timeout(const Duration(minutes: 3));
      if (!_active(generation)) return;
      _checkContext();
      if (response.statusCode != 200) {
        throw ExportFailure(_errorMessage(response));
      }
      final bytes = response.bodyBytes;
      final contentType = (response.headers['content-type'] ?? '')
          .split(';')
          .first
          .trim()
          .toLowerCase();
      final signature = options.format.signature;
      if (contentType != options.format.contentType ||
          bytes.length < signature.length ||
          !listEquals(bytes.sublist(0, signature.length), signature)) {
        final label = options.format == ExportFormat.pdf ? 'PDF' : 'ZIP';
        throw ExportFailure('올바른 $label 파일을 받지 못했어요. 다시 요청해 주세요.');
      }
      state = ExportState(
        file: ExportFile(
          bytes: bytes,
          name: options.fileName,
          format: options.format,
        ),
        message: '파일 생성이 완료됐어요. 다운로드하여 저장해 주세요.',
      );
    } on ExportFailure catch (error) {
      if (_active(generation)) state = ExportState(error: error.message);
    } on TimeoutException {
      if (_active(generation)) {
        state = const ExportState(error: '응답이 지연되고 있어요. 기간을 줄이거나 다시 요청해 주세요.');
      }
    } catch (_) {
      if (_active(generation)) {
        state = const ExportState(
          error: '파일을 받지 못했어요. 연결 상태를 확인하고 다시 요청해 주세요.',
        );
      }
    }
  }

  Future<void> save() async {
    final file = state.file;
    if (state.busy || file == null) return;
    final generation = _generation;
    state = ExportState(phase: ExportPhase.saving, file: file);
    try {
      _checkContext();
      final saved = await _saveFile(file);
      if (!_active(generation)) return;
      _checkContext();
      state = ExportState(
        file: file,
        message: saved
            ? kIsWeb
                  ? '다운로드를 시작했어요. 브라우저의 다운로드 목록을 확인해 주세요.'
                  : file.format == ExportFormat.pdf
                  ? '파일을 저장했어요. PDF 뷰어에서 바로 열어 확인해 주세요.'
                  : '파일을 저장했어요. ZIP 압축을 해제하고 index.html을 열어 주세요.'
            : '저장을 취소했어요. 다운로드 버튼으로 다시 저장할 수 있어요.',
      );
    } on ExportFailure catch (error) {
      if (_active(generation)) state = ExportState(error: error.message);
    } catch (error, stack) {
      if (_active(generation)) {
        final failure = ExportSaveFailure.from(error);
        ref.read(exportSaveLoggerProvider)(failure, error, stack);
        state = ExportState(
          file: file,
          error: failure.message,
          saveProblem: failure.problem,
        );
      }
    }
  }

  String _errorMessage(http.Response response) {
    try {
      final body = jsonDecode(utf8.decode(response.bodyBytes));
      if (body is Map && body['detail'] is String) {
        return body['detail'] as String;
      }
    } catch (_) {
      // 프록시 등의 비 JSON 오류는 상태 코드에 맞는 안내로 바꾼다.
    }
    return switch (response.statusCode) {
      401 => '로그인이 만료됐어요. 다시 로그인해 주세요.',
      403 => '현재 이 공간의 기록을 내보낼 권한이 없어요.',
      422 => '기간과 내보낼 범위를 확인해 주세요.',
      _ => '파일을 생성하지 못했어요. 잠시 후 다시 요청해 주세요.',
    };
  }
}
