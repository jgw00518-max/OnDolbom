"""수락·재수락 결과를 현재 주보호자에게 전달한다. DB 확정은 호출자가 관리한다."""
from uuid import uuid4
from firebase_admin import firestore
from python.features.notifications.store import collection, publish, get_event
from python.database import connect
from python.features.schedules.change_notifications import _prepare_change


def prepare_response_notification(connection, schedule_seq, actor_id, history_seq=None):
    with connection.cursor() as cursor:
        cursor.execute('''SELECT s.family_room_id, s.created_at, s.accepted_at, u.name
            FROM create_schedule s JOIN family_room f ON f.family_room_id=s.family_room_id
            JOIN `user` u ON u.user_id=s.accepted_by
            WHERE s.schedule_seq=%s AND s.accepted_by=%s AND s.deleted_at IS NULL
            AND f.family_room_deleted_at IS NULL AND u.withdrawn_at IS NULL''', (schedule_seq, actor_id))
        schedule = cursor.fetchone()
        if schedule is None:
            raise ValueError('수락 결과를 확인할 수 없습니다.')
        cursor.execute('''SELECT DISTINCT p.user_id FROM participate p
            JOIN `user` u ON u.user_id=p.user_id
            WHERE p.family_room_id=%s AND p.is_representative=1
            AND p.left_at IS NULL AND u.withdrawn_at IS NULL''', (schedule['family_room_id'],))
        recipients = [row['user_id'] for row in cursor.fetchall()]
    if not recipients:
        raise ValueError('현재 주보호자를 확인할 수 없습니다.')
    kind = 'schedule_accepted' if history_seq is None else 'schedule_reconfirmed'
    # 최초 수락은 변경 이력이 없으므로 별도 이벤트 번호를 사용한다.
    identifier = f'{kind}_{schedule_seq}_{history_seq if history_seq is not None else uuid4().hex}'
    payload = dict(notification_id=identifier, notification_type=kind,
                   schedule_seq=schedule_seq, family_room_id=schedule['family_room_id'],
                   schedule_created_at=str(schedule['created_at']), history_seq=history_seq,
                   history_updated_at=str(schedule['accepted_at']), actor_id=actor_id,
                   actor_name=schedule['name'], recipient_ids=recipients)
    ref = collection().document(identifier)
    firestore.transactional(_prepare_change)(ref._client.transaction(), ref, payload)
    return identifier, str(schedule['created_at'])


def publish_response_notification(prepared):
    return publish(*prepared)


def retry_response_notification(identifier):
    """커밋된 수락 결과가 그대로 유효할 때만 미발행 알림을 복구한다."""
    event = get_event(identifier)
    if not event or event.get('status') not in ('pending', 'published'):
        return False
    kind = event.get('notification_type')
    seq = event.get('schedule_seq')
    history = event.get('history_seq')
    if kind not in ('schedule_accepted', 'schedule_reconfirmed'):
        return False
    if event.get('notification_id') != identifier:
        return False
    if kind == 'schedule_reconfirmed':
        if history is None or identifier != f'{kind}_{seq}_{history}':
            return False
    elif history is not None or not identifier.startswith(f'{kind}_{seq}_'):
        return False
    conn = connect()
    try:
        with conn.cursor() as cursor:
            # 롤백된 수락이나 이후 해제·교체된 담당자의 결과를 뒤늦게 보내지 않는다.
            cursor.execute("""SELECT s.family_room_id, s.created_at, s.accepted_at
                FROM create_schedule s
                JOIN family_room f ON f.family_room_id=s.family_room_id
                JOIN participate p ON p.family_room_id=s.family_room_id AND p.user_id=s.accepted_by
                JOIN `user` u ON u.user_id=p.user_id
                WHERE s.schedule_seq=%s AND s.accepted_by=%s
                AND s.deleted_at IS NULL AND f.family_room_deleted_at IS NULL
                AND p.left_at IS NULL AND u.withdrawn_at IS NULL""",
                (seq, event.get('actor_id')))
            schedule = cursor.fetchone()
            if not schedule or any((
                schedule['family_room_id'] != event.get('family_room_id'),
                str(schedule['created_at']) != event.get('schedule_created_at'),
                str(schedule['accepted_at']) != event.get('history_updated_at'),
                schedule['accepted_at'] is None,
            )):
                return False
            if kind == 'schedule_reconfirmed':
                cursor.execute("""SELECT history_seq FROM update_schedule
                    WHERE history_seq=%s AND schedule_seq=%s AND family_room_id=%s
                    AND update_accepted_by=%s AND update_accepted_at IS NOT NULL
                    AND history_seq=(SELECT MAX(h.history_seq) FROM update_schedule h
                        WHERE h.schedule_seq=%s)""",
                    (history, seq, schedule['family_room_id'], event.get('actor_id'), seq))
                if cursor.fetchone() is None:
                    return False
        # 공통 publish는 pending일 때만 푸시를 예약하고 기존 읽음 기록을 유지한다.
        return publish(identifier, event['schedule_created_at'])
    finally:
        conn.close()
