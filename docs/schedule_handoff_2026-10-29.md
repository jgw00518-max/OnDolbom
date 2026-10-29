# 2026-10-29 일정 변경 GitHub 업로드·A 인수인계

이 문서는 2026-10-29 작업의 GitHub PR 전달 기록이다. 오늘 변경과 실제 검수 결과, A 담당 후속 작업을 함께 전달한다.

## PR 본문에 추가할 내용

재수락 기한 초과 시 자동 배정 해제는 정상 동작했지만, 12시간 초과~24시간 이하 긴급 요청의 만료 알림이 pending에 남는 문제가 있었다. 일정의 만료 알림 발행 조건을 긴급 여부 대신 실제 응답 기한 유무로 수정했다. 기한 없는 12시간 이하 요청은 자동 만료 발행에서 계속 제외한다.

검증: `python -B -m unittest python.tests.test_expiry_publication` 4개 통과. 기한 있는 긴급 요청의 담당자·주보호자 안내, 기한 없는 요청 제외, 기한 직전 제외, 일반 요청을 검증했다. 수정 후 실제 Firebase pending 복구는 아래 후속 검수로 확인했다. 앱·배지·기기 수신은 A 연결 후 통합 검수가 필요하다.

**A 후속:** V2 알림함의 자동 만료·미응답 유형 허용, 자동 만료 재모집 제외 조건 해제, 유형별 제목, 목록/배지 일치, 기기 푸시 대상·문구·라우팅 연결. 상세 수신자와 파일 위치는 `docs/schedule_notifications.md` 9절 참고. B가 자동 해제를 구현했다는 것과 A의 알림 표시·푸시 완료를 구분한다.

## 오늘 함께 반영한 화면·비교 기능

- 이름·메모 단독 변경: 상세 첫 진입에서 회색 이전 값 → 붉은 굵은 최신 값, 다시 열면 최신 내용만 표시. 확인 버튼 없이 현재 기기의 계정·공간·일정별 확인 버전을 저장한다. 다른 기기와 동기화하지 않는다.
- 일정 상세: 삭제/변경 버튼을 가로 배치하고 아이콘 제거, 삭제/거절은 차분한 코랄 배경·흰 글씨. 일반 기한은 검은색 굵게, 긴급 기한은 붉게 표시. 기한 있는 요청에만 미응답 자동 해제 문구 표시.
- 삭제 알림 및 가족 공간 전환창을 앱 테마로 통일. 기존 읽음·권한·전환 처리 유지.
- 일정 알림 API 실패 시 기존 503 응답과 함께 서버 진단 로그 기록.
- 최종 자동 검증: 변경 비교 5개 + 만료 발행 4개 + 기존 일정 조회 7개 = 16개 통과. 변경 Flutter 파일 3개 분석 통과.
- 사용자 수동 확인: 재수락·거절·재모집, 메모 수정 시 기한 유지, 시간 재수정 시 재계산, 담당자 외 응답 제한, 일반/긴급 기한 표시, 변경 알림·상세 재진입, 삭제 알림 수신, 자동 배정 해제와 만료/미응답 Firestore 발행. 모든 알림 유형의 기기 푸시 검수를 완료했다는 의미는 아니다.

## 업로드 때 누락하지 않을 파일

- `python/features/schedules/change_notifications.py`
- `python/tests/test_expiry_publication.py` — 새 검증 파일
- `docs/schedule_notifications.md` — 9절
- `docs/notification-v2-integration.md` — 자동 만료 후속 연결 링크
- `docs/schedule_handoff_2026-10-29.md` — 이 전달 기록

위는 이번 만료 알림 수정·문서 관련 파일이며, 브랜치 전체 변경 파일 목록을 대체하지 않는다. 앞서 작업한 이름·메모 비교 기능의 신규 `content_review.py` 등은 실제 최종 diff에 맞춰 별도로 포함한다. `.env`, 비밀 키, 로컬 백업·중간 작업 스크립트는 업로드 대상에 넣지 않는다.

## 운영 전달

