"""이름·메모만 변경한 최신 이력의 비교 정보를 만든다."""


def content_change(snapshots):
    previous = None
    change = None
    changes = []
    for current in snapshots:
        if previous is not None:
            time_changed = any(current[k] != previous[k] for k in
                               ('schedule_date', 'start_time', 'end_time'))
            text_changed = any(current[k] != previous[k] for k in
                               ('schedule_name', 'schedule_memo'))
            if time_changed:
                change = None
                changes = []
            elif text_changed:
                change = {'version': str(current['history_seq']),
                          'before': previous.copy()}
                changes.append(change.copy())
        previous = current
    if change is not None:
        change['changes'] = changes
    return change


def get_content_change(conn, schedule_seq, family_room_id):
    with conn.cursor() as cursor:
        cursor.execute(
            """SELECT 0 AS history_seq, schedule_date, schedule_name,
                CAST(start_time AS CHAR) AS start_time,
                CAST(end_time AS CHAR) AS end_time, schedule_memo
                FROM create_schedule WHERE schedule_seq=%s AND family_room_id=%s
                AND deleted_at IS NULL""", (schedule_seq, family_room_id))
        initial = cursor.fetchone()
        if initial is None:
            return None
        cursor.execute(
            """SELECT history_seq, schedule_date,
                updated_schedule_name AS schedule_name,
                CAST(updated_start_time AS CHAR) AS start_time,
                CAST(updated_end_time AS CHAR) AS end_time,
                updated_schedule_memo AS schedule_memo
                FROM update_schedule WHERE schedule_seq=%s AND family_room_id=%s
                ORDER BY history_seq""", (schedule_seq, family_room_id))
        return content_change([initial, *cursor.fetchall()])
