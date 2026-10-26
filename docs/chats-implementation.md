# 공간별 텍스트 채팅

## 구성

- `python/features/chats/router.py`: 채팅 자체 인증 연결, 이력 조회, WebSocket 인증·저장·전달.
- `python/features/chats/connection_manager.py`: 단일 프로세스의 공간별 연결 관리.
- `python/features/chats/schema.sql`: 기존 `live_chat`에 재전송 식별자와 이모지 문자셋 추가.
- `python/tests/test_chats.py`: 모의 Firebase·DB 기반 HTTP·WebSocket 테스트.
- `python/main.py`: `/chats` 라우터 등록.

- `lib/model/chats/chat_message.dart`: 서버 메시지 JSON 모델.
- `lib/vm/chats/chat_vm.dart`: Riverpod 연결·인증·이력·전송 확인·재연결 상태.
- `lib/view/chats/chat_view.dart`: 가족 채팅 화면, 말풍선·입력·재전송·이전 대화 조회.
- `test/chat_test.dart`: 토큰·전송 확인·UUID 재사용·이력 복구·화면 이동 테스트.

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
이미지 BLOB·삭제된 메시지는 반환하지 않는다.
이력과 실시간 메시지, 재전송 응답은 `user.name`을 `author_name`으로 반환한다.
Flutter는 저장된 본인·다른 가족 메시지 모두 이 이름을 표시하며 이름이 비어 있으면 `이름 없는 가족`을 표시한다.
`user_id`는 본인 메시지 구분·인증·중복 처리용 식별자로 유지한다.

```json
{
  "results": [{
    "chat_seq": 7,
    "family_room_id": "room-a",
    "user_id": "서버가 결정한 내부 사용자 ID",
    "author_name": "김가족",
    "chat_content": "안녕하세요 😀",
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
- 페이지가 비어 있으면 results는 빈 배열이다. 새 참여자는 현재 공간의 과거 텍스트도 조회할 수 있다.
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

## 범위와 제한

- 텍스트 전송·이력·인증·중복 방지까지 구현했다. 이미지·읽음·수정·삭제 API는 포함하지 않는다.
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
- 재연결은 마지막 ID 이후의 모든 페이지를 순서대로 복구하며, 실시간 수신과 ID로 합쳐 정렬한다.
- 화면 종료·계정 또는 공간 변경 시 이전 연결·구독·타이머를 정리한다.
  앱이 백그라운드로 가면 연결을 닫고 복귀 시 연결·누락 이력을 복구한다.
- 다른 가족 이름 조회는 아직 추가하지 않았으며 본인은 나, 다른 작성자는 내부 user_id로 표시한다.
- 실패 메시지는 화면 메모리에서 유지한다. 앱을 완전히 종료하면 미확정 임시 메시지는 보존하지 않는다.

두 계정·두 기기를 같은 공간에 연결해 메시지 전송·재실행 후 기록 유지·오프라인 후 복구를 확인한다.
서로 다른 공간에는 메시지가 전달되지 않아야 한다. 토큰·공간 권한 검증은 서버에서 수행한다.
실제 Firebase·MySQL을 연결한 종단 테스트는 모의 테스트와 별도로 필요하다.

```powershell
flutter test test/chat_test.dart
```
