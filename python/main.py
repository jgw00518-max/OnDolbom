"""프로젝트 루트에서 python -m uvicorn python.main:app --reload 로 실행."""

from fastapi import FastAPI

app = FastAPI(title="온돌봄 사용자 API")

# 기능 담당자가 구현한 router만 여기에서 include_router로 등록한다.


@app.get("/health", tags=["health"])
def health() -> dict[str, str]:
    """서버 프로세스 상태만 확인한다. DB 연결 성공을 의미하지 않는다."""
    return {"status": "ok"}
