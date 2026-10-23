"""프로젝트 루트에서 python -m uvicorn python.main:app --reload 로 실행."""

from fastapi import FastAPI
from python.features.auth.router import router as auth_router

from python.features.family_room.router import router as family_room_router

app = FastAPI(title="온돌봄 사용자 API")
app.include_router(auth_router, prefix="/auth", tags=["auth"])

app.include_router(
    family_room_router,
    prefix="/family-room",
    tags=["family_room"],
)

# 기능 담당자가 구현한 router만 여기에서 include_router로 등록한다.


@app.get("/health", tags=["health"])
def health() -> dict[str, str]:
    """서버 프로세스 상태만 확인한다. DB 연결 성공을 의미하지 않는다."""
    return {"status": "ok"}

# 이 파일을 직접 실행하면 FastAPI 서버를 시작한다.
if __name__ == "__main__":
    import uvicorn

    uvicorn.run(
        "python.main:app",
        host="0.0.0.0",
        port=8000,
        reload=True,
    )
