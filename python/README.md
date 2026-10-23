# 사용자 앱 백엔드 공통 기반

프로젝트 루트 `C:\My\ondolbom`에서 실행합니다.

```powershell
python -m pip install -r python/requirements.txt
python -m uvicorn python.main:app --reload
```

`GET /health`는 서버 실행 상태만 확인합니다. DB 연결 검사는 아닙니다.
`python/.env.example`의 항목을 참고해 로컬 `python/.env`를 작성합니다.
기존 설정 파일은 자동으로 덮어쓰지 않습니다. 환경변수가 파일보다 우선합니다.

- `main.py`: FastAPI 생성, 기능별 라우터 등록, `/health` 제공
- `database.py`: `.env` 읽기, 필수 MySQL 설정 검사, DictCursor·수동 commit 연결 생성

## 폴더 구성과 기능 추가

`main.py`에서 FastAPI를 생성하고 기능별 `APIRouter`를 등록합니다.
DB 연결과 환경 설정 읽기는 `database.py`에서 처리합니다.
오류 응답은 FastAPI 기본 형식을 사용하며, 기능별 오류는 API에서 `HTTPException` 등으로 처리합니다.

기능 담당자가 개발할 때 `features/기능명/` 안에 `__init__.py`와 `router.py`를
추가합니다. 수업의 `fastapi_02.py`는 `main.py`, `items.py`는 기능별
`router.py`에 대응합니다. API 공통 prefix와 tags는 `main.py`에서 등록합니다.

처음에는 `router.py`에서 요청·업무 처리·SQL을 구현해도 됩니다.
코드가 커지는 기능만 `schemas.py`, `service.py`, `repository.py`로 분리합니다.
모든 기능에 계층 분리를 강제하지 않습니다.

DB를 사용하는 API는 동기 `def`로 작성하고 `from python.database import connect`로
연결 함수를 가져옵니다. 각 API에서 연결한 뒤 하나의 업무에서 같은 연결을 사용합니다.
전체 성공 후 한 번 commit하고, 실패하면 rollback한 뒤 오류를 전달하며,
finally에서 연결을 종료합니다. 분리한 SQL 함수에서는 개별 commit하지 않습니다.

인증 방식·실제 테이블은 확정하지 않았습니다. 현재 사용자 조회와 공간 권한
검사는 아직 구현하지 않았습니다. 공간별 API는 구현 시 현재 참여 여부와
필요한 역할을 서버에서 검사해야 합니다. 권한 검사 함수를 구현한 상태는 아닙니다.
이메일과 파일 처리 공통 모듈은 실제 처리 방식 확정 후 추가합니다. 기능 router는 구현 후
`main.py`에 등록합니다. 기능별 코드는 이 예시에 포함하지 않습니다.

테스트는 실제 DB나 `.env`를 사용하지 않습니다.

```powershell
python -m pip install -r python/requirements-dev.txt
python -m unittest discover -s python/tests -p "test_*.py" -v
```
