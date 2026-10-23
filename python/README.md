# 사용자 앱 백엔드 공통 기반

프로젝트 루트 `C:\My\ondolbom`에서 실행합니다.

```powershell
python -m pip install -r python/requirements.txt
python -m uvicorn python.main:app --reload
```

`GET /health`는 서버 실행 상태만 확인합니다. DB 연결 검사는 아닙니다.
`python/.env.example`의 항목을 참고해 로컬 `python/.env`를 작성합니다.
기존 설정 파일은 자동으로 덮어쓰지 않습니다. 환경변수가 파일보다 우선합니다.

- `main.py`: FastAPI 생성, 기능별 라우터 등록, `/health` 제공
- `database.py`: `.env` 읽기, 필수 MySQL 설정 검사, DictCursor·수동 commit 연결 생성

## 메모 API와 인증 연결

`POST /memos/insert`에 아래 JSON을 보내 텍스트 메모를 작성합니다.

```json
{
  "family_room_id": "실제 공간 ID",
  "memo_content": "저녁 식사 후 산책했습니다."
}
```

`participate.is_active = 1`, `left_at IS NULL`인 참여만 허용하며 삭제된 공간이나
탈퇴한 사용자는 작성할 수 없습니다. 내용은 앞뒤 공백 제거 후 1~10,000자입니다.
메모 ID는 서버에서 UUID로 만들고 좋아요는 0, 작성 시간은 DB 기본값으로 저장합니다.
성공하면 HTTP 201과 `{"result": "OK", "memo_id": "생성된 UUID"}`를 반환합니다.
공간 참여 조건을 만족하지 못하면 403, 입력 오류는 422, DB 오류는 500입니다.

메모 조회·작성은 `python/auth.py`의 `get_current_user_id`를 공통 의존성으로 사용합니다.
인증 담당 코드가 토큰을 검증하고 DB의 사용자 ID를 `request.state.user_id`에 설정해야 합니다.
로그인·토큰 검증 자체는 아직 미구현이므로 연결 전 실제 요청은 401입니다.
클라이언트가 사용자 ID나 임의의 Bearer 값을 전달하는 것으로는 인증되지 않습니다.
작성자는 인증된 사용자로 결정하며, 이전 클라이언트가 본문에 보내는 `user_id`는 무시합니다.
`GET /memos/select?family_room_id=공간ID`도 현재 공간 참여 여부를 검사합니다.
참여 종료·사용자 탈퇴·공간 삭제 시에는 조회와 작성 모두 403을 반환합니다.
공통 인증 의존성은 투약일지 조회에서도 사용합니다.

## 투약일지 작성·조회 API

`POST /medications/insert`로 현재 참여 중인 공간에 투약일지를 작성합니다.
아래 항목은 모두 필수이며 문자열의 앞뒤 공백은 제거합니다.

```json
{
  "family_room_id": "실제 공간 ID",
  "medication_info": "기록할 약 정보",
  "medication_date": "2026-10-23",
  "medication_time": "아침",
  "dosage_unit": "정",
  "dosage": "0.500"
}
```

약 정보는 최대 100자, 투약 시간과 단위는 각각 최대 20자입니다.
용량은 0보다 커야 하고 MySQL `DECIMAL(10,3)`에 맞게 정수부 최대 7자리,
소수부 최대 3자리로 제한합니다. 용량은 JSON 숫자 또는 숫자 문자열로 보낼 수 있습니다.
시간은 현재 DB의 문자열 필드에 맞춰 `아침` 또는 `09:00`처럼 기록하며
정해진 시간대 목록이나 시간 형식은 아직 강제하지 않습니다.
작성자는 인증 정보로 결정하므로 본문에 `user_id`를 보내지 않습니다.
정의되지 않은 추가 필드와 투약 확인 시각 등 서버 관리 필드는 입력할 수 없습니다.

성공 응답은 HTTP 201과 `{"result": "OK", "medication_log_seq": 42}` 형식입니다.
일지 번호는 DB 자동 증가 값이며 기록 시각은 DB 기본값을 사용합니다.
투약 확인 시각은 null로 시작합니다. 투약 완료 체크 API는 이번 작성 기능에 포함하지 않습니다.
저장 중 참여 종료·공간 삭제·사용자 탈퇴와의 충돌을 막도록 참여 확인 행을 잠그고,
전체 성공 시 한 번 commit, 실패 시 rollback하며 연결을 종료합니다.

