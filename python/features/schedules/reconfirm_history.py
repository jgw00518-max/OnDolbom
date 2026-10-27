"""기존 변경 이력에서 현재 재수락 요청과 비교 기준을 찾는다."""


def get_pending_reconfirm_request(
    conn,
    schedule_seq: int,
    family_room_id: str,
    accepted_by: str | None,
):
    if accepted_by is None:
        return None

    with conn.cursor() as cursor:
        cursor.execute(
            """
            SELECT
                history_seq,
                update_accepted_by,
                update_accepted_at,
                updated_at,
                schedule_date,
                updated_schedule_name AS schedule_name,
                CAST(updated_start_time AS CHAR) AS start_time,
                CAST(updated_end_time AS CHAR) AS end_time,
                updated_schedule_memo AS schedule_memo
            FROM update_schedule
            WHERE schedule_seq = %s
              AND family_room_id = %s
            ORDER BY history_seq DESC
            """,
            (schedule_seq, family_room_id),
        )
        histories = cursor.fetchall()

        if not histories:
            return None

        latest = histories[0]

        if (
            latest["update_accepted_by"] != accepted_by
            or latest["update_accepted_at"] is not None
        ):
            return None

        request = latest
        request_history_seqs = [latest["history_seq"]]
        previous = None

        # 날짜·시간과 담당자가 같은 연속 대기 이력은 동일 요청이다.
        # 이름·메모 변경으로 새 이력이 생겨도 최초 요청을 유지한다.
        for history in histories[1:]:
            same_request = (
                history["update_accepted_by"] == accepted_by
                and history["update_accepted_at"] is None
                and history["schedule_date"] == request["schedule_date"]
                and history["start_time"] == request["start_time"]
                and history["end_time"] == request["end_time"]
            )

            if not same_request:
                previous = history
                break

            request = history
            request_history_seqs.append(history["history_seq"])

        # 이전 이력이 없는 첫 변경이면 최초 등록 내용과 비교한다.
        if previous is None:
            cursor.execute(
                """
                SELECT
                    schedule_date,
                    schedule_name,
                    CAST(start_time AS CHAR) AS start_time,
                    CAST(end_time AS CHAR) AS end_time,
                    schedule_memo
                FROM create_schedule
                WHERE schedule_seq = %s
                  AND family_room_id = %s
                  AND deleted_at IS NULL
                """,
                (schedule_seq, family_room_id),
            )
            previous = cursor.fetchone()

        if previous is None:
            raise ValueError(
                "재수락 요청의 변경 전 내용을 확인하지 못했습니다."
            )

    return {
        "request_history_seq": request["history_seq"],
        "request_history_seqs": request_history_seqs,
        "requested_at": request["updated_at"],
        "latest_history_seq": latest["history_seq"],
        "before": previous,
        "current": latest,
    }