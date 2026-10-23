# 메모·투약일지 MVP 구현 현황

작성일: 2026-10-23 (KST)

문서 작성 기준은 `feature/memos-medications-mvp` 브랜치의 `d1d5f64` 코드입니다.
이 구현 이력에서 새 `feature/mvp-progress-docs` 브랜치를 생성합니다.
기존 구조 문서의 계획과 구분하기 위해 실제 구현 내용과 미연결 항목을 함께 기록합니다.

## 1. 개발 환경과 담당 범위

- 프론트엔드: Dart / Flutter / Riverpod
- 백엔드: Python / FastAPI / PyMySQL
- DB: MySQL
- 개발 서버는 가상환경 없이 프로젝트 루트에서 `python python/main.py`로 실행
- 담당 MVP: 메모 작성·조회, 투약 정보 작성·수정·조회, 가족 공동 체크리스트,
  공간별 텍스트 채팅

## 2. 기능별 상태

| 기능 | 백엔드 | 프론트엔드 | 남은 작업 |
| --- | --- | --- | --- |
| 메모 목록 | 공간별 조회·페이지 처리·권한 검사 구현 | 목록·새로고침·추가 조회 구현 | 홈 진입과 실제 인증 연결 |
| 메모 상세 | 별도 상세 API 없음 | 목록에서 받은 데이터로 상세 표시 | 별도 상세 API는 필요 시 추가 |
| 메모 작성 | 내용 검증·참여 확인·저장 구현 | 작성·검증·등록·취소 확인 구현 | 실제 인증 후 저장 흐름 검증 |
| 투약일지 조회 | 공간·투약 날짜별 조회 구현 | 미구현 | 화면·VM·모델 추가 |
| 투약 정보 작성·수정 | 미구현 | 미구현 | 데이터 계약 확정 후 구현 |
| 가족 공동 체크리스트 | 미구현 | 미구현 | 테이블·API·화면 설계 |
| 공간별 텍스트 채팅 | 미구현 | 미구현 | 메시지 저장·조회·실시간 연결 구현 |

사진 첨부, 메모 수정·삭제, 좋아요 조작은 현재 구현 범위에 없습니다.
서버가 제공하는 좋아요 개수만 화면에 표시합니다.

## 3. 주요 파일

```text
lib/
  model/memos/memo.dart              메모 필드와 JSON 변환
  vm/memos/memo_vm.dart              Riverpod 상태·HTTP·페이지 처리
  view/memos/memo_list_view.dart     목록과 상세 화면
  view/memos/memo_form_view.dart     작성·등록·취소 확인
  view/memos/memo_style.dart         공통 화면·스타일·작성 시간 표시
python/
  main.py                           메모·투약일지 라우터 등록과 직접 실행
  auth.py                           공통 인증 의존성 연결 지점
  database.py                       환경 설정과 MySQL 연결
  features/memos/router.py           메모 작성·조회
  features/medications/router.py     투약일지 조회
  tests/test_auth.py                인증 연결 지점 테스트
  tests/test_memos.py               메모 API 테스트
  tests/test_medications.py         투약일지 조회 테스트
  tests/test_database.py            DB 설정·서버 상태 테스트
test/
  memo_test.dart                    모의 API 기반 메모 UI·VM 테스트
  widget_test.dart                  앱 기본 진입 테스트
```

`features`와 각 구현 기능 폴더에는 패키지용 `__init__.py`가 있습니다.
API 요청 모델과 SQL은 기능별 `router.py`에서 함께 관리합니다.
MySQL 연결은 요청마다 생성하고 `finally`에서 종료합니다.

## 4. 구현된 API

| 메서드 | 경로 | 입력 | 응답 |
| --- | --- | --- | --- |
| GET | `/health` | 없음 | `{"status":"ok"}` |
| GET | `/memos/select` | `family_room_id`, `limit`, `offset` | `{"results":[...]}` |
| POST | `/memos/insert` | JSON의 `family_room_id`, `memo_content` | HTTP 201, `result`, `memo_id` |
| GET | `/medications/select` | `family_room_id`, 선택적 `medication_date`, `limit`, `offset` | `{"results":[...]}` |

