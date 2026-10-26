# 투약일지 프론트엔드

## 구현 범위

목업의 시간별 그룹 목록과 약 추가 입력창을 참고했습니다.
색상을 별도로 지정하지 않고 `main.dart`의 `colorScheme`, `appBarTheme`,
`cardTheme`와 Material 버튼 테마를 사용합니다. `main.dart`는 변경하지 않습니다.

- 홈의 돌봄 메뉴에서 메모 또는 투약일지로 이동
- 선택 공간과 날짜의 투약일지 조회, 날짜 이전·다음·오늘 이동과 달력 선택
- 복약 시간별 카드, 불러온 기록의 완료 개수와 복약 상태 표시
- 항목을 눌러 약 정보·날짜·시간·용량·작성자 상세 확인
- 작성자는 조회 API의 `user.name AS author_name`으로 표시하며, 이름이 없으면 `이름 없는 가족` 표시
- 약 추가 시 식사·식전/식후·분, 약 정보, 용량, 단위 입력
- 입력 검증, 작성 중 취소 확인, 중복 제출 방지, 저장 실패 시 입력 보존
- 저장 성공 후 해당 공간·날짜 목록 갱신, 새로고침·추가 조회·오류 재시도
- 작성·수정은 현재 공간의 활성 주보호자만 허용하며, 일반 참여자는 조회·상세 확인만 가능

홈의 진입 메뉴는 로컬 작업 파일에만 연결되어 있습니다. 사용자 요청에 따라
`lib/view/home.dart`는 이번 커밋에서 제외합니다. 커밋만 체크아웃한 환경에서는
기존 홈 또는 라우트에 `MedicationListView` 진입을 별도로 연결해야 합니다.

주보호자는 투약 정보 상세의 수정 버튼으로 기존 약 정보·날짜·시간·용량·단위를 수정할 수 있습니다.
약 추가 버튼도 주보호자에게만 표시합니다. 작성 중 주보호자 권한이나 선택 공간이 바뀌면 저장을 차단합니다.
VM은 토큰 조회 후 요청 전에도 작성 권한을 재검사하고 서버는 `is_representative = 1`을 검사합니다.
수정 성공 후 원래 목록을 갱신하고 날짜를 변경했다면 변경한 날짜의 목록으로 이동합니다.
삭제 API와 조작 버튼은 아직 제공하지 않습니다.
복약 완료 체크는 백엔드 API와 Flutter 목록·상세에 연결했습니다.
목록의 체크 아이콘 또는 상세의 `복약 완료 체크` 버튼으로 등록하며, 체크한 사용자 이름과 서버 시간을 표시합니다.
주보호자 외 일반 참여자도 체크할 수 있고, 이미 완료된 기록의 중복 체크는 최초 사용자·시간을 유지합니다.
해제 API는 체크한 본인과 현재 주보호자에게 허용하며, 목록의 완료 체크 아이콘과 상세의 `체크 해제` 버튼에 연결했습니다.
확인창에서 해제를 선택하면 미완료 상태로 갱신하며 확인자·체크 시간과 완료 개수도 함께 변경합니다.
처리 중 중복 클릭을 차단하고 실패하면 기존 미완료 상태에서 재시도합니다.
복약 상태는 서버의 `medication_confirmed_at` 값으로 표시하며, 새 기록은 미확인 상태입니다.
추가한 기록은 선택한 날짜 한 번의 기록이며 반복 일정으로 생성하지 않습니다.

## 파일

| 파일 | 역할 |
| --- | --- |
| `lib/model/medications/medication.dart` | JSON 모델, 날짜와 용량 표시·검증 |
| `lib/vm/medications/medication_vm.dart` | Riverpod 상태, 조회·작성·수정 API와 주보호자 UI 권한·페이지 처리 |
| `lib/view/medications/medication_list_view.dart` | 날짜·시간별 목록과 상세 |
| `lib/view/medications/medication_form_view.dart` | 약 추가 입력창 |
| `lib/view/medications/medication_edit_view.dart` | 기존 값 입력, 날짜 변경, 검증·취소 확인·실패 시 입력 보존 |
| `lib/vm/family_context.dart` | 두 기능이 공유하는 선택 공간·사용자·서버 주소와 인증 토큰 연결 지점 |
| `lib/view/home.dart` | 메모·투약일지 진입 메뉴 |

