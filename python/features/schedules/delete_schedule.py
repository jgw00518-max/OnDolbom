"""일정 삭제 전 최신 내용과 현재 배정을 확인한다."""

from fastapi import HTTPException
from python.features.schedules.change_notifications import prepare_change
from python.database import connect
from python.features.notifications.store import get_event, publish


# 호출한 API에서 주보호자 확인과 공간 잠금을 먼저 수행한다.
def get_schedule_for_delete(
    conn,
    schedule_seq: int,
    family_room_id: str,
):
    with conn.cursor() as cursor:
        cursor.execute(
            """
            SELECT
                s.schedule_seq,
                s.family_room_id,
                s.accepted_by,
                s.accepted_at,
                s.schedule_state,
                s.created_at,
                s.deleted_at,
                h.history_seq,
                CASE WHEN h.history_seq IS NULL
                    THEN s.schedule_date
                    ELSE h.schedule_date
                END AS schedule_date,
                CASE WHEN h.history_seq IS NULL
                    THEN s.schedule_name
                    ELSE h.updated_schedule_name
                END AS schedule_name,
                CAST(
                    CASE WHEN h.history_seq IS NULL
                        THEN s.start_time
                        ELSE h.updated_start_time
                    END AS CHAR
                ) AS start_time,
                CAST(
                    CASE WHEN h.history_seq IS NULL
                        THEN s.end_time
                        ELSE h.updated_end_time
                    END AS CHAR
                ) AS end_time,
                CASE WHEN h.history_seq IS NULL
                    THEN s.schedule_memo
                    ELSE h.updated_schedule_memo
                END AS schedule_memo
            FROM create_schedule AS s
            LEFT JOIN update_schedule AS h
              ON h.schedule_seq = s.schedule_seq
             AND h.family_room_id = s.family_room_id
             AND h.history_seq = (
                 SELECT MAX(h2.history_seq)
                 FROM update_schedule AS h2
                 WHERE h2.schedule_seq = s.schedule_seq
                   AND h2.family_room_id = s.family_room_id
             )
            WHERE s.schedule_seq = %s
              AND s.family_room_id = %s
            FOR UPDATE
            """,
            (schedule_seq, family_room_id),
        )
        schedule = cursor.fetchone()

    if schedule is None:
        raise HTTPException(
            404,
            "해당 돌봄 공간의 일정을 찾을 수 없습니다.",
        )

    return schedule

# 호출한 API에서 알림 준비까지 성공한 뒤 commit한다.
def mark_schedule_deleted(
    conn,
    schedule: dict,
    changed_by: str,
):
    if schedule["deleted_at"] is not None:
        return None

    with conn.cursor() as cursor:
        cursor.execute(
            """
            UPDATE create_schedule
            SET deleted_at = CURRENT_TIMESTAMP,
                accepted_by = NULL
            WHERE schedule_seq = %s
              AND family_room_id = %s
              AND deleted_at IS NULL
            """,
            (
                schedule["schedule_seq"],
                schedule["family_room_id"],
            ),
        )

        if cursor.rowcount != 1:
            raise HTTPException(
                409,
                "일정 상태가 변경됐습니다. 다시 조회해 주세요.",
            )

        # 최신 내용은 보존하고 삭제 처리자의 새 이력을 남긴다.
        cursor.execute(
            """
            INSERT INTO update_schedule (
                schedule_seq,
                schedule_date,
                family_room_id,
                changed_by,
                update_accepted_by,
                update_accepted_at,
                updated_schedule_name,
                updated_start_time,
                updated_end_time,
                updated_schedule_memo
            )
            VALUES (
                %s, %s, %s, %s, NULL, NULL,
                %s, %s, %s, %s
            )
            """,
            (
                schedule["schedule_seq"],
                schedule["schedule_date"],
                schedule["family_room_id"],
                changed_by,
                schedule["schedule_name"],
                schedule["start_time"],
                schedule["end_time"],
                schedule["schedule_memo"],
            ),
        )
        history_seq = cursor.lastrowid

        cursor.execute(
            """
            SELECT deleted_at
            FROM create_schedule
            WHERE schedule_seq = %s
              AND family_room_id = %s
            """,
            (
                schedule["schedule_seq"],
                schedule["family_room_id"],
            ),
        )
        deleted_at = cursor.fetchone()["deleted_at"]

    return {
        **schedule,
        "history_seq": history_seq,
        "deleted_at": deleted_at,
        "deleted_by": changed_by,
        "former_assignee_id": schedule["accepted_by"],
        "accepted_by": None,
    }

