"""일정 변경·재수락 알림 처리."""

from firebase_admin import firestore

from python.database import connect
from python.features.notifications.store import (
    collection,
    exclude_actor,
    get_event,
    publish,
)
from google.cloud.firestore_v1.base_query import FieldFilter

from python.features.schedules.reconfirm_policy import get_reconfirm_deadline

# 일정 변경 이력별 알림을 준비한다.
def _prepare_change(transaction, ref, payload):
    payload = exclude_actor(payload)
    snapshot = ref.get(transaction=transaction)

    if snapshot.exists:
        old = snapshot.to_dict()

        # 같은 변경의 재시도인지 확인한다.
        for key in (
            "schedule_seq",
            "family_room_id",
            "schedule_created_at",
            "notification_type",
            "history_seq",
            "history_updated_at",
        ):
            if old.get(key) != payload[key]:
                raise ValueError("일정 변경 알림 정보가 일치하지 않습니다.")

        # 재시도해도 최초 수신자와 기존 읽음 상태를 유지한다.
        return

    transaction.create(
        ref,
        {
            **payload,
            "status": "pending",
            "created_at": firestore.SERVER_TIMESTAMP,
        },
    )


def prepare_change(payload):
    identifier = (
        f"{payload['notification_type']}_"
        f"{payload['schedule_seq']}_"
        f"{payload['history_seq']}"
    )
    ref = collection().document(identifier)

    firestore.transactional(_prepare_change)(
        ref._client.transaction(),
        ref,
        {**payload, "notification_id": identifier},
    )

    return identifier

# 변경 이력을 저장한 연결에서 기존 담당자 한 명의 재수락 알림을 준비한다.
def prepare_reconfirm_notification(conn, schedule_seq: int, history_seq: int):
    with conn.cursor() as cursor:
        cursor.execute(
            """
            SELECT
                s.family_room_id,
                s.created_at,
                s.accepted_by,
                h.updated_at,
                h.changed_by
            FROM create_schedule AS s
            JOIN family_room AS f
              ON f.family_room_id = s.family_room_id
            JOIN update_schedule AS h
              ON h.schedule_seq = s.schedule_seq
             AND h.family_room_id = s.family_room_id
            JOIN participate AS p
              ON p.family_room_id = s.family_room_id
             AND p.user_id = s.accepted_by
            JOIN `user` AS u
              ON u.user_id = p.user_id
            WHERE s.schedule_seq = %s
              AND h.history_seq = %s
              AND s.deleted_at IS NULL
              AND f.family_room_deleted_at IS NULL
              AND p.left_at IS NULL
              AND u.withdrawn_at IS NULL
              AND s.schedule_state = '미완료'
              AND h.update_accepted_by = s.accepted_by
              AND h.update_accepted_at IS NULL
              AND h.history_seq = (
                  SELECT MAX(h2.history_seq)
                  FROM update_schedule AS h2
                  WHERE h2.schedule_seq = s.schedule_seq
              )
            LIMIT 1
            FOR UPDATE
            """,
            (schedule_seq, history_seq),
        )
        schedule = cursor.fetchone()

    if schedule is None:
        raise ValueError("재수락 알림을 준비할 유효한 변경 요청이 없습니다.")

    # 수신자는 외부 입력으로 받지 않고 현재 DB의 기존 담당자로 정한다.
    return prepare_change(
        {
            "notification_type": "schedule_reconfirm",
            "schedule_seq": schedule_seq,
            "history_seq": history_seq,
            "family_room_id": schedule["family_room_id"],
            "schedule_created_at": str(schedule["created_at"]),
            "history_updated_at": str(schedule["updated_at"]),
            "actor_id": schedule.get("changed_by"),
            "recipient_ids": [schedule["accepted_by"]],
        }
    )

