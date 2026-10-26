# 공간별 텍스트·이미지 채팅

## 구성

- `python/features/chats/router.py`: 채팅 자체 인증 연결, 이력 조회, WebSocket 인증·저장·전달.
- `python/features/chats/connection_manager.py`: 단일 프로세스의 공간별 연결 관리.
- `python/features/chats/schema.sql`: 기존 `live_chat`에 재전송 식별자와 이모지 문자셋 추가.
- `python/tests/test_chats.py`: 모의 Firebase·DB 기반 HTTP·WebSocket 테스트.
- `python/tests/test_chat_images.py`: 단일 이미지 업로드·조회·재전송·실시간 전달 테스트.
- `python/tests/test_chat_mutations.py`: 본문 수정·메시지 전체 삭제·변경 조회·원문 비노출 테스트.
- `python/main.py`: `/chats` 라우터 등록.

- `lib/model/chats/chat_message.dart`: 서버 메시지 JSON 모델.
- `lib/vm/chats/chat_vm.dart`: Riverpod 연결·인증·이력·전송 확인·재연결 상태.
- `lib/view/chats/chat_view.dart`: 가족 채팅 화면, 말풍선·입력·재전송·이전 대화 조회.
- `lib/vm/chats/chat_image_vm.dart`: 단일 사진 선택과 인증된 이미지 조회.
- `lib/view/chats/chat_image_view.dart`: 이미지 말풍선 표시·조회 재시도·확대.
- `lib/view/chats/chat_edit_dialog.dart`: 본문 수정·검증·실패 시 입력 보존.
- `test/chat_test.dart`: 토큰·전송 확인·UUID 재사용·이력 복구·화면 이동 테스트.
- `test/chat_image_test.dart`: multipart 업로드·재전송·중복 병합·계정 변경·이미지 화면 검증.
- `test/chat_mutation_test.dart`: 수정·삭제 화면·권한·동기화·늦은 응답 회귀 검증.
- `test/chat_outcome_test.dart`: 수정·삭제 응답 유실 시 실시간 확인·재조회·결과 불확실 처리 검증.

가족 공간 홈의 실시간 채팅 메뉴에서 선택 공간의 채팅 화면으로 이동한다.
공통 `python/auth.py`를 만들지 않는다.
Firebase 검증은 기존 `features/auth/firebase_auth.py`의 함수를 사용한다.

## 실행 전 준비

1. 기존 MySQL과 Firebase 서비스 계정 설정을 `python/.env`에 준비한다.
2. DB 관리자 도구에서 `python/features/chats/schema.sql`을 한 번 적용한다.
   이번 작업은 테이블 정의만 조회했으며 DB 구조나 사용자 메시지를 변경하지 않았다.
   아직 적용되지 않은 DB에서는 `client_message_id` 조회가 실패하여 API가 503을 반환한다.
   기존 메시지는 요청 ID가 NULL인 상태로 보존한다. 새 메시지만 UUID가 필수다.
3. 프로젝트 루트에서 필요한 패키지를 설치한다.

```powershell
python -m pip install -r python/requirements.txt
python -m python.main
```

`uvicorn[standard]`로 WebSocket 서버 지원 패키지도 설치한다. 별도 가상환경은 필수가 아니다.
개발 중 reload·서버 재시작은 연결을 끊으므로 앱에서 재연결해야 한다.
여러 실제 기기를 연결할 때는 다음 명령과 PC의 LAN IP를 사용한다.

```powershell
python -m uvicorn python.main:app --host 0.0.0.0 --port 8000 --workers 1 --ws-max-size 65536
```

운영에서는 HTTPS/WSS를 사용한다. 접속 URL이나 쿼리에 토큰을 넣지 않는다.

## 이전 메시지 조회

`GET /chats/messages?family_room_id=room-a&limit=30`

