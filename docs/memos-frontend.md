# 메모 기능 구현 안내

확인일: 2026-10-26 (KST), 현재 작업 트리의 구현 기준.

## 1. 구현 범위

- 선택한 가족 공간의 메모 목록 조회와 최신순 표시
- 목록 데이터를 이용한 메모 상세 보기
- 메모 작성·빈 내용 검증·등록 후 목록 갱신
- 본인 메모 상세에서 수정·삭제, 수정 내용 미리 채우기와 저장 후 상세·목록 갱신
- 삭제 확인과 성공 후 목록 복귀, 수정·삭제 중 중복 요청 방지와 실패 시 재시도
- 당겨서 새로고침, 20개씩 추가 조회, 빈 목록·로딩·오류·재시도 표시
- 등록 중 중복 제출 방지와 실패 시 작성 내용 보존
- 작성 중 취소 확인, 선택 공간이 바뀌면 기존 작성 화면의 저장 차단
- 좋아요 개수 표시
- 목록·상세에서 좋아요 등록: 사용자당 메모별 한 번만 허용, 취소 불가
- 작성·수정 시 사진 한 장 첨부, 미리보기·교체·제거, 목록·상세 표시와 상세에서만 확대

수정·삭제는 서버 API와 Flutter 화면·VM 연결을 완료했습니다.
해당 공간의 작성자 본인에게만 수정·삭제 버튼을 표시하며, 공간·계정 변경 시 처리를 차단합니다.
사진은 선택 사항이며 텍스트는 필수입니다. 좋아요 등록은 서버 API와 Flutter 버튼 연결을 완료했습니다.
메모 조회 API는 `user.name`을 `author_name`으로 함께 반환합니다.
목록·상세 모두 작성자 이름을 표시하며 이름이 없으면 `이름 없는 가족`으로 표시합니다.
사용자 ID는 내부 식별에만 사용하고 작성자 표시에는 사용하지 않습니다.

## 2. 파일 구성

| 파일 | 역할 |
| --- | --- |
| `lib/model/memos/memo.dart` | 메모 필드와 JSON 변환, nullable 날짜·내용 처리 |
| `lib/vm/memos/memo_vm.dart` | Riverpod 목록 상태, 조회·작성·수정·삭제 API 호출과 오류 변환 |
| `lib/view/memos/memo_list_view.dart` | 목록·상세·추가 조회·재시도, 수정 진입·삭제 확인 |
| `lib/view/memos/memo_form_view.dart` | 작성·수정 공용 입력·검증·저장·취소 확인 |
| `lib/view/memos/memo_image_view.dart` | 인증된 이미지 표시·재시도·확대 |
| `lib/view/memos/memo_like_button.dart` | 목록·상세 공용 좋아요 버튼·처리 상태·오류 안내 |
| `lib/view/memos/memo_style.dart` | 공통 화면 구조, 작성자·시간·좋아요 표시 |
| `lib/vm/family_context.dart` | 메모·투약일지의 공통 선택 공간·사용자·서버 주소 |
| `python/features/memos/router.py` | 공간별 메모 조회·작성과 참여 권한 검사 |
| `python/features/memos/images.py` | 단일 이미지·용량·실제 형식 검증, JPEG 정규화 |
| `python/features/memos/schema.sql` | 사용자별 좋아요 기록 테이블·복합 기본키·외래키 |
| `python/features/memos/migrate_likes.py` | 기존 테이블을 변경하지 않는 명시적 좋아요 테이블 생성 |
| 각 기능의 `router.py` | 기능별 `get_current_user_id`에서 인증된 사용자 ID 조회 |
| `test/memo_test.dart` | 모의 API 기반 UI·VM 검증 |
| `test/memo_edit_test.dart` | 수정·삭제 UI·API 연결, 실패·재시도·권한·공간 변경 검증 |
| `test/memo_image_test.dart` | 사진 작성·유지·교체·제거·확대·실패 후 재시도 |
| `test/memo_like_test.dart` | 좋아요 API 연결·화면 간 상태 공유·중복 차단·실패 재시도·계정 변경 |
| `python/tests/test_memos.py` | API 검증·작성자 사칭 방지·트랜잭션 테스트 |
| `python/tests/test_memo_images.py` | 이미지 API·단일 첨부·권한·원자적 저장 검증 |
| `python/tests/test_memo_likes.py` | 좋아요 등록·중복 방지·인증·권한·롤백·취소 API 부재 |
| `python/tests/test_memo_likes_mysql.py` | 명시적 실행 시 실제 MySQL 임시 메모로 동시성 검증 |