기존 `memoContextProvider`는 `familyContextProvider`의 별칭으로 유지합니다.
따라서 메모와 투약일지에 서로 다른 공간 상태를 복사해서 두지 않습니다.
투약일지 목록은 공간·사용자·날짜를 키로 분리하고 오래된 요청의 결과가 새 상태를 덮어쓰지 않게 합니다.

## API 계약

### 주보호자 투약 정보 수정

`PATCH /medications/update/{medication_log_seq}`에 Firebase ID 토큰을 Bearer 헤더로 전달합니다.
`family_room_id`와 수정할 필드만 보냅니다.

```json
{
  "family_room_id": "공간ID",
  "medication_info": "변경할 약 정보",
  "dosage": "1.250"
}
```

수정 허용 필드는 `medication_info`, `medication_date`, `medication_time`, `dosage_unit`, `dosage`입니다.
작성과 같은 길이·날짜·용량 조건을 적용하며 수정 필드는 하나 이상이어야 합니다.
필드 생략은 기존 값 유지이며 명시적인 null은 허용하지 않습니다.
작성자·작성 시각·복약 확인 시각은 수정하지 않고 `record_updated_at`만 서버 시각으로 갱신합니다.
이미 복약 확인된 기록도 내용 수정은 가능하며 기존 복약 확인 상태를 유지합니다.

서버가 현재 미탈퇴 사용자·활성 참여·미삭제 공간·`is_representative = 1`을 검사합니다.
다른 가족이 작성한 기록도 해당 공간의 주보호자는 수정할 수 있습니다.
다른 공간의 기록·삭제된 기록은 수정할 수 없습니다. 권한 검사와 대상 행을 같은 트랜잭션에서 잠급니다.

- 성공 200: `{"result": "OK", "medication_log_seq": 42}`
- 미인증 401, 주보호자 권한 없음 403, 대상 기록 없음 404
- 빈 수정·null·추가 필드·잘못된 값 422, DB 실패 500

### 조회·작성

목록은 `GET /medications/select`에 `family_room_id`, `medication_date`, `limit=20`,
`offset`을 전달합니다. 날짜는 `YYYY-MM-DD`입니다.

작성은 `POST /medications/insert`에 다음 필드만 보냅니다.
작성자는 현재 공간의 주보호자여야 하며, 일반 참여자는 403을 반환합니다.

```json
{
  "family_room_id": "공간ID",
  "medication_info": "기록할 약 정보",
  "medication_date": "2026-10-23",
  "medication_time": "아침 식후 30분",
  "dosage": "0.500",
  "dosage_unit": "정"
}
```

사용자 ID와 투약 확인 시각은 본문에 보내지 않습니다.
용량은 부동소수점 변환 없이 숫자 문자열로 전달하고 양수·정수부 7자리·소수부 3자리 이내를 검증합니다.
약 정보는 100자, 단위는 20자 이내입니다. 분은 0~9999 범위이며
식사·시점·분을 합친 문자열을 서버의 `medication_time`에 저장합니다.
입력 기본값은 목업을 따른 것이며 사용자가 실제 기록에 맞게 선택합니다.

### 복약 완료 체크 (백엔드)

기존 작성자 `user_id`와 체크 시간 `medication_confirmed_at`은 유지하고,
`confirmed_by_user_id` nullable 사용자 외래키를 추가했습니다.
현재 연결된 개발 MySQL에는 적용했습니다. 다른 DB에는 서버 실행 전에 다음 명령으로 적용합니다.
앱 실행 시 DDL을 자동 실행하지 않으며 이미 컬럼이 있으면 다시 추가하지 않습니다.

```powershell
python -m python.features.medications.migrate_confirmation
```

```text
POST /medications/confirm/{medication_log_seq}
Authorization: Bearer <Firebase ID 토큰>
Content-Type: application/json

{"family_room_id":"공간ID"}
```

체크는 주보호자뿐 아니라 해당 공간의 활성 참여자가 모두 할 수 있습니다.
체크 사용자 ID는 인증 정보, 체크 시간은 DB의 `CURRENT_TIMESTAMP`로 결정합니다.
클라이언트가 체크 사용자·이름·시간을 전달하면 422로 거절합니다.
참여·공간·사용자와 대상 투약일지를 잠근 뒤 체크하여 동시 요청에도 최초 체크만 반영합니다.
이미 체크된 기록에 재요청하거나 다른 참여자가 체크해도 최초 사용자·시간을 유지합니다.
체크 해제는 아래 DELETE API를 사용합니다. 작성자와 약 정보·내용 수정 시각은 변경하지 않습니다.