HTTP 헤더는 `Authorization: Bearer <Firebase ID 토큰>`이다.
검증된 UID의 내부 MySQL 사용자 ID로 현재 공간 참여를 확인한다.
기본 결과는 `chat_seq` 내림차순이며 최대 100개까지 요청할 수 있다.
이미지 BLOB는 반환하지 않는다. 이미지 존재 여부는 `has_image`(0 또는 1)로 반환한다.
삭제된 메시지도 위치를 유지하기 위해 반환하지만 `chat_content`는 `삭제된 메시지입니다.`,
`has_image`는 0이며 원문은 반환하지 않는다. `is_deleted`와 `live_chat_deleted_at`으로 구분한다.
이력과 실시간 메시지, 재전송 응답은 `user.name`을 `author_name`으로 반환한다.
Flutter는 본인 메시지를 `나`로 표시하고, 다른 가족은 이 이름을 표시하며 이름이 비어 있으면 `이름 없는 가족`을 표시한다.
`user_id`는 본인 메시지 구분·인증·중복 처리용 식별자로 유지한다.

```json
{
  "results": [{
    "chat_seq": 7,
    "family_room_id": "room-a",
    "user_id": "서버가 결정한 내부 사용자 ID",
    "author_name": "김가족",
    "chat_content": "안녕하세요 😀",
    "has_image": 0,
    "sent_at": "2026-10-25T18:00:00",
    "client_message_id": "b87782b2-2e2f-43af-a617-cff3735083bb",
    "live_chat_updated_at": null
  }],
  "has_more": false,
  "next_before_id": null,
  "next_after_id": null
}
```

- 이전 기록: `before_id=가장작은chat_seq`를 사용하고 `next_before_id`로 추가 조회한다.
- 재연결 복구: `after_id=마지막chat_seq`를 사용한다. 이 경우 오름차순이며
  `next_after_id`가 있으면 다음 페이지도 조회한다. 기록이 없으면 `after_id=0`부터 시작할 수 있다.
- before_id와 after_id는 동시에 사용할 수 없다.
- 페이지가 비어 있으면 results는 빈 배열이다. 새 참여자는 현재 공간의 과거 대화도 조회할 수 있다.
- 시간은 기존 DB의 DATETIME 기준이며 시간대가 포함되지 않는다. 앱에서 임의로 UTC로 간주하지 않는다.

## WebSocket 프로토콜

주소: `ws://127.0.0.1:8000/chats/ws/{family_room_id}`

1. 연결 후 10초 안에 첫 텍스트 JSON 프레임으로 인증한다.

```json
{"type":"auth","token":"Firebase ID 토큰"}
```

2. 토큰·등록 계정·현재 공간 참여를 확인한 뒤 아래 응답을 보낸다.

```json
{"type":"ready","user_id":"내부 사용자 ID","family_room_id":"room-a"}
```

3. 새 메시지마다 UUID를 한 번 생성한다. 실패 후 같은 메시지를 재전송할 때는 같은 UUID를 사용한다.

```json
{"type":"message","client_message_id":"b87782b2-2e2f-43af-a617-cff3735083bb","content":"안녕하세요 😀"}
```

내용은 앞뒤 공백을 제거한 1~4,000자다. 사용자 ID·시간·이미지 등 추가 필드를 보내면 422 오류다.
서버가 내부 사용자 ID와 DB 시각·자동 증가 chat_seq를 결정한다.
DB 저장과 commit 성공 후 같은 공간의 권한 있는 연결에만 아래 메시지를 보낸다. 발신자도 수신한다.

```json
{"type":"message","message":{"chat_seq":7,"family_room_id":"room-a","user_id":"내부 사용자 ID","chat_content":"안녕하세요 😀","sent_at":"2026-10-25T18:00:00","client_message_id":"b87782b2-2e2f-43af-a617-cff3735083bb","live_chat_updated_at":null},"duplicate":false}
```

같은 작성자·공간·UUID의 재전송은 새로 저장하지 않고 발신자에게만 원본과 duplicate=true를 반환한다.
같은 UUID로 내용을 바꾸거나 삭제된 메시지를 재사용하면 오류 응답을 보낸다.
이미지 메시지의 UUID를 텍스트 WebSocket 전송에 재사용하는 것도 409로 거절한다.