API 호출은 화면이 아닌 VM에서 수행합니다. 요청 모델·SQL은 기능별 `router.py`에 함께 둡니다.

## 3. 공통 테마와 상태

메모 전용 색상 상수를 제거하고 `main.dart`의 테마를 사용하도록 변경했습니다.

- 화면 배경: `scaffoldBackgroundColor`
- 로고·화면 제목: `appBarTheme.titleTextStyle`, `colorScheme.primary`
- 공간 표시 영역: `secondaryContainer`, `onSecondaryContainer`, `outline`
- 보조 설명·아이콘: `onSurfaceVariant`
- 목록·상세 카드: `Card`를 사용해 공통 `cardTheme` 적용
- 버튼·입력창: 상위 Material 테마 사용

`memoContextProvider`는 `familyContextProvider`의 별칭입니다.
현재는 `FAMILY_ROOM_ID`, `USER_ID`, `FAMILY_ROOM_NAME` 실행 옵션을 읽습니다.
로그인·공간 선택 기능이 준비되면 공통 provider를 연결해야 합니다.
목록은 선택 공간·사용자별로 구분하며 이전 공간의 요청 결과가 새 목록을 덮어쓰지 않게 합니다.

## 4. API

### 목록 조회

```text
GET /memos/select?family_room_id=공간ID&limit=20&offset=0
```

`limit`은 1~100, `offset`은 0 이상입니다. 삭제되지 않은 공간의 삭제되지 않은 메모를
작성 시간·메모 ID·작성자 ID 내림차순으로 반환합니다. 결과가 없으면 `{"results": []}`입니다.

### 메모 작성

```text
POST /memos/insert
```

```json
{
  "family_room_id": "공간ID",
  "memo_content": "가족에게 전달할 돌봄 메모"
}
```

내용은 앞뒤 공백 제거 후 1~10,000자입니다.
작성자는 인증 정보에서 결정하며 클라이언트가 보낸 `user_id`는 무시합니다.
기존 Flutter VM은 본문에 이 필드를 보내지만 실제 작성자 결정에는 사용되지 않습니다.
서버는 UUID와 좋아요 0을 저장하고 작성 시간은 DB 기본값을 사용합니다.
성공하면 HTTP 201과 `{"result":"OK","memo_id":"생성된 UUID"}`를 반환합니다.

### 메모 수정·삭제

```text
PATCH /memos/update/{memo_id}
Authorization: Bearer <Firebase ID 토큰>
Content-Type: application/json

{"family_room_id":"공간ID","memo_content":"수정할 내용"}

DELETE /memos/delete/{memo_id}?family_room_id=공간ID
Authorization: Bearer <Firebase ID 토큰>
```

현재 공간에 참여 중인 작성자 본인만 수정·삭제할 수 있습니다.
수정 내용은 앞뒤 공백 제거 후 1~10,000자이며, 수정 본문은 위 두 필드만 허용합니다.
수정 시 `memo_updated_at`을 갱신하고 작성자·작성 시간·좋아요는 유지합니다.
삭제는 `memo_deleted_at`을 기록하는 소프트 삭제이며 이후 목록 조회에서 제외됩니다.
성공 시 두 API 모두 HTTP 200과 `{"result":"OK","memo_id":"대상 메모 ID"}`를 반환합니다.

미인증은 401, 공간 참여 권한이 없거나 다른 작성자의 메모인 경우 403,
해당 공간에 메모가 없거나 이미 삭제된 경우 404, 입력 오류는 422입니다.
참여 상태와 메모를 같은 트랜잭션에서 잠근 뒤 처리하며, 실패 시 rollback합니다.
DB 오류는 내부 정보를 숨긴 500으로 반환합니다.

### 텍스트와 이미지 함께 저장

기존 JSON API는 그대로 사용할 수 있으며, 이미지 변경이 있으면 아래 multipart API를 호출합니다.
Swagger UI에서도 `family_room_id`, `memo_content`, `image` 파일을 지정해 테스트할 수 있습니다.
모든 요청에 Firebase ID 토큰의 Bearer 헤더가 필요합니다.

