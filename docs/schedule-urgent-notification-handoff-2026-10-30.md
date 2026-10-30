# A 전달용 — 24시간 긴급 일정·재수락 알림 연동

작성일: 2026-10-30. B(장은혜)의 일정 처리 변경에 따른 A 알림 연동 요청이다. 이 문서는 전달용이며 실제 메시지를 발송한 것은 아니다.

## 전달 요약

긴급 기준이 12시간에서 **정확히 24시간을 포함한 24시간 이하**로 통일됐다. B는 일정 처리·알림 이벤트 생성·조회 연결을 수정했고, A 담당 공통 알림 코드는 수정하지 않았다. A는 새 두 유형의 푸시와 알림함 제목·이동을 연결하면 된다. 현재 실제 앱 알림 도착·푸시는 검증 전이다.

## 확정 PROCESS

| 상황 | 처리 및 알림 |
| --- | --- |
| 현재 수락자 없이 시작까지 24시간 이하 진입 | 현재 참여 가족 전체에게 긴급 모집 알림 1회 |
| 처음부터 24시간 이하인 미수락 일정 등록 | 현재 참여 가족 전체에게 긴급 모집 알림 1회 |
| 일정 변경으로 미수락·24시간 이하 조건 충족 | 현재 참여 가족 전체에게 긴급 모집 알림 1회 |
| 담당 취소·재수락 거절 후 24시간 이하 | 배정 해제 후 긴급 모집. 직접 취소·거절한 본인은 작업 알림 제외. 본인 화면의 주보호자 연락 안내 유지 |
| 재수락 요청 당시 또는 대기 중 시작까지 24시간 이하 | 주보호자에게 기존 담당 가족과 전화로 확인하도록 1회 안내. 기존 담당 배정 유지 |
| 긴급 재수락 미응답 | 자동 배정 해제·추가 재촉·시작 시 미확인 알림 없음 |
| 일반 재수락 미응답 | 요청+24시간과 시작-24시간 중 빠른 시각을 기한으로 사용. 긴급 구간 진입 전 만료라면 배정 해제·기존 담당자 만료 안내·주보호자 미응답 안내·전체 가족 재모집 |

기한과 긴급 진입 시각이 같으면 긴급 전환을 우선한다. 재수락 대기는 담당자가 없는 상태로 간주하지 않는다. 기존 등록·변경 안내와 72시간 재알림을 폐기한 것은 아니다.

## 새 이벤트 계약 — 현재 B 구현 기준

저장 위치는 기존 Firestore `schedule_notifications`이다. DB 컬럼 추가는 없다. 이벤트의 `recipient_ids`를 그대로 사용하고 현재 참여·권한을 발송 직전에 재검사한다. 작업자를 A에서 일괄 추가 제외하면 안 된다. 자동 긴급 모집에는 등록자도 포함될 수 있다.

| 항목 | 미수락 긴급 모집 | 긴급 재수락 전화 안내 |
| --- | --- | --- |
| notification_type | `schedule_urgent` | `schedule_reconfirm_urgent` |
| notification_id | `schedule_urgent_{schedule_seq}_{생성 식별 해시}` | `schedule_reconfirm_urgent_{schedule_seq}_{request_history_seq}` |
| 수신자 | 현재 참여 가족 전체. 직접 취소·거절자는 제외 | 현재 참여 주보호자 |
| reason | `urgent_recruitment` | `urgent_reconfirm_phone` |
| 식별·권한 정보 | `schedule_seq`, `family_room_id`, `schedule_created_at` | 왼쪽 공통 정보와 `request_history_seq`, `requested_user_id`, `history_updated_at` |
| 추가 내용 | `is_urgent=true`, `actor_id`, `schedule_start_at`, `message` | `history_seq`는 최초 요청 번호, `processed_by=system`, `schedule_start_at`, `message` |
| 저장·발행 | 트랜잭션으로 `published`와 `push_pending=true`를 함께 저장 | 기존 prepare_change → DB 처리 확정 → 공통 publish 사용 |

생성 식별 해시는 공간 ID와 일정 생성 시각을 SHA-256으로 만든다. 일정 번호가 재사용되어도 과거 이벤트와 섞이지 않도록 B 함수가 식별자를 만든다. A에서 새 ID를 만들지 않는다.

긴급 취소·거절 재모집은 별도 일반 재모집 푸시와 이중 발송하지 않도록 `schedule_urgent`로 합친다. 원래의 `schedule_recruitment` 문서는 `status=superseded`로 기록될 수 있으며 발송 대상이 아니다. 기존 주보호자용 참여 취소 사실 안내는 별도 유지한다.

