import logging
from uuid import uuid4

from fastapi import APIRouter, Depends, File, Form, HTTPException, Path, Query, Request, Response, UploadFile
from pydantic import BaseModel, ConfigDict, Field
import pymysql

from python.features.auth.firebase_auth import require_firebase_user
from python.database import connect
from python.features.memos.images import read_image

router = APIRouter(prefix="/memos", tags=["메모"])
logger = logging.getLogger(__name__)


def get_current_user_id(claims: dict = Depends(require_firebase_user)) -> str:
    """검증된 UID에 연결된 등록·미탈퇴 사용자의 내부 ID를 반환한다."""
    conn = None
    try:
        conn = connect()
        with conn.cursor() as cursor:
            cursor.execute(
                """SELECT user_id, withdrawn_at
                   FROM `user`
                   WHERE user_firebase_uid = %s
                     AND BINARY user_firebase_uid = BINARY %s
                   LIMIT 1""",
                (claims["uid"], claims["uid"]),
            )
            user = cursor.fetchone()
        if user is None:
            raise HTTPException(403, "사용자 정보 등록을 먼저 완료해 주세요.")
        if user["withdrawn_at"] is not None:
            raise HTTPException(403, "탈퇴 처리된 계정입니다.")
        return user["user_id"]
    except (pymysql.MySQLError, ValueError):
        raise HTTPException(503, "사용자 정보를 확인하지 못했습니다.") from None
    finally:
        if conn is not None:
            conn.close()


class MemoCreate(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True)

    family_room_id: str = Field(min_length=1, max_length=50)
    memo_content: str = Field(min_length=1, max_length=2000)


class MemoUpdate(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True, extra="forbid")

    family_room_id: str = Field(min_length=1, max_length=50)
    memo_content: str = Field(min_length=1, max_length=2000)


class MemoLikeCreate(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True, extra="forbid")

    family_room_id: str = Field(min_length=1, max_length=50)
    author_user_id: str = Field(min_length=1, max_length=50)


@router.post("/like/{memo_id}")
def like_memo(
    data: MemoLikeCreate,
    memo_id: str = Path(min_length=1, max_length=50, pattern=r"\S"),
    current_user_id: str = Depends(get_current_user_id),
):
    """현재 공간 참여자가 메모에 한 번만 좋아요를 등록한다. 취소는 제공하지 않는다."""
    conn = None
    try:
        conn = connect()
        with conn.cursor() as cursor:
            # 참여 종료·공간 삭제·사용자 탈퇴와 등록이 엇갈리지 않도록 잠근다.
            cursor.execute(
                """SELECT p.participate_seq FROM participate AS p
                   JOIN family_room AS f ON f.family_room_id = p.family_room_id
                   JOIN `user` AS u ON u.user_id = p.user_id
                   WHERE p.family_room_id = %s AND p.user_id = %s
                     AND p.is_active = 1 AND p.left_at IS NULL
                     AND f.family_room_deleted_at IS NULL AND u.withdrawn_at IS NULL
                   LIMIT 1 FOR UPDATE""",
                (data.family_room_id, current_user_id),
            )
            if cursor.fetchone() is None:
                raise HTTPException(403, "해당 돌봄 공간에 좋아요를 등록할 수 없습니다.")

            key = (memo_id, data.family_room_id, data.author_user_id)
            # 메모 행 잠금으로 같은 메모의 동시 요청·삭제를 직렬화한다.
            cursor.execute(
                """SELECT COALESCE(likes, 0) AS likes FROM memo
                   WHERE memo_id = %s AND family_room_id = %s AND user_id = %s
                     AND memo_deleted_at IS NULL
                   FOR UPDATE""",
                key,
            )
            memo = cursor.fetchone()
            if memo is None:
                raise HTTPException(404, "메모가 없거나 삭제되었습니다.")
            likes = memo["likes"]
            like_key = (*key, current_user_id)
            cursor.execute(
                """SELECT 1 FROM memo_like
                   WHERE memo_id = %s AND family_room_id = %s
                     AND memo_author_id = %s AND user_id = %s
                   LIMIT 1 FOR UPDATE""",
                like_key,
            )
            already_liked = cursor.fetchone() is not None
            if not already_liked:
                cursor.execute(
                    """INSERT INTO memo_like (memo_id, family_room_id, memo_author_id, user_id)
                       VALUES (%s, %s, %s, %s)""",
                    like_key,
                )
                cursor.execute(
                    """UPDATE memo SET likes = COALESCE(likes, 0) + 1
                       WHERE memo_id = %s AND family_room_id = %s AND user_id = %s
                         AND memo_deleted_at IS NULL""",
                    key,
                )
                likes += 1
        conn.commit()
        return {"result": "OK", "memo_id": memo_id, "likes": likes,
                "is_liked": True, "already_liked": already_liked}
    except HTTPException:
        if conn is not None:
            conn.rollback()
        raise
    except (pymysql.MySQLError, ValueError):
        if conn is not None:
            conn.rollback()
        logger.exception("메모 좋아요 등록 실패")
        raise HTTPException(500, "좋아요를 등록하지 못했습니다.") from None
    finally:
        if conn is not None:
            conn.close()