```json
{"type":"error","status":409,"detail":"이미 다른 내용으로 사용한 메시지 ID입니다."}
```

입력 오류는 status=422이며 입력을 고쳐 같은 연결에서 다시 보낼 수 있다.
서버가 `{"type":"ping"}`을 보내면 `{"type":"pong"}`으로 응답할 수 있다.
아무 메시지를 보내지 않는 연결도 30초마다 인증·현재 공간 권한을 다시 확인한다.
전송·수신 직전에도 확인하며, 토큰 만료 시 연결을 종료한다. 새 토큰으로 다시 연결해야 한다.
읽기만 하는 사용자도 탈퇴·강퇴·공간 삭제 후 다음 전달 검사에서 제외한다.

### 종료 코드

| 코드 | 의미 |
| --- | --- |
| 4400 | 인증 프레임 형식 오류·잘못된 JSON·바이너리 입력 |
| 4401 | 토큰 만료·유효하지 않은 인증 |
| 4403 | 미등록·탈퇴 계정·현재 공간 참여 권한 없음 |
| 4408 | 첫 인증 메시지 대기 시간 초과 |
| 1009 | 64 KiB를 초과한 프레임 |
| 1013 | DB·인증 서버 오류 또는 수신 연결 지연. 잠시 후 재연결 |

### 클라이언트 연결 순서

먼저 WebSocket 인증 완료 후 수신 메시지를 임시 보관하면서 HTTP 이력을 조회한다.
두 결과를 chat_seq로 합치고 중복 제거·정렬한다. 재연결도 같은 방식으로 누락 기록을 복구한다.
전송 직후에는 임시 말풍선으로 표시하고 UUID가 일치하는 서버 메시지를 받은 뒤 저장 완료로 표시한다.
서버 저장은 성공했지만 응답이 유실될 수 있으므로 오류 시 새 UUID로 무조건 재전송하지 않는다.

## 이미지 첨부 API

`POST /chats/messages/with-image`는 Firebase Bearer 인증과 `multipart/form-data`를 사용한다.
Swagger UI에서 `Authorize`로 토큰을 설정한 뒤 해당 POST의 `Try it out`에서 이미지 파일을 선택한다.

| 필드 | 필수 | 설명 |
| --- | --- | --- |
| `family_room_id` | O | 현재 참여 중인 가족 공간 ID |
| `client_message_id` | O | 클라이언트가 생성한 UUID. 동일 메시지 재시도에도 동일 값 사용 |
| `content` | X | 앞뒤 공백 제거 후 최대 4,000자. 생략/빈 문자열이면 이미지 단독 메시지 |
| `image` | O | 단일 파일. 같은 이름으로 두 개를 보내거나 다른 첨부 필드를 추가하면 422 |

현재 참여 중인 등록·미탈퇴 사용자만 전송할 수 있다. 작성자와 전송 시각은 서버가 결정한다.
JPG·PNG·WEBP, 최대 5MiB, 최대 2천만 픽셀의 정지 이미지만 허용한다.
실제 파일 형식을 검증하고 방향 보정·최대 2560px 축소·JPEG 변환·EXIF 제거를 수행한다.
검증은 기존 `python/features/memos/images.py`의 로직을 재사용한다.

기존 `live_chat.chat_image LONG BLOB`를 사용하며 테이블 구조를 변경하지 않는다.
텍스트와 이미지를 하나의 메시지 행에 저장하고 commit 후 현재 권한이 있는 같은 공간의
WebSocket 연결에만 알린다. 업로드 자체에는 WebSocket 연결이 필수가 아니다.

최초 저장은 201, 동일 재전송은 200이며 응답은 다음과 같다.

