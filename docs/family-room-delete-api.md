# 가족 공간 소프트 삭제 API

```http
DELETE /family-room/{family_room_id}
Authorization: Bearer <Firebase ID 토큰>
```

요청 본문은 필요하지 않다. 공간 ID는 공백 없는 1~50자다.
검증된 Firebase UID에 연결된 미탈퇴 계정의 내부 사용자 ID로 권한을 확인한다.
공간의 최초 생성자가 아닌 **현재 활성 참여 중인 주보호자**만 삭제할 수 있다.
조건은 `participate.is_active = 1`, `left_at IS NULL`, `is_representative = 1`, 사용자 미탈퇴다.

성공 응답은 HTTP 200이다.

```json
{
  "result": "OK",
  "family_room_id": "공간ID",
  "family_room_deleted_at": "2026-10-27T17:30:00",
  "already_deleted": false
}
```

## 데이터 보존과 중복 요청

- 공간 행을 먼저 잠근 뒤 주보호자 참여·사용자 행을 확인하고 잠근다.
- `family_room.family_room_deleted_at`만 DB 현재 시각으로 갱신한다.
- 일정·투약일지·메모·채팅·이미지 BLOB·좋아요·참여·초대·문의·답변을 변경하거나 삭제하지 않는다.
- 참여의 `is_active`, `left_at` 및 개별 기록의 삭제 시각도 유지한다.
- 성공 시 한 번 commit하고, DB 실패 시 rollback하며 연결을 닫는다.
- 삭제 트랜잭션 안에서 현재 활성 참여·미탈퇴 가족을 수신자로 확정하고 `family_room_deleted` 알림을 Firestore에 `pending`으로 준비한다. 실제 삭제 작업자는 제외한다. 알림 준비 실패 시 공간 삭제도 rollback한다.
- DB commit 후 알림을 발행하며, 발행 실패 시 공간 삭제는 유지하고 기존 통합 worker가 미발행 알림을 재시도한다. 삭제 시각·공간 생성 시각이 DB와 일치하는 이벤트만 발행한다.
- 중복 삭제는 현재 주보호자 권한을 다시 확인한 후 HTTP 200과 `already_deleted: true`를 반환한다.
  최초 삭제 시각을 유지하고 UPDATE는 다시 수행하지 않는다.
- 같은 공간의 삭제 요청은 공간 행 잠금으로 직렬화된다.
- 새 테이블·컬럼·마이그레이션은 추가하지 않는다. 복구 API와 하드 삭제는 포함하지 않는다.

## 연결·접근 차단

DB commit이 성공한 후 현재 서버 프로세스의 해당 공간 채팅 연결을 목록에서 제거하고 `4403`으로 종료한다.
다른 공간의 연결은 유지한다. 개별 소켓 종료 실패는 이미 확정된 공간 삭제를 실패로 바꾸지 않는다.
새 채팅 연결과 이후 송수신은 기존 참여 검사에서 삭제된 공간 접근을 거절한다.

현재 연결 관리자는 단일 프로세스의 메모리 구조다. 다른 프로세스의 연결이나
삭제 직전 인증을 마치고 뒤늦게 등록된 연결은 기존 송수신 검사·유휴 30초 검사로 종료된다.
모든 서버에서 즉시 종료하려면 별도 프로세스 간 이벤트 전달이 필요하다.

기존 기능의 `family_room_deleted_at IS NULL` 검사로 공간 목록 노출과 메모·채팅·투약일지·일정·이미지·내보내기 접근을 차단한다.
초대 생성·수락 등도 기존 공간 검사를 사용하며 초대 원본은 보존한다.
일정 알림은 기존 준비·발행·조회 시 공간 상태를 확인한다. 삭제된 공간의 pending 알림은
재발행되지 않지만 Firestore 원본 이벤트는 보존된다. 삭제 검사 직후 이미 진행 중인 외부 발송까지
분산 트랜잭션으로 취소하지는 않는다. 별도 푸시·예약 발송기를 추가하면 발송 직전 공간 상태를 검사해야 한다.

문의·답변은 개인 문의 이력으로 보존하며 기존 정책대로 작성자 본인 조회를 허용한다.
이미 사용자의 기기에 저장된 ZIP·PDF는 서버에서 회수하지 않는다.
## Flutter 연결

현재 활성 주보호자에게 가족 공간 홈 우측 상단 `⋮` 메뉴를 표시한다.
`가족 공간 삭제`를 누르면 아래 내용을 가진 확인창을 연다.

- 제목: `가족 공간을 삭제할까요?`
- 설명: `모든 가족이 이 공간을 이용할 수 없게 됩니다.`
- 돌봄 대상자 이름을 입력하는 TextField
- `공간 삭제`, `취소` 버튼

