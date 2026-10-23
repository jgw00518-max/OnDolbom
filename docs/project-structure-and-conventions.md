# 온돌봄 파일 구조와 협업 코드 작성 기준

확인 기준: 2026-10-23, 현재 `ondolbom` 프로젝트의 실제 파일.

이 문서는 현재 구현 상태, 합의한 폴더 구성, 개발 전에 통일할 항목을 구분한다.
관리자 웹·관리자 전용 API는 별도 프로젝트 범위다. 아래 예시는 구조 설명이며
실제 기능 API·DB 테이블·인증 구현이 추가된 상태를 의미하지 않는다.

## 1. 현재 파일 구조

```text
ondolbom/
├─ lib/
│  ├─ main.dart                       # 앱 시작·MaterialApp 설정
│  ├─ firebase_options.dart           # FlutterFire가 생성한 플랫폼 설정
│  ├─ model/
│  │  └─ .gitkeep
│  ├─ view/
│  │  └─ home.dart                    # 현재 Placeholder 화면
│  └─ vm/
│     └─ .gitkeep
├─ python/
│  ├─ __init__.py
│  ├─ main.py                        # FastAPI 생성·/health
│  ├─ database.py                    # .env 읽기·MySQL 연결
│  ├─ requirements.txt               # 서버 실행 패키지
│  ├─ requirements-dev.txt           # 실행 패키지 + 테스트용 httpx
│  ├─ .env                           # 로컬 DB 설정, Git 제외
│  ├─ .env.example                   # 공유할 설정 항목
│  ├─ README.md                      # 서버 실행·DB 사용 규칙
│  ├─ features/
│  │  └─ __init__.py
│  └─ tests/
│     ├─ test_database.py            # 서버 상태·연결 설정 테스트
│     └─ features/
│        └─ .gitkeep
├─ test/
│  ├─ widget_test.dart               # 시작 화면 테스트
│  ├─ view/.gitkeep
│  └─ vm/.gitkeep
├─ docs/
│  ├─ project-structure-and-conventions.md
│  ├─ process.md                     # 현재 빈 문서
│  ├─ api.md                         # 현재 빈 문서
│  ├─ permissions.md                 # 현재 빈 문서
│  └─ pending-decisions.md            # 현재 빈 문서
├─ android/                          # Firebase Android 설정 포함
├─ ios/                              # 기존 Flutter 플랫폼 코드
├─ firebase.json                     # FlutterFire 설정 정보
├─ pubspec.yaml
├─ pubspec.lock
├─ analysis_options.yaml
├─ .gitignore
└─ README.md
```

`lib/common/`, `lib/service/`, `lib/app/`, `python/common/`은 현재 사용하지 않는다.
빈 필수 폴더는 `.gitkeep`으로 Git에 유지한다. 캐시·빌드 결과물은 위 트리에서 생략했다.

## 2. 구현된 부분과 아직 없는 부분

| 구분 | 현재 상태 |
| --- | --- |
| Flutter 앱 | `MyApp`에서 `Home`을 표시. 실제 기능 화면은 없음 |
| 상태 관리 | GetX·Provider·Riverpod 중 아직 패키지를 선택하지 않음 |
| 프론트 API 통신 | 아직 미구현 |
| Firebase | `firebase_core` 의존성과 생성 설정 파일 있음. `main.dart`에서 초기화하지 않음 |
| FastAPI | `/health`만 구현. 기능 라우터는 아직 등록하지 않음 |
| DB 연결 | 환경 설정 검사·연결 생성 구현. 실제 DB 연결 성공을 보장하는 상태는 아님 |
| 인증·공간 권한 | 아직 미구현. Firebase 설정 파일 존재만으로 로그인 구현을 의미하지 않음 |
| 기능 데이터 | 실제 테이블·컬럼·API 계약은 이 문서에서 확정하지 않음 |

## 3. 기능 담당자가 추가할 위치

