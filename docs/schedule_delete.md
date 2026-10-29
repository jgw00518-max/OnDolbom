# 일정 삭제 연동 안내

2026-10-27 기준. 일정 상태 처리는 B, 공통 알림함 화면·도착 표시·예약 재알림은 A의 담당 범위이다.

등록·변경·재수락·만료·재모집을 포함한 전체 유형과 남은 연결은 [전체 일정 알림 연동 안내](schedule_notifications.md)를 참고한다.

## 삭제 처리

- `DELETE /schedules/{schedule_seq}?family_room_id={family_room_id}`
- Firebase 인증 후 현재 공간에 참여 중인 주보호자만 실행할 수 있다. 최초 작성자와 현재 주보호자가 달라도 현재 권한을 기준으로 한다.
- 수락자 승인 없이 삭제한다. `create_schedule.deleted_at`을 기록하고 `accepted_by`를 비운다. 원본과 기존 이력을 보존하며 삭제 처리자의 새 이력을 추가한다.
- 전체 현재 가족을 삭제 알림 수신자로 고정한다. 이전 담당자도 현재 가족이면 포함된다. 탈퇴·참여 종료 가족은 제외한다.
- 알림 준비 실패 시 DB 변경을 rollback한다. DB commit 뒤 발행 실패 시 삭제는 유지하며 `notification_published: false`를 반환한다.
- 같은 삭제를 재요청해도 이력을 추가하지 않는다. `changed: false`로 반환하며 같은 알림 발행을 재시도한다.
- 삭제된 일정은 목록·수정·수락·재수락·일반 만료·긴급 미확인 처리에서 제외한다.

## 삭제 알림 API — A 연동 지점

기존 공통 `/notifications`와 별도로 B의 schedules 폴더에 구현했다. 현재 공통 Flutter 알림함은 기존 API를 사용하므로, 아래 API로 연결하고 문자열 알림 ID와 유형을 처리하는 작업은 A와 통합해야 한다.

| 동작 | 경로 |
| --- | --- |
| 목록 | `GET /schedules/schedule-notifications` |
| 읽음 | `POST /schedules/schedule-notifications/{notification_id}/read` |
| 일정 열기 | `GET /schedules/schedule-notifications/{notification_id}/schedule` |

- `notification_id`: `schedule_deleted_{schedule_seq}_{history_seq}` 문자열이다. 숫자로 변환하지 않는다.
- `notification_type`: `schedule_deleted`.
- 목록에는 `deleted: true`, `deleted_at`, 삭제 당시 일정명·날짜·시작/종료·메모가 포함된다.
- 목록·읽음은 발행된 알림의 수신자이면서 현재도 해당 공간에 참여 중인 가족만 허용한다. 삭제된 공간과 탈퇴 계정은 접근할 수 없다.
- 삭제 알림의 일정 열기는 HTTP **410**과 `삭제된 일정입니다.`를 반환한다. 알림함에서 삭제 안내와 읽음을 처리하고 일반 일정 상세창·수락 버튼을 열지 않는다.
- 삭제 전 등록·변경·재수락 알림은 해당 일정이 삭제되면 조회 대상에서 제외된다.
- 목록의 `next_before_id`를 다음 요청의 `before_id`에 그대로 전달한다.

## 미발행 알림 재시도

API 서버와 별도 터미널에서 프로젝트 최상위 폴더 기준 실행한다.

```powershell
python -m python.features.schedules.reconfirm_expiry_worker
```

- 실행 중 1분마다 확인한다. 코드 변경 후 실행 중인 worker는 Ctrl+C로 종료하고 다시 실행한다.
- `pending` 상태의 삭제 알림을 같은 문서 ID로 재시도한다. 발행 직전 실제 삭제·최신 이력·공간 상태·삭제 당시 내용이 일치하는지 확인한다.
- 이미 발행된 문서를 다시 만들거나 기존 읽음 상태를 초기화하지 않는다.
- 한 알림의 오류가 다른 알림 재시도를 중단하지 않는다.

## 예약 재알림과의 경계

A의 72시간 예약 처리에서는 발송 직전에 `deleted_at IS NULL`과 현재 공간 상태를 반드시 확인해야 한다. 예약 작업이 별도로 저장되어 있다면 삭제 시 취소도 연동한다. 이번 변경은 A의 예약 저장 구조나 알림함 UI를 수정하지 않는다.

## 확인 방법

프로젝트 최상위 폴더에서 다음 검증을 실행한다. 실제 DB나 Firestore를 변경하지 않는 대체 연결을 사용한다.

```powershell
python -B -m unittest python.tests.test_schedule_delete python.tests.test_schedule_query
```

삭제 관련 29개와 기존 월별 조회 7개를 확인한다. 주보호자 제한, 다른 공간 차단, 수락자 유무, 준비 실패 rollback, 발행 실패 후 삭제 유지, 중복 삭제, 삭제 알림 목록·읽음·410, 위조/불일치 알림 차단, 삭제 후 수락·재수락·만료 안내 차단, 삭제 알림 재시도를 포함한다.

앱에서 마지막으로 확인할 항목:

1. 주보호자로 테스트 일정을 열고 일정 삭제 → 취소: 일정·배정 유지, DELETE 요청 없음.
2. 테스트 일정 삭제하기: 상세창이 닫히고 목록에서 제외됨.
3. DB에서 `deleted_at` 값과 `accepted_by IS NULL`, 삭제자의 새 이력 확인.
4. Firestore에서 `schedule_deleted_일정번호_삭제이력번호`의 `published`와 현재 가족 수신자 확인.
5. A의 알림함 통합 후 삭제 안내 조회·읽음과 삭제된 일정 열기 차단 확인.

앱의 취소 동작과 버튼·확인창 디자인, 실제 삭제하기 클릭 후 DB·Firestore 저장까지 사용자 확인을 마쳤다.

확인 사례: 일정 8번 `qwe`(2026-10-27 18:30~19:30)를 삭제하여 2026-10-27 21:09:56에 삭제 이력 23번이 생성됐다. 원본과 삭제 이력의 담당자 필드는 NULL로 정리됐고, `schedule_deleted_8_23` 문서는 현재 가족 4명을 수신자로 보관한 채 21:09:57(한국 시간)에 published 상태가 됐다. 삭제 처리자와 기존 담당자 정보도 보존됐다.
