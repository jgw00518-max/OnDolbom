# 메모·채팅 내보내기 API

기존 DB 구조를 유지하며 새 테이블·컬럼·인덱스·마이그레이션을 추가하지 않는다.
`memo`, `live_chat`에서 읽고 `participate`, `family_room`, `user`로 권한·표시 이름을 확인한다.
투약 정보·투약일지 테이블은 조회하지 않는다.

## 요청과 응답

```http
POST /exports/download
Authorization: Bearer <Firebase ID 토큰>
Content-Type: application/json
```

```json
{
  "family_room_id": "공간ID",
  "start_date": "2026-10-01",
  "end_date": "2026-10-27",
  "scopes": ["memos", "chats"],
  "include_images": true,
  "format": "html_zip"
}
```

| 필드 | 조건 |
| --- | --- |
| `family_room_id` | 필수, 앞뒤 공백 제거 후 1~50자 |
| `start_date`, `end_date` | 필수, `YYYY-MM-DD`, 시작일 ≤ 종료일 |
| `scopes` | `memos`, `chats` 중 하나 또는 둘 다. 기본은 둘 다. 빈 배열·중복 불가 |
| `include_images` | 기본 false |
| `format` | `html_zip` 또는 `pdf`, 기본값은 기존과 동일하게 `html_zip` |

추가 필드는 거절한다. 사용자 ID·역할은 요청으로 받지 않고 검증한 Firebase UID로 결정한다.
시작일은 1000-01-01 이상, 종료일은 9999-12-30 이하로 제한한다(MySQL 날짜 범위와 다음 날 경계 계산).
기간 길이·레코드 건수·전체 파일 크기에 별도 제한은 추가하지 않는다.

성공 시 HTTP 200으로 JSON 대신 선택한 형식의 바이너리를 반환한다.

| 형식 | Content-Type | 파일명 예시 |
| --- | --- | --- |
| `html_zip` | `application/zip` | `ondolbom_20261001_20261027.zip` |
| `pdf` | `application/pdf` | `ondolbom_20261001_20261027.pdf` |

`Content-Disposition: attachment; filename="선택한 형식의 파일명"`,
`Content-Length`, `Cache-Control: private, no-store`, `X-Content-Type-Options: nosniff` 헤더를 제공한다.
인증 헤더가 필요한 POST이므로 앱에서 응답 바이트를 파일로 저장한다. 브라우저 주소창용 GET 링크는 없다.
서버 `/docs`에서 요청 스키마와 바이너리 응답을 확인할 수 있다.

```text
ondolbom_20261001_20261027.zip
├─ index.html       # 공간·기간·조회 기준 시각·이미지 옵션·각 범위 건수
├─ memos.html       # memos 선택 시에만 생성
├─ chats.html       # chats 선택 시에만 생성
└─ images/          # 이미지 포함 옵션 + 실제 첨부 이미지가 있을 때만 생성
```

ZIP을 압축 해제한 뒤 `index.html`을 열면 외부 서비스·이미지 URL 없이 확인할 수 있다.
기록이 없어도 HTTP 200으로 안내와 0건 표시를 담은 ZIP을 반환한다.
본문·이름·공간명은 HTML 이스케이프하며 스크립트와 외부 리소스를 제한하는 CSP를 포함한다.
이미지 파일명은 서버가 생성한 범위·순번으로 구성한다.

### PDF 내보내기

같은 API에 `"format": "pdf"`를 보내면 ZIP을 거치지 않고 PDF 한 개를 반환한다.

```json
{
  "family_room_id": "공간ID",
  "start_date": "2026-10-01",
  "end_date": "2026-10-27",
  "scopes": ["memos", "chats"],
  "include_images": true,
  "format": "pdf"
}
```

- 공간·기간·조회 기준 시각·이미지 옵션을 첫 부분에 표시한다.
- 안내·메모·채팅을 각각 새 페이지에서 시작하고, 번호가 있는 배너로 구역을 구분한다.
  선택한 범위만 포함하며, 안내에는 문서 구성 목록을 표시한다.
  모든 페이지 머리글에 현재 구역을 표시하고 PDF 책갈피로 구역 이동을 지원한다.