입력 앞뒤 공백을 제거한 이름이 현재 돌봄 대상자 이름과 일치할 때만 삭제 버튼을 활성화한다.
이름 확인은 앱의 실수 방지 장치이며 서버 권한 검사를 대신하지 않는다. API 본문에 이름은 보내지 않는다.
요청 직전과 토큰·응답 수신 후 계정·선택 공간·대상자 이름·주보호자 참여 상태를 다시 검사한다.
처리 중에는 입력·중복 요청·취소·뒤로가기를 막는다. 오류 시 입력과 공간 목록을 보존하고 재시도를 허용한다.
시간 초과는 삭제 실패로 단정하지 않고 결과 재확인을 안내한다. API가 중복 요청을 지원하므로 다시 요청할 수 있다.
성공 시 해당 공간만 앱 목록·선택에서 제거하고 가족 공간 목록으로 돌아가 서버 목록을 새로 조회한다.

구현은 `lib/view/family_room/family_room_delete_dialog.dart`, `family_room_home.dart`,
`lib/vm/family_room/family_room_notifier.dart`에 있다.

## 공간 삭제 알림

- 삭제 당시 활성 참여 중인 미탈퇴 가족에게 앱 알림함·배지·FCM을 연결한다. 삭제 작업자, 이미 나간 가족·강퇴된 가족·탈퇴 계정은 제외한다.
- 기존 `schedule_notifications` 컬렉션에 `notification_type=family_room_deleted`, `family_room_id`, `room_created_at`, `room_deleted_at`, `care_recipient_name`, `actor_id`, `recipient_ids`를 저장한다. 공간 ID·생성 시각·삭제 시각 해시로 문서를 식별해 중복 삭제 요청과 worker 재시도가 읽음 상태를 초기화하거나 푸시를 다시 예약하지 않는다.
- 기존 `GET /schedules/schedule-notifications?scope=v2`, `/activity/badges`, 개별/전체 읽음·삭제 API에 포함된다. 일정 번호나 일정 날짜·시간은 만들지 않는다.
- `GET /schedules/schedule-notifications/{notification_id}/room`은 Firebase 인증 및 최초 수신자·현재 미탈퇴 계정·삭제 당시 참여·공간 생성/삭제 시각을 재검사한 뒤 삭제 안내만 반환한다. 비수신자는 404이며 `/schedule`로 일정 진입을 시도하면 410이다. 일반 공간·일정·채팅 접근 차단은 유지한다.
- 앱은 전용 제목·아이콘과 삭제 시각 안내창을 표시한다. 앱 실행 중 푸시 수신 시 알림함·배지·공간 목록도 갱신한다. 잠금 화면 푸시에는 대상자 이름·건강정보를 포함하지 않는다.
- FCM과 미발행 재시도는 [기존 통합 worker](notification-worker.md)를 알림 담당자 한 명이 별도로 실행해야 동작한다. API는 worker를 자동 실행하지 않는다. 성공 응답은 공간 삭제 확정을 뜻하며 실제 기기 도착·읽음의 보장은 아니다.
- 과거 이미 삭제되어 `pending` 알림이 없는 공간은 소급 발송하지 않는다. 기존 pending 조회·푸시 큐를 재사용하며 주기나 전체 조회를 추가하지 않는다. MySQL 스키마·Firestore 색인 추가는 없다. API·담당 worker 재시작과 Flutter 앱 Hot Restart 후 적용한다.

검증은 `python -m unittest python.tests.test_family_room_delete_notifications python.tests.test_family_room_delete`와
`flutter test test/room_deletion_notification_test.dart`로 수행한다. DB·Firestore·FCM을 모의 처리하며 실제 공간을 삭제하거나 실제 푸시를 발송하지 않는다.

## 오류와 검증

| HTTP | 의미 |
| --- | --- |
| 401 | Firebase 토큰 누락·유효하지 않음 |
| 403 | 사용자 미등록·탈퇴, 현재 활성 주보호자 권한 없음 |
| 404 | 가족 공간 없음 |
| 422 | 잘못된 공간 ID |
| 503 | 인증 서비스·DB 설정·조회·저장 실패 |

```powershell
python -m unittest python.tests.test_family_room_delete python.tests.test_chats -v
flutter test --no-pub test/family_room_delete_test.dart test/family_care_connection_test.dart
```

테스트는 실제 DB와 Firebase를 대체한다. 데이터 보존 SQL, 권한, 중복 요청, 실패 시 연결 유지,
실제 TestClient WebSocket의 삭제 후 종료·재접속 거절·다른 공간 연결 유지를 검증한다.
