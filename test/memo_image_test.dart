import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:ondolbom/model/memos/memo.dart';
import 'package:ondolbom/view/memos/memo_image_view.dart';
import 'package:ondolbom/view/memos/memo_list_view.dart';
import 'package:ondolbom/vm/family_room/family_context.dart';
import 'package:ondolbom/vm/memos/memo_vm.dart';

import 'memo_test.dart' as fixture;

final photo = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAIAAAACCAIAAAD91JpzAAAAEElEQVR4nGP8zwACTGCSAQANHQEDgslx/wAAAABJRU5ErkJggg==',
);

Future<void> mountImages(
  WidgetTester tester,
  http.Client client, {
  Future<Uint8List?> Function()? picker,
}) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        memoContextProvider.overrideWithValue(fixture.selected),
        apiTokenLoaderProvider.overrideWithValue(() async => 'test-token'),
        memoHttpClientProvider.overrideWithValue(client),
        memoImagePickerProvider.overrideWithValue(picker ?? () async => photo),
      ],
      child: const MaterialApp(home: MemoListView()),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> tapText(WidgetTester tester, String text) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await tester.pumpAndSettle();
  final target = text == '메모 쓰기' ? find.byTooltip(text) : find.text(text);
  await tester.ensureVisible(target);
  await tester.tap(target);
  await tester.pumpAndSettle();
}

void expectMultipart(
  http.Request request, {
  bool image = true,
  bool remove = false,
}) {
  expect(request.headers['Authorization'], 'Bearer test-token');
  expect(
    request.headers['content-type'],
    startsWith('multipart/form-data; boundary='),
  );
  final body = latin1.decode(request.bodyBytes);
  expect(body, contains('name="family_room_id"\r\n\r\nroom-a'));
  expect(body, contains('name="memo_content"'));
  expect(RegExp('name="image"').allMatches(body).length, image ? 1 : 0);
  if (image) expect(body, contains(latin1.decode(photo)));
  if (remove) expect(body, contains('name="remove_image"\r\n\r\ntrue'));
}