- 선택한 범위별로 작성자·작성 시각·수정 여부·본문을 표시하고 각 범위 끝에 건수를 표시한다.
- A4 문서에서 긴 한글 본문·줄바꿈을 여러 페이지에 나누고 머리글·페이지 번호를 넣는다.
- 이미지 포함 시 비율을 유지해 페이지에 맞춰 넣는다. 제외 시 첨부 존재 안내만 표시한다.
- 기록이 없는 범위도 빈 기록 안내와 0건을 담은 정상 PDF를 반환한다.
- 동봉한 나눔고딕 Regular·Bold를 PDF에 임베딩하여 별도 시스템 한글 폰트 설치가 필요 없다.
- 폰트가 지원하지 않는 이모지·특수 문자는 `[U+1F600]` 같은 문자 코드로 표시하고 문서에 안내한다.
  완성형 한글은 그대로 표시한다. 원문은 DB에서 변경하지 않는다.
- 본문을 일반 텍스트로 처리해 사용자 입력의 HTML 태그·외부 링크·이미지 URL을 실행·조회하지 않는다.
- 기존과 동일한 인증·권한·날짜·삭제 기록·투약 데이터 제외 규칙을 사용한다.

배포 시 `python -m pip install -r python/requirements.txt`로 PDF 생성 의존성을 설치하고,
`python/features/exports/fonts/`의 TTF 두 개와 `OFL.txt`를 서버에 함께 배포한다.
Flutter 내보내기 화면의 파일 형식 라디오 버튼에서 HTML·PDF를 선택할 수 있다.
선택에 따라 API 요청, 응답 검증, 파일 확장자와 저장 안내를 적용한다. [Flutter 안내](exports-frontend.md)를 참고한다.

## 조회 기준과 권한

- 현재 참여 중인 주보호자와 일반 가족 모두 허용한다. 역할에 따른 추가 제한은 없다.
- Firebase 서명·만료·폐기를 검증하고 정확히 일치하는 UID의 등록·미탈퇴 사용자만 허용한다.
- 참여 조건은 `is_active = 1`, `left_at IS NULL`, 사용자 미탈퇴, 공간 미삭제다.
- 파일 생성 시작 시와 생성 완료 후 전송 직전에 참여 여부를 각각 검사한다.
  마지막 검사 이후 전송 중 발생한 권한 변경까지 원자적으로 묶지는 않는다.
- 가입 이전 기록도 기존 채팅 조회 정책과 동일하게 포함한다.
- 메모 `written_at`, 채팅 `sent_at`이 시작일 00:00 이상, 종료일 다음 날 00:00 미만인 기록을 조회한다.
  기존 DB 저장 시각을 그대로 사용하고 UTC·한국 시간으로 임의 변환하지 않는다.
  한국 날짜 기준 서비스를 위해서는 기존 DB 저장 시각·세션 시간대도 일관되게 설정해야 한다.
- 작성 시각 오름차순으로 정렬하고 같은 시각은 메모 ID·작성자 ID 또는 채팅 번호로 정렬한다.
- 삭제된 메모는 제외한다. 삭제된 채팅은 삭제 안내만 담고 원문·이미지는 SQL 조회 단계에서 차단한다.
- 수정된 기록은 생성 작업의 읽기 스냅샷 기준 본문을 담으며 수정 여부를 표시한다.
  작성자 이름도 조회 시점의 이름이다.
- 메모·채팅·첨부 이미지는 InnoDB `REPEATABLE READ`의 동일 읽기 전용 스냅샷에서 읽는다.
  요청 접수 시점의 과거 버전을 별도로 저장하거나 복원하는 방식은 아니다.
- 투약 정보·투약일지 데이터는 제외하지만, 메모·채팅 본문에 사용자가 직접 작성한 투약 관련 문장은 포함한다.
- 이미지 제외 시 BLOB 본문을 선택하지 않고 첨부 존재 여부만 조회·표시한다.