# 삭제된 일정의 정보와 현재 전체 가족 수신자를 보관한다.
def prepare_schedule_delete_notification(conn, deleted: dict):
    with conn.cursor() as cursor:
        cursor.execute(
            """
            SELECT
                s.family_room_id,
                s.created_at,
                s.deleted_at,
                h.updated_at,
                f.care_recipient_name
            FROM create_schedule AS s
            JOIN family_room AS f
              ON f.family_room_id = s.family_room_id
            JOIN update_schedule AS h
              ON h.schedule_seq = s.schedule_seq
             AND h.family_room_id = s.family_room_id
            WHERE s.schedule_seq = %s
              AND s.family_room_id = %s
              AND h.history_seq = %s
              AND h.changed_by = %s
              AND s.deleted_at IS NOT NULL
              AND s.accepted_by IS NULL
              AND f.family_room_deleted_at IS NULL
              AND h.update_accepted_by IS NULL
              AND h.update_accepted_at IS NULL
              AND h.history_seq = (
                  SELECT MAX(h2.history_seq)
                  FROM update_schedule AS h2
                  WHERE h2.schedule_seq = s.schedule_seq
                    AND h2.family_room_id = s.family_room_id
              )
            LIMIT 1
            """,
            (
                deleted["schedule_seq"],
                deleted["family_room_id"],
                deleted["history_seq"],
                deleted["deleted_by"],
            ),
        )
        schedule = cursor.fetchone()

        if schedule is None:
            raise ValueError(
                "삭제 알림을 준비할 유효한 처리 이력이 없습니다."
            )

        cursor.execute(
            """
            SELECT DISTINCT p.user_id
            FROM participate AS p
            JOIN `user` AS u ON u.user_id = p.user_id
            WHERE p.family_room_id = %s
              AND p.left_at IS NULL
              AND u.withdrawn_at IS NULL
            """,
            (schedule["family_room_id"],),
        )
        recipients = sorted(
            row["user_id"] for row in cursor.fetchall()
        )

    if not recipients:
        raise ValueError("삭제 알림을 받을 현재 가족이 없습니다.")

    return prepare_change({
        "notification_type": "schedule_deleted",
        "schedule_seq": deleted["schedule_seq"],
        "history_seq": deleted["history_seq"],
        "family_room_id": schedule["family_room_id"],
        "schedule_created_at": str(schedule["created_at"]),
        "history_updated_at": str(schedule["updated_at"]),
        "deleted_at": str(schedule["deleted_at"]),
        "deleted_by": deleted["deleted_by"],
        "actor_id": deleted["deleted_by"],
        "former_assignee_id": deleted["former_assignee_id"],
        "schedule_name": deleted["schedule_name"],
        "schedule_date": str(deleted["schedule_date"]),
        "start_time": deleted["start_time"],
        "end_time": deleted["end_time"],
        "schedule_memo": deleted["schedule_memo"],
        "care_recipient_name": schedule["care_recipient_name"],
        "recipient_ids": recipients,
    })

# 삭제와 이력 저장이 DB에 확정된 뒤 삭제 알림을 발행한다.
def publish_schedule_delete_notification(
    schedule_seq: int,
    history_seq: int,
):
    identifier = f"schedule_deleted_{schedule_seq}_{history_seq}"
    event = get_event(identifier)

    if (
        event is None
        or event.get("status") not in ("pending", "published")
        or event.get("notification_type") != "schedule_deleted"
    ):
        return False

    conn = connect()

    try:
        with conn.cursor() as cursor:
            cursor.execute(
                """
                SELECT
                    s.family_room_id,
                    s.created_at,
                    s.deleted_at,
                    h.updated_at,
                    h.changed_by,
                    h.schedule_date,
                    h.updated_schedule_name AS schedule_name,
                    CAST(h.updated_start_time AS CHAR) AS start_time,
                    CAST(h.updated_end_time AS CHAR) AS end_time,
                    h.updated_schedule_memo AS schedule_memo
                FROM create_schedule AS s
                JOIN family_room AS f
                  ON f.family_room_id = s.family_room_id
                JOIN update_schedule AS h
                  ON h.schedule_seq = s.schedule_seq
                 AND h.family_room_id = s.family_room_id
                WHERE s.schedule_seq = %s
                  AND h.history_seq = %s
                  AND s.deleted_at IS NOT NULL
                  AND s.accepted_by IS NULL
                  AND f.family_room_deleted_at IS NULL
                  AND h.update_accepted_by IS NULL
                  AND h.update_accepted_at IS NULL
                  AND h.history_seq = (
                      SELECT MAX(h2.history_seq)
                      FROM update_schedule AS h2
                      WHERE h2.schedule_seq = s.schedule_seq
                        AND h2.family_room_id = s.family_room_id
                  )
                LIMIT 1
                """,
                (schedule_seq, history_seq),
            )
            saved = cursor.fetchone()

        if saved is None:
            return False

        expected = {
            "notification_id": identifier,
            "schedule_seq": schedule_seq,
            "history_seq": history_seq,
            "family_room_id": saved["family_room_id"],
            "schedule_created_at": str(saved["created_at"]),
            "history_updated_at": str(saved["updated_at"]),
            "deleted_at": str(saved["deleted_at"]),
            "deleted_by": saved["changed_by"],
            "schedule_name": saved["schedule_name"],
            "schedule_date": str(saved["schedule_date"]),
            "start_time": saved["start_time"],
            "end_time": saved["end_time"],
            "schedule_memo": saved["schedule_memo"],
        }

        if any(
            event.get(key) != value
            for key, value in expected.items()
        ):
            return False

        if not event.get("recipient_ids"):
            return False

        # 준비할 때 고정한 전체 가족 수신자와 읽음 상태를 유지한다.
        return publish(
            identifier,
            str(saved["created_at"]),
        )

    finally:
        conn.close()