def _lock_owned_memo(cursor, family_room_id: str, memo_id: str, user_id: str):
    """참여 상태와 메모를 같은 트랜잭션에서 잠그고 작성자 권한을 검사한다."""
    cursor.execute(
        """
        SELECT p.participate_seq
        FROM participate AS p
            JOIN family_room AS f ON f.family_room_id = p.family_room_id
            JOIN `user` AS u ON u.user_id = p.user_id
        WHERE p.family_room_id = %s AND p.user_id = %s
            AND p.is_active = 1 AND p.left_at IS NULL
            AND f.family_room_deleted_at IS NULL
            AND u.withdrawn_at IS NULL
        LIMIT 1 FOR UPDATE
        """,
        (family_room_id, user_id),
    )
    if cursor.fetchone() is None:
        raise HTTPException(403, "해당 돌봄 공간에 접근할 수 없습니다.")

    cursor.execute(
        """SELECT user_id FROM memo
           WHERE memo_id = %s AND family_room_id = %s
             AND memo_deleted_at IS NULL
           FOR UPDATE""",
        (memo_id, family_room_id),
    )
    memos = cursor.fetchall()
    if not memos:
        raise HTTPException(404, "메모가 없거나 삭제되었습니다.")
    if not any(memo["user_id"] == user_id for memo in memos):
        raise HTTPException(403, "메모 작성자만 수정하거나 삭제할 수 있습니다.")


@router.patch("/update/{memo_id}")
def update_memo(
    memo: MemoUpdate,
    memo_id: str = Path(min_length=1, max_length=50, pattern=r"\S"),
    current_user_id: str = Depends(get_current_user_id),
):
    """JSON 수정은 기존 이미지를 유지한다."""
    return _update_memo(memo, memo_id, current_user_id)