수업의 `model / view / vm` 분류를 유지한다. 기능 폴더는 담당자가 구현할 때 추가한다.

기능명은 프론트의 세 영역과 백엔드에서 동일하게 사용한다.

| 기능명 제안 | 담당 범위 | 기존 역할 분담상 담당 |
| --- | --- | --- |
| `auth`, `users` | 가족 계정·로그인·계정 찾기 | 진건웅 |
| `notifications` | 알림 발송·조회·예약 실행 | 진건웅 |
| `inquiries`, `notices`, `faqs` | 가족 문의·결과 확인, 공지·FAQ 조회 | 진건웅 |
| `family_spaces` | 공간·초대·구성원·역할·참여 종료·삭제 | 장은혜 |
| `care_recipients` | 공간에 연결된 대상자 정보 | 장은혜 |
| `schedules` | 일정·수락·변경·교체·일정 이력 | 장은혜 |
| `memos`, `medications`, `chat`, `exports` | 메모·투약·채팅·내보내기 | 김승현 |

관리자 담당 업무는 이 저장소에 넣지 않는다. 기능 폴더명은 팀 합의 후 고정한다.

### 3.1. 기능을 시작할 때 생성하는 기본 구조

| 생성 위치 | 추가할 파일 | 작성 내용 |
| --- | --- | --- |
| `lib/model/기능명/` | 데이터별 `.dart` | API 데이터와 JSON 변환. 서버 필드와 일치시킴 |
| `lib/view/기능명/` | 화면별 `기능명_화면명_view.dart` | 목록·상세·입력 등 실제 필요한 화면 |
| `lib/vm/기능명/` | `기능명_vm.dart` | 화면 상태·API 호출. 커지면 목록·상세·입력 VM으로 분리 |
| `python/features/기능명/` | `__init__.py`, `router.py` | 패키지 표시와 기능별 API 구현 |
| `test/vm/기능명/`, `test/view/기능명/` | 검증 대상별 `_test.dart` | 상태 처리·화면 동작의 관련 테스트 |
| `python/tests/features/기능명/` | `test_처리명.py` | API·권한·업무 규칙의 관련 테스트 |

모든 화면·테스트 파일을 빈 상태로 미리 만들지 않는다. 실제 개발하는 부분만 추가한다.
프론트 VM은 화면마다 반드시 하나씩 만들 필요가 없으며, 작은 기능은 하나로 시작한다.
백엔드의 `__init__.py`는 비워도 된다. 별도 기능 실행용 `main.py`는 만들지 않는다.

### 3.2. 예시 1 — 일정 기능

일정 목록·상세·입력과 수락 처리를 개발할 때의 기본 예시다.

```text
lib/
├─ model/schedules/
│  └─ schedule.dart
├─ view/schedules/
│  ├─ schedule_list_view.dart
│  ├─ schedule_detail_view.dart
│  └─ schedule_form_view.dart
└─ vm/schedules/
   └─ schedule_vm.dart

python/features/schedules/
├─ __init__.py
└─ router.py

test/vm/schedules/
└─ schedule_vm_test.dart
python/tests/features/schedules/
└─ test_schedule_acceptance.py
```

- `schedule.dart`: 확정 API에 맞춘 일정 데이터와 JSON 변환.
- `schedule_vm.dart`: 목록 조회·등록·수락 요청, 로딩·오류·성공 후 데이터 갱신.
- `router.py`: 일정 API, 현재 공간 권한 확인, 시간 중복·동시 수락 처리와 SQL.
- 수락 테스트: 동시에 요청해도 담당자가 두 명 배정되지 않는지 검증한다.
  실제 동시성 보장은 테스트 DB에서 확인해야 하며 mock 테스트만으로 확정하지 않는다.
- 변경·교체 기능을 구현할 때 필요한 요청 모델·화면을 같은 기능 폴더에 추가한다.
  요청·SQL 코드가 커지면 그때 `schemas.py`, `service.py`, `repository.py`로 분리한다.