## 실패와 재요청

오류는 기존 FastAPI 방식의 JSON `{"detail": "안내 문구"}`로 반환한다.
입력 검증 오류의 `detail`은 FastAPI 기본 배열 형식이다.

| HTTP | 의미 |
| --- | --- |
| 401 | 토큰 누락·만료·유효하지 않음 |
| 403 | 미등록·탈퇴 사용자, 현재 공간 참여 권한 없음, 삭제된 공간 |
| 422 | 잘못된 날짜·범위·형식·추가 필드 |
| 500 | 첨부 이미지·PDF 렌더링·폰트 처리 실패 또는 임시 파일 생성 실패 |
| 503 | 인증 서비스·DB 설정·연결·조회 실패 |

손상된 이미지는 조용히 누락시키지 않고 생성 전체를 실패 처리한다.
이 경우 이미지 제외 후 재요청할 수 있다는 안내를 반환한다.
DB 내부 오류·실제 저장 경로는 오류 응답에 노출하지 않는다.

## 실행 방식과 한계

요청 내에서 파일을 완성한 뒤 응답하므로 HTTP 202·작업 ID·진행률·상태 조회·파일 이력은 제공하지 않는다.
앱은 응답 대기 중 '파일 생성 중'을 표시하고, 다운로드 오류 시 동일 본문으로 다시 요청한다.
재요청은 매번 현재 기록을 다시 읽어 새 파일을 생성한다. 동일 작업의 중복 실행 방지는 없다.

서버는 비버퍼링 DB 커서로 한 건씩 읽고 임시 디스크에 HTML·ZIP을 기록한다.
전체 BLOB 목록이나 ZIP을 메모리에 적재하지 않지만, 한 레코드·이미지 단위의 메모리는 필요하다.
PDF도 레코드 전체 목록을 별도로 만들지 않고 순서대로 배치하지만, ReportLab이 페이지·이미지·폰트의
PDF 객체를 문서 완성까지 보관하므로 문서 크기와 첨부 이미지 수에 따라 메모리 사용량이 늘어난다.
스냅샷 트랜잭션은 파일 생성 동안 유지하고 완료 후 종료한다. 데이터 쓰기·commit은 하지 않는다.
파일 전송 완료·실패·클라이언트 연결 종료 시 임시 ZIP/PDF를 닫고, 생성 오류 시에도 임시 파일을 정리한다.

대용량·동시 요청은 서버 디스크·처리 시간·DB 스냅샷 유지 비용을 사용한다.
서버·프록시·클라이언트의 요청 시간 제한이 적용될 수 있다. 생성 중 요청 중단이
동기 생성 작업을 즉시 취소하지는 않으며, 생성 작업이 반환되면서 정리된다.
실제 DB 변경 없이 도입할 수 있으나 장시간 작업 복구와 앱 재실행 후 상태 확인은 제공하지 않는다.

## 파일과 검증

- `python/features/exports/router.py`: 입력·인증·권한·SQL·다운로드·자원 정리
- `python/features/exports/generator.py`: HTML·이미지 ZIP 생성
- `python/features/exports/pdf_generator.py`: 한글·이미지·페이지 분할 PDF 생성
- `python/features/exports/fonts/`: 배포용 한글 폰트와 라이선스
- `python/main.py`: 라우터 등록
- `python/tests/test_exports.py`: 모의 DB·인증 기반 API 및 파일 내용 검증
- `python/tests/test_exports_pdf.py`: 실제 PDF 파서로 한글·폰트·페이지·이미지·권한 검증

```powershell
python -m pip install -r python/requirements-dev.txt
python -m unittest python.tests.test_exports python.tests.test_exports_pdf -v
```

테스트는 실제 DB·Firebase를 사용하지 않는다. 실제 MySQL 스키마·저장 시간대와
Firebase 인증을 연결한 다운로드 확인은 별도로 필요하다.