def _update_memo(memo: MemoUpdate, memo_id: str, current_user_id: str,
                 image_changed: bool = False, image_data: bytes | None = None):
    conn = None
    try:
        conn = connect()
        with conn.cursor() as cursor:
            _lock_owned_memo(cursor, memo.family_room_id, memo_id, current_user_id)
            image_sql = ", memo_image = %s" if image_changed else ""
            params = (memo.memo_content,)
            if image_changed:
                params += (image_data,)
            cursor.execute(
                f"""UPDATE memo
                   SET memo_content = %s{image_sql}, memo_updated_at = CURRENT_TIMESTAMP
                   WHERE memo_id = %s AND family_room_id = %s AND user_id = %s
                     AND memo_deleted_at IS NULL""",
                (*params, memo_id, memo.family_room_id, current_user_id),
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
        logger.exception("메모 수정 실패")
        raise HTTPException(500, "메모를 수정하지 못했습니다.") from None
    finally:
        if conn is not None:
            conn.close()


@router.delete("/delete/{memo_id}")
def delete_memo(
    memo_id: str = Path(min_length=1, max_length=50, pattern=r"\S"),
    family_room_id: str = Query(min_length=1, max_length=50, pattern=r"\S"),
    current_user_id: str = Depends(get_current_user_id),
):
    """현재 공간에 참여 중인 작성자가 메모를 소프트 삭제한다."""
    conn = None
    try:
        conn = connect()
        with conn.cursor() as cursor:
            _lock_owned_memo(cursor, family_room_id, memo_id, current_user_id)
            cursor.execute(
                """UPDATE memo SET memo_deleted_at = CURRENT_TIMESTAMP
                   WHERE memo_id = %s AND family_room_id = %s AND user_id = %s
                     AND memo_deleted_at IS NULL""",
                (memo_id, family_room_id, current_user_id),
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
        logger.exception("메모 삭제 실패")
        raise HTTPException(500, "메모를 삭제하지 못했습니다.") from None
    finally:
        if conn is not None:
            conn.close()


@router.post("/insert", status_code=201)
def insert_memo(memo: MemoCreate, current_user_id: str = Depends(get_current_user_id)):
    """인증된 사용자의 현재 공간 참여를 확인하고 그 사용자를 작성자로 저장한다."""
    return _insert_memo(memo, current_user_id)


def _insert_memo(memo: MemoCreate, current_user_id: str, image_data: bytes | None = None):
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
                    detail="해당 돌봄 공간에 메모를 작성할 수 없습니다.",
                )

            memo_id = str(uuid4())
            image_column = ", memo_image" if image_data is not None else ""
            image_value = ", %s" if image_data is not None else ""
            params = (memo_id, memo.family_room_id, current_user_id, memo.memo_content, 0)
            if image_data is not None:
                params += (image_data,)
            cursor.execute(
                f"""
                INSERT INTO memo
                    (memo_id, family_room_id, user_id, memo_content, likes{image_column})
                VALUES (%s, %s, %s, %s, %s{image_value})
                """,
                params,
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


def _form_content(family_room_id: str, memo_content: str) -> dict:
    room, content = family_room_id.strip(), memo_content.strip()
    if not 1 <= len(room) <= 50 or not 1 <= len(content) <= 2000:
        raise HTTPException(422, "공간 ID와 1~2,000자의 메모 내용을 입력해 주세요.")
    return {"family_room_id": room, "memo_content": content}


async def _single_memo_image(
    request: Request,
    image: UploadFile = File(
        default=None,
        description="선택 사항: 이미지 파일 한 장 (최대 5MB)",
        json_schema_extra={"format": "binary"},
    ),
) -> UploadFile | None:
    # 단일 binary 스키마로 Swagger 파일 선택기를 표시한다. 같은 필드에
    # 파일을 반복 전송해도 마지막 파일만 저장하지 않고 명시적으로 거절한다.
    form = await request.form()
    if len(form.getlist("image")) > 1:
        raise HTTPException(422, "이미지는 한 장만 첨부할 수 있습니다.")
    return image


@router.post("/insert-with-image", status_code=201)
def insert_memo_with_image(
    family_room_id: str = Form(min_length=1, max_length=50),
    memo_content: str = Form(min_length=1, max_length=2000),
    image: UploadFile | None = Depends(_single_memo_image),
    current_user_id: str = Depends(get_current_user_id),
):
    """텍스트와 최대 한 장의 이미지를 같은 트랜잭션으로 저장한다."""
    memo = MemoCreate(**_form_content(family_room_id, memo_content))
    return _insert_memo(memo, current_user_id, read_image([image] if image else None))


@router.patch("/update-with-image/{memo_id}")
def update_memo_with_image(
    memo_id: str = Path(min_length=1, max_length=50, pattern=r"\S"),
    family_room_id: str = Form(min_length=1, max_length=50),
    memo_content: str = Form(min_length=1, max_length=2000),
    image: UploadFile | None = Depends(_single_memo_image),
    remove_image: bool = Form(default=False),
    current_user_id: str = Depends(get_current_user_id),
):
    """이미지 생략은 유지, 첨부는 교체, remove_image=true는 제거한다."""
    memo = MemoUpdate(**_form_content(family_room_id, memo_content))
    data = read_image([image] if image else None, remove_image)
    return _update_memo(memo, memo_id, current_user_id,
                        image_changed=bool(image) or remove_image, image_data=data)


@router.get("/image/{memo_id}")
def select_memo_image(
    memo_id: str = Path(min_length=1, max_length=50, pattern=r"\S"),
    family_room_id: str = Query(min_length=1, max_length=50),
    author_user_id: str = Query(min_length=1, max_length=50),
    current_user_id: str = Depends(get_current_user_id),
):
    """현재 공간 참여자에게만 삭제되지 않은 메모의 이미지를 전달한다."""
    conn = None
    try:
        conn = connect()
        with conn.cursor() as cursor:
            cursor.execute(
                """SELECT 1 FROM participate AS p
                   JOIN family_room AS f ON f.family_room_id = p.family_room_id
                   JOIN `user` AS u ON u.user_id = p.user_id
                   WHERE p.family_room_id = %s AND p.user_id = %s
                     AND p.is_active = 1 AND p.left_at IS NULL
                     AND f.family_room_deleted_at IS NULL AND u.withdrawn_at IS NULL
                   LIMIT 1""",
                (family_room_id, current_user_id),
            )
            if cursor.fetchone() is None:
                raise HTTPException(403, "해당 돌봄 공간에 접근할 수 없습니다.")
            cursor.execute(
                """SELECT m.memo_image FROM memo AS m
                   JOIN family_room AS f ON f.family_room_id = m.family_room_id
                   WHERE m.memo_id = %s AND m.family_room_id = %s AND m.user_id = %s
                     AND m.memo_deleted_at IS NULL AND f.family_room_deleted_at IS NULL
                   LIMIT 1""",
                (memo_id, family_room_id, author_user_id),
            )
            row = cursor.fetchone()
            if row is None or not row["memo_image"]:
                raise HTTPException(404, "메모 이미지가 없거나 삭제되었습니다.")
            data = bytes(row["memo_image"])
        # 신규 업로드는 JPEG로 저장한다. 기존 PNG·WEBP BLOB도 표시한다.
        media_type = "image/png" if data.startswith(b"\x89PNG\r\n\x1a\n") else (
            "image/webp" if data.startswith(b"RIFF") else "image/jpeg")
        return Response(content=data, media_type=media_type, headers={
            "Cache-Control": "private, no-store", "X-Content-Type-Options": "nosniff",
        })
    except (pymysql.MySQLError, ValueError):
        logger.exception("메모 이미지 조회 실패")
        raise HTTPException(500, "메모 이미지를 불러오지 못했습니다.") from None
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
                    detail="해당 돌봄 공간에 접근할 수 없습니다.",
                )
            cursor.execute(
                """
                SELECT m.memo_id, m.family_room_id, m.user_id, m.memo_content,
                    m.likes, m.written_at, m.memo_updated_at,
                    u.name AS author_name, (m.memo_image IS NOT NULL) AS has_image,
                    EXISTS (
                        SELECT 1 FROM memo_like AS ml
                        WHERE ml.memo_id = m.memo_id AND ml.family_room_id = m.family_room_id
                          AND ml.memo_author_id = m.user_id AND ml.user_id = %s
                    ) AS is_liked
                FROM memo AS m
                    JOIN family_room AS f ON f.family_room_id = m.family_room_id
                    LEFT JOIN `user` AS u ON u.user_id = m.user_id
                WHERE m.family_room_id = %s
                    AND m.memo_deleted_at IS NULL
                    AND f.family_room_deleted_at IS NULL
                ORDER BY m.written_at DESC, m.memo_id DESC, m.user_id DESC
                LIMIT %s OFFSET %s
                """,
                (current_user_id, family_room_id, limit, offset),
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