HTTP 200 응답 예:

```json
{
  "result": "OK",
  "medication_log_seq": 42,
  "already_confirmed": false,
  "medication_confirmed_at": "2026-10-26T14:25:03",
  "confirmed_by_user_id": "체크 사용자 ID",
  "confirmed_by_name": "김가족"
}
```

`confirmed_by_name`은 체크 사용자의 현재 `user.name`입니다.
목록 조회에도 `confirmed_by_user_id`, `confirmed_by_name`, `medication_confirmed_at`을 반환합니다.
미체크 기록은 세 값이 null입니다. 이전에 체크 시간만 저장된 기록의 사용자는 추측하지 않고 null로 유지합니다.
미인증 401, 공간 권한 없음 403, 다른 공간·삭제·없는 기록 404, 입력 오류 422, DB 오류 500입니다.

관련 파일은 `python/features/medications/schema.sql`, `migrate_confirmation.py`, `router.py`이며,
모의 API 테스트는 `python/tests/test_medication_confirmation.py`에서 수행합니다.
실제 MySQL 동시성 검증은 기존 기록을 변경하지 않고 임시 기록만 생성·정리합니다.

```powershell
$env:ONDOLBOM_MYSQL_TESTS = '1'
python -m unittest python.tests.test_medication_confirmation_mysql -v
Remove-Item Env:ONDOLBOM_MYSQL_TESTS
```

## 투약 완료 체크 해제 API

`DELETE /medications/confirm/{medication_log_seq}`에 Firebase Bearer 토큰과 JSON 본문을 전달합니다.
Swagger UI의 해당 DELETE 항목에서도 테스트할 수 있습니다.

```json
{
  "family_room_id": "공간 ID",
  "expected_confirmed_at": "2026-10-26T14:25:03",
  "expected_confirmed_by_user_id": "체크 사용자 ID"
}
```

두 `expected_` 필드는 목록/체크 응답의 `medication_confirmed_at`, `confirmed_by_user_id`
원본 값을 그대로 사용합니다. 시간은 화면의 오전/오후 표시로 변환하지 않습니다.
확인자가 없는 과거 완료 기록은 `expected_confirmed_by_user_id`에 null을 명시합니다.

- 현재 공간의 활성 참여자이며, 체크한 본인 또는 현재 주보호자여야 합니다.
- 일반 가족은 타인의 체크를 해제할 수 없고, 확인자 없는 과거 기록은 현재 주보호자만 해제할 수 있습니다.
- 참여 종료·비활성·탈퇴·삭제된 공간은 403, 없거나 삭제된 기록·다른 공간 기록은 404입니다.
- 체크 시간 또는 확인자가 달라졌으면 409이며, 목록을 갱신한 뒤 다시 확인해야 합니다.
- 이미 미완료라면 활성 참여자의 재요청에 200과 `already_unconfirmed: true`를 반환하며 변경하지 않습니다.
- 정상 해제는 기존 두 체크 컬럼을 NULL로 변경합니다. 테이블 구조 변경이나 해제 이력 저장은 없습니다.
- 미인증은 401, 입력 오류는 422, DB 오류는 500입니다. 실패 시 rollback합니다.

HTTP 200 응답 예:

```json
{
  "result": "OK",
  "medication_log_seq": 42,
  "already_unconfirmed": false,
  "medication_confirmed_at": null,
  "confirmed_by_user_id": null,
  "confirmed_by_name": null
}
```