API 서버와 재수락 worker는 별도 프로세스다. 같은 DB를 보는 담당자 한 명이 worker를 실행하고 수정 후 재시작해야 한다. 팀원이 최신 코드를 받았는지도 확인한다. 이미 pending인 문서는 worker가 검증 후 재시도하며 문서 상태를 직접 수정해 복구하지 않는다.


### 후속 실제 검수 완료 — 2026-10-29

사용자 제공 Firestore 화면으로 worker 재시작 후 기존 pending 복구를 확인했다. 같은 일정 40번·자동 해제 이력 114번·요청 이력 113번·응답 기한 2026-10-29 16:55:00의 두 문서가 발행됐다.

- `schedule_reconfirm_expired_40_114`: published, published_at 2026-10-29 17:00:11 (UTC+9), 기존 담당자 수신자 1명.
- `schedule_reconfirm_unanswered_40_114`: published, published_at 2026-10-29 17:00:12 (UTC+9), 주보호자 수신자 1명.

B의 자동 배정 해제 및 이번 긴급 만료 알림 발행 조건 수정의 실제 검수는 완료했다. A의 V2 알림함·배지·푸시 연결과 기기 수신 검수는 별도로 남는다. 위의 수정 후 발행 확인 필요 문구는 이 후속 기록으로 갱신한다.


## 다음 업로드·PR에 추가 — 일정 참여 취소

담당 가족이 본인의 미완료 일정 참여를 취소하는 버튼·확인창과 POST /schedules/{schedule_seq}/withdraw를 추가했다. 최신 일정/본인 배정/현재 참여/수락 시각을 검증한 뒤 배정을 해제하고 처리 이력을 기록한다. 주보호자용 schedule_withdrawn과 현재 전체 가족용 schedule_recruitment(reason=participation_withdrawal)를 준비·발행하며 pending 재시도를 연결했다.

**실제 확인:** 서버 재시작 후 앱의 참여 취소 처리와 재모집 알림 표시를 사용자가 확인했다. 자동 검사 총 26개 및 Flutter 분석 통과. 다른 가족의 재수락 및 주보호자 전용 안내·Firestore 상세·기기 푸시는 전부 완료했다고 보고하지 않는다.

**A 전달 필수:** 주보호자 참여 취소 전용 알림은 공통 앱에 아직 미연결이다. schedule_withdrawn V2 허용·전용 제목/아이콘·읽음/배지·기기 푸시를 연결한다. 재모집은 이미 앱 표시를 확인했으나 주보호자에게 schedule_declined로 오표시하지 않도록 reason 분기가 필요하다. 상세는 docs/schedule_withdrawal.md 참고.

새 기능 업로드 대상:

- python/features/schedules/withdraw_schedule.py (신규)
- python/tests/test_schedule_withdrawal.py (신규)
- docs/schedule_withdrawal.md (신규)
- python/features/schedules/router.py
- python/features/schedules/reconfirm_expiry_worker.py
- lib/model/schedules/schedule.dart
- lib/vm/schedules/schedule_vm.dart
- lib/view/schedules/schedule_detail.dart
- docs/schedule_notifications.md, docs/schedule_handoff_2026-10-29.md 및 V2 후속 안내 문서

이 후속 기능은 앞선 525a3f6 커밋에 포함되지 않았고 아직 새 commit·push는 하지 않았다. 최종 업로드 때 git diff와 status 기준으로 포함 범위를 확인한다.


### 참여 취소 시 24시간 미만 안내

미래 일정의 시작까지 24시간 미만 남은 경우 참여 취소 확인창에 주보호자에게 연락해 새 담당 가족을 찾도록 요청하는 안내를 추가했다. 정확히 24시간 이상 또는 이미 시작한 일정에는 이 사전 안내를 표시하지 않는다. 앱 기기의 현재 시각과 표시된 일정의 시작 시각으로 판단한다. 안내 추가이며 취소 제한·승인·새 알림 수신자 정책을 도입하지 않는다. 서버는 계속 현재 배정과 최신 이력을 검증한다.
