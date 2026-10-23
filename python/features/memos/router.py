import logging
from uuid import uuid4

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, ConfigDict, Field
import pymysql

if __package__.startswith("python."):
    from ...auth import get_current_user_id
    from ...database import connect
else:
    from auth import get_current_user_id
    from database import connect

router = APIRouter(prefix="/memos", tags=["메모"])
logger = logging.getLogger(__name__)


class MemoCreate(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True)

    family_room_id: str = Field(min_length=1, max_length=50)
    memo_content: str = Field(min_length=1, max_length=10000)


@router.post("/insert", status_code=201)
def insert_memo(memo: MemoCreate, current_user_id: str = Depends(get_current_user_id)):
    """인증된 사용자의 현재 공간 참여를 확인하고 그 사용자를 작성자로 저장한다."""
    conn = None
    try:
        conn = connect()
        with conn.cursor() as cursor:
            # 저장 완료까지 참여 종료·공간 삭제·사용자 탈퇴와 충돌하지 않게 잠근다.
            cursor.execute(
                """
                SELECT p.participate_seq
                FROM participate AS p
                    JOIN family_room AS f ON f.family_room_id = p.family_room_id
                    JOIN `user` AS u ON u.user_id = p.user_id
                WHERE p.family_room_id = %s
                    AND p.user_id = %s
                    AND p.is_active = 1
                    AND p.left_at IS NULL
                    AND f.family_room_deleted_at IS NULL
                    AND u.withdrawn_at IS NULL
                LIMIT 1
                FOR UPDATE
                """,
                (memo.family_room_id, current_user_id),
            )
            if cursor.fetchone() is None:
                raise HTTPException(
                    status_code=403,
                    detail="해당 가족 공간에 메모를 작성할 수 없습니다.",
                )

            memo_id = str(uuid4())
            cursor.execute(
                """
                INSERT INTO memo
                    (memo_id, family_room_id, user_id, memo_content, likes)
                VALUES (%s, %s, %s, %s, %s)
                """,
                (memo_id, memo.family_room_id, current_user_id, memo.memo_content, 0),
            )
        conn.commit()
        return {"result": "OK", "memo_id": memo_id}

    except HTTPException:
        if conn is not None:
            conn.rollback()
        raise
    except (pymysql.MySQLError, ValueError):
        if conn is not None:
            conn.rollback()
        logger.exception("메모 작성 실패")
        raise HTTPException(
            status_code=500,
            detail="메모를 저장하지 못했습니다.",
        ) from None
    finally:
        if conn is not None:
            conn.close()


@router.get("/select")
def select_memos(
    family_room_id: str = Query(min_length=1, max_length=50),
    limit: int = Query(default=20, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
    current_user_id: str = Depends(get_current_user_id),
):
    """인증된 사용자가 현재 참여 중인 공간의 메모를 조회한다."""
    conn = None
    try:
        conn = connect()
        with conn.cursor() as cursor:
            cursor.execute(
                """
                SELECT 1
                FROM participate AS p
                    JOIN family_room AS f ON f.family_room_id = p.family_room_id
                    JOIN `user` AS u ON u.user_id = p.user_id
                WHERE p.family_room_id = %s AND p.user_id = %s
                    AND p.is_active = 1 AND p.left_at IS NULL
                    AND f.family_room_deleted_at IS NULL
                    AND u.withdrawn_at IS NULL
                LIMIT 1
                """,
                (family_room_id, current_user_id),
            )
            if cursor.fetchone() is None:
                raise HTTPException(
                    status_code=403,
                    detail="해당 가족 공간에 접근할 수 없습니다.",
                )
            cursor.execute(
                """
                SELECT m.memo_id, m.family_room_id, m.user_id, m.memo_content,
                    m.likes, m.written_at, m.memo_updated_at
                FROM memo AS m
                    JOIN family_room AS f ON f.family_room_id = m.family_room_id
                WHERE m.family_room_id = %s
                    AND m.memo_deleted_at IS NULL
                    AND f.family_room_deleted_at IS NULL
                ORDER BY m.written_at DESC, m.memo_id DESC, m.user_id DESC
                LIMIT %s OFFSET %s
                """,
                (family_room_id, limit, offset),
            )
            return {"results": cursor.fetchall()}

    except (pymysql.MySQLError, ValueError):
        logger.exception("메모 목록 조회 실패")
        raise HTTPException(
            status_code=500,
            detail="메모 목록을 불러오지 못했습니다.",
        ) from None
    finally:
        if conn is not None:
            conn.close()