```json
{
  "type": "message",
  "message": {
    "chat_seq": 7,
    "family_room_id": "room-a",
    "user_id": "서버가 결정한 사용자 ID",
    "author_name": "김가족",
    "chat_content": "사진 설명",
    "has_image": 1,
    "sent_at": "2026-10-26T18:00:00",
    "client_message_id": "b87782b2-2e2f-43af-a617-cff3735083bb",
    "live_chat_updated_at": null
  },
  "duplicate": false
}
```

WebSocket 이벤트도 같은 형식이며 이미지 바이너리는 포함하지 않는다.
HTTP 응답과 WebSocket 이벤트가 모두 도착하면 클라이언트는 `chat_seq`와 UUID로 중복을 제거해야 한다.
응답 유실 후 재전송은 동일 UUID·텍스트·파일을 사용한다. 서버는 정규화된 이미지의 SHA-256과
텍스트를 비교해 일치하면 원본을 반환하고 다시 전달하지 않는다. 다른 이미지·텍스트나 이미 삭제된
메시지의 UUID 재사용은 409다. 저장 후 실시간 전달에 실패해도 저장 성공 응답을 유지하며 이력으로 복구한다.

이미지는 `GET /chats/messages/{chat_seq}/image?family_room_id=공간ID`로 조회한다.
Bearer 토큰과 현재 공간 참여 권한이 필요하며 삭제·다른 공간·이미지 없는 메시지는 404다.
새 첨부는 `image/jpeg`, 기존 PNG·WEBP는 해당 형식으로 반환한다.
응답에는 `Cache-Control: private, no-store`, `X-Content-Type-Options: nosniff`를 설정한다.

미인증 401, 참여 권한 없음 403, 이미지 크기 초과 413, 형식·필드 오류 422,
UUID 충돌 409, DB/사용자 조회 실패 503이다. DB 저장 실패는 rollback하며 실시간 전달하지 않는다.

```powershell
python -m unittest python.tests.test_chat_images python.tests.test_chats -v
```

테스트는 DB·Firebase를 대체하며 공유 DB에 메시지를 쓰지 않는다.
실제 DB에서는 이미지 컬럼의 타입을 읽기 전용으로 확인했다.
Flutter 입력창의 사진 버튼으로 갤러리에서 한 장을 선택한다. 선택한 사진은 미리보기에서
교체·제거할 수 있고, 텍스트 없이 사진만 보낼 수도 있다. 사진 선택 취소는 기존 입력을 유지한다.
사진 선택 시 크기를 검사하고 전송 시에도 비어 있지 않은 최대 5MiB의 파일인지 확인한다.
카메라 촬영·다중 사진·동영상 첨부는 지원하지 않는다.

이미지 메시지는 HTTP multipart로 전송하고 텍스트만 있는 메시지는 기존 WebSocket을 사용한다.
전송 중 로컬 사진과 진행 상태를 표시하며 실패하면 같은 UUID·내용·이미지 바이트로 재전송한다.
HTTP 응답과 WebSocket 이벤트는 기존 중복 병합으로 하나의 메시지만 표시한다.
업로드 중 소켓 재연결로 같은 이미지를 중복 업로드하지 않으며,
실시간 저장 확인이 먼저 도착한 경우 늦은 HTTP 오류로 메시지를 실패 상태로 되돌리지 않는다.

이미지가 있는 메시지만 Bearer 인증으로 파일을 별도 조회한다. 말풍선 사진을 누르면
확대 창과 핀치 확대를 제공하며, 조회에 실패하면 `사진 다시 불러오기`로 재시도한다.
사진 선택·업로드·조회 중 계정이나 공간이 바뀌면 이전 결과를 새 화면에 적용하지 않는다.
앱 실행 중 실패한 메시지는 원본을 유지하지만 앱 종료 후 전송 대기 기록 복원은 지원하지 않는다.

```powershell
flutter analyze --no-pub
flutter test --no-pub test/chat_image_test.dart test/chat_test.dart
```

## 메시지 본문 수정·전체 삭제 API

