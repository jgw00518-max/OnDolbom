# Firebase 일정 등록 알림

## 일정 번호 재사용 충돌 처리

- 일정 등록 로그에 `Schedule identity mismatch`가 기록되고 503이 발생하던 문제를 수정했다. 동일한 숫자 `schedule_seq`의 과거 Firestore 문서가 다른 공간·생성 시각을 가리키면 새 일정 등록까지 롤백되던 경우다.
- 충돌이 없으면 기존 숫자 문서 ID를 유지한다. 충돌이 있으면 `schedule_created_{schedule_seq}_{공간·생성 시각 해시}` 문서를 새로 준비하며 과거 문서와 읽음·삭제 기록을 덮어쓰거나 삭제하지 않는다.
- 앱이 사용하는 V2 알림함은 문자열 `notification_id`와 기존 읽음·삭제 API를 그대로 사용한다. 같은 일정 재시도는 같은 문서를 재사용해 수신자·읽음 상태를 유지한다.
- 발행은 DB의 공간 ID·일정 생성 시각과 일치하는 문서만 허용한다. 기존 통합 worker와 등록 알림 재시도 명령은 숫자·문자열 ID를 모두 지원하며, 과거 pending 문서로 재사용된 다른 일정을 발행하지 않는다.
- 발행 후보 확인에 건별 문서 조회가 추가된다(기본 1건, 충돌 시 최대 2건). 기존 pending 조회를 재사용하며 전체 조회나 새 반복 조회 주기를 추가하지 않는다.
- MySQL 구조·데이터 변경이나 Firestore 정리는 필요 없다. API·담당 worker를 재시작하면 적용된다. 검증: `python -m unittest python.tests.features.test_registration_collision`. 실제 일정 생성 없이 DB·Firestore를 모의 처리한다.

## 구현 범위

앱 내 알림 원본과 개인별 읽음 상태를 **Firebase Cloud Firestore**에 저장한다.
Firebase Authentication은 로그인 확인용이다. FCM 기기 푸시와 실시간 구독은 이번 범위에 포함하지 않는다.
Flutter는 기존 FastAPI를 통해 조회하므로 cloud_firestore 패키지가 필요 없다.
이전 MySQL notification 테이블 생성 SQL과 저장 코드는 제거했다. 공유 DB에는 적용한 적이 없다.
일정·현재 가족 참여 정보는 기존 MySQL에서 검증하며 알림 기능 때문에 새 MySQL 테이블을 만들지 않는다.

## 먼저 필요한 Firebase 설정

1. 기존 ondolbom-3125e 프로젝트에서 Firestore Database → 데이터베이스 만들기를 선택한다.
2. 기본 `(default)` 데이터베이스를 운영 모드로 생성한다. 팀과 사용할 위치를 정한다.
3. 서버는 기존 Firebase Admin 서비스 계정 키를 사용한다. 키를 Git에 올리지 않는다.
4. `firestore.indexes.json`의 복합 색인을 콘솔에서 생성한다. 컬렉션 schedule_notifications,
   recipient_ids 배열 포함, status 오름차순, schedule_seq 내림차순이다.
5. `firestore.rules`는 알림 컬렉션의 앱 직접 접근을 차단하는 예시다.
   기존 규칙이 있다면 해당 match를 병합하고, 다른 규칙에서 알림 접근을 허용하지 않는지 확인한다.
   Admin SDK 권한은 규칙이 아닌 서비스 계정 IAM으로 관리한다.

데이터베이스 생성·위치 선택·색인/규칙 배포는 이 코드 변경으로 자동 실행하지 않는다.
기존 firebase.json도 다른 설정 보호를 위해 변경하지 않았다. 규칙 파일을 무조건 덮어쓰지 않는다.

## 저장 구조

- `schedule_notifications/{schedule_seq}`: 일정당 하나의 이벤트.
  family_room_id, schedule_seq, schedule_created_at(일정 식별 검증용), recipient_ids,
  status(pending/published), created_at, published_at.
- 하위 `reads/{내부 사용자 ID의 SHA256}`: read_at. 최초 읽음 시간을 트랜잭션으로 유지한다.
- recipient_ids는 Firebase UID가 아닌 MySQL 내부 user_id다. 이름·전화번호·메모는 저장하지 않는다.
- API notification_id는 schedule_seq와 같다. 수신자별 읽음 상태는 별도로 저장한다.
- Firestore 시각은 서버 타임스탬프(UTC), 일정 날짜·시간은 MySQL 값이다.
- 탈퇴·강퇴·공간/일정 삭제 시 서버가 현재 권한을 재검사해 목록·상세·읽음을 차단한다.
  물리적인 Firestore 기록 정리는 별도 수명주기 작업이며 이번 구현은 접근 차단까지다.

## 일정 담당자가 연결할 순서

현재 저장소에는 일정 등록 API가 없어 자동 호출 연결은 아직 할 수 없다.
등록 담당자는 인증·공간 권한·시간 중복 검사 후 다음 흐름을 연결한다.