| API | multipart/form-data 필드 |
| --- | --- |
| `POST /memos/insert-with-image` | `family_room_id`, `memo_content`, 선택 사항 `image` 파일 한 장 |
| `PATCH /memos/update-with-image/{memo_id}` | 위 필드와 선택 사항 `remove_image` (기본 false) |

수정 시 이미지와 제거 옵션을 모두 생략하면 기존 사진을 유지합니다.
새 `image`를 보내면 교체하고, `remove_image=true`만 보내면 제거합니다.
첨부와 제거의 동시 요청·두 장 이상·잘못된 이미지는 422, 5MiB 초과는 413을 반환합니다.
JPG·PNG·WEBP의 실제 내용을 검증하며, 움직이는 이미지와 2천만 픽셀 초과 이미지는 거절합니다.
서버는 방향을 보정하고 최대 2560px로 축소한 JPEG로 저장하며 위치 정보 등 메타데이터를 제거합니다.
투명 영역은 흰색으로 합성합니다. 텍스트와 사진은 같은 트랜잭션으로 저장·수정합니다.
실패하면 둘 다 rollback하며 Flutter는 입력과 선택 사진을 보존해 재시도할 수 있습니다.

기존 DB의 `memo.memo_image` LONG BLOB 컬럼을 사용하므로 스키마 변경은 필요 없습니다.
목록은 이미지 본문 대신 `has_image` 플래그만 반환합니다.
사진은 `GET /memos/image/{memo_id}?family_room_id=공간ID&author_user_id=작성자ID`로 조회합니다.
작성자 ID는 메모의 복합 식별에 사용하며, 조회 권한은 인증된 현재 공간 참여 여부로 검사합니다.
응답은 이미지 바이너리이며 `Cache-Control: private, no-store`를 설정합니다.
삭제된 메모나 공간의 사진은 조회할 수 없습니다.

Flutter는 갤러리에서 한 장만 선택하고, 텍스트만 변경하면 기존 JSON 수정 API로 사진을 유지합니다.
교체·제거 성공 시 해당 이미지 상태를 갱신해 상세와 목록에 반영합니다.
iOS 사진 접근 설명은 `ios/Runner/Info.plist`에 추가했습니다.

### 좋아요 등록 (취소 불가)

배포 시 API 실행 전에 테이블을 한 번 생성합니다. 앱 시작 시 DDL은 자동 실행하지 않습니다.
현재 연결된 개발 DB에는 적용했습니다. 기존 메모와 좋아요 개수는 초기화하지 않습니다.

```powershell
python -m python.features.memos.migrate_likes
```

`memo_like`의 기본키는 `(memo_id, family_room_id, memo_author_id, user_id)`입니다.
앞의 세 컬럼은 기존 메모 복합키를 참조하고, 마지막 `user_id`는 좋아요를 누른 사용자입니다.
두 외래키는 물리 삭제를 제한하며, 기존 소프트 삭제·탈퇴 처리를 유지합니다.

```text
POST /memos/like/{memo_id}
Authorization: Bearer <Firebase ID 토큰>
Content-Type: application/json

{"family_room_id":"공간ID","author_user_id":"메모 작성자 ID"}
```

좋아요를 누르는 사용자 ID는 인증 토큰에서 결정하며 요청 본문으로 받지 않습니다.
현재 참여 중인 공간의 삭제되지 않은 메모에만 등록할 수 있고, 본인 메모도 허용합니다.
참여와 메모 행을 잠근 뒤 기록 추가와 `memo.likes` 증가를 한 트랜잭션으로 처리합니다.
동시 요청과 재전송에서도 같은 사용자의 좋아요는 한 번만 등록됩니다.
이미 등록했다면 기록·개수를 바꾸지 않고 HTTP 200으로 기존 상태를 반환합니다.

최초 등록 응답 예:

```json
{"result":"OK","memo_id":"메모 ID","likes":1,"is_liked":true,"already_liked":false}
```

