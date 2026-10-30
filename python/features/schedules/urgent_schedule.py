"""담당자 없는 24시간 이하 일정의 긴급 모집. 일정당 한 번 발행한다."""
from datetime import datetime, timedelta
from hashlib import sha256
import logging

from firebase_admin import firestore
from python.database import connect
from python.features.notifications.store import collection
from python.features.schedules.reminders import load_state, start_key, unassigned
from python.features.schedules.reminder_cache import CompletedReminders

logger = logging.getLogger(__name__)
completed = CompletedReminders()


def is_urgent(current):
    if not unassigned(current):
        return False
    day, clock = start_key(current)
    return timedelta(0) < datetime.combine(day, clock) - current['server_now'] <= timedelta(hours=24)


def urgent_identifier(current):
    # 재수정 때 초기화할지는 미정이므로 동일 일정에는 보수적으로 한 번만 발행한다.
    identity = sha256(f"{current['family_room_id']}|{current['created_at']}".encode()).hexdigest()
    return f"schedule_urgent_{current['schedule_seq']}_{identity}"


def _publish_once(transaction, ref, payload):
    snapshot = ref.get(transaction=transaction)
    if snapshot.exists:
        return False
    transaction.create(ref, {**payload, 'status': 'published', 'push_pending': True,
                            'created_at': firestore.SERVER_TIMESTAMP,
                            'published_at': firestore.SERVER_TIMESTAMP})
    return True


def process_urgent_schedule(schedule_seq, *, expected_event=None):
    connection = connect()
    try:
        with connection.cursor() as cursor:
            cursor.execute('SELECT family_room_id FROM create_schedule WHERE schedule_seq=%s', (schedule_seq,))
            original = cursor.fetchone()
            if original is None:
                return None
            cursor.execute('''SELECT family_room_id FROM family_room WHERE family_room_id=%s
                AND family_room_deleted_at IS NULL FOR UPDATE''', (original['family_room_id'],))
            if cursor.fetchone() is None:
                return None
        loaded = load_state(connection, schedule_seq, lock=True)
        if loaded is None:
            return None
        current, _ = loaded
        if current['family_room_id'] != original['family_room_id'] or not is_urgent(current):
            return None
        with connection.cursor() as cursor:
            cursor.execute('''SELECT history_seq, changed_by, update_accepted_by,
                    update_accepted_at FROM update_schedule
                WHERE schedule_seq=%s AND family_room_id=%s ORDER BY history_seq DESC LIMIT 2''',
                (schedule_seq, current['family_room_id']))
            histories = cursor.fetchall()
            if expected_event is not None and (
                    not histories or histories[0]['history_seq'] != expected_event.get('history_seq')
                    or str(current['created_at']) != expected_event.get('schedule_created_at')
                    or current['family_room_id'] != expected_event.get('family_room_id')):
                return None
            # 직접 취소·거절한 직전 담당자는 자동 검사에서도 제외한다.
            actor = None
            if len(histories) == 2:
                latest, previous = histories
                if (latest['update_accepted_by'] is None
                        and previous['update_accepted_by'] == latest['changed_by']):
                    actor = latest['changed_by']
            if expected_event is not None:
                actor = expected_event.get('actor_id')
            cursor.execute('''SELECT DISTINCT p.user_id FROM participate p JOIN `user` u ON u.user_id=p.user_id
                WHERE p.family_room_id=%s AND p.left_at IS NULL AND u.withdrawn_at IS NULL FOR UPDATE''',
                (current['family_room_id'],))
            recipients = sorted(row['user_id'] for row in cursor.fetchall() if row['user_id'] != actor)
        if not recipients:
            return None
        identifier = urgent_identifier(current)
        if completed.contains(identifier):
            return False
        ref = collection().document(identifier)
        day, clock = start_key(current)
        published = firestore.transactional(_publish_once)(ref._client.transaction(), ref, dict(
            notification_id=identifier, notification_type='schedule_urgent',
            schedule_seq=schedule_seq, family_room_id=current['family_room_id'],
            schedule_created_at=str(current['created_at']), recipient_ids=recipients,
            is_urgent=True, actor_id=actor, schedule_start_at=str(datetime.combine(day, clock)),
            reason='urgent_recruitment',
            message='일정 시작까지 24시간 이하이며 담당 가족이 없습니다. 긴급 돌봄 일정을 확인하고 수락해 주세요.'))
        completed.remember(identifier)
        return published
    finally:
        try:
            connection.rollback()
        finally:
            connection.close()


def redirect_urgent_recruitment(event):
    """긴급 재모집과 24시간 자동 알림을 같은 식별자로 합친다."""
    result = process_urgent_schedule(event['schedule_seq'], expected_event=event)
    if result is None:
        return None
    # 별도 일반 재모집을 발송하지 않도록 기록한다. 실패하면 같은 긴급 ID로 재시도한다.
    collection().document(event['notification_id']).update({'status': 'superseded', 'is_urgent': True})
    return True


def try_urgent_schedule(schedule_seq):
    try:
        return bool(process_urgent_schedule(schedule_seq))
    except Exception:
        logger.exception('일정 %s 긴급 모집 확인 실패; worker에서 재시도', schedule_seq)
        return False


def check_urgent_schedules():
    connection = connect()
    try:
        with connection.cursor() as cursor:
            cursor.execute('''SELECT s.schedule_seq FROM create_schedule s
                JOIN family_room f ON f.family_room_id=s.family_room_id
                LEFT JOIN update_schedule h ON h.schedule_seq=s.schedule_seq AND h.family_room_id=s.family_room_id
                  AND h.history_seq=(SELECT MAX(h2.history_seq) FROM update_schedule h2
                    WHERE h2.schedule_seq=s.schedule_seq AND h2.family_room_id=s.family_room_id)
                WHERE s.deleted_at IS NULL AND f.family_room_deleted_at IS NULL
                  AND s.schedule_state='미완료' AND s.accepted_by IS NULL
                  AND TIMESTAMP(COALESCE(h.schedule_date,s.schedule_date),
                    COALESCE(h.updated_start_time,s.start_time)) > CURRENT_TIMESTAMP
                  AND TIMESTAMP(COALESCE(h.schedule_date,s.schedule_date),
                    COALESCE(h.updated_start_time,s.start_time)) <= DATE_ADD(CURRENT_TIMESTAMP, INTERVAL 24 HOUR)''')
            rows = cursor.fetchall()
    finally:
        connection.close()
    return sum(try_urgent_schedule(row['schedule_seq']) for row in rows)
