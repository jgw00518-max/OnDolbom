# 일정 알림 전체 연동 안내

2026-10-27 실제 구현 기준. 정책상 필요한 항목과 현재 코드에 연결된 항목을 구분한다. 삭제 세부 처리와 실제 확인 결과는 [삭제 연동 안내](schedule_delete.md)를 함께 참고한다.

> 최신 후속: [9. 2026-10-29 자동 만료 알림 A/B 인수인계](#9-2026-10-29-자동-만료-알림-ab-인수인계)를 우선 참고한다. 아래 2026-10-27의 공통 알림함 미통합 설명은 당시 기록이며, 현재 V2 연결 상태는 9절과 `notification-v2-integration.md`로 구분한다.

## 담당 범위

- B: 일정 변경·재수락·응답·만료·삭제 처리, 변경 이력, 알림 대상 계산, Firestore 준비·발행, 일정 전용 알림 조회/읽음 API.
- A: 공통 알림함 모델·목록·아이콘·읽지 않음 표시·배지·기기 알림/푸시, 알림에서 일정 상세로 이동, 72시간 예약 재알림과 상태 변경 연동.
- B의 추가 처리는 `python/features/schedules/`에 두고 기존 공통 저장 함수를 재사용했다. A의 공통 notifications 파일과 Flutter 알림함은 이번 작업에서 수정하지 않았다.
- Firestore `published` 기록과 앱 알림함·기기 도착 표시의 구현 범위는 구분한다.

## 1. 연결할 알림 8종

| notification_type | 발생 상황 | 수신자 | 앱 처리 방향 |
| --- | --- | --- | --- |
| `schedule_created` | 일정 등록. 기존 Firestore 등록 문서에는 유형 필드가 없고 새 조회 API가 기본 유형으로 반환 | 등록자를 포함한 현재 전체 가족 | 새 일정 안내, 현재 일정 확인 |
| `schedule_changed` | 기존 담당자가 있는 일정의 이름·메모만 변경. 재수락 대기 중 이름·메모 추가 변경도 포함 | 기존 담당자 1명 | 변경 안내. 이름·메모 변경만으로 새 재수락 요청을 만들지 않음 |
| `schedule_reconfirm` | 기존 담당자가 있는 일정의 날짜·시작·종료 중 하나 이상 변경 | 기존 담당자 1명 | 최신 일정과 변경 전후 비교 확인. 현재 요청일 때만 기존 담당자가 재수락/거절 |
| `schedule_recruitment` | 재수락 거절 후 재모집, 또는 일반 무응답 만료 후 일정 시작 전 재모집 | 주보호자·기존 담당자를 포함한 현재 전체 가족 | 현재 모집 상태를 다시 조회하고 수락 가능 여부 표시 |
| `schedule_reconfirm_expired` | 일반 재수락 요청 기한 만료와 배정 해제 | 현재 가족으로 남아 있는 기존 담당자 | 요청 만료·배정 해제 안내 |
| `schedule_reconfirm_unanswered` | 일반 재수락 기한까지 담당자 무응답 | 현재 주보호자 | 담당자의 미응답·배정 해제 안내 |
| `schedule_reconfirm_unverified` | 긴급 재수락이 시작 시각까지 미응답 | 현재 주보호자 | 직접 확인 안내. 자동 수락·거절·배정 해제 없음 |
| `schedule_deleted` | 주보호자가 일정을 삭제 | 현재 전체 가족, 기존 담당자가 현재 가족이면 포함 | 삭제 안내·읽음 처리. 일반 일정 상세 열기 차단 |

- 수신자 ID는 MySQL `user.user_id`이며 Firebase UID와 구분한다. 화면 입력으로 수신 대상을 선택하지 않는다.
- 등록·삭제·재모집의 전체 가족에는 주보호자도 포함한다. 참여 종료·탈퇴 가족은 준비 시 제외하며 조회 시에도 현재 권한을 재확인한다.
- 재수락 성공 시 전체 가족 추가 알림은 없다. 별도 `schedule_reconfirmed` 또는 `schedule_declined` 유형은 만들지 않았다. 거절 후 전체 알림은 `schedule_recruitment`이다.
- 날짜/시간과 이름/메모를 함께 변경하면 재수락 요청으로 함께 안내한다. 별도 이름·메모 변경 알림을 중복 발행하지 않는다.
- 긴급 변경 저장 직후 주보호자에게 나오는 전화 안내 팝업은 일정 편집 화면에서 처리한다. 이때 담당자는 `schedule_reconfirm`을 받고, 시작 이후 미확인일 때 주보호자가 `schedule_reconfirm_unverified`를 받는다.

## 2. ID·저장 형식

- 컬렉션: `schedule_notifications`.
- 기존 등록 문서 ID: 일정 번호의 십진수 문자열(예: `8`).
- 새 유형의 문서 ID: `{notification_type}_{schedule_seq}_{history_seq}`.
- 예: `schedule_changed_13_13`, `schedule_reconfirm_13_14`, `schedule_deleted_8_23`.
- 긴급 미확인 유형의 이력 번호는 최신 메모 이력이 아닌 최초 재수락 요청 이력이다. 메모 추가 변경으로 미확인 안내가 중복 생성되지 않는다.
- 만료·미응답 유형의 이력 번호는 자동 배정 해제 이력이며, 원래 요청 번호는 Firestore의 `request_history_seq`에 보관한다.
- `status`: `pending` 준비 → DB 확정 확인 후 `published`.
- 같은 문서 ID로 재시도하며 최초 수신자와 읽음 상태를 보존한다.
- 준비 실패 시 해당 DB 작업을 rollback한다. commit 이후 발행 실패 시 저장한 일정·응답·삭제는 유지한다.

## 3. 공통 알림함에서 사용할 API

모든 요청에 Firebase Bearer 토큰이 필요하다. 사용자의 현재 MySQL 계정·가족 공간 참여 권한을 서버에서 확인한다.

| 동작 | 경로 |
| --- | --- |
| 목록 | `GET /schedules/schedule-notifications?limit=30&before_id={cursor}` |
| 읽음 | `POST /schedules/schedule-notifications/{notification_id}/read` |
| 현재 일정 정보 확인 | `GET /schedules/schedule-notifications/{notification_id}/schedule` |

- 목록 응답: `results`, `next_before_id`.
- 알림 항목의 `notification_id`와 페이지 커서는 문자열로 다룬다. `next_before_id`가 null이면 마지막 페이지이다.
- 현재 A의 Flutter 구현은 `/notifications`, 숫자형 `id`·`nextBeforeId`, `open(int)`를 사용하므로 위 경로와 문자열 계약으로 통합해야 한다.
- 모델에 `notification_type`을 반영하고 유형별 제목·안내·이동 동작을 구분한다. 기존 등록 유형의 기본값은 `schedule_created`이다.
- Firestore의 내부 처리 필드가 모두 API에 그대로 노출되는 구조는 아니다. 현재 API는 유형·ID·이력 번호·일정 표시 정보·읽음 시각을 반환하고, 삭제 유형에는 `deleted`, `deleted_at`을 더한다.
- 일반 알림의 일정 표시 정보는 MySQL의 최신 내용이다. 모든 알림이 발송 당시 전체 내용의 고정 스냅샷을 반환하는 것은 아니다. 삭제 유형은 삭제 당시 전체 내용과 DB 이력을 대조하여 반환한다.

## 4. 알림을 눌렀을 때의 처리

### 삭제 안내

1. `notification_type == schedule_deleted`이면 삭제 안내를 표시하고 읽음 API를 호출한다.
2. 일반 일정 상세창이나 수락 버튼을 열지 않는다.
3. 일정 정보 확인 경로를 호출하면 410 `삭제된 일정입니다.`가 반환된다.
4. 현재 A의 `open()`은 일정 조회 성공 후 읽음을 호출하므로, 삭제 유형은 이 순서를 분리해야 읽음 처리할 수 있다.

### 그 외 안내

1. 현재 일정 정보 확인 API에서 권한과 최신 날짜·시간을 확인한다.
2. 실제 B의 일정 상세 화면을 열 때는 가족 공간과 날짜를 기준으로 월별 일정 API를 다시 조회하고 해당 `schedule_seq`를 찾는다.
3. 월별 조회 응답을 기존 `Schedule.fromJson`으로 해석하고 `ScheduleDetail`에 전달한다. 알림 API의 응답은 일정 상태·담당자·재수락 비교 정보 전체를 가진 `Schedule` 응답과 구분한다.
4. 재수락 버튼은 현재 일정의 `reconfirm_required`, `reconfirm_user_id`, 최신 이력과 로그인한 MySQL 사용자 ID를 기준으로 표시한다. 알림 유형만으로 응답 권한을 판단하지 않는다.
5. 날짜/시간을 다시 변경하여 종료된 요청이나 이미 처리된 요청의 응답은 서버에서 409로 막는다. 안내 후 현재 일정을 재조회한다.
6. 과거 알림 이후 다른 가족이 수락했을 수도 있으므로 담당자·모집 상태를 알림 문구만으로 확정하지 않는다.

월별 조회 경로:

`GET /schedules?family_room_id={room}&year={year}&month={month}`

현재 화면의 선택 공간과 알림의 공간이 다르면 해당 공간의 현재 참여를 확인하고 공간 전환 흐름과 연결한다.

## 5. 재수락 응답 정책

- 날짜·시작·종료 변경: 새 내용 저장 후 기존 담당자에게 재수락 요청. 응답 대기 중 다른 가족 수락 차단.
- 일반 요청: `요청 시각 + 24시간`과 `새 시작 시각 - 12시간` 중 이른 시각이 기한이다.
- 요청 시 새 시작까지 12시간 이하(정확히 12시간 포함): 긴급 요청. 자동 배정 해제 없이 전화 확인과 앱 응답을 기다린다. 시작 이후 미응답이면 주보호자에게 미확인 안내.
- 대기 중 이름·메모 변경: 변경 안내만 추가하고 기존 요청·기한·비교 기준 유지.
- 대기 중 날짜·시간 변경: 새 요청과 새 기한 계산. 종료된 이전 요청으로 응답 불가.
- 응답 API: `POST /schedules/{schedule_seq}/changes/{history_seq}/respond`, 본문 `{"accepted": true}` 또는 `{"accepted": false}`.
- 알림함 자체에 응답 버튼을 새로 만들기보다 B의 기존 일정 상세 재수락·거절 흐름에 연결하는 것을 통합 방향으로 제안한다. 최종 화면 구성은 A/B 통합 시 맞춘다.

## 6. 주기 프로그램과 자동 재시도 범위

```powershell
python -m python.features.schedules.reconfirm_expiry_worker
```

- API 서버와 별도로 실행해야 일반 만료·긴급 시작 후 미확인을 자동 처리한다. 현재 주기는 1분이다.
- 자동 재시도에 연결된 유형: `schedule_recruitment`, `schedule_reconfirm_expired`, `schedule_reconfirm_unanswered`, `schedule_reconfirm_unverified`, `schedule_deleted`.
- **등록·일반 변경·재수락 요청 알림의 pending 자동 재시도는 현재 이 프로그램에 연결되어 있지 않다.** 발행 함수는 있지만 자동 재시도 범위를 별도로 연결해야 한다.
- 재모집의 자동 재시도는 시작 전인지 확인한다. 발행 직전에 현재 일정·최신 이력·배정·공간 상태를 재검증한다.
- 실행 중인 프로그램은 코드 변경 후 재시작한다. 이 프로그램은 72시간 예약 재알림 실행기가 아니다.

## 7. A/B 추가 연결 및 미구현 범위

아래 항목을 완료 항목과 구분해 PR에 남긴다.

| 항목 | 현재 상태와 추가 연결 |
| --- | --- |
| 공통 알림함·문자열 ID·유형별 표시·배지·푸시 | A의 현재 클라이언트에 통합 필요. Firestore 발행 확인과 기기 도착 확인을 구분 |
| 수락자 없는 일정의 변경 안내 | 최신 정책은 전체 현재 가족에게 안내. 현재 update_schedule은 기존 수락자가 있을 때만 알림을 준비하므로 B의 변경 분기와 A 연동이 추가로 필요 |
| 등록·일반 변경·재수락 요청 발행 실패 복구 | 위 3종의 pending 자동 재시도 추가 필요 |
| 미수락 일정의 시작 72시간 전 재알림 | A의 예약 처리와 연결 필요 |
| 날짜·시작 변경에 따른 예약 취소/재계산 | A/B 연동 필요. 앞당겨 시작까지 72시간 이하인 미수락 일정의 즉시 재알림도 해당 후속 정책에 맞춰 연결 |
| 일정 삭제 시 예약 취소·발송 차단 | 별도 예약이 있다면 취소 연결. 실제 발송 직전 deleted_at·공간 상태 확인 필요 |
| 참여 종료·탈퇴·공간 삭제 이후 알림 접근/발송 | 조회 단계는 현재 권한 재검사. 공통 푸시·예약 처리에서도 현재 상태 확인 필요 |
| system 내부 처리자 | 자동 만료 이력용. 일반 회원 목록·집계에서 제외 필요. Firebase UID와 가족 참여 없음 |

사용자 요청으로 이번 마무리는 삭제까지 진행했다. 위 미구현 항목을 문서화했으며 추가 기능 코드를 임의로 연결하지 않았다. 교체·주보호자 이전 등 별도 기능의 알림을 이번 PR 구현 완료로 포함하지 않는다.

## 8. 설정과 검증 범위

- `firestore.indexes.json`에는 수신자 배열·published 상태·생성 시각 내림차순 조회용 복합 색인이 포함되어 있다. 대상 Firebase 프로젝트에도 색인이 반영되어야 한다.
- 추가 DB 컬럼은 만들지 않았다. 자동 만료를 실행할 DB에는 내부 처리자 `user_id=system`, `name=시스템`, `user_firebase_uid=NULL`이 필요하다. 가족 참여나 로그인 계정으로 사용하지 않는다. 현재 공유 DB에서 이 등록을 확인했다.
- 자동 검증: 삭제 29개 + 기존 일정 조회 7개, 총 36개 통과. 이 숫자는 전체 알림 8종에 대한 모든 자동 검증을 의미하지 않는다.
- 앱/DB/Firestore 수동 확인: 메모만 변경 시 배정 유지·담당자 알림, 종료시간 변경과 재수락·거절·재모집, 대기 중 메모/시간 추가 변경과 이전 요청 409, 일반 만료 처리, 긴급 미확인 자동 안내 및 배정 유지, 실제 일정 삭제.
- 실제 삭제 확인: 일정 8번, 삭제 이력 23번, `schedule_deleted_8_23` published, 수신자 4명, 담당 배정 NULL.
- 기기 알림·배지·72시간 예약·A의 전체 알림함 통합 검증은 별도이다. 날짜/시작 변경의 모든 조합이나 정확한 12시간 경계를 실제 앱에서 전부 확인했다고 보고하지 않는다.


## 9. 2026-10-29 자동 만료 알림 A/B 인수인계

### B 완료 및 이번 수정

- 공유 DB의 일정 40번에서 재수락 응답 기한 2026-10-29 16:45 경과 후 담당자 `accepted_by=NULL`을 읽기 전용 조회로 확인했다. 자동 배정 해제는 동작한다.
- 수정 전 Firestore 확인: `schedule_reconfirm_expired_40_111`, `_40_114` 및 `schedule_reconfirm_unanswered_40_111`, `_40_114`는 pending, `schedule_recruitment_40_111`, `_40_114`는 published였다. 이는 확인 당시 상태이며 수정 후 복구 완료를 뜻하지 않는다.
- `python/features/schedules/change_notifications.py`의 `publish_reconfirm_expiry_notification()`에서 긴급 여부로 제외하던 조건을 `response_due_at is None`으로 변경했다. 12시간 초과~24시간 이하 요청은 기한이 있으므로 기한 도달 후 발행한다. 12시간 이하는 자동 만료하지 않는다. 일반 요청·기한 전 발행 차단·문서 및 이력 검증은 유지한다.
- `python/tests/test_expiry_publication.py` 4개 검사 통과: 기한 있는 긴급 요청의 담당자/주보호자 안내, 기한 없는 긴급 제외, 기한 직전 제외, 일반 만료 발행. 실제 공유 Firestore 발행을 호출하지 않는 대체 연결 검사이다.
- 이번 수정으로 A 담당 공통 알림 저장·푸시, V2 필터, Flutter 제목 매핑은 변경하지 않았다.

### A 후속 연결 — 아직 완료되지 않음

| 위치 | 필요한 작업 |
| --- | --- |
| `python/features/schedules/notification_router.py`의 `visible_v2()` | `schedule_reconfirm_expired`, `schedule_reconfirm_unanswered`를 허용 유형에 추가하고 `request_history_seq`가 있는 자동 만료 `schedule_recruitment`를 제외하는 조건을 해제. 기존 현재 참여·계정·공간·일정 접근 검사는 유지 |
| `lib/model/notifications/schedule_notification.dart` | 만료·미응답 전용 제목 추가. 기존 담당자에게 응답 기한 초과에 따른 배정 해제, 현재 주보호자에게 담당 가족 미응답 안내. 현재 기본 제목인 신규 일정 등록으로 표시하지 않기 |
| 알림함·`/activity/badges` | 동일 `visible_v2` 기준으로 목록과 미읽음 개수 일치. 기존 문자열 ID·개별 읽음 상태 유지 |
| `python/features/notifications/store.py`의 `PUSH_TYPES`, `supports_push()` 및 푸시 문구 | 만료·미응답 유형과 자동 만료 재모집이 현재 푸시 대상에서 제외됨. 기기 푸시를 연결할 때 유형·문구·라우팅을 함께 추가하고 기존 수신자 경계 유지 |

수신자 계약: `schedule_reconfirm_expired`는 기존 담당자, `schedule_reconfirm_unanswered`는 현재 주보호자, 자동 만료 `schedule_recruitment`는 현재 전체 참여 가족이다. 문서의 `recipient_ids`를 임의로 확대하지 않는다.

위 V2 필터는 schedules 폴더에 있지만 공통 알림함·배지 통합 경로이므로 이번에는 A 연결 항목으로 남겼다. B는 만료 처리와 발행 조건을 수정한다.

### 실행 및 통합 검수

1. API 서버와 별도로, 동일 DB를 보는 담당자 한 명만 `python -m python.features.schedules.reconfirm_expiry_worker`를 실행한다. 72시간 재알림 worker와 구분한다.
2. 코드 반영 후 API 서버와 재수락 worker를 각각 재시작한다. 기존 pending은 worker 재시도 대상이지만 최신 이력·문서 검증을 통과해야 published로 전환된다. Firestore 상태를 수동으로 published로 바꾸지 않는다.
3. 새 만료 검수 요청으로 자동 배정 해제, 담당자/주보호자 안내와 전체 가족 재모집 문서의 published 상태를 확인한다.
4. 각 역할의 앱 알림함·문구·배지·읽음·최신 상세 연결을 확인한다. 다른 가족은 재모집 안내를 받되 기존 담당자 전용 만료 안내를 받지 않아야 한다.
5. 푸시를 연결한 경우 실제 기기 도착은 앱 알림함 및 Firestore published와 별도로 검수한다. 재시도 시 중복 알림·읽음 초기화도 확인한다.

GitHub 업로드/PR 전달 문안: [2026-10-29 인수인계](schedule_handoff_2026-10-29.md).


### 후속 실제 검수 완료 — 2026-10-29

사용자 제공 Firestore 화면으로 worker 재시작 후 기존 pending 복구를 확인했다. 같은 일정 40번·자동 해제 이력 114번·요청 이력 113번·응답 기한 2026-10-29 16:55:00의 두 문서가 발행됐다.

- `schedule_reconfirm_expired_40_114`: published, published_at 2026-10-29 17:00:11 (UTC+9), 기존 담당자 수신자 1명.
- `schedule_reconfirm_unanswered_40_114`: published, published_at 2026-10-29 17:00:12 (UTC+9), 주보호자 수신자 1명.

B의 자동 배정 해제 및 이번 긴급 만료 알림 발행 조건 수정의 실제 검수는 완료했다. A의 V2 알림함·배지·푸시 연결과 기기 수신 검수는 별도로 남는다. 위의 수정 후 발행 확인 필요 문구는 이 후속 기록으로 갱신한다.


## 10. 담당 가족의 일정 참여 철회 후속

새 B 구현과 A의 새 유형·재모집 문구 연결은 [일정 참여 철회 인수인계](schedule_withdrawal.md)를 따른다. 주보호자 철회 안내와 전체 가족 재모집을 별도 이벤트로 준비한다. 자동 만료와 구분하며 이번 범위에서 A 공통 모델·푸시는 변경하지 않았다.
