"""일정 담당자가 호출하는 Firestore 알림 준비·발행 함수."""
from python.database import connect
from python.features.notifications import store


def prepare_schedule_notifications(connection, schedule_seq: int):
    """일정 INSERT 후 commit 전에 호출한다. 실패하면 호출자가 MySQL을 rollback한다."""
    with connection.cursor() as cursor:
        cursor.execute('''SELECT s.family_room_id, s.created_at, s.created_by,
            (TIMESTAMP(s.schedule_date, s.start_time) > CURRENT_TIMESTAMP
             AND TIMESTAMP(s.schedule_date, s.start_time)
                 <= DATE_ADD(CURRENT_TIMESTAMP, INTERVAL 72 HOUR)) AS within_reminder_window
            FROM create_schedule s
            JOIN family_room f ON f.family_room_id = s.family_room_id
            WHERE s.schedule_seq = %s AND s.deleted_at IS NULL
            AND f.family_room_deleted_at IS NULL FOR UPDATE''', (schedule_seq,))
        schedule = cursor.fetchone()
        if schedule is None:
            raise ValueError('알림을 생성할 유효한 일정이 없습니다.')
        # 서버 DB 시각 기준 72시간 이내는 재알림만 준비한다. 등록 이벤트 자체를
        # 만들지 않아 worker가 나중에 등록 푸시까지 중복 발송하는 것도 막는다.
        if schedule.get('within_reminder_window'):
            return False
        # 등록자를 제외할 수 있도록 DB에서 실제 등록자와 현재 가족을 조회한다. 수신자를 외부 입력으로 받지 않는다.
        cursor.execute('''SELECT DISTINCT p.user_id FROM participate p
            JOIN `user` u ON u.user_id = p.user_id AND u.withdrawn_at IS NULL
            WHERE p.family_room_id = %s AND p.left_at IS NULL''', (schedule['family_room_id'],))
        recipients = [row['user_id'] for row in cursor.fetchall()]
    if not recipients:
        raise ValueError('알림을 받을 가족이 없습니다.')
    store.prepare(dict(schedule_seq=schedule_seq, family_room_id=schedule['family_room_id'],
                       schedule_created_at=str(schedule['created_at']), actor_id=schedule.get('created_by'),
                       recipient_ids=recipients))
    return True


def publish_schedule_notifications(schedule_seq: int, *, identifier=None):
    """commit 후 새 DB 연결로 확정 여부를 확인한다. 실패 시 같은 ID로 재시도한다."""
    connection = connect()
    try:
        with connection.cursor() as cursor:
            cursor.execute('''SELECT s.created_at, s.family_room_id FROM create_schedule s
                JOIN family_room f ON f.family_room_id = s.family_room_id
                WHERE s.schedule_seq = %s AND s.deleted_at IS NULL
                AND f.family_room_deleted_at IS NULL''', (schedule_seq,))
            row = cursor.fetchone()
        if row is None:
            return False
        identity = dict(schedule_seq=schedule_seq, family_room_id=row['family_room_id'],
                        schedule_created_at=str(row['created_at']))
        candidates = [str(schedule_seq), store.registration_identifier(identity)]
        if identifier is not None:
            # worker는 조회한 바로 그 문서만 복구한다. 과거 문서로 새 일정 알림을 발행하지 않는다.
            if str(identifier) not in candidates:
                return False
            candidates = [str(identifier)]
        for candidate in candidates:
            event = store.get_event(candidate)
            if (event is not None and event.get('schedule_seq') == schedule_seq
                    and event.get('notification_type') in (None, 'schedule_created')
                    and all(event.get(key) == identity[key]
                            for key in ('family_room_id', 'schedule_created_at'))):
                return store.publish(candidate, identity['schedule_created_at'])
        return False
    finally:
        connection.close()
