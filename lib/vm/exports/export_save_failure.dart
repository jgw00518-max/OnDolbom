import 'package:flutter/services.dart';

import 'export_os_error_stub.dart'
    if (dart.library.io) 'export_os_error_io.dart'
    as os;

enum ExportSaveProblem {
  pluginUnavailable,
  permissionDenied,
  noSpace,
  locationUnavailable,
  pickerUnavailable,
  alreadyActive,
  unknown,
}

class ExportSaveFailure {
  const ExportSaveFailure(this.problem, this.code);

  final ExportSaveProblem problem;
  // OS·플러그인 코드만 보관하고 경로나 원본 메시지는 로그에 넘기지 않는다.
  final String code;

  String get message => switch (problem) {
    ExportSaveProblem.pluginUnavailable =>
      '파일 저장 기능을 사용할 수 없어요. 앱을 완전히 종료한 뒤 다시 실행해 주세요. 계속되면 앱을 업데이트해 주세요.',
    ExportSaveProblem.permissionDenied => '선택한 위치에 저장할 수 없어요. 다른 폴더를 선택해 주세요.',
    ExportSaveProblem.noSpace =>
      '선택한 저장 위치의 공간이 부족해요. 공간을 확보하거나 다른 위치를 선택해 주세요.',
    ExportSaveProblem.locationUnavailable =>
      '선택한 저장 위치를 사용할 수 없어요. 다른 위치를 선택해 주세요.',
    ExportSaveProblem.pickerUnavailable =>
      '파일 저장 창을 열 수 없어요. 앱을 다시 실행하거나 기기의 파일 앱을 확인해 주세요.',
    ExportSaveProblem.alreadyActive =>
      '파일 저장 창이 이미 열려 있어요. 현재 창을 닫은 뒤 다시 시도해 주세요.',
    ExportSaveProblem.unknown => '파일을 저장하지 못했어요. 저장 위치를 바꾸거나 다시 시도해 주세요.',
  };

  factory ExportSaveFailure.from(Object error) {
    if (error is MissingPluginException) {
      return const ExportSaveFailure(
        ExportSaveProblem.pluginUnavailable,
        'missing_plugin',
      );
    }
    final code = error is PlatformException
        ? error.code.trim().toLowerCase().replaceAll(RegExp(r'[\s-]+'), '_')
        : os.exportFileSystemCode(error);
    final direct = switch (code) {
      'permission_denied' ||
      'access_denied' ||
      'security_exception' ||
      'eacces' ||
      'eperm' => ExportSaveProblem.permissionDenied,
      'enospc' || 'disk_full' || 'no_space_left' => ExportSaveProblem.noSpace,
      'enoent' ||
      'enodev' ||
      'enotdir' ||
      'unknown_path' => ExportSaveProblem.locationUnavailable,
      'no_activity' ||
      'unknown_activity' ||
      'invalid_format_type' => ExportSaveProblem.pickerUnavailable,
      'already_active' || 'multiple_request' => ExportSaveProblem.alreadyActive,
      _ => null,
    };
    // file_picker Android는 IOException을 일반 코드와 원래 메시지로 반환한다.
    // 명확한 시스템 식별자가 있을 때만 세부 원인을 확정한다.
    final nativeMessage = error is PlatformException ? error.message ?? '' : '';
    final detected =
        direct ??
        (RegExp(
              r'\bENOSPC\b|\bERROR_DISK_FULL\b|\bNo space left on device\b',
              caseSensitive: false,
            ).hasMatch(nativeMessage)
            ? ExportSaveProblem.noSpace
            : RegExp(
                r'\bEACCES\b|\bEPERM\b|\bSecurityException\b|\bPermission denied\b',
                caseSensitive: false,
              ).hasMatch(nativeMessage)
            ? ExportSaveProblem.permissionDenied
            : RegExp(
                r'\bENOENT\b|\bENODEV\b|\bENOTDIR\b',
                caseSensitive: false,
              ).hasMatch(nativeMessage)
            ? ExportSaveProblem.locationUnavailable
            : ExportSaveProblem.unknown);
    final safeCode = code != null && RegExp(r'^[a-z0-9_]{1,64}$').hasMatch(code)
        ? code
        : 'unrecognized';
    return ExportSaveFailure(detected, safeCode);
  }
}
