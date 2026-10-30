# 채팅 읽음·미읽음 배지·FCM

## 로컬 DB 적용 내용

`python/features/chats/notifications_schema.sql`을 로컬 `ondolbom`에 적용했다. 기존 `live_chat`, `participate`, 사용자·공간 테이블의 컬럼은 변경하지 않았다.

| 새 테이블 | 주요 컬럼 | 연결 |
|---|---|---|
| `chat_read_status` | `participate_seq` PK, `last_read_chat_seq`, `last_read_at`, `updated_at` | `participate.participate_seq` FK |
| `chat_push_outbox` | `chat_seq`, `family_room_id`, `user_id` 복합 PK, `status`, `attempts`, `next_attempt_at`, `lease_until`, `lease_token`, `created_at` | `live_chat`의 같은 복합 키에 FK |

- 마지막 읽음 번호는 공간 내 메시지인지 서버에서 검증하는 커서다. `live_chat.chat_seq` 단독 FK를 추가하지 않는다.
- 최초 도입 시 현재 참여 2건의 읽음 위치를 각 공간의 최신 메시지까지 초기화했다. 이후 새 메시지부터 미읽음으로 계산한다. 기존 메시지와 참여를 삭제하지 않는다.
- SQL 재실행은 이미 존재하는 읽음 위치를 덮어쓰지 않는다. 초대 수락 시 새 참여 행의 읽음 위치도 현재 최신 메시지로 초기화한다. 과거 대화 조회 권한은 유지한다.
- 공유 DB나 다른 로컬 DB를 사용할 팀원은 **API/worker 실행 전에 같은 SQL을 적용**해야 한다. 이 프로젝트는 스키마를 서버 시작 시 자동 생성하지 않는다.

## 동작

1. 텍스트·이미지는 기존 채팅 API가 저장한다. 동일 트랜잭션에서 새 메시지에 대한 푸시 대기 행도 저장한다.
2. 같은 `client_message_id`의 재전송은 기존 메시지를 반환하고 새 대기 행을 생성하지 않는다.
3. 앱은 `GET /chats/unread`로 현재 참여 공간별 미읽음 수를 받아 공간 홈의 실시간 채팅 메뉴에 숫자를 표시한다. 본인 메시지·삭제된 메시지·종료된 공간은 제외한다.
4. 실제로 열린 채팅 화면에 반영된 최신 번호까지 `POST /chats/read` (`family_room_id`, `chat_seq`)로 읽음 처리한다. 다른 화면이 위에 있거나 앱이 백그라운드면 읽음 처리하지 않는다. 요청은 300ms로 묶는다. 실패 시 다시 시도 버튼을 표시한다.
5. 여러 기기의 늦은 읽음 요청이 위치를 되돌리지 않도록 DB에서 `GREATEST`로 갱신한다. 채팅방 진입 시 이전 미읽음도 최신 조회 번호까지 읽음으로 처리한다.
6. 기존 알림 worker가 MySQL 채팅 큐를 약 5초 간격으로 검사한다. 현재 참여 중인 다른 가족에게만 FCM을 발송하며 발송 직전에 읽음·삭제·탈퇴·계정 연결을 다시 확인한다. 이미 읽은 메시지는 발송을 건너뛴다.
7. 앱 실행 중에는 실제 해당 메시지가 열린 채팅 화면에 반영됐는지 확인해 기기 알림 표시를 생략한다. 그렇지 않으면 기기 알림을 표시한다. 같은 공간의 기기 알림은 같은 태그로 갱신한다.
8. 푸시를 누르면 인증·프로필·최신 참여 공간을 확인한 뒤 해당 공간을 선택하고 채팅방을 연다. 접근 종료된 공간은 열지 않는다.

미읽음 수는 MySQL에서 계산하며 별도 `unread_count` 컬럼을 두지 않는다. 갱신 시점은 공간 선택/목록 갱신, 채팅 화면 복귀·읽음 완료, 채팅 푸시 수신, 앱 복귀와 앱 사용 중 5분 보조 갱신이다.

## 푸시 저장소·재시도

- MySQL: 원본 채팅, 읽음 위치, 푸시 대기.
- Firebase: 기존 `push_devices` 및 `push_deliveries` 재사용, FCM 발송. **메시지마다 Firestore 일반 알림 문서를 만들지는 않지만 기기·발송 기록 조회/쓰기는 발생한다.**
- 잠금 화면에는 채팅 원문·사진·건강정보 대신 일반 도착 안내만 보낸다.
- MySQL 큐는 잠금·2분 임대·임대 토큰으로 동시 처리를 조절하고 기존 기기별 발송 기록을 재사용한다. 30초부터 간격을 늘려 최대 5회 재시도한다. 최종 실패는 `failed`로 남고, 성공·읽음/권한으로 건너뜀은 `done`이다.
- 외부 FCM 전송과 DB/Firestore 상태 확정은 하나의 트랜잭션이 아니므로, 전송 성공 직후 기록 실패 같은 장애에서 정확히 한 번을 보장하지 않는다. 기기 알림 태그와 발송 기록으로 중복을 줄인다.
- 일정 Firestore 큐 검사 실패와 채팅 큐 검사는 분리한다. 다만 Firebase 기기 조회 자체가 한도/연결 오류면 채팅 푸시도 실패·재시도할 수 있다. 미읽음 숫자와 채팅 조회는 MySQL을 사용한다.

## 실행과 검증

프로젝트 루트에서 API와 기존 worker를 실행한다. 별도의 두 번째 worker를 만들 필요는 없다.

```powershell
python -m uvicorn python.main:app --host 0.0.0.0 --port 8000 --reload --no-access-log
```

다른 터미널:

```powershell
python -m python.features.schedules.reminder_worker
```

- worker와 API는 같은 MySQL·Firebase 프로젝트 설정을 사용해야 한다. 팀원이 서로 다른 로컬 DB를 사용하면 각 DB의 큐는 서로 공유되지 않는다. 공유 개발 DB에서는 대표 worker 한 곳만 실행한다.
- 기존 WebSocket 전달은 단일 API 프로세스의 연결 목록을 사용한다. 두 기기의 실시간 대화 검증은 같은 API 서버로 연결한다. 이번 작업은 여러 API 서버 간 WebSocket 중계를 추가하지 않는다.
- 자동 검증: `python -m unittest python.tests.test_chat_notifications python.tests.test_chats python.tests.test_chat_images python.tests.features.test_push`
- 앱 검증: `flutter test test/chat_notifications_test.dart test/push_service_test.dart test/push_bridge_test.dart`
- 실제 MySQL에서는 별도 연결의 임시 테이블로 미읽음 계산·단조 읽음 갱신·공간 검사·큐 임대/완료를 검증했다. 임시 데이터는 연결 종료 시 삭제되며 실제 메시지나 푸시는 생성하지 않았다.
- 기기 확인: 같은 공간의 계정 A/B → B가 다른 화면/백그라운드일 때 A가 텍스트·사진 전송 → B의 푸시·채팅 숫자 증가 → 푸시 클릭 → 해당 채팅방 진입과 숫자 해제. A에게 자기 메시지 알림이 없는지, 읽은/삭제된/탈퇴한 대상에게 지연 푸시가 가지 않는지도 확인한다.


## 통합 실행 안내

기존 `python -m python.features.schedules.reminder_worker` 명령이 재수락 기한 만료·긴급 미확인 검사와 미발행 재시도까지 함께 시작한다. 별도 재수락 worker는 중복 실행하지 않는다. 작업별 주기·종료·전환 방법은 [통합 알림 worker](notification-worker.md)를 따른다.