## A 구현 요청

1. `python/features/notifications/store.py`
   - 새 두 유형을 푸시 지원 목록에 등록한다.
   - 기존 수신자·읽음 상태·중복 방지 계약을 유지한다.
2. `python/features/notifications/push.py`
   - 새 유형별 문구를 연결한다. 기존 일정 알림 상세 이동 경로를 재사용한다.
   - 미지원 유형을 등록 알림으로 바꾸거나 일반 재모집을 추가 발송하지 않는다.
3. `lib/model/notifications/schedule_notification.dart`
   - 두 유형에 맞는 알림함 제목을 추가한다. 필요 시 상세 본문은 API `message`를 연결한다.
   - 현재 기본 제목으로 떨어질 수 있으므로 이 부분까지 연결해야 사용자에게 긴급 안내가 올바르게 보인다.
4. A의 별도 재시도·배지·수신 필터가 유형을 제한한다면 새 유형도 확인한다. B의 재수락 worker와 중복 생성 경로를 추가하지 않는다.

위 3개 파일의 최소 변경 예시는 문서 마지막에 첨부했다. **검토용 제안이며 적용본이 아니다.** A의 최신 변경과 합쳐 필요한 부분만 반영한다. 전체 파일을 교체하지 않는다.

## 문구 제안

문구는 구현 제안이며 수신 대상·발송 횟수 등 확정 정책과 구분한다.

| 유형 | 알림함 제목 제안 | 푸시 본문 제안 |
| --- | --- | --- |
| schedule_urgent | 시작까지 24시간 이하, 긴급 돌봄 담당자가 필요해요 | 시작까지 24시간 이하인 일정에 담당 가족이 없습니다. 긴급 일정을 확인해 주세요. |
| schedule_reconfirm_urgent | 기존 담당 가족에게 전화로 변경 내용을 확인해 주세요 | 일정 시작까지 24시간 이하입니다. 기존 담당 가족에게 전화로 변경 내용을 확인해 주세요. |

건강정보·일정 메모는 잠금 화면에 노출하지 않는다.

## 폐기 유형과 이미 저장된 이벤트

- 기존 `schedule_reconfirm_unverified`는 시작 후 미확인 알림으로, 이번 정책에서 폐기됐다. B는 새 생성·재시도·조회 표시를 중단했다. 과거 pending을 재발송하지 않는다.
- 공통 연동 전에 전화 안내가 `published`로 저장됐다면 당시 지원 목록에 없어 `push_pending`이 누락됐을 수 있다. A가 필요 시 현재 요청·현재 참여 권한·시작 전 여부·기존 발송 여부를 확인하고 복구한다. 전체 과거 문서를 일괄 재발송하지 않는다.
- 미수락 긴급 이벤트는 현재 `push_pending=true`로 저장되지만 공통 지원 목록 연결 전에는 발송이 완성되지 않는다.

## B 완료 범위와 검증 수준

- 실제 프로젝트: `D:/grace2/ondolbom`, 작업 브랜치: `codex/schedule-urgent-24h`. 아직 commit·push하지 않았다. A에게 브랜치가 전달됐다고 간주하지 않는다.
- B 변경은 `python/features/schedules/` 9개 파일과 `lib/view/schedules/schedule_detail.dart`이다. 변경 파일은 `change_notifications.py`, `notification_router.py`, `reconfirm_expiry.py`, `reconfirm_expiry_worker.py`, `reconfirm_policy.py`, `router.py`, `urgent_reconfirm.py`, `urgent_schedule.py`, `withdraw_schedule.py`와 위 일정 상세 화면이다. 실제 구현은 프로젝트 소스를 확인한다.
- 즉시 확인: 등록·변경 저장 확정 후 호출. 주기 확인: 기존 재수락 worker의 60초 주기. 정확히 경계 시각과 실제 발송 사이에는 확인 주기·처리 지연이 있을 수 있다.
- 정책 경계·중복·수신자 제외 등 신규 모의 테스트 12개 통과. 관련 기존 모의 테스트 30개는 외부 후처리 호출을 차단하고 테스트 하나의 현재 시각 응답 입력을 보완한 검사본으로 통과했다.
- 수정 화면 분석 및 Python 문법 검사 통과. 실제 DB·Firestore·FCM 연동 테스트는 하지 않았다. 기존 월별 조회·인증 TestClient 검사는 멈춰 중단했으며 통과에 포함하지 않았다.
- worker 실행·재시작은 하지 않았다. 운영 담당자 한 명이 통합 후 실행 상태를 확인한다.