# DB 저장이 확정된 재수락 요청만 발행한다.
def publish_reconfirm_notification(schedule_seq: int, history_seq: int):
    identifier = f"schedule_reconfirm_{schedule_seq}_{history_seq}"
    event = get_event(identifier)

    if event is None or event.get("status") not in ("pending", "published"):
        return False

    conn = connect()

    try:
        with conn.cursor() as cursor:
            cursor.execute(
                """
                SELECT
                    s.family_room_id,
                    s.created_at,
                    s.accepted_by,
                    h.updated_at
                FROM create_schedule AS s
                JOIN family_room AS f
                  ON f.family_room_id = s.family_room_id
                JOIN update_schedule AS h
                  ON h.schedule_seq = s.schedule_seq
                 AND h.family_room_id = s.family_room_id
                JOIN participate AS p
                  ON p.family_room_id = s.family_room_id
                 AND p.user_id = s.accepted_by
                JOIN `user` AS u
                  ON u.user_id = p.user_id
                WHERE s.schedule_seq = %s
                  AND h.history_seq = %s
                  AND s.deleted_at IS NULL
                  AND f.family_room_deleted_at IS NULL
                  AND p.left_at IS NULL
                  AND u.withdrawn_at IS NULL
                  AND s.schedule_state = '미완료'
                  AND h.update_accepted_by = s.accepted_by
                  AND h.update_accepted_at IS NULL
                  AND h.history_seq = (
                      SELECT MAX(h2.history_seq)
                      FROM update_schedule AS h2
                      WHERE h2.schedule_seq = s.schedule_seq
                  )
                LIMIT 1
                """,
                (schedule_seq, history_seq),
            )
            schedule = cursor.fetchone()

        if schedule is None:
            return False

        expected = {
            "notification_id": identifier,
            "notification_type": "schedule_reconfirm",
            "schedule_seq": schedule_seq,
            "history_seq": history_seq,
            "family_room_id": schedule["family_room_id"],
            "schedule_created_at": str(schedule["created_at"]),
            "history_updated_at": str(schedule["updated_at"]),
            "recipient_ids": [schedule["accepted_by"]],
        }

        if any(event.get(key) != value for key, value in expected.items()):
            return False

        return publish(identifier, str(schedule["created_at"]))

    finally:
        conn.close()

# 기존 등록 알림과 변경 알림을 생성 시각순으로 함께 조회한다.
def list_notification_events(user_id, before_id, limit):
    query = (
        collection()
        .where(filter=FieldFilter("status", "==", "published"))
        .where(filter=FieldFilter("recipient_ids", "array_contains", user_id))
        .order_by("created_at", direction=firestore.Query.DESCENDING)
    )

    if before_id is not None:
        snapshot = collection().document(str(before_id)).get(timeout=10)
        previous = snapshot.to_dict() if snapshot.exists else None

        if (
            previous is None
            or previous.get("status") != "published"
            or user_id not in previous.get("recipient_ids", [])
        ):
            raise ValueError("알림 조회 위치를 확인할 수 없습니다.")

        # 일정 번호가 같더라도 마지막 문서 다음부터 이어서 조회한다.
        query = query.start_after(snapshot)

    events = []

    for snapshot in query.limit(limit).stream(timeout=10):
        event = snapshot.to_dict()

        # 기존 등록 알림은 숫자, 변경 알림은 별도 문자열 번호를 사용한다.
        event["notification_id"] = (
            int(snapshot.id) if snapshot.id.isdecimal() else snapshot.id
        )
        events.append(event)

    return events

# 이름·메모만 변경한 경우 기존 담당자 한 명에게 변경 안내를 준비한다.
def prepare_schedule_change_notification(
    conn,
    schedule_seq: int,
    history_seq: int,
):
    with conn.cursor() as cursor:
        cursor.execute(
            """
            SELECT
                s.family_room_id,
                s.created_at,
                s.accepted_by,
                h.updated_at,
                h.changed_by
            FROM create_schedule AS s
            JOIN family_room AS f
              ON f.family_room_id = s.family_room_id
            JOIN update_schedule AS h
              ON h.schedule_seq = s.schedule_seq
             AND h.family_room_id = s.family_room_id
            JOIN participate AS p
              ON p.family_room_id = s.family_room_id
             AND p.user_id = s.accepted_by
            JOIN `user` AS u
              ON u.user_id = p.user_id
            WHERE s.schedule_seq = %s
              AND h.history_seq = %s
              AND s.deleted_at IS NULL
              AND f.family_room_deleted_at IS NULL
              AND p.left_at IS NULL
              AND u.withdrawn_at IS NULL
              AND s.schedule_state = '미완료'
              AND h.update_accepted_by = s.accepted_by
              AND h.history_seq = (
                  SELECT MAX(h2.history_seq)
                  FROM update_schedule AS h2
                  WHERE h2.schedule_seq = s.schedule_seq
              )
            LIMIT 1
            FOR UPDATE
            """,
            (schedule_seq, history_seq),
        )
        schedule = cursor.fetchone()

    if schedule is None:
        raise ValueError("변경 안내를 준비할 유효한 일정이 없습니다.")

    return prepare_change(
        {
            "notification_type": "schedule_changed",
            "schedule_seq": schedule_seq,
            "history_seq": history_seq,
            "family_room_id": schedule["family_room_id"],
            "schedule_created_at": str(schedule["created_at"]),
            "history_updated_at": str(schedule["updated_at"]),
            "actor_id": schedule.get("changed_by"),
            "recipient_ids": [schedule["accepted_by"]],
        }
    )

