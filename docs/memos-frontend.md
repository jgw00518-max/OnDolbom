# 메모 기능 구현 안내

확인일: 2026-10-23 (KST), `feature/memos-medications-mvp` 브랜치의 현재 구현 기준.

## 1. 구현 범위

- 선택한 가족 공간의 메모 목록 조회와 최신순 표시
- 목록 데이터를 이용한 메모 상세 보기
- 메모 작성·빈 내용 검증·등록 후 목록 갱신
- 당겨서 새로고침, 20개씩 추가 조회, 빈 목록·로딩·오류·재시도 표시
- 등록 중 중복 제출 방지와 실패 시 작성 내용 보존
- 작성 중 취소 확인, 선택 공간이 바뀌면 기존 작성 화면의 저장 차단
- 좋아요 개수 표시

수정·삭제·사진 첨부·좋아요 조작은 구현하지 않았습니다.
작성자 이름은 API 응답에 없으므로 본인은 `나`, 다른 작성자는 사용자 ID로 표시합니다.

## 2. 파일 구성

| 파일 | 역할 |
| --- | --- |
| `lib/model/memos/memo.dart` | 메모 필드와 JSON 변환, nullable 날짜·내용 처리 |
| `lib/vm/memos/memo_vm.dart` | Riverpod 목록 상태, 조회·작성 API 호출과 오류 변환 |
| `lib/view/memos/memo_list_view.dart` | 목록·상세·추가 조회·재시도 |
| `lib/view/memos/memo_form_view.dart` | 작성·검증·저장·취소 확인 |
| `lib/view/memos/memo_style.dart` | 공통 화면 구조, 작성자·시간·좋아요 표시 |
| `lib/vm/family_context.dart` | 메모·투약일지의 공통 선택 공간·사용자·서버 주소 |
| `python/features/memos/router.py` | 공간별 메모 조회·작성과 참여 권한 검사 |
| 각 기능의 `router.py` | 기능별 `get_current_user_id`에서 인증된 사용자 ID 조회 |
| `test/memo_test.dart` | 모의 API 기반 UI·VM 검증 |
| `python/tests/test_memos.py` | API 검증·작성자 사칭 방지·트랜잭션 테스트 |

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