## A·B 통합 확인 항목

- 처음부터 24시간 이하인 미수락 등록과 일반 일정의 24시간 경계 진입에서 긴급 안내가 각 수신 계정에 보이는지.
- 일정 변경으로 긴급 조건이 된 경우와 정확히 24시간인 경우를 포함하는지.
- 취소·거절자에게 본인 작업 푸시가 안 가고, 다른 현재 참여 가족은 받는지.
- 취소·거절 재모집과 자동 긴급 알림이 중복 발송되지 않는지. 여러 worker 확인·재시도 후에도 같은 이벤트의 푸시가 반복되지 않는지.
- 재수락 대기가 24시간에 진입하면 주보호자에게 전화 안내가 1회 가고 기존 담당 배정은 유지되는지.
- 긴급 미응답에 시작 후 미확인 알림·자동 해제가 발생하지 않는지.
- 일반 구간의 만료 안내와 재모집은 정상인지.
- 수락·삭제·공간 종료·참여 종료 후 권한 없는 알림 표시와 발송을 차단하는지.
- 새 알림을 누르면 해당 공간의 올바른 일정 상세로 이동하고 읽음·배지가 갱신되는지.

## 미정 사항

일정 재수정·재배정 후 다시 긴급이 되었을 때 1회 기준을 초기화할지는 미정이다. 현재 B 구현은 동일 일정 생성 식별자당 1회로 보수적으로 처리한다. A가 별도의 반복 발송·초기화 정책을 임의 추가하지 않는다. 긴급 표시 위치·디자인도 별도 결정 사항이다.


## 공통 알림 최소 변경 예시 — 미적용

아래 예시는 2026-10-30 확인본 기준이다. 최신 코드와 비교 후 필요한 부분만 반영한다.

```diff
--- a/python/features/notifications/store.py
+++ b/python/features/notifications/store.py
@@ -6,7 +6,7 @@
 from python.features.auth.firebase_auth import get_firebase_app


-PUSH_TYPES = frozenset({'family_room_deleted', 'schedule_created', 'schedule_changed', 'schedule_deleted', 'schedule_reconfirm',
+PUSH_TYPES = frozenset({'schedule_urgent', 'schedule_reconfirm_urgent', 'family_room_deleted', 'schedule_created', 'schedule_changed', 'schedule_deleted', 'schedule_reconfirm',
                         'schedule_accepted', 'schedule_reconfirmed', 'schedule_recruitment', 'schedule_reminder', 'schedule_withdrawn',
                         'schedule_reconfirm_expired', 'schedule_reconfirm_unanswered', 'schedule_reconfirm_unverified'})

--- a/python/features/notifications/push.py
+++ b/python/features/notifications/push.py
@@ -117,6 +117,8 @@
         notification=messaging.Notification(title='온돌봄', body='푸시 연결 테스트입니다.' if test else {
             'chat_message': '가족의 새 채팅이 도착했습니다. 앱에서 확인해 주세요.',
             'family_room_deleted': '참여하던 돌봄 공간이 삭제되었습니다. 앱에서 안내를 확인해 주세요.',
+            'schedule_urgent': '시작까지 24시간 이하인 일정에 담당 가족이 없습니다. 긴급 일정을 확인해 주세요.',
+            'schedule_reconfirm_urgent': '일정 시작까지 24시간 이하입니다. 기존 담당 가족에게 전화로 변경 내용을 확인해 주세요.',
             'schedule_created': '새 돌봄 일정이 등록되었습니다. 앱에서 확인해 주세요.',
             'schedule_changed': '돌봄 일정이 변경되었습니다. 앱에서 확인해 주세요.',
             'schedule_deleted': '돌봄 일정이 삭제되었습니다. 앱에서 확인해 주세요.',
--- a/lib/model/notifications/schedule_notification.dart
+++ b/lib/model/notifications/schedule_notification.dart
@@ -48,6 +48,8 @@

   String get title => switch (type) {
     'family_room_deleted' => '참여하던 돌봄 공간이 삭제되었어요',
+    'schedule_urgent' => '시작까지 24시간 이하, 긴급 돌봄 담당자가 필요해요',
+    'schedule_reconfirm_urgent' => '기존 담당 가족에게 전화로 변경 내용을 확인해 주세요',
     'schedule_reminder' => '시작까지 72시간 이내, 돌봄 담당자가 필요해요',
     'schedule_accepted' => '가족이 돌봄 일정을 수락했어요',
     'schedule_reconfirmed' => '담당자가 변경된 일정을 재수락했어요',
```