참여·역할과 투약일지 행을 체크 API와 같은 순서로 잠급니다.
동시 해제 요청은 한 번만 변경하며, 해제 후에는 기존 POST API로 다시 체크할 수 있습니다.
Flutter는 현재 선택 공간의 본인 체크 또는 주보호자에게만 해제 조작을 제공합니다.
해제 전 확인창을 표시하고, 처리 중에는 같은 항목의 체크·해제·수정을 비활성화합니다.
API 응답의 미완료 상태를 목록·상세에 반영하며 `already_unconfirmed: true`도 성공으로 처리합니다.
실패하면 기존 상태를 유지하고 재시도할 수 있습니다. 409는 목록을 다시 조회하고 변경 안내를 표시합니다.
원본 체크 시간과 사용자 ID를 보내며, 토큰 로딩 중 계정·공간이나 주보호자 권한이 바뀌면 요청을 차단합니다.
추가 페이지 응답이 늦게 도착해도 해당 요청 중 완료된 체크·해제 결과를 덮어쓰지 않습니다.
Flutter 검증은 `test/medication_unconfirmation_test.dart`에서 수행합니다.
권한·충돌·실패 테스트는 `python/tests/test_medication_unconfirmation.py`에서 수행합니다.

## 실행과 인증 연결

프로젝트 루트에서 서버를 실행하고 별도 터미널에서 Flutter를 실행합니다.

```powershell
python -m python.main
```

```powershell
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000
```

서버 주소는 로그인·가족 공간 기능과 같은 설정을 사용하며 기본값은 `http://10.0.2.2:8000`입니다.
데스크톱·웹은 `API_BASE_URL=http://127.0.0.1:8000`을 지정합니다. `API_BASE_URL` 실행 옵션으로 바꿀 수 있습니다.
실제 기기에서는 기기가 접근할 수 있는 서버 주소와 서버 바인딩 설정이 필요합니다.

가족 공간 홈의 투약일지 메뉴에서 목록으로 이동합니다.
현재 선택한 공간과 서버에서 조회한 MySQL 사용자 프로필을 사용하며, 실행 옵션의 공간·사용자 ID는 사용하지 않습니다.
`apiTokenLoaderProvider`는 현재 로그인한 사용자의 Firebase ID 토큰을 가져옵니다.
투약일지 VM은 조회·작성 요청에 `Authorization: Bearer ...` 헤더를 전달합니다.
토큰이 없으면 서버 요청을 보내지 않으며, 서버는 각 라우터에서 토큰과 공간 권한을 확인합니다.
미인증·권한 거절은 화면에 표시하며 테스트용 기록으로 대체하지 않습니다.

## 검증

```powershell
flutter analyze --no-pub
flutter test --no-pub
```

`test/medication_test.dart`에서 모델 변환·입력 검증, 실제 앱 테마,
작성 후 조회 갱신, 작은 화면과 실패 시 입력 보존, 중복 제출 방지,
인증 오류·재시도, 날짜·공간 상태 분리와 페이지 처리를 모의 API로 검증합니다.
테스트는 실제 투약 기록을 작성하지 않습니다.
테스트는 앱의 테마를 사용하되 투약일지 화면을 직접 실행하므로 제외된 홈 파일에 의존하지 않습니다.


## Flutter 투약 정보 수정 확인

가족 공간의 현재 참여 정보가 주보호자인 경우 상세 창에 수정 버튼이 표시된다.
권한이 바뀌거나 공간이 바뀌면 편집 창의 저장을 막고, 서버도 매 요청마다 주보호자를 재검사한다.
복약 시간은 추가 화면처럼 식사·복약 시점 드롭다운과 0~9999분 입력란으로 수정한다.
기존 `점심 식전 15분` 형태는 각 입력값으로 복원한다. 자유 형식 기록은 원문을 안내하고
사용자가 세 값을 직접 선택하도록 검증하여 임의의 기본값으로 덮어쓰지 않는다.
등록된 작성자·복약 완료 상태는 PATCH 본문에 보내지 않는다.
저장 중 중복 제출·창 닫기를 막고 실패 시 입력을 보존한다. 변경 후 취소할 때는 확인 창을 표시한다.

```powershell
flutter test test/medication_test.dart test/medication_edit_test.dart
```

`test/medication_create_permission_test.dart`에서 일반 참여자의 약 추가 버튼 비표시,
작성 중 역할 해제와 토큰 대기 중 권한 변경에 대한 등록 차단도 검증합니다.

`test/medication_confirmation_test.dart`에서 목록·상세의 체크 연결과 완료 개수,
최초 체크 사용자의 이름·시간 표시, 중복 요청·오류 재시도, 계정 변경,
페이지 추가 조회와 체크의 경합을 검증합니다. 과거 확인자 정보가 없는 기록은
사용자 ID 대신 `확인자 정보 없음`으로 표시하고 체크 시간은 유지합니다.
