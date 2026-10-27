"""가족 본인의 문의 작성·조회. 관리자 답변 작성은 별도 관리자 프로젝트가 담당한다."""
from fastapi import APIRouter, Depends, HTTPException, Path, Query
from pydantic import BaseModel, ConfigDict, Field, field_validator
from pymysql import MySQLError

from python.database import connect
from python.features.auth.firebase_auth import require_firebase_user
from python.features.activity.receipts import answer_token

router = APIRouter(prefix="/inquiries", tags=["inquiries"])


class InquiryCreate(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)
    question_title: str = Field(min_length=1, max_length=100)
    question_content: str = Field(min_length=1, max_length=10000)
    family_room_id: str | None = Field(default=None, min_length=1, max_length=50)

    @field_validator("question_title", "question_content")
    @classmethod
    def supported_text(cls, value):
        # 현재 공유 테이블은 utf8mb3다. 저장 실패 대신 지원하지 않는 문자를 안내한다.
        if any(ord(char) > 0xFFFF for char in value):
            raise ValueError("현재 문의는 일부 이모지를 지원하지 않습니다. 이모지를 제외해 주세요.")
        return value


def current_user(cursor, claims, *, lock=False):
    cursor.execute(
        """SELECT user_id, withdrawn_at FROM `user`
           WHERE user_firebase_uid = %s AND BINARY user_firebase_uid = BINARY %s
           LIMIT 1""" + (" FOR UPDATE" if lock else ""),
        (claims["uid"], claims["uid"]),
    )
    row = cursor.fetchone()
    if row is None or row["withdrawn_at"] is not None:
        raise HTTPException(403, "사용자 등록 상태를 확인해 주세요.")
    return row["user_id"]


# 답변 존재 여부는 기존 answer 테이블로 계산한다. 처리 상태 컬럼을 새로 만들지 않는다.
SUMMARY = """SELECT q.question_seq, q.question_title, q.family_room_id, q.questioned_at,
    EXISTS(SELECT 1 FROM answer a WHERE a.question_seq = q.question_seq
        AND a.user_id = q.user_id AND a.answer_deleted_at IS NULL) AS answered
    FROM question q"""


@router.get("")
def list_inquiries(before_seq: int | None = Query(default=None, gt=0),
                   claims: dict = Depends(require_firebase_user)):
    connection = None
    try:
        connection = connect()
        with connection.cursor() as cursor:
            user_id = current_user(cursor, claims)
            sql = SUMMARY + " WHERE q.user_id = %s AND q.question_deleted_at IS NULL"
            params = [user_id]
            if before_seq is not None:
                sql += " AND q.question_seq < %s"
                params.append(before_seq)
            cursor.execute(sql + " ORDER BY q.question_seq DESC LIMIT 51", params)
            rows = cursor.fetchall()
        return {"items": rows[:50], "next_cursor": rows[49]["question_seq"] if len(rows) > 50 else None}
    except (MySQLError, ValueError):
        raise HTTPException(503, "문의 목록을 불러오지 못했습니다.") from None
    finally:
        if connection is not None:
            connection.close()


@router.post("", status_code=201)
def create_inquiry(payload: InquiryCreate, claims: dict = Depends(require_firebase_user)):
    connection = None
    try:
        connection = connect()
        with connection.cursor() as cursor:
            user_id = current_user(cursor, claims, lock=True)
            if payload.family_room_id is not None:
                # 공간 연결 시에만 현재 참여·공간 삭제 상태를 검사한다. 공간 없는 문의도 허용한다.
                cursor.execute("""SELECT p.participate_seq FROM participate p
                    JOIN family_room f ON f.family_room_id = p.family_room_id
                    WHERE p.user_id = %s AND p.family_room_id = %s AND p.left_at IS NULL
                    AND f.family_room_deleted_at IS NULL LIMIT 1 FOR UPDATE""",
                    (user_id, payload.family_room_id))
                if cursor.fetchone() is None:
                    raise HTTPException(403, "현재 참여 중인 공간만 문의에 연결할 수 있습니다.")
            # 작성자는 클라이언트 입력이 아니라 검증된 Firebase UID에서 결정한다.
            cursor.execute("""INSERT INTO question
                (user_id, family_room_id, question_title, question_content) VALUES (%s, %s, %s, %s)""",
                (user_id, payload.family_room_id, payload.question_title, payload.question_content))
            question_seq = cursor.lastrowid
        connection.commit()
        return {"question_seq": question_seq}
    except HTTPException:
        if connection is not None:
            connection.rollback()
        raise
    except (MySQLError, ValueError):
        if connection is not None:
            connection.rollback()
        raise HTTPException(503, "저장 결과를 확인하지 못했습니다. 문의 목록을 확인한 후 다시 시도해 주세요.") from None
    finally:
        if connection is not None:
            connection.close()


@router.get("/{question_seq}")
def inquiry_detail(question_seq: int = Path(gt=0), claims: dict = Depends(require_firebase_user)):
    connection = None
    try:
        connection = connect()
        with connection.cursor() as cursor:
            user_id = current_user(cursor, claims)
            cursor.execute("""SELECT question_seq, question_title, question_content,
                family_room_id, questioned_at FROM question
                WHERE question_seq = %s AND user_id = %s AND question_deleted_at IS NULL""",
                (question_seq, user_id))
            question = cursor.fetchone()
            # 다른 사용자의 문의와 삭제된 문의는 존재 여부도 구분해 공개하지 않는다.
            if question is None:
                raise HTTPException(404, "문의를 찾을 수 없습니다.")
            cursor.execute("""SELECT answer_seq, answer_content, answered_at FROM answer
                WHERE question_seq = %s AND user_id = %s AND answer_deleted_at IS NULL
                ORDER BY answered_at, answer_seq""", (question_seq, user_id))
            answers = cursor.fetchall()
        return {**question, "answered": bool(answers), "answers": answers,
                "badge_token": answer_token(answers) if answers else None}
    except (MySQLError, ValueError):
        raise HTTPException(503, "문의 내용을 불러오지 못했습니다.") from None
    finally:
        if connection is not None:
            connection.close()
