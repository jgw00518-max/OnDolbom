"""프로젝트 루트에서 python -m python.main 으로 실행."""

from fastapi import FastAPI

from python.features.auth.router import router as auth_router
from python.features.notifications.router import router as notifications_router
from python.features.family_room.router import router as family_room_router
from python.features.memos.router import router as memos_router
from python.features.medications.router import router as medications_router


app = FastAPI(title="온돌봄 사용자 API")

app.include_router(
    auth_router,
    prefix="/auth",
    tags=["auth"],
)

# 알림 목록·읽음·일정 조회 API를 /notifications 경로에 등록한다.
app.include_router(
    notifications_router,
    prefix="/notifications",
    tags=["notifications"],
)

app.include_router(
    family_room_router,
    prefix="/family-room",
    tags=["family_room"],
)

# 각 기능 파일에 지정된 경로를 유지한다.
app.include_router(memos_router)
app.include_router(medications_router)


@app.get("/health", tags=["health"])
def health() -> dict[str, str]:
    """서버 실행 상태만 확인한다. DB 연결 검사는 아니다."""
    return {"status": "ok"}


if __name__ == "__main__":
    import uvicorn

    uvicorn.run(
        "python.main:app",
        host="127.0.0.1",
        port=8000,
        reload=True,
    )
