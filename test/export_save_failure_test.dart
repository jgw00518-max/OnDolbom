import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:ondolbom/vm/exports/export_save_failure.dart';

void main() {
  test('플러그인·권한·용량·위치·저장 창 오류를 확인된 코드로 구분한다', () {
    final cases = <(Object, ExportSaveProblem)>[
      (
        MissingPluginException('No implementation found'),
        ExportSaveProblem.pluginUnavailable,
      ),
      (
        PlatformException(code: 'permission_denied'),
        ExportSaveProblem.permissionDenied,
      ),
      (
        PlatformException(
          code: 'Error while saving file',
          message: 'open failed: EACCES (Permission denied)',
        ),
        ExportSaveProblem.permissionDenied,
      ),
      (
        PlatformException(
          code: 'Error while saving file',
          message: 'write failed: ENOSPC (No space left on device)',
        ),
        ExportSaveProblem.noSpace,
      ),
      (PlatformException(code: 'disk_full'), ExportSaveProblem.noSpace),
      (
        PlatformException(
          code: 'Error while saving file',
          message: 'open failed: ENOENT (No such file or directory)',
        ),
        ExportSaveProblem.locationUnavailable,
      ),
      (
        PlatformException(code: 'unknown_path'),
        ExportSaveProblem.locationUnavailable,
      ),
      (
        PlatformException(code: 'no_activity'),
        ExportSaveProblem.pickerUnavailable,
      ),
      (
        PlatformException(code: 'invalid_format_type'),
        ExportSaveProblem.pickerUnavailable,
      ),
      (
        PlatformException(code: 'already_active'),
        ExportSaveProblem.alreadyActive,
      ),
      (
        PlatformException(code: 'multiple_request'),
        ExportSaveProblem.alreadyActive,
      ),
    ];
    for (final (error, problem) in cases) {
      expect(ExportSaveFailure.from(error).problem, problem);
    }
  });

  test('원인이 불명확한 쓰기 오류·details 숫자로 용량 부족을 추정하지 않는다', () {
    for (final error in [
      Exception('disk'),
      PlatformException(
        code: 'Error while saving file',
        message: 'Failed to write file',
      ),
      PlatformException(code: 'Failed to write file', details: {'code': 28}),
      const FileSystemException('write failed'),
    ]) {
      final failure = ExportSaveFailure.from(error);
      expect(failure.problem, ExportSaveProblem.unknown);
      expect(failure.message, contains('저장 위치를 바꾸거나'));
    }
  });

  test('OS별 파일 시스템 오류 번호를 구분한다', () {
    for (final (code, problem) in [
      (Platform.isWindows ? 112 : 28, ExportSaveProblem.noSpace),
      (Platform.isWindows ? 5 : 13, ExportSaveProblem.permissionDenied),
      (Platform.isWindows ? 3 : 2, ExportSaveProblem.locationUnavailable),
    ]) {
      final failure = ExportSaveFailure.from(
        FileSystemException(
          'private OS message',
          '/private/path',
          OSError('native detail', code),
        ),
      );
      expect(failure.problem, problem);
      expect(failure.message, isNot(contains('private')));
    }
  });

  test('네이티브 경로·원본 메시지·details를 안내나 진단 코드에 노출하지 않는다', () {
    final failure = ExportSaveFailure.from(
      PlatformException(
        code: '/private/folder',
        message: '/private/folder/record.pdf: ENOSPC (No space left on device)',
        details: {'token': 'private-token'},
      ),
    );
    expect(failure.problem, ExportSaveProblem.noSpace);
    expect(failure.code, 'unrecognized');
    expect(failure.message, isNot(contains('private')));
  });
}
