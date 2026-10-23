"""기능 API가 공유하는 인증 연결 지점. 토큰 검증 자체는 인증 담당 코드에서 수행한다."""

from fastapi import HTTPException, Request


def get_current_user_id(request: Request) -> str:
    """토큰 검증 후 서버가 request.state.user_id에 설정한 사용자만 허용한다.

    클라이언트의 user_id나 Authorization 헤더를 그대로 사용자 ID로 취급하지 않는다.
    현재 토큰 검증 코드가 없어 설정값이 없으면 401로 거절한다.
    """
    user_id = getattr(request.state, "user_id", None)
    if not isinstance(user_id, str) or not user_id.strip() or len(user_id) > 50:
        raise HTTPException(status_code=401, detail="로그인이 필요합니다.")
    return user_id