# DB에 저장된 변경 이력과 수신자를 확인한 뒤 변경 안내를 발행한다.
def publish_schedule_change_notification(
    schedule_seq: int,
    history_seq: int,
):
    identifier = f"schedule_changed_{schedule_seq}_{history_seq}"
    event = get_event(identifier)

    if event is None or event.get("status") not in ("pending", "published"):
        return False

    conn = connect()

    try:
        with conn.cursor() as cursor:
            cursor.execute(
                """
                SELECT
                    s.family_room_id,
                    s.created_at,
                    s.accepted_by,
                    h.updated_at
                FROM create_schedule AS s
                JOIN family_room AS f
                  ON f.family_room_id = s.family_room_id
                JOIN update_schedule AS h
                  ON h.schedule_seq = s.schedule_seq
                 AND h.family_room_id = s.family_room_id
                JOIN participate AS p
                  ON p.family_room_id = s.family_room_id
                 AND p.user_id = s.accepted_by
                JOIN `user` AS u
                  ON u.user_id = p.user_id
                WHERE s.schedule_seq = %s
                  AND h.history_seq = %s
                  AND s.deleted_at IS NULL
                  AND f.family_room_deleted_at IS NULL
                  AND p.left_at IS NULL
                  AND u.withdrawn_at IS NULL
                  AND s.schedule_state = '미완료'
                  AND h.update_accepted_by = s.accepted_by
                  AND h.history_seq = (
                      SELECT MAX(h2.history_seq)
                      FROM update_schedule AS h2
                      WHERE h2.schedule_seq = s.schedule_seq
                  )
                LIMIT 1
                """,
                (schedule_seq, history_seq),
            )
            schedule = cursor.fetchone()

        if schedule is None:
            return False

        expected = {
            "notification_id": identifier,
            "notification_type": "schedule_changed",
            "schedule_seq": schedule_seq,
            "history_seq": history_seq,
            "family_room_id": schedule["family_room_id"],
            "schedule_created_at": str(schedule["created_at"]),
            "history_updated_at": str(schedule["updated_at"]),
            "recipient_ids": [schedule["accepted_by"]],
        }

        if any(event.get(key) != value for key, value in expected.items()):
            return False

        return publish(identifier, str(schedule["created_at"]))

    finally:
        conn.close()

# 거절로 배정이 해제된 일정의 재모집 알림을 준비한다.
def prepare_recruitment_notification(
    conn,
    schedule_seq: int,
    history_seq: int,
):
    with conn.cursor() as cursor:
        cursor.execute(
            """
            SELECT
                s.family_room_id,
                s.created_at,
                h.updated_at,
                h.changed_by
            FROM create_schedule AS s
            JOIN family_room AS f
              ON f.family_room_id = s.family_room_id
            JOIN update_schedule AS h
              ON h.schedule_seq = s.schedule_seq
             AND h.family_room_id = s.family_room_id
            WHERE s.schedule_seq = %s
              AND h.history_seq = %s
              AND s.deleted_at IS NULL
              AND f.family_room_deleted_at IS NULL
              AND s.schedule_state = '미완료'
              AND s.accepted_by IS NULL
              AND h.update_accepted_by IS NULL
              AND h.update_accepted_at IS NULL
              AND h.history_seq = (
                  SELECT MAX(h2.history_seq)
                  FROM update_schedule AS h2
                  WHERE h2.schedule_seq = s.schedule_seq
                    AND h2.family_room_id = s.family_room_id
              )
            LIMIT 1
            FOR UPDATE
            """,
            (schedule_seq, history_seq),
        )
        schedule = cursor.fetchone()

        if schedule is None:
            raise ValueError("재모집 알림을 준비할 유효한 일정이 없습니다.")

        # 주보호자와 기존 담당자를 포함한 현재 전체 가족을 조회한다.
        cursor.execute(
            """
            SELECT DISTINCT p.user_id
            FROM participate AS p
            JOIN `user` AS u
              ON u.user_id = p.user_id
            WHERE p.family_room_id = %s
              AND p.left_at IS NULL
              AND u.withdrawn_at IS NULL
            """,
            (schedule["family_room_id"],),
        )
        recipients = [row["user_id"] for row in cursor.fetchall()]

    if not recipients:
        raise ValueError("재모집 알림을 받을 가족이 없습니다.")

    return prepare_change(
        {
            "notification_type": "schedule_recruitment",
            "schedule_seq": schedule_seq,
            "history_seq": history_seq,
            "family_room_id": schedule["family_room_id"],
            "schedule_created_at": str(schedule["created_at"]),
            "history_updated_at": str(schedule["updated_at"]),
            "actor_id": schedule.get("changed_by"),
            "recipient_ids": recipients,
        }
    )

