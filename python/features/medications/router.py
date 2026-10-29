import logging
from datetime import date, timedelta
from uuid import uuid4
from decimal import Decimal

from fastapi import APIRouter, Depends, HTTPException, Path, Query
from pydantic import BaseModel, ConfigDict, Field, NaiveDatetime, model_validator
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

    # 시작일을 포함해 날짜별로 생성하며 과도한 행 생성을 제한한다.
    duration_days: int = Field(default=1, ge=1, le=365, strict=True)

    @model_validator(mode="after")
    def validate_period(self):
        try:
            self.medication_date + timedelta(days=self.duration_days - 1)
        except OverflowError:
            raise ValueError("복용 기간의 종료일을 확인해 주세요.") from None
        return self


class MedicationUpdate(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True, extra="forbid")

    family_room_id: str = Field(min_length=1, max_length=50)
    medication_info: str | None = Field(default=None, min_length=1, max_length=100)
    medication_date: date | None = None
    medication_time: str | None = Field(default=None, min_length=1, max_length=20)
    dosage_unit: str | None = Field(default=None, min_length=1, max_length=20)
    dosage: Decimal | None = Field(default=None, gt=0, max_digits=10, decimal_places=3)

    @model_validator(mode="after")
    def validate_changes(self):
        changed = self.model_fields_set - {"family_room_id"}
        if not changed:
            raise ValueError("수정할 투약 정보를 하나 이상 입력해 주세요.")
        if any(getattr(self, name) is None for name in changed):
            raise ValueError("투약 정보는 null로 변경할 수 없습니다.")
        return self


class MedicationConfirm(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True, extra="forbid")

    family_room_id: str = Field(min_length=1, max_length=50)


class MedicationUnconfirm(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True, extra="forbid")

    family_room_id: str = Field(min_length=1, max_length=50)
    # 목록 응답의 원본 값을 전달한다. 표시용으로 변환한 시간이 아니다.
    expected_confirmed_at: NaiveDatetime
    expected_confirmed_by_user_id: str | None = Field(min_length=1, max_length=50)


@router.delete("/confirm/{medication_log_seq}")
def unconfirm_medication(
    data: MedicationUnconfirm,
    medication_log_seq: int = Path(gt=0),
    current_user_id: str = Depends(get_current_user_id),
):
    """활성 참여자인 체크 본인 또는 현재 주보호자가 완료 체크를 해제한다."""
    conn = None
    try:
        conn = connect()
        with conn.cursor() as cursor:
            # 체크와 같은 잠금 순서로 참여 종료·역할 변경·동시 체크와 직렬화한다.
            cursor.execute(
                """SELECT p.participate_seq, p.is_representative FROM participate AS p
                   JOIN family_room AS f ON f.family_room_id = p.family_room_id
                   JOIN `user` AS u ON u.user_id = p.user_id
                   WHERE p.family_room_id = %s AND p.user_id = %s
                     AND p.is_active = 1 AND p.left_at IS NULL
                     AND f.family_room_deleted_at IS NULL AND u.withdrawn_at IS NULL
                   LIMIT 1 FOR UPDATE""",
                (data.family_room_id, current_user_id),
            )
            member = cursor.fetchone()
            if member is None:
                raise HTTPException(403, "해당 가족 공간의 투약일지 체크를 해제할 수 없습니다.")
            key = (medication_log_seq, data.family_room_id)
            cursor.execute(
                """SELECT medication_confirmed_at, confirmed_by_user_id FROM medication_log
                   WHERE medication_log_seq = %s AND family_room_id = %s
                     AND record_deleted_at IS NULL FOR UPDATE""", key,
            )
            record = cursor.fetchone()
            if record is None:
                raise HTTPException(404, "투약일지가 없거나 삭제되었습니다.")
            already_unconfirmed = record["medication_confirmed_at"] is None
            if not already_unconfirmed:
                if (not member["is_representative"]
                        and record["confirmed_by_user_id"] != current_user_id):
                    raise HTTPException(403, "체크한 본인 또는 현재 주보호자만 체크를 해제할 수 있습니다.")
                if (record["medication_confirmed_at"] != data.expected_confirmed_at
                        or record["confirmed_by_user_id"] != data.expected_confirmed_by_user_id):
                    raise HTTPException(409, "체크 기록이 변경되었습니다. 목록을 새로고침해 주세요.")
                cursor.execute(
                    """UPDATE medication_log
                       SET medication_confirmed_at = NULL, confirmed_by_user_id = NULL
                       WHERE medication_log_seq = %s AND family_room_id = %s
                         AND record_deleted_at IS NULL""", key,
                )
        conn.commit()
        return {"result": "OK", "medication_log_seq": medication_log_seq,
                "already_unconfirmed": already_unconfirmed,
                "medication_confirmed_at": None, "confirmed_by_user_id": None,
                "confirmed_by_name": None}
    except HTTPException:
        if conn is not None:
            conn.rollback()
        raise
    except (pymysql.MySQLError, ValueError):
        if conn is not None:
            conn.rollback()
        logger.exception("투약일지 체크 해제 실패")
        raise HTTPException(500, "투약일지 체크를 해제하지 못했습니다.") from None
    finally:
        if conn is not None:
            conn.close()