`GET /medications/select?family_room_id=공간ID`로 공간별 투약일지를 조회합니다.
선택적으로 `medication_date=2026-10-23`을 추가하면 해당 투약 날짜만 조회합니다.
`limit`은 기본 20개(1~100), `offset`은 기본 0입니다.
투약 날짜·기록 시간·일지 번호 내림차순으로 정렬하며 삭제된 기록과 공간을 제외합니다.
응답은 `{"results": [...]}`이고, 기록이 없으면 빈 배열입니다.
`dosage`는 JSON 숫자, 날짜는 `YYYY-MM-DD`, 일시는 ISO 형식으로 반환합니다.

인증 담당 코드가 토큰 검증 후 `request.state.user_id`를 설정해야 합니다.
작성·조회 모두 인증 미연결 상태에서는 401, 현재 공간 참여자가 아니거나 공간이 삭제된 경우에는
403을 반환합니다. 참여는 `is_active = 1`, `left_at IS NULL`을 기준으로 하며
탈퇴한 사용자도 접근할 수 없습니다. 요청의 사용자 ID를 인증 정보로 사용하지 않습니다.
구현 파일은 `features/medications/router.py`입니다.

## 폴더 구성과 기능 추가

`main.py`에서 FastAPI를 생성하고 기능별 `APIRouter`를 등록합니다.
DB 연결과 환경 설정 읽기는 `database.py`에서 처리합니다.
오류 응답은 FastAPI 기본 형식을 사용하며, 기능별 오류는 API에서 `HTTPException` 등으로 처리합니다.

기능 담당자가 개발할 때 `features/기능명/` 안에 `__init__.py`와 `router.py`를
추가합니다. 수업의 `fastapi_02.py`는 `main.py`, `items.py`는 기능별
`router.py`에 대응합니다. API 공통 prefix와 tags는 `main.py`에서 등록합니다.

처음에는 `router.py`에서 요청·업무 처리·SQL을 구현해도 됩니다.
코드가 커지는 기능만 `schemas.py`, `service.py`, `repository.py`로 분리합니다.
모든 기능에 계층 분리를 강제하지 않습니다.

DB를 사용하는 API는 동기 `def`로 작성하고 `from python.database import connect`로
연결 함수를 가져옵니다. 각 API에서 연결한 뒤 하나의 업무에서 같은 연결을 사용합니다.
전체 성공 후 한 번 commit하고, 실패하면 rollback한 뒤 오류를 전달하며,
finally에서 연결을 종료합니다. 분리한 SQL 함수에서는 개별 commit하지 않습니다.

Firebase ID 토큰 검증과 `GET /auth/me` 사용자 조회를 구현했습니다.
서버 서비스 계정과 프로젝트 설정은 [인증 안내](../docs/email-auth-setup.md)를 참고합니다.
검증 UID로 `user.user_firebase_uid`를 조회합니다. `POST /auth/profile`은 이름·전화번호를
필수로 받아 최초 등록하며 전화번호를 `010-1234-5678`로 저장합니다.
같은 UID의 재요청은 기존 프로필을 반환하고 수정하지 않습니다. 실제 계약은 [API 문서](../docs/api.md)를 참고합니다.
설정 오류는 503, 인증 실패는 401, 탈퇴 사용자는 403으로 응답합니다.
공간 권한 검사는 아직 구현하지 않았습니다. 공간별 API는 구현 시 현재 참여 여부와
필요한 역할을 서버에서 검사해야 합니다. 권한 검사 함수를 구현한 상태는 아닙니다.
이메일과 파일 처리 공통 모듈은 실제 처리 방식 확정 후 추가합니다. 기능 router는 구현 후
`main.py`에 등록합니다. 기능별 코드는 이 예시에 포함하지 않습니다.

테스트는 실제 DB나 `.env`를 사용하지 않습니다.

```powershell
python -m pip install -r python/requirements-dev.txt
python -m unittest discover -s python/tests -p "test_*.py" -v
```