# 거절 이력이 DB에 확정된 후 재모집 알림을 발행한다.
def publish_recruitment_notification(
    schedule_seq: int,
    history_seq: int,
):
    identifier = f"schedule_recruitment_{schedule_seq}_{history_seq}"
    event = get_event(identifier)

    if event is None or event.get("status") not in ("pending", "published"):
        return False

    conn = connect()

    try:
        with conn.cursor() as cursor:
            cursor.execute(
                """
                SELECT
                    s.family_room_id,
                    s.created_at,
                    h.updated_at
                FROM create_schedule AS s
                JOIN family_room AS f
                  ON f.family_room_id = s.family_room_id
                JOIN update_schedule AS h
                  ON h.schedule_seq = s.schedule_seq
                 AND h.family_room_id = s.family_room_id
                WHERE s.schedule_seq = %s
                  AND h.history_seq = %s
                  AND s.deleted_at IS NULL
                  AND f.family_room_deleted_at IS NULL
                  AND s.schedule_state = '미완료'
                  AND s.accepted_by IS NULL
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
            schedule = cursor.fetchone()

        if schedule is None:
            return False

        expected = {
            "notification_id": identifier,
            "notification_type": "schedule_recruitment",
            "schedule_seq": schedule_seq,
            "history_seq": history_seq,
            "family_room_id": schedule["family_room_id"],
            "schedule_created_at": str(schedule["created_at"]),
            "history_updated_at": str(schedule["updated_at"]),
        }

        if any(event.get(key) != value for key, value in expected.items()):
            return False

        # 준비할 때 확정한 전체 가족 수신자를 그대로 유지한다.
        if not event.get("recipient_ids"):
            return False

        return publish(identifier, str(schedule["created_at"]))

    finally:
        conn.close()

# 자동 만료된 기존 담당자와 현재 주보호자의 알림을 준비한다.
def prepare_reconfirm_expiry_notifications(conn, expired: dict):
    schedule_seq = expired["schedule_seq"]
    history_seq = expired["history_seq"]

    with conn.cursor() as cursor:
        cursor.execute(
            """
            SELECT s.family_room_id, s.created_at, h.updated_at
            FROM create_schedule AS s
            JOIN family_room AS f
              ON f.family_room_id = s.family_room_id
            JOIN update_schedule AS h
              ON h.schedule_seq = s.schedule_seq
             AND h.family_room_id = s.family_room_id
            WHERE s.schedule_seq = %s
              AND s.family_room_id = %s
              AND h.history_seq = %s
              AND s.deleted_at IS NULL
              AND f.family_room_deleted_at IS NULL
              AND s.schedule_state = '미완료'
              AND s.accepted_by IS NULL
              AND h.changed_by = 'system'
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
            (schedule_seq, expired["family_room_id"], history_seq),
        )
        schedule = cursor.fetchone()

        if schedule is None:
            raise ValueError(
                "만료 알림을 준비할 유효한 처리 이력이 없습니다."
            )

        cursor.execute(
            """
            SELECT DISTINCT p.user_id, p.is_representative
            FROM participate AS p
            JOIN `user` AS u ON u.user_id = p.user_id
            WHERE p.family_room_id = %s
              AND p.left_at IS NULL
              AND u.withdrawn_at IS NULL
            """,
            (schedule["family_room_id"],),
        )
        members = cursor.fetchall()

    member_ids = {member["user_id"] for member in members}
    representative_ids = sorted({
        member["user_id"]
        for member in members
        if member["is_representative"] == 1
    })

    if not representative_ids:
        raise ValueError(
            "미응답 안내를 받을 현재 주보호자가 없습니다."
        )

    # 자동 처리 사유와 기존 요청·담당자를 함께 보존한다.
    payload = {
        "schedule_seq": schedule_seq,
        "history_seq": history_seq,
        "family_room_id": schedule["family_room_id"],
        "schedule_created_at": str(schedule["created_at"]),
        "history_updated_at": str(schedule["updated_at"]),
        "request_history_seq": expired["request_history_seq"],
        "former_assignee_id": expired["accepted_by"],
        "response_due_at": str(expired["response_due_at"]),
        "processed_by": "system",
        "reason": "response_timeout",
    }
    identifiers = []

    # 기존 담당자에게 요청 만료·배정 해제를 알린다.
    if expired["accepted_by"] in member_ids:
        identifiers.append(prepare_change({
            **payload,
            "notification_type": "schedule_reconfirm_expired",
            "recipient_ids": [expired["accepted_by"]],
        }))

    # 현재 주보호자에게 담당자의 미응답 사실을 알린다.
    identifiers.append(prepare_change({
        **payload,
        "notification_type": "schedule_reconfirm_unanswered",
        "recipient_ids": representative_ids,
    }))

    return identifiers