```python
from python.features.notifications.schedule_notifications import (
    prepare_schedule_notifications, publish_schedule_notifications,
)

# connection은 일정 INSERT에 사용하는 MySQL 연결이다.
try:
    # 일정 INSERT 후 schedule_seq 확보
    prepare_schedule_notifications(connection, schedule_seq)
    connection.commit()
except Exception:
    connection.rollback()
    raise

# commit 완료 뒤 실행한다. 실패해도 이미 저장한 일정을 rollback했다고 응답하면 안 된다.
try:
    publish_schedule_notifications(schedule_seq)
except Exception:
    # 운영 로그/재시도 대상으로 남긴다. 아래 재시도 명령으로 복구할 수 있다.
    pass
```

준비 단계는 등록자를 포함한 현재 전체 가족을 고정하고 pending 문서를 저장한다.
MySQL commit 전에는 앱에 표시하지 않는다. 발행 단계는 새 연결로 확정된 일정을 확인한 뒤
published로 변경한다. 반복 호출은 같은 문서를 사용해 중복·읽음 초기화를 막는다.
Firestore와 MySQL은 하나의 원자적 트랜잭션이 아니므로 commit 직후 장애는 재시도로 복구한다.
서버 운영 시 아래 명령을 주기적으로 실행하도록 작업 스케줄러 등에 등록해야 한다.

```powershell
python -m python.features.notifications.retry_pending
```

이 명령은 pending을 다시 확인한다. rollback되어 존재하지 않는 일정은 발행하지 않고 남겨둔다.
실패 기록/오래된 pending 정리는 운영 정책을 정한 후 추가한다.
대규모 가족 공간은 Firestore 문서 크기 제한을 고려해 수신자 문서 분리가 필요하다.

## API·화면

Firebase ID 토큰이 필요하다. 사용자 ID를 요청으로 받아 다른 사람 알림을 조회하지 않는다.

| API | 동작 |
| --- | --- |
| GET /notifications | 내 알림 최신순 목록 |
| GET /notifications?before_id=7&limit=30 | 다음 페이지(최대 100건) |
| GET /notifications/{id}/schedule | 현재 권한으로 일정 내용 확인 |
| POST /notifications/{id}/read | 개인별 최초 읽음 기록 |

응답 목록은 results와 next_before_id다. 권한 없는 항목을 제외해 빈 페이지라도 다음 커서가 있을 수 있다.
401 인증, 403 프로필 미등록, 404 접근 불가, 503 DB/Firestore 설정·색인·연결 오류다.
홈의 알림 아이콘에서 목록·새로고침·더보기·상세 대화상자를 이용한다.
알림을 선택해도 일정을 자동 수락하지 않는다. 실제 일정 상세 화면 연결은 담당자와 통합한다.

## 검증 순서

1. Firestore와 색인을 준비하고 서버를 재시작한다.
2. 일정 담당자의 등록 API에 준비/발행 함수를 연결한다.
3. 등록자와 다른 참여 가족 모두 목록을 확인한다. 참여 종료 가족은 받지 않아야 한다.
4. 읽음 시간이 계정별로 다르며 반복 읽기에도 최초 시간이 유지되는지 확인한다.
5. 함수 재호출, commit 실패, 발행 실패 후 재시도를 검증한다.
6. 탈퇴·강퇴·삭제 후 직접 상세/읽음 요청도 차단되는지 확인한다.

자동 테스트는 대체 객체를 사용한다. 실제 Firestore 권한·색인·가족 전달 검증을 대신하지 않는다.

## 목록 중복 표시 점검

- 같은 알림 ID가 최초 응답 또는 추가 조회 페이지에 반복되면 Flutter VM에서 한 항목으로 합친다. 추가 조회 도중 완료된 읽음 상태도 보존한다.
- 내용이 같아도 ID가 다른 실제 일정 변경·재수락 이벤트는 숨기지 않는다. API 서버 수만으로 중복이라고 판단하지 않는다. 등록 알림은 일정 번호, 변경 알림은 종류·일정 번호·이력 번호, 72시간 알림은 시작 시간 버전으로 Firestore 문서를 식별하고 트랜잭션으로 생성한다.
- 중복 신고 시 동일 notification_id인지, notification_type·schedule_seq·history_seq·reminder_key가 같은지 먼저 확인한다. 서로 다른 변경 이력이 최신 일정 내용으로 표시되는 경우도 있어 제목만으로 같은 이벤트인지 판단할 수 없다.
- 2026-10-29 점검 당시 Firestore ResourceExhausted로 실문서 조회는 실패했다. 기존 문서를 삭제하거나 서로 다른 ID를 임의로 병합하지 않았다.


### 알림 모두 읽음

`POST /schedules/schedule-notifications/read-all`은 본인이 현재 조회할 수 있는 미읽음 알림을 모든 페이지에서 찾아 개인 Firestore 읽음 기록만 갱신합니다. 삭제된 알림과 기존 읽음 기록은 제외하며 다른 가족의 상태는 변경하지 않습니다. 성공 후 목록과 배지를 갱신하고, 처리 중 새로 도착한 알림은 재조회 결과에 따릅니다. DB 테이블 변경은 없습니다.
