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

메모 조회·작성은 메모 라우터 내부의 `get_current_user_id`를 사용합니다.
요청의 `Authorization: Bearer <Firebase ID 토큰>`을 기존 Firebase 인증 코드로 검증합니다.
검증된 UID로 MySQL `user.user_firebase_uid`를 정확히 비교하여 내부 `user_id`를 조회합니다.
토큰 누락·만료·폐기는 401, 미등록·탈퇴 계정은 403, 인증 설정·연결 및 사용자 조회 DB 오류는 503입니다.
클라이언트가 사용자 ID나 임의의 Bearer 값을 전달하는 것으로는 인증되지 않습니다.
작성자는 인증된 사용자로 결정하며, 이전 클라이언트가 본문에 보내는 `user_id`는 무시합니다.
`GET /memos/select?family_room_id=공간ID`도 현재 공간 참여 여부를 검사합니다.
참여 종료·사용자 탈퇴·공간 삭제 시에는 조회와 작성 모두 403을 반환합니다.
투약일지 조회·작성도 투약일지 라우터 내부에 별도로 구현한 인증 의존성을 사용합니다.

메모 사진 첨부는 `POST /memos/insert-with-image`,
`PATCH /memos/update-with-image/{memo_id}`에서 multipart/form-data로 지원합니다.
필수 필드는 `family_room_id`, `memo_content`이며 `image`는 최대 한 장(5MiB)입니다.
수정 시 파일 생략은 유지, 파일 첨부는 교체, `remove_image=true`는 제거입니다.
기존 `memo_image` LONG BLOB에 텍스트와 함께 한 트랜잭션으로 저장합니다.
추가 의존성 `Pillow`, `python-multipart`는 `requirements.txt`에 포함되어 있습니다.
이미지 조회와 Flutter 동작은 [메모 기능 구현 안내](../docs/memos-frontend.md)를 참고하세요.

메모 좋아요 등록은 `POST /memos/like/{memo_id}`이며 JSON 본문은
`{"family_room_id":"공간ID","author_user_id":"메모 작성자 ID"}`입니다.
Bearer 토큰의 사용자로 한 번만 등록하며 취소 API는 없습니다.
재전송은 HTTP 200과 `already_liked:true`를 반환하고 개수를 증가시키지 않습니다.
목록 응답에는 현재 사용자의 `is_liked` 플래그도 포함됩니다.
처음 배포하는 DB에서는 서버 실행 전 `python -m python.features.memos.migrate_likes`로
좋아요 기록 테이블을 생성해야 합니다. 기존 메모 테이블과 데이터는 유지합니다.

## 채팅 본문 수정·전체 삭제 API

`PATCH /chats/messages/{chat_seq}`에 `family_room_id`, `content` JSON을 보내 본문을 수정합니다.
`DELETE /chats/messages/{chat_seq}?family_room_id=공간ID`로 메시지 전체를 소프트 삭제합니다.
현재 공간의 활성 참여자인 작성자 본인만 허용하며, 이미지만 변경하는 기능은 없습니다.
삭제된 메시지는 조회·이벤트에서 원문 대신 삭제 안내를 반환하며 이미지 조회도 차단합니다.
저장 후 기존 `message` WebSocket 이벤트에 `action: updated/deleted`를 추가해 전달합니다.
재연결 시 과거 메시지의 수정·삭제는 `POST /chats/messages/refresh`로 최대 100개씩 조회합니다.
필드·응답·권한은 [채팅 안내](../docs/chats-implementation.md)를 참고하세요.

## 채팅 이미지 전송 API

`POST /chats/messages/with-image`에 Bearer 토큰과 multipart/form-data를 전달합니다.
필수 입력은 `family_room_id`, `client_message_id`(UUID), `image` 한 장이며,
`content`는 선택입니다. 최대 5MiB의 JPG·PNG·WEBP 정지 이미지를 허용합니다.
기존 `live_chat.chat_image`에 메시지와 함께 저장하므로 테이블 변경은 없습니다.
저장 후 기존 WebSocket으로 `has_image`를 포함한 메시지 정보를 전달합니다.
이미지는 `GET /chats/messages/{chat_seq}/image?family_room_id=공간ID`로 인증 후 조회합니다.
동일 UUID·내용·이미지 재시도는 원본 반환, 다른 내용의 UUID 재사용은 409입니다.
필드·응답·Swagger 테스트 방법은 [채팅 안내](../docs/chats-implementation.md)를 참고하세요.

## 투약일지 체크 해제 API

`DELETE /medications/confirm/{medication_log_seq}`로 체크를 해제합니다.
JSON 본문에는 `family_room_id`, `expected_confirmed_at`, `expected_confirmed_by_user_id`가 필요합니다.
두 expected 값에는 목록/체크 응답의 체크 시간·사용자 ID 원본을 전달합니다.
현재 공간의 활성 참여자 중 체크한 본인 또는 현재 주보호자만 허용합니다.
기록이 변경되었으면 409, 이미 미완료면 200과 `already_unconfirmed:true`를 반환합니다.
해제 시 기존 체크 시간과 확인자 ID를 NULL로 비우며 테이블 구조는 변경하지 않습니다.
본문·응답 예와 상세 권한은 [투약일지 안내](../docs/medications-frontend.md)를 참고하세요.

## 투약일지 작성·조회 API

`POST /medications/insert`로 현재 참여 중인 공간의 주보호자만 투약일지를 작성합니다.
일반 참여자의 작성은 403으로 거절하며 조회는 기존처럼 허용합니다.
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
투약 확인 시각은 null로 시작합니다.
복약 완료 체크는 `POST /medications/confirm/{medication_log_seq}`에
`{"family_room_id":"공간ID"}`를 전송합니다. 해당 공간의 활성 참여자가 체크할 수 있습니다.
인증된 사용자 ID와 DB 시간을 저장하고 `confirmed_by_user_id`, `confirmed_by_name`,
`medication_confirmed_at`을 응답합니다. 체크 이름은 `user.name`에서 조회합니다.
목록에도 이 필드를 반환하며 재요청은 `already_confirmed:true`로 최초 체크를 유지합니다.
최초 배포 시 `python -m python.features.medications.migrate_confirmation`으로 체크 사용자 컬럼을 추가합니다.
저장 중 참여 종료·공간 삭제·사용자 탈퇴와의 충돌을 막도록 참여 확인 행을 잠그고,
전체 성공 시 한 번 commit, 실패 시 rollback하며 연결을 종료합니다.

`GET /medications/select?family_room_id=공간ID`로 공간별 투약일지를 조회합니다.
선택적으로 `medication_date=2026-10-23`을 추가하면 해당 투약 날짜만 조회합니다.
`limit`은 기본 20개(1~100), `offset`은 기본 0입니다.
투약 날짜·기록 시간·일지 번호 내림차순으로 정렬하며 삭제된 기록과 공간을 제외합니다.
응답은 `{"results": [...]}`이고, 기록이 없으면 빈 배열입니다.
`dosage`는 JSON 숫자, 날짜는 `YYYY-MM-DD`, 일시는 ISO 형식으로 반환합니다.

작성·조회 모두 Firebase ID 토큰이 필요하며 각 라우터의 인증 의존성에서 사용자 ID를 조회합니다.
유효한 토큰이 없으면 401, 현재 공간 참여자가 아니거나 공간이 삭제된 경우에는
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
