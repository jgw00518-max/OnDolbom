import logging
from datetime import date

from fastapi import APIRouter, Depends, HTTPException, Query
import pymysql

if __package__.startswith("python."):
    from ...auth import get_current_user_id
    from ...database import connect
else:
    from auth import get_current_user_id
    from database import connect

router = APIRouter(prefix="/medications", tags=["투약일지"])
logger = logging.getLogger(__name__)


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