### 3.3. 예시 2 — 메모 기능

메모 목록·상세·작성과 좋아요 처리를 개발할 때의 예시다.

```text
lib/
├─ model/memos/
│  └─ memo.dart
├─ view/memos/
│  ├─ memo_list_view.dart
│  ├─ memo_detail_view.dart
│  ├─ memo_form_view.dart
│  └─ widgets/
│     └─ memo_card.dart
└─ vm/memos/
   └─ memo_vm.dart

python/features/memos/
├─ __init__.py
└─ router.py

test/view/memos/
└─ memo_detail_view_test.dart
python/tests/features/memos/
└─ test_memo_likes.py
```

- `memo.dart`: 메모와 API가 제공하는 좋아요 상태 등의 데이터 변환.
- `memo_vm.dart`: 조회·작성·수정·삭제·좋아요 API 호출과 화면 상태 갱신.
- `memo_card.dart`: 메모 화면에서만 쓰는 위젯. 다른 기능에 복사하지 않는다.
- `router.py`: 메모 API, 공간 참여·작성자 권한 확인, 중복 좋아요 방지.
- 좋아요 테스트: 반복 요청에도 한 번만 반영되고, 취소 기능을 제공하지 않는지 검증한다.

### 3.4. 파일 생성 후 연결하는 순서

1. 담당 기능 이름·API 입출력·실제 DB 이름을 관련 팀원과 확인한다.
2. 위 규칙에 따라 필요한 모델·화면·VM과 백엔드 `router.py`를 추가한다.
3. 구현된 라우터를 `python/main.py`에서 import하고 `include_router()`로 등록한다.
4. Flutter 화면 진입 경로와 선택한 상태 관리 방식에 따른 VM 등록을 연결한다.
   모든 화면·VM을 `main.dart`에 직접 import하도록 강제하는 것은 아니다.
5. API·모델 필드와 로그인·현재 공간 전달 방식을 맞추고 관련 테스트를 추가한다.
6. 관련 테스트 후 문서 하단의 전체 검증을 실행하고 PR에 변경·검증 내용을 적는다.

이 문서의 예시는 생성 방법 안내다. 실제 기능 폴더·파일을 이번 문서 수정으로 생성하지 않는다.

## 4. 프론트 코드 작성 기준

| 위치 | 책임 |
| --- | --- |
| `main.dart` | 앱 시작·상태 관리 등록·앱 설정·화면 경로 연결 |
| `model/기능명/` | 데이터 필드, `fromJson`·`toJson` |
| `view/기능명/` | 화면 표시·입력·VM 호출·기능 전용 위젯 |
| `vm/기능명/` | 화면 데이터·로딩·오류 상태, API 호출, 성공 후 상태 갱신 |

- 파일명은 `snake_case`, 클래스명은 `UpperCamelCase`, 함수·변수명은 `lowerCamelCase`를 사용한다.
- 화면에서 HTTP 요청과 SQL 처리를 직접 구현하지 않는다. HTTP 요청은 VM에서 처리한다.
- JSON 필드·자료형·null 허용 여부는 서버 계약과 맞춘다. DB 이름을 추측해 모델을 만들지 않는다.
- 공통 로그인·선택 공간 상태는 하나의 공유 상태를 사용한다. 각 VM에 독립적으로 복사해 두지 않는다.
- 공간 전환·참여 종료 시 이전 공간 데이터·진행 중 요청·채팅 연결 처리 규칙을 맞춘다.
- 서버 주소·인증 헤더·HTTP 타임아웃·오류 해석은 각자 다른 방식으로 작성하지 않는다.
  공통 폴더 없이 어느 파일에서 공유할지는 팀 합의가 필요하다.
- 화면 파일명에 기능명을 넣는다. 화면이 커지면 전용 위젯은 해당 기능의 `widgets/`에 둔다.
- Firebase 생성 설정은 플랫폼 연결 정보다. 초기화·로그인·서버 토큰 검증은 별도 구현한다.