재요청은 `already_liked:true`이며 `likes`는 그대로입니다.
목록 조회에도 인증된 사용자의 `is_liked` 플래그(0/1)를 포함합니다.
Flutter는 이 플래그의 bool·정수 형태를 모두 읽으며, 이미 등록된 메모는 채운 하트와
비활성 버튼으로 표시합니다. 목록과 상세는 공간·메모·작성자별로 요청 상태와 응답을 공유합니다.
등록 중에는 중복 클릭을 막으며, 성공 응답의 개수를 두 화면에 반영합니다.
실패하면 기존 개수와 상태를 유지하고 재시도를 허용합니다.
공간·계정이 바뀌면 버튼을 비활성화하고 토큰 조회 후에도 현재 공간을 검사합니다.
미인증은 401, 공간 접근 권한 없음은 403, 메모 없음·삭제는 404,
잘못된 입력이나 추가 필드는 422, DB 실패는 내부 정보를 숨긴 500입니다.
`DELETE`, `PATCH`, `PUT /memos/like/{memo_id}`는 405이며 좋아요 취소·토글 API는 없습니다.

실제 DB 동시성 검증은 명시적으로 아래 명령을 실행합니다.
활성 참여자 한 명이 필요하며 UUID 임시 메모와 해당 좋아요만 생성·정리합니다.
기존 메모·좋아요는 변경하지 않습니다.

```powershell
$env:ONDOLBOM_MYSQL_TESTS = '1'
python -m unittest python.tests.test_memo_likes_mysql -v
Remove-Item Env:ONDOLBOM_MYSQL_TESTS
```

## 5. 인증·권한과 남은 연결

조회·작성 모두 `get_current_user_id`에서 Bearer Firebase ID 토큰을 검증하고,
검증된 UID로 MySQL 내부 사용자 ID를 조회합니다. 별도의 request.state 설정은 필요하지 않습니다.
토큰 누락·만료·폐기는 401, 미등록·탈퇴 계정은 403으로 거절합니다.
Flutter 메모 VM은 호출 시점의 Firebase ID 토큰을 조회·작성 요청의 Bearer 헤더로 전달합니다.
실행 옵션의 `USER_ID`는 인증 수단이 아닙니다.

인증 이후에도 공간별로 다음 조건을 검사합니다.

- 사용자·공간이 `participate`에 존재
- `is_active = 1`, `left_at IS NULL`
- 사용자가 탈퇴하지 않았고 공간이 삭제되지 않음

권한이 없으면 403, 입력 오류는 422, DB 오류는 내부 정보를 숨긴 500을 반환합니다.
저장은 참여 확인 행을 잠근 뒤 같은 연결로 수행하고 전체 성공 시 commit합니다.
오류가 나면 rollback하며, 연결은 `finally`에서 종료합니다.

`lib/view/family_room_home.dart`의 메모 메뉴에서 목록으로 이동합니다.
공간은 `familyRoomProvider`의 선택 공간, 사용자 ID는 서버에서 조회한 로그인 프로필을 사용합니다.
작성 요청에는 사용자 ID를 보내지 않으며, 작성자는 서버가 인증 토큰으로 결정합니다.

## 6. 실행

프로젝트 루트에서 가상환경 없이 서버를 실행합니다.

```powershell
python -m pip install -r python/requirements.txt
python -m python.main
```

로그인 후 가족 공간을 선택하면 메모 메뉴를 사용할 수 있습니다. 별도 터미널에서 실행합니다.

```powershell
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000
```

기본 서버 주소는 로그인·가족 공간 기능과 동일한 `http://10.0.2.2:8000`입니다.
데스크톱·웹에서는 `API_BASE_URL=http://127.0.0.1:8000`을 지정합니다. 다른 서버는 `API_BASE_URL` 실행 옵션으로 지정합니다.
실제 기기에는 접근 가능한 서버 주소·바인딩 설정이 필요합니다.

## 7. 검증과 다음 작업

```powershell
flutter analyze --no-pub
flutter test --no-pub
python -m unittest discover -s python/tests -p "test_*.py" -v
```

테스트는 실제 DB를 변경하지 않습니다. 조회→상세→작성→목록 갱신, 빈 내용,
저장 실패·중복 제출·재시도·취소 확인·페이지·공간 상태 분리와 서버 인증·권한 검사를 확인합니다.
공통 테마를 사용하며 공간 홈에서의 메뉴 진입과 토큰 헤더 전달도 모의 API로 검증합니다.
실제 Firebase 계정에서 MySQL 저장까지의 통합 검증은 별도로 필요합니다.

다음 작업은 실제 기기에서 로그인·공간 선택 후 작성·조회를 확인하는 것입니다.