두 API 모두 Firebase Bearer 인증이 필요하며 현재 공간의 활성 참여자인 작성자 본인만 허용한다.
현재 주보호자도 다른 가족의 메시지를 수정·삭제할 수 없다.
기존 수정·삭제 시각 컬럼을 사용하며 테이블 구조는 변경하지 않는다.

### 본문 수정

`PATCH /chats/messages/{chat_seq}`

```json
{
  "family_room_id": "room-a",
  "content": "수정할 본문"
}
```

본문은 앞뒤 공백을 제거하고 최대 4,000자다. 텍스트만 있는 메시지의 본문을 비울 수 없다.
이미지 메시지는 설명을 빈 문자열로 바꿀 수 있으며 첨부 이미지는 그대로 유지한다.
`image`, `remove_image`, 작성자, 요청 UUID 등 다른 필드는 받지 않는다.
실제 내용 변경 시에만 `live_chat_updated_at`을 DB 시각으로 기록한다.
같은 내용의 반복 요청은 200과 `changed: false`를 반환하며 수정 시각과 실시간 전달을 갱신하지 않는다.

HTTP 200 응답은 `type: "message"`, `action: "updated"`, `changed`, `message`로 구성한다.
`message`는 조회 API와 같은 전체 메시지 정보이며 수정된 본문과 수정 시각을 포함한다.

### 메시지 전체 삭제

`DELETE /chats/messages/{chat_seq}?family_room_id=room-a`

`live_chat_deleted_at`에 DB 시각을 기록하는 소프트 삭제다.
DB의 원본 텍스트·이미지는 유지하되, API에서는 원문을 숨기고 이미지 조회는 404로 차단한다.
이미지만 삭제하거나 교체하는 API는 제공하지 않는다.

HTTP 200 응답 예:

```json
{
  "type": "message",
  "action": "deleted",
  "already_deleted": false,
  "message": {
    "chat_seq": 7,
    "family_room_id": "room-a",
    "user_id": "작성자 ID",
    "author_name": "김가족",
    "chat_content": "삭제된 메시지입니다.",
    "has_image": 0,
    "is_deleted": true,
    "live_chat_deleted_at": "2026-10-26T18:02:00"
  }
}
```

예시에서 생략한 `sent_at`, `client_message_id`, `live_chat_updated_at`도 실제 응답에 포함한다.
본인의 이미 삭제된 메시지에 반복 요청하면 `already_deleted: true`이며 추가 변경·전달은 없다.
삭제된 메시지는 수정할 수 없고 409다. 원래 전송 UUID로 재시도해도 삭제 기록을 복원하지 않는다.

### 실시간 전달과 재연결 복구

변경을 commit한 후 현재 참여 권한이 있는 같은 공간의 연결에 HTTP 응답과 동일한 이벤트를 보낸다.
기존 Flutter와 호환되도록 `type: "message"`를 유지하고 `action`으로 수정·삭제를 구분한다.
클라이언트는 기존 `chat_seq`의 말풍선을 갱신한다. 전달 실패가 저장 실패로 바뀌지는 않는다.
참여 상태와 대상 메시지를 잠가 수정·삭제를 직렬화하며, 동시에 서로 다른 본문으로 수정하면
나중에 처리된 수정 내용이 저장된다. 별도의 버전 검사나 수정 이력 저장은 포함하지 않는다.

기존 `after_id` 조회는 새 메시지만 복구하므로 과거 메시지의 수정·삭제를 확인하려면
`POST /chats/messages/refresh`를 사용한다.

```json
{
  "family_room_id": "room-a",
  "message_ids": [7, 8, 9]
}
```

한 요청에 1~100개의 양수 ID를 받으며 중복 ID는 한 번만 조회한다.
`results`에 해당 공간의 최신 메시지와 삭제 표시 기록을 반환하고,
해당 공간에 없는 ID는 `missing_ids`로 반환한다. 다른 공간의 메시지 내용은 반환하지 않는다.
재연결 시 화면에 불러온 ID를 100개씩 나누어 이 API로 갱신하고 새 메시지는 기존 `after_id`로 조회한다.
실시간 이벤트와 늦게 도착한 응답이 경합하는 경우 클라이언트는 필요시 최신 상태를 다시 조회해야 한다.