@router.post("/confirm/{medication_log_seq}")
def confirm_medication(
    data: MedicationConfirm,
    medication_log_seq: int = Path(gt=0),
    current_user_id: str = Depends(get_current_user_id),
):
    """활성 공간 참여자가 복약 완료를 체크한다. 재요청은 최초 사용자·시간을 유지한다."""
    conn = None
    try:
        conn = connect()
        with conn.cursor() as cursor:
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
                raise HTTPException(403, "해당 가족 공간의 투약일지를 체크할 수 없습니다.")
            target_sql = """SELECT m.medication_confirmed_at, m.confirmed_by_user_id,
                            checker.name AS confirmed_by_name
                         FROM medication_log AS m
                         LEFT JOIN `user` AS checker ON checker.user_id = m.confirmed_by_user_id
                         WHERE m.medication_log_seq = %s AND m.family_room_id = %s
                           AND m.record_deleted_at IS NULL"""
            key = (medication_log_seq, data.family_room_id)
            cursor.execute(target_sql + " FOR UPDATE", key)
            record = cursor.fetchone()
            if record is None:
                raise HTTPException(404, "투약일지가 없거나 삭제되었습니다.")
            already_confirmed = record["medication_confirmed_at"] is not None
            if not already_confirmed:
                cursor.execute(
                    """UPDATE medication_log
                       SET medication_confirmed_at = CURRENT_TIMESTAMP, confirmed_by_user_id = %s
                       WHERE medication_log_seq = %s AND family_room_id = %s
                         AND record_deleted_at IS NULL AND medication_confirmed_at IS NULL""",
                    (current_user_id, *key),
                )
                # 클라이언트 시간이 아닌 DB에 실제 저장된 시간과 사용자 이름을 반환한다.
                cursor.execute(target_sql, key)
                record = cursor.fetchone()
                if record is None:
                    raise HTTPException(500, "체크 결과를 확인하지 못했습니다.")
        conn.commit()
        return {"result": "OK", "medication_log_seq": medication_log_seq,
                "already_confirmed": already_confirmed, **record}
    except HTTPException:
        if conn is not None:
            conn.rollback()
        raise
    except (pymysql.MySQLError, ValueError):
        if conn is not None:
            conn.rollback()
        logger.exception("투약일지 체크 실패")
        raise HTTPException(500, "투약일지를 체크하지 못했습니다.") from None
    finally:
        if conn is not None:
            conn.close()


