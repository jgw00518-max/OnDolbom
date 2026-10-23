"""프로젝트 루트에서 python -m uvicorn python.main:app --reload 로 실행."""

from fastapi import FastAPI
from python.features.auth.router import router as auth_router
from python.features.notifications.router import router as notifications_router

app = FastAPI(title="온돌봄 사용자 API")
# 기능 파일에서는 APIRouter만 만들고, 공통 URL prefix는 여기에서 한 번 등록한다.
app.include_router(auth_router, prefix="/auth", tags=["auth"])
app.include_router(notifications_router, prefix="/notifications", tags=["notifications"])

# 기능 담당자가 구현한 router만 여기에서 include_router로 등록한다.


@app.get("/health", tags=["health"])
def health() -> dict[str, str]:
    """서버 프로세스 상태만 확인한다. DB 연결 성공을 의미하지 않는다."""
    return {"status": "ok"}