수정·삭제·refresh의 오류는 미인증 401, 참여/작성자 권한 없음 403, 대상 없음/다른 공간 404,
삭제된 메시지 수정 409, 입력 오류 422, DB 오류 503이다.
Flutter에서는 저장된 본인 메시지를 길게 누르거나 `메시지 메뉴` 버튼을 눌러 수정·삭제한다.
다른 가족·삭제된 메시지·전송 대기 중인 메시지에는 수정·삭제 메뉴가 없다.
수정창은 기존 본문을 불러오며 이미지 메시지는 설명만 바꿀 수 있다.
텍스트 메시지의 빈 내용은 거절하고 실패 시 입력을 보존한다. 처리 중 중복 제출은 차단한다.
저장 후 말풍선에 `수정됨`을 표시하며 삭제는 확인창을 거쳐 메시지 전체에 적용한다.
삭제된 메시지의 사진은 말풍선과 이미 열린 확대 창에서도 숨긴다.

실시간 변경 이벤트를 즉시 반영하고 변경 메시지를 재조회해 서버의 최신 상태를 확인한다.
재연결 시 기존 메시지 ID를 100개씩 refresh로 갱신하며, 새 메시지는 기존 after_id로 복구한다.
각 요청 시작 시점의 메시지 변경 상태를 기록해 그 뒤 도착한 실시간 변경을 늦은 조회 응답이 덮어쓰지 않는다.
이미 삭제된 메시지는 오래된 생성·수정 응답으로 복원하지 않으며, 수정 시각이 더 오래된 응답도 무시한다.
수정 응답 대기 중 같은 메시지의 다른 이벤트가 도착하면 필요시 서버 최신 상태를 다시 확인한다.
계정·공간이 바뀌면 이전 요청을 새 상태에 반영하지 않고, 열려 있는 수정창의 저장을 차단한다.
수정창을 연 뒤 본문이 다른 기기에서 변경되면 창을 닫고 다시 열도록 안내한다.

### 수정·삭제 응답 유실 처리

수정·삭제 요청을 실제로 전송한 뒤 연결이 끊기거나 타임아웃·5xx 오류·잘못된 성공 응답이
발생하면 HTTP 오류만으로 저장 실패를 확정하지 않는다.

1. 요청 이후 받은 실시간/조회 결과가 수정 본문(이미지 유지 포함) 또는 삭제 상태와 일치하면 성공 처리한다.
2. 확인된 결과가 없으면 해당 메시지를 refresh로 한 번 조회해 서버의 최신 상태를 확인한다.
3. 최신 상태가 요청과 일치하면 성공, 다르면 최신 상태를 반영하고 내용을 확인하도록 안내한다.
4. 조회까지 실패해 결과를 확인할 수 없으면 `변경 결과를 확인하지 못했습니다. 다시 연결해 확인해 주세요.`를 표시한다.

기존 캐시만으로 성공을 추정하지 않는다. 조회 대기 중 일치하는 실시간 결과가 도착한 경우도
고려하되 인증·권한 오류를 성공으로 덮어쓰지 않는다. 401·403·422 등 명시적인 클라이언트 오류나
토큰 로딩처럼 요청 전 실패에는 이 저장 확인 절차를 적용하지 않는다.
수정창과 입력은 유지하며 수정·삭제 요청 자체는 자동으로 반복하지 않는다.
결과 확인 중 계정·공간이 바뀌면 이전 요청의 결과를 새 상태에 반영하지 않는다.
별도의 백엔드·테이블 구조 변경 없이 기존 refresh API를 사용한다.

```powershell
python -m unittest python.tests.test_chat_mutations python.tests.test_chats python.tests.test_chat_images -v
```

테스트는 실제 DB·Firebase를 대체하며 공유 DB의 대화를 변경하지 않는다.

## 범위와 제한

