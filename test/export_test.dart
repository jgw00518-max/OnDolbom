import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show MissingPluginException, PlatformException;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ondolbom/model/exports/export_options.dart';
import 'package:ondolbom/model/family/family_room.dart';
import 'package:ondolbom/view/exports/export_view.dart';
import 'package:ondolbom/view/family_room/family_room_home.dart';
import 'package:ondolbom/vm/auth/auth_vm.dart';
import 'package:ondolbom/vm/exports/export_vm.dart';
import 'package:ondolbom/vm/exports/export_save_failure.dart';
import 'package:ondolbom/vm/family_room/family_context.dart';
import 'package:ondolbom/vm/family_room/family_room_notifier.dart';
import 'package:ondolbom/vm/family_room/family_room_state.dart';

const selected = (
  familyRoomId: 'room-a',
  userId: 'user-a',
  roomName: '가족 A의 공간',
);
final today = DateTime(2026, 10, 27);
final zipBytes = Uint8List.fromList([0x50, 0x4b, 0x03, 0x04, 1, 2, 3, 4]);
final pdfBytes = Uint8List.fromList(utf8.encode('%PDF-1.7\nexample'));
http.Response pdfResponse() => http.Response.bytes(
  pdfBytes,
  200,
  headers: {'content-type': 'application/pdf'},
);
http.Response zipResponse() => http.Response.bytes(
  zipBytes,
  200,
  headers: {'content-type': 'application/zip'},
);
ExportOptions options({
  bool memos = true,
  bool chats = true,
  bool images = false,
  ExportFormat format = ExportFormat.html,
}) => ExportOptions(
  startDate: DateTime(2026, 10, 1),
  endDate: today,
  memos: memos,
  chats: chats,
  includeImages: images,
  format: format,
);

class ExportRooms extends FamilyRoomNotifier {
  @override
  FamilyRoomState build() => const FamilyRoomState(
    selectedRoomId: 'room-a',
    rooms: [
      FamilyRoom(
        familyRoomId: 'room-a',
        createdBy: 'user-a',
        careRecipientName: '가족 A',
      ),
    ],
  );
}

class RecordingExportPicker extends FilePicker {
  String? savedName;
  List<String>? extensions;
  Uint8List? savedBytes;

  @override
  Future<String?> saveFile({
    String? dialogTitle,
    String? fileName,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Uint8List? bytes,
    bool lockParentWindow = false,
  }) async {
    savedName = fileName;
    extensions = allowedExtensions;
    savedBytes = bytes;
    return '/saved/$fileName';
  }
}

final testContextProvider = NotifierProvider<TestExportContext, FamilyContext>(
  TestExportContext.new,
);

class TestExportContext extends Notifier<FamilyContext> {
  @override
  FamilyContext build() => selected;

  void select(FamilyContext context) => state = context;
}

ProviderContainer containerFor(
  http.Client client, {
  Future<String?> Function()? tokenLoader,
  Future<bool> Function(ExportFile)? saver,
  void Function(ExportSaveFailure, Object, StackTrace)? logger,
}) => ProviderContainer(
  overrides: [
    familyContextProvider.overrideWith((ref) => ref.watch(testContextProvider)),
    apiBaseUrlProvider.overrideWithValue('http://localhost:8000/'),
    apiTokenLoaderProvider.overrideWithValue(
      tokenLoader ?? () async => 'id-token',
    ),
    exportHttpClientProvider.overrideWithValue(client),
    exportTodayProvider.overrideWithValue(today),
    exportFileSaverProvider.overrideWithValue(saver ?? (_) async => true),
    exportSaveLoggerProvider.overrideWithValue(logger ?? (_, _, _) {}),
  ],
);