`limit` 기본값은 20이며 1~100, `offset` 기본값은 0이며 음수를 허용하지 않습니다.
투약 날짜 필터는 `YYYY-MM-DD` 형식입니다. 조회 결과가 없으면 빈 배열을 반환합니다.
`/health`는 프로세스 상태만 확인하며 DB 연결이나 인증 성공을 의미하지 않습니다.

### 메모

- 실제 DB의 `memo` 테이블과 `family_room_id` 컬럼을 사용합니다.
- 목록은 삭제된 메모와 공간을 제외하고 작성 시간·메모 ID·작성자 ID 내림차순으로 조회합니다.
- 작성 내용은 앞뒤 공백을 제거하고 1~10,000자로 제한합니다.
- 작성자는 서버가 얻은 인증 사용자이며 클라이언트 본문의 `user_id`는 무시합니다.
- UUID로 메모 ID를 생성하고, 좋아요는 0, 작성 시간은 DB 기본값으로 저장합니다.
- 참여 확인 시 행을 잠그고 저장 성공 후 한 번 commit하며 실패 시 rollback합니다.

작성 요청 예시:

```json
{
  "family_room_id": "실제 공간 ID",
  "memo_content": "가족에게 전달할 돌봄 메모"
}
```

### 투약일지

- 실제 DB의 `medication_log` 테이블을 사용합니다.
- 공간별로 조회하며 `medication_date`를 전달하면 해당 투약 날짜만 반환합니다.
- 삭제된 기록과 공간을 제외합니다.
- 투약 날짜·기록 시간·일지 번호 내림차순으로 정렬합니다.
- 약 정보, 투약 날짜·시간, 용량·단위, 확인 시각, 기록·수정 시각을 반환합니다.
- 용량은 JSON 숫자, 날짜와 일시는 JSON 문자열이며 nullable 필드는 null을 유지합니다.

## 5. 인증·권한 연결 현황

메모 조회·작성과 투약일지 조회는 `python/auth.py`의 `get_current_user_id`를 사용합니다.
이 함수는 서버의 `request.state.user_id`를 읽는 연결 지점이며 **토큰 검증 구현은 아닙니다.**
현재 기준 코드에는 로그인 API, Firebase ID 토큰 검증, 해당 state를 설정하는 코드가 없습니다.
따라서 실제 요청은 인증 단계에서 HTTP 401을 반환합니다.
사용자 ID나 임의 Bearer 문자열을 전달하는 것으로 인증을 통과할 수 없습니다.

인증을 연결하면 다음 조건을 모두 만족하는 사용자의 요청만 허용합니다.

- `participate`의 사용자·공간 일치
- `is_active = 1`, `left_at IS NULL`
- 공간의 `family_room_deleted_at IS NULL`
- 사용자의 `withdrawn_at IS NULL`

참여 조건을 만족하지 못하면 403, 입력 오류는 422, DB 오류는 내부 정보를 숨긴 500입니다.