- 텍스트·이미지 전송, 본문 수정·전체 삭제·변경 조회·실시간 전달 API를 구현했다. 읽음 API는 포함하지 않는다.
- 공간별 연결은 메모리에 있으므로 단일 프로세스 기준이다. 여러 worker·서버에는 Redis 등 전달 계층이 필요하다.
- Firebase 검증·공간 권한 재확인과 DB 작업은 스레드풀에서 실행하여 이벤트 루프를 막지 않는다.
- 전달 직전 검증은 현재 참여 여부 기준이다. 가입 시점 이전 기록을 숨기는 정책은 적용하지 않았다.
- Firebase/DB 검사 시점 직후에 권한이 변경되는 짧은 경합 구간은 실시간 분산 트랜잭션으로 묶지 않는다.
- 자동 테스트는 실제 MySQL의 스키마 적용이나 실제 Firebase 토큰·네트워크 종단 검증을 대신하지 않는다.

```powershell
python -m unittest python.tests.test_chats -v
```


## Flutter 실행과 확인

현재 선택 공간은 `familyContextProvider`, 토큰은 기존 `apiTokenLoaderProvider`를 사용한다.
별도의 WebSocket 서버 주소를 입력할 필요 없이 API_BASE_URL의 HTTP/HTTPS를 WS/WSS로 변환한다.

```powershell
flutter run --dart-define=API_BASE_URL=http://10.0.2.2:8000
```

실제 휴대폰은 에뮬레이터 주소 대신 PC의 LAN IP를 지정한다.
로그인·프로필 등록·가족 공간 선택 후 실시간 채팅 메뉴를 연다.
채팅 화면은 main.dart 테마를 따르며 새 의존성 추가 없이 기존 web_socket_channel을 사용한다.

- ready 응답의 사용자·공간이 현재 선택 상태와 일치할 때만 연결 완료로 처리한다.
- 전송 중에는 한 메시지의 확인을 기다린다. 다른 연결과 새 메시지 수신은 계속 처리한다.
- 15초 안에 서버 확인이 없거나 연결이 끊기면 전송 확인 실패와 재전송 버튼을 표시한다.
  재전송은 동일 UUID를 사용한다. 저장이 확정됐던 메시지는 이력 복구로도 확인된다.
- 연결이 끊기면 1·2·4·8·16초 간격으로 최대 5회 자동 재연결한다.
  이후 다시 연결 버튼으로 수동 시도할 수 있다. 권한 거절은 자동 반복하지 않는다.
- 서버의 ping에는 pong으로 응답한다. 토큰 만료 후에는 토큰 로더를 다시 호출해 연결한다.
- 처음에는 최신 30개를 가져오고 이전 대화 더 보기로 과거 기록을 조회한다.
- 재연결은 마지막 ID 이후의 모든 페이지를 순서대로 복구하고, 기존 메시지의 수정·삭제는 refresh로 갱신한다.
  실시간 수신·조회·HTTP 변경 응답은 ID로 합쳐 정렬하고 삭제된 원문과 이미지를 표시하지 않는다.
- 화면 종료·계정 또는 공간 변경 시 이전 연결·구독·타이머를 정리한다.
  앱이 백그라운드로 가면 연결을 닫고 복귀 시 연결·누락 이력을 복구한다.
- 본인은 `나`, 다른 가족은 `user.name`으로 표시한다. 이름이 없으면 `이름 없는 가족`을 표시한다.
- 실패 메시지는 화면 메모리에서 유지한다. 앱을 완전히 종료하면 미확정 임시 메시지는 보존하지 않는다.

두 계정·두 기기를 같은 공간에 연결해 메시지 전송·재실행 후 기록 유지·오프라인 후 복구를 확인한다.
서로 다른 공간에는 메시지가 전달되지 않아야 한다. 토큰·공간 권한 검증은 서버에서 수행한다.
실제 Firebase·MySQL을 연결한 종단 테스트는 모의 테스트와 별도로 필요하다.

```powershell
flutter test test/chat_test.dart
```