void main() {
  test('저장 오류별 상태·진단 로그를 남기고 생성 파일로 재시도한다', () async {
    for (final (error, problem) in <(Object, ExportSaveProblem)>[
      (MissingPluginException(), ExportSaveProblem.pluginUnavailable),
      (
        PlatformException(code: 'permission_denied'),
        ExportSaveProblem.permissionDenied,
      ),
      (
        PlatformException(
          code: 'Error while saving file',
          message: 'ENOSPC (No space left on device)',
        ),
        ExportSaveProblem.noSpace,
      ),
      (
        PlatformException(code: 'unknown_path'),
        ExportSaveProblem.locationUnavailable,
      ),
      (Exception('unclassified'), ExportSaveProblem.unknown),
    ]) {
      var posts = 0;
      var saves = 0;
      final logged = <ExportSaveProblem>[];
      final client = MockClient((_) async {
        posts++;
        return zipResponse();
      });
      final container = containerFor(
        client,
        saver: (_) async {
          if (++saves == 1) throw error;
          return true;
        },
        logger: (failure, actual, stack) {
          expect(identical(actual, error), isTrue);
          expect(stack.toString(), isNotEmpty);
          logged.add(failure.problem);
        },
      );
      final provider = exportVmProvider(selected);
      final sub = container.listen(provider, (_, _) {});
      try {
        await container.read(provider.notifier).generate(options());
        final file = container.read(provider).file;
        await container.read(provider.notifier).save();
        expect(container.read(provider).saveProblem, problem);
        expect(
          container.read(provider).error,
          ExportSaveFailure.from(error).message,
        );
        expect(identical(container.read(provider).file, file), isTrue);
        expect(logged, [problem]);
        await container.read(provider.notifier).save();
        expect(container.read(provider).saveProblem, isNull);
        expect(container.read(provider).error, isNull);
        expect(posts, 1);
      } finally {
        sub.close();
        container.dispose();
        client.close();
      }
    }
  });
  test('파일 저장기에 PDF·HTML에 맞는 확장자와 바이트를 전달한다', () async {
    FilePicker? previous;
    try {
      previous = FilePicker.platform;
    } on Error {
      // 네이티브 플러그인이 등록되지 않은 테스트 런타임도 지원한다.
    }
    final picker = RecordingExportPicker();
    FilePicker.platform = picker;
    addTearDown(() {
      if (previous != null) FilePicker.platform = previous;
    });
    final container = ProviderContainer();
    addTearDown(container.dispose);
    for (final format in ExportFormat.values) {
      final bytes = format == ExportFormat.pdf ? pdfBytes : zipBytes;
      final name = options(format: format).fileName;
      final saved = await container.read(exportFileSaverProvider)(
        ExportFile(bytes: bytes, name: name, format: format),
      );
      expect(saved, isTrue);
      expect(picker.savedName, name);
      expect(picker.extensions, [format.extension]);
      expect(picker.savedBytes, bytes);
    }
  });
  test('PDF 형식은 API 요청·파일명·저장 안내에 적용된다', () async {
    ExportFile? saved;
    final client = MockClient((request) async {
      expect(jsonDecode(request.body)['format'], 'pdf');
      expect(request.headers['Accept'], 'application/pdf');
      return pdfResponse();
    });
    final container = containerFor(
      client,
      saver: (file) async {
        saved = file;
        return true;
      },
    );
    addTearDown(container.dispose);
    addTearDown(client.close);
    final provider = exportVmProvider(selected);
    final sub = container.listen(provider, (_, _) {});
    addTearDown(sub.close);
    await container
        .read(provider.notifier)
        .generate(options(format: ExportFormat.pdf));
    await container.read(provider.notifier).save();
    expect(saved!.bytes, pdfBytes);
    expect(saved!.name, 'ondolbom_20261001_20261027.pdf');
    expect(saved!.format, ExportFormat.pdf);
    expect(container.read(provider).message, contains('PDF 뷰어'));
    expect(container.read(provider).message, isNot(contains('압축')));
  });

  test('PDF 요청에 ZIP 응답이나 잘못된 PDF 서명을 받으면 저장하지 않는다', () async {
    for (final response in [
      zipResponse(),
      http.Response.bytes(
        zipBytes,
        200,
        headers: {'content-type': 'application/pdf'},
      ),
    ]) {
      final client = MockClient((_) async => response);
      final container = containerFor(client);
      final provider = exportVmProvider(selected);
      final sub = container.listen(provider, (_, _) {});
      try {
        await container
            .read(provider.notifier)
            .generate(options(format: ExportFormat.pdf));
        expect(container.read(provider).file, isNull);
        expect(container.read(provider).error, contains('올바른 PDF'));
      } finally {
        sub.close();
        container.dispose();
        client.close();
      }
    }
  });
  test('API에 선택 기간·범위·이미지 옵션과 Firebase 토큰을 전달한다', () async {
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.url.toString(), 'http://localhost:8000/exports/download');
      expect(request.headers['Authorization'], 'Bearer id-token');
      expect(jsonDecode(request.body), {
        'family_room_id': 'room-a',
        'start_date': '2026-10-01',
        'end_date': '2026-10-27',
        'scopes': ['chats'],
        'include_images': true,
        'format': 'html_zip',
      });
      return zipResponse();
    });
    final container = containerFor(client);
    addTearDown(container.dispose);
    addTearDown(client.close);
    final provider = exportVmProvider(selected);
    final sub = container.listen(provider, (_, _) {});
    addTearDown(sub.close);
    await container
        .read(provider.notifier)
        .generate(options(memos: false, images: true));
    expect(container.read(provider).file!.bytes, zipBytes);
    expect(
      container.read(provider).file!.name,
      'ondolbom_20261001_20261027.zip',
    );
  });

  test('생성 중 중복 요청을 막고 저장 실패·취소 후 ZIP을 다시 저장한다', () async {
    var posts = 0;
    var saves = 0;
    final pending = Completer<http.Response>();
    final client = MockClient((_) {
      posts++;
      return pending.future;
    });
    final container = containerFor(
      client,
      saver: (file) async {
        expect(file.bytes, zipBytes);
        saves++;
        if (saves == 1) throw Exception('disk');
        return saves != 2;
      },
    );
    addTearDown(container.dispose);
    addTearDown(client.close);
    final provider = exportVmProvider(selected);
    final sub = container.listen(provider, (_, _) {});
    addTearDown(sub.close);
    final vm = container.read(provider.notifier);
    final generating = vm.generate(options());
    await vm.generate(options());
    await Future<void>.delayed(Duration.zero);
    expect(posts, 1);
    pending.complete(zipResponse());
    await generating;
    await vm.save();
    expect(container.read(provider).error, contains('저장하지 못했어요'));
    expect(container.read(provider).file, isNotNull);
    await vm.save();
    expect(container.read(provider).message, contains('취소'));
    await vm.save();
    expect(container.read(provider).message, contains('파일을 저장했어요'));
    expect(posts, 1);
  });

  test('서버 실패 사유를 표시하고 동일 옵션으로 재요청할 수 있다', () async {
    var posts = 0;
    final client = MockClient(
      (_) async => ++posts == 1
          ? http.Response(
              jsonEncode({'detail': '이미지를 제외하고 다시 요청해 주세요.'}),
              500,
              headers: {'content-type': 'application/json; charset=utf-8'},
            )
          : zipResponse(),
    );
    final container = containerFor(client);
    addTearDown(container.dispose);
    addTearDown(client.close);
    final provider = exportVmProvider(selected);
    final sub = container.listen(provider, (_, _) {});
    addTearDown(sub.close);
    await container.read(provider.notifier).generate(options());
    expect(container.read(provider).error, '이미지를 제외하고 다시 요청해 주세요.');
    await container.read(provider.notifier).generate(options());
    expect(container.read(provider).file, isNotNull);
  });

  test('빈 범위·미래 종료일·역전 기간·로그인 누락은 다운로드 요청을 보내지 않는다', () async {
    var posts = 0;
    final client = MockClient((_) async {
      posts++;
      return zipResponse();
    });
    final container = containerFor(client, tokenLoader: () async => null);
    addTearDown(container.dispose);
    addTearDown(client.close);
    final provider = exportVmProvider(selected);
    final sub = container.listen(provider, (_, _) {});
    addTearDown(sub.close);
    for (final option in [
      options(memos: false, chats: false),
      ExportOptions(
        startDate: today,
        endDate: today.add(const Duration(days: 1)),
        memos: true,
        chats: true,
        includeImages: false,
      ),
      ExportOptions(
        startDate: today.add(const Duration(days: 1)),
        endDate: today,
        memos: true,
        chats: true,
        includeImages: false,
      ),
      options(),
    ]) {
      await container.read(provider.notifier).generate(option);
      expect(container.read(provider).error, isNotNull);
    }
    expect(posts, 0);
  });

  test('ZIP이 아닌 성공 응답은 파일로 저장하지 않는다', () async {
    final client = MockClient(
      (_) async => http.Response('<html>proxy</html>', 200),
    );
    final container = containerFor(client);
    addTearDown(container.dispose);
    addTearDown(client.close);
    final provider = exportVmProvider(selected);
    final sub = container.listen(provider, (_, _) {});
    addTearDown(sub.close);
    await container.read(provider.notifier).generate(options());
    expect(container.read(provider).file, isNull);
    expect(container.read(provider).error, contains('ZIP'));
  });

  test('토큰 조회 중 계정·공간 변경 시 HTTP 요청을 보내지 않는다', () async {
    final pending = Completer<String?>();
    var posts = 0;
    final client = MockClient((_) async {
      posts++;
      return zipResponse();
    });
    final container = containerFor(client, tokenLoader: () => pending.future);
    addTearDown(container.dispose);
    addTearDown(client.close);
    final provider = exportVmProvider(selected);
    final sub = container.listen(provider, (_, _) {});
    addTearDown(sub.close);
    final task = container.read(provider.notifier).generate(options());
    container.read(testContextProvider.notifier).select((
      familyRoomId: 'room-b',
      userId: 'user-b',
      roomName: 'B',
    ));
    pending.complete('token');
    await task;
    expect(posts, 0);
    expect(container.read(provider).error, contains('변경'));
  });

  test('응답 대기 중 공간 변경 시 ZIP을 노출하거나 저장하지 않는다', () async {
    final pending = Completer<http.Response>();
    final client = MockClient((_) => pending.future);
    var saves = 0;
    final container = containerFor(
      client,
      saver: (_) async {
        saves++;
        return true;
      },
    );
    addTearDown(container.dispose);
    addTearDown(client.close);
    final provider = exportVmProvider(selected);
    final sub = container.listen(provider, (_, _) {});
    addTearDown(sub.close);
    final task = container.read(provider.notifier).generate(options());
    await Future<void>.delayed(Duration.zero);
    container.read(testContextProvider.notifier).select((
      familyRoomId: 'room-b',
      userId: 'user-a',
      roomName: 'B',
    ));
    pending.complete(zipResponse());
    await task;
    await container.read(provider.notifier).save();
    expect(container.read(provider).file, isNull);
    expect(saves, 0);
  });

  Future<void> mount(
    WidgetTester tester, {
    bool home = false,
    http.Client? client,
    Future<bool> Function(ExportFile)? saver,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          familyContextProvider.overrideWithValue(selected),
          apiTokenLoaderProvider.overrideWithValue(() async => 'id-token'),
          authUserProvider.overrideWith((ref) => Stream.value(null)),
          exportTodayProvider.overrideWithValue(today),
          familyRoomProvider.overrideWith(ExportRooms.new),
          exportFileSaverProvider.overrideWithValue(saver ?? (_) async => true),
          if (client != null)
            exportHttpClientProvider.overrideWithValue(client),
        ],
        child: MaterialApp(
          home: home
              ? const FamilyRoomHome()
              : const ExportView(selected: selected),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('가족 공간 우측 상단 메뉴에서 내보내기 화면으로 이동한다', (tester) async {
    await mount(tester, home: true);
    expect(find.text('메모·채팅 내보내기'), findsNothing);
    await tester.tap(find.byTooltip('가족 공간 메뉴'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('메모·채팅 내보내기'));
    await tester.pumpAndSettle();
    expect(find.byType(ExportView), findsOneWidget);
    expect(find.byType(CheckboxListTile), findsNWidgets(2));
    expect(find.text('포함'), findsOneWidget);
    expect(find.text('제외'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('날짜 두 칸은 가로 배치되며 종료일 달력은 오늘 이후를 막는다', (tester) async {
    await mount(tester);
    final start = find.byKey(const Key('export-start'));
    final end = find.byKey(const Key('export-end'));
    expect(tester.getTopLeft(start).dy, tester.getTopLeft(end).dy);
    expect(tester.getTopLeft(start).dx, lessThan(tester.getTopLeft(end).dx));
    await tester.tap(end);
    await tester.pumpAndSettle();
    final picker = tester.widget<DatePickerDialog>(
      find.byType(DatePickerDialog),
    );
    expect(picker.lastDate, today);
    expect(picker.firstDate, DateTime(2026, 10, 1));
    await tester.tap(find.text('20'));
    await tester.tap(find.text('선택'));
    await tester.pumpAndSettle();
    expect(find.text('2026-10-20'), findsOneWidget);
    await tester.tap(start);
    await tester.pumpAndSettle();
    expect(
      tester.widget<DatePickerDialog>(find.byType(DatePickerDialog)).lastDate,
      DateTime(2026, 10, 20),
    );
    await tester.tap(find.text('5'));
    await tester.tap(find.text('선택'));
    await tester.pumpAndSettle();
    expect(find.text('2026-10-05'), findsOneWidget);
  });

  testWidgets('선택한 체크박스·라디오 값으로 생성하고 다운로드한다', (tester) async {
    ExportFile? saved;
    final client = MockClient((request) async {
      final body = jsonDecode(request.body) as Map;
      expect(body['scopes'], ['chats']);
      expect(body['include_images'], true);
      return zipResponse();
    });
    addTearDown(client.close);
    await mount(
      tester,
      client: client,
      saver: (file) async {
        saved = file;
        return true;
      },
    );
    await tester.tap(find.text('메모'));
    await tester.tap(find.text('포함'));
    await tester.ensureVisible(find.byKey(const Key('export-generate')));
    await tester.tap(find.byKey(const Key('export-generate')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('export-save')));
    await tester.tap(find.byKey(const Key('export-save')));
    await tester.pumpAndSettle();
    expect(saved!.bytes, zipBytes);
    expect(find.textContaining('파일을 저장했어요'), findsOneWidget);
    // 옵션 변경 시 이전 파일을 잘못 저장하지 않도록 결과를 비운다.
    await tester.ensureVisible(find.text('제외'));
    await tester.tap(find.text('제외'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('export-save')), findsNothing);
  });

  testWidgets('범위를 모두 해제하면 요청 버튼을 비활성화한다', (tester) async {
    await mount(tester);
    await tester.tap(find.text('메모'));
    await tester.tap(find.text('채팅'));
    await tester.pumpAndSettle();
    expect(find.text('메모 또는 채팅을 하나 이상 선택해 주세요.'), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(find.byKey(const Key('export-generate')))
          .onPressed,
      isNull,
    );
  });

  testWidgets('용량 부족 안내를 빨간 글씨로 표시하고 파일과 다운로드 버튼을 유지한다', (tester) async {
    final client = MockClient((_) async => zipResponse());
    addTearDown(client.close);
    await mount(
      tester,
      client: client,
      saver: (_) async {
        throw PlatformException(
          code: 'Error while saving file',
          message: 'ENOSPC (No space left on device)',
        );
      },
    );
    await tester.ensureVisible(find.byKey(const Key('export-generate')));
    await tester.tap(find.byKey(const Key('export-generate')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('export-save')));
    await tester.tap(find.byKey(const Key('export-save')));
    await tester.pumpAndSettle();
    final message = find.text('선택한 저장 위치의 공간이 부족해요. 공간을 확보하거나 다른 위치를 선택해 주세요.');
    expect(message, findsOneWidget);
    final element = tester.element(message);
    expect(
      tester.widget<Text>(message).style!.color,
      Theme.of(element).colorScheme.error,
    );
    expect(find.text('ondolbom_20261001_20261027.zip'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const Key('export-save')))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets('HTML·PDF 선택으로 파일을 생성하고 형식을 바꾸면 이전 결과를 지운다', (tester) async {
    ExportFile? saved;
    final formats = <String>[];
    final client = MockClient((request) async {
      final format = jsonDecode(request.body)['format'] as String;
      formats.add(format);
      return format == 'pdf' ? pdfResponse() : zipResponse();
    });
    addTearDown(client.close);
    await mount(
      tester,
      client: client,
      saver: (file) async {
        saved = file;
        return true;
      },
    );
    await tester.ensureVisible(find.byKey(const Key('export-format-pdf')));
    await tester.tap(find.byKey(const Key('export-format-pdf')));
    await tester.pumpAndSettle();
    expect(find.text('PDF 문서 한 개로 받아 바로 열 수 있어요.'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('export-generate')));
    await tester.tap(find.byKey(const Key('export-generate')));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const Key('export-save')));
    await tester.tap(find.byKey(const Key('export-save')));
    await tester.pumpAndSettle();
    expect(saved!.format, ExportFormat.pdf);
    expect(saved!.name, endsWith('.pdf'));
    await tester.ensureVisible(find.byKey(const Key('export-format-html')));
    await tester.tap(find.byKey(const Key('export-format-html')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('export-save')), findsNothing);
    await tester.ensureVisible(find.byKey(const Key('export-generate')));
    await tester.tap(find.byKey(const Key('export-generate')));
    await tester.pumpAndSettle();
    expect(formats, ['pdf', 'html_zip']);
    expect(find.text('ondolbom_20261001_20261027.zip'), findsOneWidget);
  });
}