@router.post("/insert", status_code=201)
def insert_medication(
    medication: MedicationCreate,
    current_user_id: str = Depends(get_current_user_id),
):
    """현재 공간의 주보호자만 미확인 상태의 투약일지를 작성한다."""
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
                    AND p.is_representative = 1
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
                    detail="현재 공간의 주보호자만 투약일지를 작성할 수 있습니다.",
                )

            if medication.duration_days == 1:
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
            else:
                # 각 날짜의 체크는 독립적으로 저장하고 같은 추가 요청만 묶음 ID를 공유한다.
                series_id = uuid4().hex
                cursor.executemany("""INSERT INTO medication_log
                    (family_room_id, user_id, medication_info, medication_date,
                     medication_time, dosage_unit, dosage, medication_series_id)
                    VALUES (%s, %s, %s, %s, %s, %s, %s, %s)""", [
                    (medication.family_room_id, current_user_id, medication.medication_info,
                     medication.medication_date + timedelta(days=offset), medication.medication_time,
                     medication.dosage_unit, medication.dosage, series_id)
                    for offset in range(medication.duration_days)])
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


@router.delete("/delete/{medication_log_seq}")
def delete_medication_period(data: MedicationConfirm, medication_log_seq: int = Path(gt=0),
                             current_user_id: str = Depends(get_current_user_id)):
    """현재 주보호자가 같은 약 묶음의 오늘·미래 항목을 삭제 처리한다."""
    conn = None
    try:
        conn = connect()
        with conn.cursor() as cursor:
            # 작성·체크와 동일하게 공간 참여를 먼저 잠가 역할 변경과 직렬화한다.
            cursor.execute("""SELECT p.participate_seq FROM participate p
                JOIN family_room f ON f.family_room_id=p.family_room_id
                JOIN `user` u ON u.user_id=p.user_id
                WHERE p.family_room_id=%s AND p.user_id=%s AND p.is_representative=1
                AND p.is_active=1 AND p.left_at IS NULL AND f.family_room_deleted_at IS NULL
                AND u.withdrawn_at IS NULL LIMIT 1 FOR UPDATE""", (data.family_room_id, current_user_id))
            if cursor.fetchone() is None:
                raise HTTPException(403, "현재 공간의 주보호자만 약을 삭제할 수 있습니다.")
            cursor.execute("""SELECT medication_series_id FROM medication_log
                WHERE medication_log_seq=%s AND family_room_id=%s
                AND record_deleted_at IS NULL FOR UPDATE""", (medication_log_seq, data.family_room_id))
            item = cursor.fetchone()
            if item is None:
                raise HTTPException(404, "투약 정보를 찾을 수 없습니다.")
            # 약 이름·작성 시각으로 추측하지 않아 같은 이름으로 별도 등록한 약을 보호한다.
            series = item['medication_series_id']
            where = 'medication_series_id=%s' if series else 'medication_log_seq=%s'
            cursor.execute(f"""UPDATE medication_log SET record_deleted_at=CURRENT_TIMESTAMP,
                record_updated_at=CURRENT_TIMESTAMP WHERE family_room_id=%s AND {where}
                AND medication_date>=CURRENT_DATE AND record_deleted_at IS NULL""",
                (data.family_room_id, series if series else medication_log_seq))
            deleted_count = cursor.rowcount
        conn.commit()
        return {'result': 'OK', 'deleted_count': deleted_count}
    except HTTPException:
        if conn is not None:
            conn.rollback()
        raise
    except (pymysql.MySQLError, ValueError):
        if conn is not None:
            conn.rollback()
        raise HTTPException(503, "약을 삭제하지 못했습니다. 다시 시도해 주세요.") from None
    finally:
        if conn is not None:
            conn.close()