## 5. 백엔드 코드 작성 기준

수업의 `fastapi_02.py`는 `python/main.py`, `items.py`는 기능별 `router.py`에 대응한다.

```python
# 기능 담당자가 추가할 router.py의 기본 형태
from fastapi import APIRouter

router = APIRouter()

# 이 아래에 실제 API를 구현한다.
```

구현한 라우터는 `main.py`에서 import하고 `app.include_router()`로 등록한다.
prefix·tags는 등록 위치인 `main.py`에서 지정해 이중 prefix를 피한다.
구체 URL·HTTP 메서드는 API 문서에서 합의한다. 기능별로 `FastAPI()`를 새로 만들지 않는다.

- 처음에는 `router.py`에서 입력 모델·업무 처리·SQL을 함께 관리할 수 있다.
- 복잡한 기능만 `schemas.py`, `service.py`, `repository.py`로 분리한다. 전체 기능에 강제하지 않는다.
- 동기 PyMySQL을 사용하는 API는 일반 `def`로 작성한다.
- `from python.database import connect`로 연결을 생성한다. 삭제된 공통 의존성은 사용하지 않는다.
- 연결은 요청별로 만들고 `finally`에서 종료한다. cursor는 `with conn.cursor()`로 관리한다.
- 변경 SQL은 한 업무에서 같은 연결을 사용하고 전체 성공 후 한 번 commit한다.
  실패 시 rollback하고 오류를 다시 전달한다. 보조 SQL 함수에서는 개별 commit하지 않는다.
- SQL 값은 `%s` 파라미터 바인딩으로 전달한다. 입력값을 문자열로 이어 SQL을 만들지 않는다.
- `DictCursor`를 사용하므로 조회 결과의 컬럼명과 모델 변환을 맞춘다.
- 현재는 FastAPI 기본 오류 응답을 사용한다. 업무 실패는 `HTTPException`으로 구분한다.
  API 오류에 SQL·접속 정보·내부 예외 원문을 그대로 반환하지 않는다.
- 입력 오류·권한 없음·없는 데이터·중복 요청 등의 상태 코드와 응답 필드는 API별 구현 전에 합의한다.

## 6. 프로젝트 전체에서 통일해야 하는 데이터·권한 규칙

다음은 전달받은 프로세스 기준이다. 구체적인 SQL 구조를 확정하는 내용은 아니다.

- 일반 계정은 가족으로 가입한다. 주보호자·일반 가족은 공간별 역할이다.
- 공간마다 대상자 한 명, 주보호자 한 명, 공통 단체 대화방 하나를 관리한다.
- 공간별 요청은 서버에서 현재 참여 여부와 필요한 역할을 검사한다. 화면 버튼 숨김만으로 대체하지 않는다.
- 일정·투약·대상자 돌봄 메모는 현재 공간의 대상자와 연결한다. 임의 대상자 ID 전달을 신뢰하지 않는다.
- 일정 수락자는 최대 한 명이다. 조회 후 단순 저장만 하지 말고 동시 수락을 DB 처리에서 방지한다.
- 투약 체크는 해당 회차의 공유 완료 상태이며, 가족별 별도 완료 기록으로 만들지 않는다.
- 같은 메모의 좋아요는 계정별 한 번이고 취소할 수 없다. 재전송·동시 요청도 중복 방지한다.
- 채팅 저장 후 실시간 전달하며 재전송 중복을 방지한다. 입장·전송·재연결·이미지 조회에 권한을 적용한다.
- 일반 탈퇴·강퇴는 기존 작성 기록을 보존한다. 공간 삭제는 해당 공간 데이터 삭제 규칙을 적용한다.
- 초대 수락에는 로그인 이메일과 초대 이메일 일치 여부를 확인한다.
- 내보내기는 메모·채팅만 대상으로 한다. 투약 정보·투약일지는 포함하지 않는다.