[별도 로그인·회원가입 PR #1](https://github.com/jgw00518-max/OnDolbom/pull/1)의 설명에는
Firebase 인증, 공통 Riverpod 인증 상태, FastAPI ID 토큰 검증과 사용자 프로필 API가 포함되어
있습니다. 해당 인증 코드는 이 문서의 기준 코드에는 반영되어 있지 않습니다.
연동 시 실제 검증 함수의 계약과 Firebase UID에서 MySQL 사용자 ID로의 매핑을 확인해야 합니다.

## 6. 프론트엔드 연결 현황과 실행

목업의 크림색 배경·갈색 제목·흰색 카드·복숭아색 버튼을 반영한 메모 화면이 있습니다.
API 호출은 VM에서 수행하고, 선택 공간·사용자별로 목록 상태를 분리합니다.
작성 성공 시 목록을 다시 조회하고, 실패 시 입력을 보존하며 중복 제출을 막습니다.

**현재 `lib/view/home.dart`는 Placeholder이므로 앱을 실행해도 메모 화면으로 진입하지 않습니다.**
홈 화면이나 라우트에서 `MemoListView`로 연결하는 작업이 남아 있습니다.
메모 화면 테스트는 이 진입 파일과 분리해 해당 화면을 직접 구동합니다.

`memoContextProvider`는 현재 실행 옵션을 읽는 임시 상태입니다.
팀 공통 로그인·선택 공간 상태가 준비되면 여기에 연결해야 합니다.
HTTP 요청의 인증 토큰 전달도 아직 구현되지 않았습니다.
VM은 기존 호환을 위해 작성 본문에 `user_id`를 보내지만 서버는 이를 무시합니다.

화면 진입과 인증을 연결한 뒤 사용할 실행 옵션 예시:

```powershell
python python/main.py
```

별도 터미널:

```powershell
flutter run --dart-define=FAMILY_ROOM_ID=공간ID --dart-define=USER_ID=사용자ID --dart-define=FAMILY_ROOM_NAME="가족 돌봄 공간"
```

- `USER_ID` 실행 옵션은 화면용 임시 정보이며 인증 수단이 아닙니다.
- 공간 ID가 없으면 공간 선택 안내를 표시하고 요청하지 않습니다.
- 사용자 ID가 없으면 현재 화면의 작성 버튼은 비활성입니다.
- Android 에뮬레이터 기본 주소는 `http://10.0.2.2:8000`, 다른 플랫폼은
  `http://127.0.0.1:8000`입니다.
- 다른 서버는 `--dart-define=API_BASE_URL=서버주소`로 지정합니다.
- 실제 기기에는 기기에서 도달 가능한 서버 주소와 서버 바인딩 설정이 필요합니다.
- Android 로컬 HTTP 허용은 debug manifest에만 적용되어 있습니다.

## 7. 검증 결과

2026-10-23에 기준 코드에서 아래 검증을 다시 실행했습니다.

| 검증 | 결과 |
| --- | --- |
| `flutter analyze --no-pub` | 분석 문제 없음 |
| `flutter test --no-pub` | 7개 통과 |
| `python -m unittest discover -s python/tests -p "test_*.py" -v` | 25개 통과 |

테스트는 모의 HTTP 응답·DB 연결·인증 상태를 사용합니다.
미인증 요청, 다른 작성자 사칭, 공간 접근 거절, 입력 검증, 빈 목록, 오류 응답과
연결 종료, 페이지 처리, 작성 후 갱신, 중복 제출·취소 확인 등을 검증합니다.
실제 Firebase 로그인부터 MySQL 저장까지의 통합 흐름은 검증하지 않았습니다.
백엔드 테스트 실행 시 Starlette TestClient의 httpx 관련 사용 중단 예고 경고가 있으나
현재 테스트는 모두 통과합니다.

## 8. 다음 구현 순서

1. 로그인 담당 코드와 공통 인증 상태를 통합하고 사용자 ID 매핑을 확정합니다.
2. 서버 인증 의존성과 프론트 인증 토큰 전달을 연결합니다.
3. 홈·공간 선택 흐름에서 메모 화면에 진입하도록 연결합니다.
4. 실제 공간 참여자로 작성·조회하고, 미참여자·참여 종료 사용자 접근 거절을 검증합니다.
5. 투약 정보 작성·수정 API와 투약일지 프론트엔드를 구현합니다.
6. 공동 체크리스트와 공간별 텍스트 채팅을 구현합니다.

이 문서를 추가하는 커밋에는 `lib/main.dart`, 홈 화면 파일, 루트 `README.md`를 변경하지 않습니다.
DB 접속값, `.env`, Firebase 비공개 키 등 비밀 정보도 포함하지 않습니다.