void main() {
  testWidgets('사진 메모를 저장하고 목록 사진을 누르면 상세로 이동해 확대한다', (tester) async {
    var saved = false;
    var posts = 0;
    await mountImages(
      tester,
      MockClient((request) async {
        if (request.method == 'POST') {
          posts++;
          expect(request.url.path, '/memos/insert-with-image');
          expectMultipart(request);
          expect(
            utf8.decode(request.bodyBytes, allowMalformed: true),
            contains('사진 메모'),
          );
          saved = true;
          return http.Response('{"result":"OK","memo_id":"memo-1"}', 201);
        }
        if (request.url.path.contains('/image/')) {
          expect(request.url.queryParameters, {
            'family_room_id': 'room-a',
            'author_user_id': 'user-a',
          });
          expect(request.headers['Authorization'], 'Bearer test-token');
          return http.Response.bytes(photo, 200);
        }
        return fixture.listResponse(
          saved
              ? [
                  {...fixture.memoJson('memo-1', '사진 메모'), 'has_image': 1},
                ]
              : [],
        );
      }),
    );
    await tapText(tester, '메모 쓰기');
    await tester.enterText(find.byType(TextFormField), '사진 메모');
    await tapText(tester, '사진 첨부');
    expect(find.text('사진 교체'), findsOneWidget);
    expect(find.text('사진 제거'), findsOneWidget);
    await tapText(tester, '메모 등록');
    expect(posts, 1);
    expect(find.byType(MemoImageView), findsOneWidget);
    expect(find.bySemanticsLabel('첨부 사진 확대'), findsNothing);
    expect(find.byType(InteractiveViewer), findsNothing);
    await tester.tap(
      find.descendant(
        of: find.byType(MemoImageView),
        matching: find.byType(Image),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('메모 상세'), findsOneWidget);
    expect(find.byType(Dialog), findsNothing);
    expect(find.byType(MemoImageView), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('첨부 사진 확대'));
    await tester.pumpAndSettle();
    expect(find.byType(InteractiveViewer), findsOneWidget);
    await tester.tap(find.byTooltip('사진 닫기'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('기존 사진 유지·교체·제거를 저장하고 상세에 즉시 반영한다', (tester) async {
    var hasImage = true;
    var patches = 0;
    var imageReads = 0;
    await mountImages(
      tester,
      MockClient((request) async {
        if (request.url.path.contains('/image/')) {
          imageReads++;
          return http.Response.bytes(photo, 200);
        }
        if (request.method == 'PATCH') {
          patches++;
          if (patches == 1) {
            expect(request.url.path, '/memos/update/memo-1');
            expect(jsonDecode(request.body)['memo_content'], '기존 내용');
          } else {
            expect(request.url.path, '/memos/update-with-image/memo-1');
            expectMultipart(request, image: patches == 2, remove: patches == 3);
            hasImage = patches == 2;
          }
          return http.Response('{"result":"OK"}', 200);
        }
        return fixture.listResponse([
          {...fixture.memoJson('memo-1', '기존 내용'), 'has_image': hasImage},
        ]);
      }),
    );
    await tapText(tester, '기존 내용');
    await tapText(tester, '수정');
    expect(find.text('사진 교체'), findsOneWidget);
    await tapText(tester, '수정 저장');
    expect(find.byType(MemoImageView), findsOneWidget);
    final beforeReplacement = imageReads;
    await tapText(tester, '수정');
    await tapText(tester, '사진 교체');
    await tapText(tester, '수정 저장');
    expect(imageReads, greaterThan(beforeReplacement));
    await tapText(tester, '수정');
    await tapText(tester, '사진 제거');
    expect(find.text('사진 첨부'), findsOneWidget);
    await tapText(tester, '수정 저장');
    expect(patches, 3);
    expect(find.byType(MemoImageView), findsNothing);
    await tester.tap(find.byTooltip('이전 화면'));
    await tester.pumpAndSettle();
    expect(find.byType(MemoImageView), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('사진 선택 취소와 첨부 취소 후에는 텍스트만 저장한다', (tester) async {
    var picks = 0;
    var posts = 0;
    await mountImages(
      tester,
      MockClient((request) async {
        if (request.method == 'POST') {
          posts++;
          expect(request.url.path, '/memos/insert');
          expect(jsonDecode(request.body), {
            'family_room_id': 'room-a',
            'memo_content': '텍스트만',
          });
          return http.Response('{"result":"OK","memo_id":"memo-1"}', 201);
        }
        return fixture.listResponse([]);
      }),
      picker: () async => ++picks == 1 ? null : photo,
    );
    await tapText(tester, '메모 쓰기');
    await tester.enterText(find.byType(TextFormField), '텍스트만');
    await tapText(tester, '사진 첨부');
    expect(find.text('사진 제거'), findsNothing);
    await tapText(tester, '사진 첨부');
    await tapText(tester, '사진 제거');
    await tapText(tester, '메모 등록');
    expect(posts, 1);
  });

  testWidgets('첨부 저장 실패 시 텍스트·사진을 보존하고 중복 저장을 막는다', (tester) async {
    final pending = Completer<http.Response>();
    var posts = 0;
    await mountImages(
      tester,
      MockClient((request) async {
        if (request.method == 'POST') {
          posts++;
          expectMultipart(request);
          return posts == 1
              ? pending.future
              : http.Response('{"result":"OK","memo_id":"memo-1"}', 201);
        }
        return fixture.listResponse([]);
      }),
    );
    await tapText(tester, '메모 쓰기');
    await tester.enterText(find.byType(TextFormField), '보존할 내용');
    await tapText(tester, '사진 첨부');
    await tester.ensureVisible(find.text('메모 등록'));
    await tester.tap(find.text('메모 등록'));
    await tester.pump();
    await tester.tap(find.text('등록 중…'));
    expect(posts, 1);
    pending.complete(http.Response('{"detail":"save failed"}', 500));
    await tester.pumpAndSettle();
    expect(
      tester.widget<TextFormField>(find.byType(TextFormField)).controller!.text,
      '보존할 내용',
    );
    expect(find.text('사진 교체'), findsOneWidget);
    await tapText(tester, '메모 등록');
    expect(posts, 2);
  });

  testWidgets('이미지 조회 실패 후 인증 헤더를 포함해 재시도한다', (tester) async {
    var reads = 0;
    await mountImages(
      tester,
      MockClient((request) async {
        if (request.url.path.contains('/image/')) {
          expect(request.headers['Authorization'], 'Bearer test-token');
          return ++reads == 1
              ? http.Response('', 403)
              : http.Response.bytes(photo, 200);
        }
        return fixture.listResponse([
          {...fixture.memoJson('memo-1', '기존 내용'), 'has_image': true},
        ]);
      }),
    );
    expect(find.text('사진 다시 불러오기'), findsOneWidget);
    await tapText(tester, '사진 다시 불러오기');
    expect(reads, 2);
    expect(find.text('사진 다시 불러오기'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('용량을 초과한 사진 선택은 거절하고 기존 입력을 유지한다', (tester) async {
    await mountImages(
      tester,
      MockClient((_) async => fixture.listResponse([])),
      picker: () async => Uint8List(maxMemoImageBytes + 1),
    );
    await tapText(tester, '메모 쓰기');
    await tester.enterText(find.byType(TextFormField), '내용 유지');
    await tapText(tester, '사진 첨부');
    expect(find.text('이미지는 5MB 이하로 첨부해 주세요.'), findsOneWidget);
    expect(find.text('사진 제거'), findsNothing);
    expect(
      tester.widget<TextFormField>(find.byType(TextFormField)).controller!.text,
      '내용 유지',
    );
  });

  test('이미지 여부 모델은 bool과 MySQL 정수 플래그를 처리한다', () {
    for (final value in [true, 1]) {
      expect(
        Memo.fromJson({
          ...fixture.memoJson('memo-1', '내용'),
          'has_image': value,
        }).hasImage,
        isTrue,
      );
    }
    expect(Memo.fromJson(fixture.memoJson('memo-1', '내용')).hasImage, isFalse);
  });
}
