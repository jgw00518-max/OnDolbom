import logging
from datetime import date
from decimal import Decimal

from fastapi import APIRouter, Depends, HTTPException, Query
from pydantic import BaseModel, ConfigDict, Field
import pymysql

from python.features.auth.firebase_auth import require_firebase_user
from python.database import connect

router = APIRouter(prefix="/medications", tags=["투약일지"])
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


class MedicationCreate(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True, extra="forbid")

    family_room_id: str = Field(min_length=1, max_length=50)
    medication_info: str = Field(min_length=1, max_length=100)
    medication_date: date
    medication_time: str = Field(min_length=1, max_length=20)
    dosage_unit: str = Field(min_length=1, max_length=20)
    dosage: Decimal = Field(gt=0, max_digits=10, decimal_places=3)


@router.post("/insert", status_code=201)
def insert_medication(
    medication: MedicationCreate,
    current_user_id: str = Depends(get_current_user_id),
):
    """현재 공간 참여자가 미확인 상태의 투약일지를 작성한다."""
    conn = None
    try:
        conn = connect()
        with conn.cursor() as cursor:
            # 저장이 끝날 때까지 참여 종료·공간 삭제·사용자 탈퇴와의 충돌을 방지한다.
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
                LIMIT 1
                FOR UPDATE
                """,
                (medication.family_room_id, current_user_id),
            )
            if cursor.fetchone() is None:
                raise HTTPException(
                    status_code=403,
                    detail="해당 가족 공간에 투약일지를 작성할 수 없습니다.",
                )

            cursor.execute(
                """
                INSERT INTO medication_log
                    (family_room_id, user_id, medication_info, medication_date,
                     medication_time, dosage_unit, dosage)
                VALUES (%s, %s, %s, %s, %s, %s, %s)
                """,
                (medication.family_room_id, current_user_id,
                 medication.medication_info, medication.medication_date,
                 medication.medication_time, medication.dosage_unit, medication.dosage),
            )
            medication_log_seq = cursor.lastrowid
        conn.commit()
        return {"result": "OK", "medication_log_seq": medication_log_seq}

    except HTTPException:
        if conn is not None:
            conn.rollback()
        raise
    except (pymysql.MySQLError, ValueError):
        if conn is not None:
            conn.rollback()
        logger.exception("투약일지 작성 실패")
        raise HTTPException(
            status_code=500, detail="투약일지를 저장하지 못했습니다.",
        ) from None
    finally:
        if conn is not None:
            conn.close()


@router.get("/select")
def select_medications(
    family_room_id: str = Query(min_length=1, max_length=50),
    medication_date: date | None = Query(default=None),
    limit: int = Query(default=20, ge=1, le=100),
    offset: int = Query(default=0, ge=0),
    current_user_id: str = Depends(get_current_user_id),
):
    """현재 참여 중인 공간의 투약일지를 조회하며 투약 날짜 필터를 지원한다."""
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
                    status_code=403, detail="해당 가족 공간에 접근할 수 없습니다.",
                )

            sql = """
                SELECT m.medication_log_seq, m.family_room_id, m.user_id,
                    m.medication_info, m.medication_date, m.medication_time,
                    m.dosage_unit, m.dosage, m.medication_confirmed_at,
                    m.recorded_at, m.record_updated_at
                FROM medication_log AS m
                    JOIN family_room AS f ON f.family_room_id = m.family_room_id
                WHERE m.family_room_id = %s
                    AND m.record_deleted_at IS NULL
                    AND f.family_room_deleted_at IS NULL
            """
            params = [family_room_id]
            if medication_date is not None:
                sql += " AND m.medication_date = %s"
                params.append(medication_date)
            sql += """
                ORDER BY m.medication_date DESC, m.recorded_at DESC,
                    m.medication_log_seq DESC
                LIMIT %s OFFSET %s
            """
            params.extend([limit, offset])
            cursor.execute(sql, tuple(params))
            return {"results": cursor.fetchall()}

    except (pymysql.MySQLError, ValueError):
        logger.exception("투약일지 목록 조회 실패")
        raise HTTPException(
            status_code=500, detail="투약일지 목록을 불러오지 못했습니다.",
        ) from None
    finally:
        if conn is not None:
            conn.close()