# DB에 확정된 자동 만료 안내만 발행한다.
def publish_reconfirm_expiry_notification(identifier: str):
    event = get_event(identifier)

    if event is None or event.get("status") not in ("pending", "published"):
        return False

    notification_type = event.get("notification_type")

    if notification_type not in (
        "schedule_reconfirm_expired",
        "schedule_reconfirm_unanswered",
    ):
        return False

    expected_id = (
        f"{notification_type}_{event['schedule_seq']}_{event['history_seq']}"
    )

    if identifier != expected_id or event.get("notification_id") != identifier:
        return False

    conn = connect()

    try:
        with conn.cursor() as cursor:
            cursor.execute(
                """
                SELECT
                    s.family_room_id,
                    s.created_at,
                    h.updated_at,
                    r.update_accepted_by AS former_assignee_id,
                    r.updated_at AS requested_at,
                    r.schedule_date,
                    CAST(r.updated_start_time AS CHAR) AS start_time
                FROM create_schedule AS s
                JOIN family_room AS f
                  ON f.family_room_id = s.family_room_id
                JOIN update_schedule AS h
                  ON h.schedule_seq = s.schedule_seq
                 AND h.family_room_id = s.family_room_id
                JOIN update_schedule AS r
                  ON r.schedule_seq = s.schedule_seq
                 AND r.family_room_id = s.family_room_id
                WHERE s.schedule_seq = %s
                  AND h.history_seq = %s
                  AND r.history_seq = %s
                  AND r.history_seq < h.history_seq
                  AND s.deleted_at IS NULL
                  AND f.family_room_deleted_at IS NULL
                  AND h.changed_by = 'system'
                  AND h.update_accepted_by IS NULL
                  AND h.update_accepted_at IS NULL
                  AND r.update_accepted_by IS NOT NULL
                  AND r.update_accepted_at IS NULL
                LIMIT 1
                """,
                (
                    event["schedule_seq"],
                    event["history_seq"],
                    event["request_history_seq"],
                ),
            )
            saved = cursor.fetchone()

        if saved is None:
            return False

        deadline = get_reconfirm_deadline(
            requested_at=saved["requested_at"],
            schedule_date=saved["schedule_date"],
            start_time=saved["start_time"],
        )

        # 긴급 여부가 아니라 실제 기한 유무로 자동 만료 발행을 판단한다.
        # 12시간 초과~24시간 이하 요청도 기한이 지나면 발행한다.
        if (
            deadline["response_due_at"] is None
            or saved["updated_at"] < deadline["response_due_at"]
        ):
            return False

        expected = {
            "family_room_id": saved["family_room_id"],
            "schedule_created_at": str(saved["created_at"]),
            "history_updated_at": str(saved["updated_at"]),
            "former_assignee_id": saved["former_assignee_id"],
            "response_due_at": str(deadline["response_due_at"]),
            "processed_by": "system",
            "reason": "response_timeout",
        }

        if any(event.get(key) != value for key, value in expected.items()):
            return False

        recipients = event.get("recipient_ids")

        if not recipients:
            return False

        if (
            notification_type == "schedule_reconfirm_expired"
            and recipients != [saved["former_assignee_id"]]
        ):
            return False

        # 새 담당자가 배정돼도 이미 확정된 만료 안내는 발행할 수 있다.
        return publish(identifier, str(saved["created_at"]))

    finally:
        conn.close()