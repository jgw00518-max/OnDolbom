# 사용자 문의와 공통 계정 Drawer

가족 공간 목록(공간 선택 전)과 가족 공간 홈(공간 진입 후)의 `계정 메뉴` 아이콘으로 동일한 Drawer를 연다.
왼쪽 Drawer를 사용하며 두 화면의 상단 뒤로가기 버튼 대신 왼쪽 끝에 ☰ 계정 메뉴를 표시한다. 상단에 이름·이메일·전화번호, 하단에 초대·알림·문의·개인 설정·로그아웃을 표시한다.
개인 설정에서는 본인 정보를 확인하고 기기의 아이디 저장·자동 로그인 옵션을 변경한다. 이름·전화번호 수정 기능은 포함하지 않는다.
후속 메뉴는 `lib/view/widgets/account_drawer.dart`의 메뉴 목록에 추가한다.

## 구현 범위

- 문의 작성, 본인 문의 목록·상세, 기존 관리자 답변 조회
- 새 문의는 제목 1~100자·내용 1~10,000자 필수
- 공간 목록에서 진입하면 공간 없는 문의, 공간 홈에서는 현재 공간 연결 여부를 선택
- 연결 공간의 현재 참여·삭제 상태는 서버에서 검사
- 답변 대기/완료는 삭제되지 않은 답변의 존재 여부로 계산. 관리자 처리 단계와 동일한 상태가 아님
- 목록은 최신순 50건, 이전/다음 페이지 및 새로고침 제공
- 관리자 답변 작성 화면/API는 별도 관리자 웹에서 후속 구현. 이 변경은 사용자 앱에서 DB의 기존 답변을 읽는 부분까지 포함
- 첨부파일, 문의 수정·삭제, 일정·투약일지 직접 연결, 처리 상태 변경은 이번 변경에 포함하지 않음

## 실제 공유 DB

읽기 전용으로 확인한 기존 `question`·`answer` 테이블을 사용한다. 스키마 변경이나 테스트 문의 INSERT는 실행하지 않았다.

- `question`: question_seq, user_id, family_room_id(nullable), admin_id(nullable), question_title, question_content, questioned_at, question_deleted_at
- `answer`: answer_seq, question_seq, user_id, admin_id, answer_content, answered_at, answer_deleted_at
- 관리자 답변의 user_id는 해당 문의 작성자의 user_id와 일치해야 사용자 앱에 표시됨
- 두 테이블 모두 현재 utf8mb3이므로 4바이트 이모지는 입력 검증에서 거절. 지원하려면 팀과 DB 문자셋 변경을 협의해야 함

공간 참여를 종료하더라도 본인이 작성한 문의의 제목·내용·답변은 조회할 수 있다. 이 API로 공간·대상자 상세 데이터를 추가로 제공하지 않는다.

## API

모두 `Authorization: Bearer <Firebase ID token>` 필수. 검증된 UID로 등록·미탈퇴 MySQL 사용자 ID를 찾는다.
다른 가족이 같은 공간에 있어도 다른 사람의 문의는 조회할 수 없다. 클라이언트의 user_id·admin_id 입력은 허용하지 않는다.

| 경로 | 동작 |
| --- | --- |
| `GET /inquiries?before_seq=선택값` | 본인 문의 목록. `{items: [...], next_cursor: 숫자 또는 null}` |
| `POST /inquiries` | `{question_title, question_content, family_room_id: 선택값}` → 201 `{question_seq}` |
| `GET /inquiries/{question_seq}` | 본인 문의 본문과 삭제되지 않은 관리자 답변 목록 |

401 인증 실패, 403 등록/공간 권한 없음, 404 다른 작성자·삭제·없는 문의, 422 입력 오류, 503 DB 연결/처리 실패로 구분한다.
등록 실패·타임아웃 시 입력을 보존하고 목록 확인을 안내한다. 자동 재전송하지 않는다. 기존 테이블에 요청 고유키가 없으므로 응답 유실 후 수동 재등록은 중복될 수 있다.

## 파일

- Flutter 모델: `lib/model/inquiries/inquiry.dart`
- API·상태: `lib/vm/inquiries/inquiry_vm.dart`
- 화면: `lib/view/inquiries/`와 `lib/view/widgets/account_drawer.dart`
- FastAPI: `python/features/inquiries/router.py`, `python/main.py` 등록

## 검증 방법

1. 로그인·프로필 등록 후 공간 목록에서 계정 메뉴를 열어 본인 정보를 확인한다.
2. 문의하기 → 문의 작성 → 공간 없이 등록 → 목록과 상세를 확인한다. 실제 공유 DB에 저장되므로 테스트 내용임을 표시한다.
3. 공간에 진입한 뒤 같은 Drawer에서 문의를 작성하고 현재 공간 연결을 확인한다.
4. 다른 계정으로 로그인해 이전 계정의 문의가 목록·상세에서 보이지 않는지 확인한다.
5. 관리자가 기존 answer 계약대로 작성한 답변을 새로고침해 확인한다. 관리자 웹의 답변 작성 기능이 준비되기 전에는 자동 테스트의 대체 데이터로 확인한다.

자동 테스트는 DB·HTTP 대체 객체를 사용한다. 실제 공유 DB에 문의나 답변을 쓰지 않는다.
