"""수락·재수락 결과를 현재 주보호자에게 전달한다. DB 확정은 호출자가 관리한다."""
from uuid import uuid4
from firebase_admin import firestore
from python.features.notifications.store import collection, publish
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