## 7. 여러 담당자의 기능이 연결되는 작업

| 작업 | 조율 담당 | 연결할 처리 |
| --- | --- | --- |
| 공간 생성 | 장은혜 | 대상자·주보호자 참여 등록 + 김승현의 대화방 생성 |
| 일정 등록·변경·삭제 | 장은혜 | 진건웅의 알림·재알림 예약 변경·취소 |
| 탈퇴·강퇴 | 장은혜 | 담당 일정 해제 + 채팅 연결·자료 접근 해제 |
| 공간 삭제 | 장은혜 | 각 담당 기능의 데이터·파일 정리, 예약 알림 중단 |

필요한 함수의 입력·반환값·실패 처리를 먼저 정한다. 기능 담당자가 다른 기능의 SQL을
복사해 쓰지 않는다. 이메일·실시간 전달·파일 삭제처럼 DB 트랜잭션 밖의 처리는
실패 시 재시도·복구 방식도 별도로 정한다.

## 8. 구현 전에 팀이 결정할 항목

| 항목 | 정할 내용 |
| --- | --- |
| 상태 관리 | GetX·Provider·Riverpod 중 하나, VM 생성·조회·해제 방법 |
| 인증 | Firebase Auth 사용 여부·로그인 방식·토큰 전달·서버 검증·로그아웃 처리 |
| 공유 상태 | 사용자·선택 공간·역할을 관리할 파일과 인터페이스 |
| API 계약 | URL·메서드·JSON 또는 Form·필드명·응답·오류·목록 조회 규칙 |
| 시간 | 서버·DB·앱의 시간대와 날짜·시간 직렬화 형식 |
| DB | 실제 스키마·키·상태값·동시 처리 방식·변경 SQL 공유 위치 |
| 알림 | 채널, 재알림 수신 대상, 중복 발송 처리 |
| 파일·이메일 | 저장·다운로드 권한·용량·형식·발송 설정 |
| Git | 기능 브랜치명·PR 검토·병합 방식, main.py·database.py·패키지 파일 변경 담당 |

정책 미정 사항은 `pending-decisions.md`에 결정 후 기록한다. 특히 일정 변경 대기 중
담당 상태, 변경·교체 요청 충돌, 투약 체크 취소·회차 생성, 새 참여자의 과거 채팅 공개,
공간 실제 삭제·이력 보존 방식은 임의로 확정하지 않는다.
방문·QR·위치 확인도 가족용 유지가 확정되기 전에는 기능에 추가하지 않는다.

## 9. 환경 설정·실행·검증

프로젝트 루트에서 실행한다. `.env`는 각자 작성하며 Git에 올리지 않는다.
`MYSQL_HOST`, `MYSQL_PORT`, `MYSQL_USER`, `MYSQL_PASSWORD`, `MYSQL_DATABASE`를 사용한다.
`database.py`는 실행 위치와 무관하게 `python/.env`를 읽으며 환경변수가 우선한다.

```powershell
flutter pub get
flutter run

python -m pip install -r python/requirements-dev.txt
python -m uvicorn python.main:app --reload
```

서버만 실행하면 `python/requirements.txt`를 설치해도 된다.
`GET /health`는 프로세스 상태만 확인하며 DB 연결이나 인증 완료를 의미하지 않는다.

```powershell
python -m unittest discover -s python/tests -p "test_*.py" -v
dart format lib test
flutter analyze
flutter test
```

현재 백엔드 테스트는 실제 DB·실제 `.env` 없이 연결 설정을 검증한다.
이 테스트 통과만으로 DB 통합·Firebase 로그인·플랫폼 빌드가 검증되는 것은 아니다.

기능 PR에는 변경 파일, API·DB 계약 변경, 실행한 관련 테스트와 미구현 항목을 적는다.
관련 테스트를 먼저 실행하고 마지막 전체 검증은 한 번 실행한다.
