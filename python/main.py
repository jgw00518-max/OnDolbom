"""프로젝트 루트에서 python -m uvicorn python.main:app --reload 로 실행."""

from fastapi import FastAPI
from python.features.auth.router import router as auth_router

if __package__:
    from .features.memos.router import router as memos_router
    from .features.medications.router import router as medications_router
else:
    from features.memos.router import router as memos_router
    from features.medications.router import router as medications_router

app = FastAPI(title="온돌봄 사용자 API")
app.include_router(auth_router, prefix="/auth", tags=["auth"])

# 기능 담당자가 구현한 router만 여기에서 include_router로 등록한다.
app.include_router(memos_router)
app.include_router(medications_router)


@app.get("/health", tags=["health"])
def health() -> dict[str, str]:
    """서버 프로세스 상태만 확인한다. DB 연결 성공을 의미하지 않는다."""
    return {"status": "ok"}

if __name__ == "__main__":
    import uvicorn

    uvicorn.run(app, host="127.0.0.1", port=8000)