@router.patch("/update/{medication_log_seq}")
def update_medication(
    medication: MedicationUpdate,
    medication_log_seq: int = Path(gt=0),
    current_user_id: str = Depends(get_current_user_id),
):
    """현재 공간의 주보호자만 투약 내용을 부분 수정한다. 작성자·복약 확인은 보존한다."""
    conn = None
    try:
        conn = connect()
        with conn.cursor() as cursor:
            # 권한 확인 행을 잠가 수정 중 권한 변경·참여 종료와의 경합을 방지한다.
            cursor.execute(
                """
                SELECT p.participate_seq
                FROM participate AS p
                    JOIN family_room AS f ON f.family_room_id = p.family_room_id
                    JOIN `user` AS u ON u.user_id = p.user_id
                WHERE p.family_room_id = %s AND p.user_id = %s
                    AND p.is_representative = 1
                    AND p.is_active = 1 AND p.left_at IS NULL
                    AND f.family_room_deleted_at IS NULL
                    AND u.withdrawn_at IS NULL
                LIMIT 1
                FOR UPDATE
                """,
                (medication.family_room_id, current_user_id),
            )
            if cursor.fetchone() is None:
                raise HTTPException(403, "현재 공간의 주보호자만 투약 정보를 수정할 수 있습니다.")

            cursor.execute(
                """SELECT medication_log_seq FROM medication_log
                   WHERE medication_log_seq = %s AND family_room_id = %s
                     AND record_deleted_at IS NULL
                   LIMIT 1 FOR UPDATE""",
                (medication_log_seq, medication.family_room_id),
            )
            if cursor.fetchone() is None:
                raise HTTPException(404, "수정할 투약일지가 없거나 삭제되었습니다.")

            # 컬럼명은 서버의 허용 목록만 사용하고 값은 모두 파라미터로 바인딩한다.
            allowed = ("medication_info", "medication_date", "medication_time", "dosage_unit", "dosage")
            changed = [name for name in allowed if name in medication.model_fields_set]
            assignments = ", ".join(f"{name} = %s" for name in changed)
            cursor.execute(
                f"""UPDATE medication_log SET {assignments}, record_updated_at = CURRENT_TIMESTAMP
                    WHERE medication_log_seq = %s AND family_room_id = %s
                      AND record_deleted_at IS NULL""",
                (*[getattr(medication, name) for name in changed],
                 medication_log_seq, medication.family_room_id),
            )
        conn.commit()
        return {"result": "OK", "medication_log_seq": medication_log_seq}
    except HTTPException:
        if conn is not None:
            conn.rollback()
        raise
    except (pymysql.MySQLError, ValueError):
        if conn is not None:
            conn.rollback()
        logger.exception("투약 정보 수정 실패")
        raise HTTPException(500, "투약 정보를 수정하지 못했습니다.") from None
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
                    m.recorded_at, m.record_updated_at, u.name AS author_name,
                    m.confirmed_by_user_id, checker.name AS confirmed_by_name
                FROM medication_log AS m
                    JOIN family_room AS f ON f.family_room_id = m.family_room_id
                    LEFT JOIN `user` AS u ON u.user_id = m.user_id
                    LEFT JOIN `user` AS checker ON checker.user_id = m.confirmed_by_user_id
                WHERE m.family_room_id = %s
                    AND m.record_deleted_at IS NULL
                    AND f.family_room_deleted_at IS NULL
            """
            params = [family_room_id]
            if medication_date is not None:
                sql += " AND m.medication_date = %s"
                params.append(medication_date)
            sql += """
                ORDER BY m.medication_date DESC,
                    CASE
                        WHEN TRIM(m.medication_time) LIKE '아침%%' THEN 0
                        WHEN TRIM(m.medication_time) LIKE '점심%%' THEN 1
                        WHEN TRIM(m.medication_time) LIKE '저녁%%' THEN 2
                        ELSE 3
                    END,
                    CASE
                        WHEN LOCATE('식전', m.medication_time) > 0 THEN 0
                        WHEN LOCATE('식후', m.medication_time) > 0 THEN 1
                        ELSE 2
                    END,
                    m.recorded_at DESC,
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
