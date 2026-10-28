"""담당자 없는 일정의 72시간 재알림. MySQL은 조회하고 Firestore로 중복을 막는다."""
from datetime import date, datetime, time, timedelta
from hashlib import sha256
import logging

from firebase_admin import firestore
from python.database import connect
from python.features.schedules.reminder_cache import completed_reminders
from python.features.notifications.store import collection

logger = logging.getLogger(__name__)
WINDOW = timedelta(hours=72)


def start_key(row):
    return (date.fromisoformat(str(row['schedule_date'])[:10]),
            time.fromisoformat(str(row['start_time'])))


def reminder_state(schedule, histories):
    """이름·메모·종료시간·응답 이력은 재알림 횟수를 늘리지 않는다."""
    current = dict(schedule)
    previous = start_key(current)
    version = 0
    for history in histories:
        key = start_key(history)
        if key != previous:
            version = history['history_seq']
        previous = key
        current.update(history)
    fingerprint = sha256(f"{schedule['created_at']}|{version}|{previous[0]}|{previous[1]}".encode()).hexdigest()
    return current, fingerprint


def load_state(connection, schedule_seq, lock=False):
    with connection.cursor() as cursor:
        cursor.execute('''SELECT s.schedule_seq, s.family_room_id, s.created_at,
            s.schedule_date, CAST(s.start_time AS CHAR) AS start_time,
            s.accepted_by, s.schedule_state, s.deleted_at, CURRENT_TIMESTAMP AS server_now
            FROM create_schedule s WHERE s.schedule_seq=%s''' + (' FOR UPDATE' if lock else ''), (schedule_seq,))
        schedule = cursor.fetchone()
        if schedule is None:
            return None
        cursor.execute('''SELECT history_seq, schedule_date,
            CAST(updated_start_time AS CHAR) AS start_time FROM update_schedule
            WHERE schedule_seq=%s AND family_room_id=%s ORDER BY history_seq''' + (' FOR UPDATE' if lock else ''),
                       (schedule_seq, schedule['family_room_id']))
        return reminder_state(schedule, cursor.fetchall())


def unassigned(current):
    return (current['deleted_at'] is None and current['accepted_by'] is None
            and current['schedule_state'] == '미완료')


def is_due(current):
    if not unassigned(current):
        return False
    start_date, start_time = start_key(current)
    remaining = datetime.combine(start_date, start_time) - current['server_now']
    return timedelta(0) < remaining <= WINDOW


def _publish_once(transaction, ref, payload):
    snapshot = ref.get(transaction=transaction, timeout=10)
    if snapshot.exists and snapshot.to_dict().get('status') == 'published':
        return False
    # 원자적 문서 생성으로 여러 worker·API가 동시에 검사해도 한 번만 발행한다.
    transaction.set(ref, {**payload, 'status': 'published',
                          'created_at': firestore.SERVER_TIMESTAMP,
                          'published_at': firestore.SERVER_TIMESTAMP})
    return True


def process_reminder(schedule_seq):
    connection = connect()
    try:
        with connection.cursor() as cursor:
            cursor.execute('SELECT family_room_id FROM create_schedule WHERE schedule_seq=%s', (schedule_seq,))
            original = cursor.fetchone()
            if original is None:
                return False
            # 일정 변경·수락·삭제와 같은 순서(공간 → 일정)로 잠근다.
            cursor.execute('''SELECT family_room_id FROM family_room WHERE family_room_id=%s
                AND family_room_deleted_at IS NULL FOR UPDATE''', (original['family_room_id'],))
            if cursor.fetchone() is None:
                return False
        loaded = load_state(connection, schedule_seq, lock=True)
        if loaded is None:
            return False
        current, fingerprint = loaded
        if current['family_room_id'] != original['family_room_id'] or not is_due(current):
            return False
        with connection.cursor() as cursor:
            cursor.execute('''SELECT p.user_id FROM participate p JOIN `user` u
                ON u.user_id=p.user_id WHERE p.family_room_id=%s AND p.left_at IS NULL
                AND u.withdrawn_at IS NULL FOR UPDATE''', (current['family_room_id'],))
            recipients = sorted({row['user_id'] for row in cursor.fetchall()})
        if not recipients:
            return False
        identifier = f'schedule_reminder_{schedule_seq}_{fingerprint}'
        # 일정 번호와 시작 시간 변경 버전이 모두 같을 때만 Firestore 조회를 생략한다.
        if completed_reminders.contains(identifier):
            return False
        ref = collection().document(identifier)
        # 실제 발행까지 DB 잠금을 유지한다. 발송 직전에 바뀐 배정·시간을 놓치지 않는다.
        published = firestore.transactional(_publish_once)(ref._client.transaction(), ref, dict(
            notification_id=identifier, notification_type='schedule_reminder',
            schedule_seq=schedule_seq, family_room_id=current['family_room_id'],
            schedule_created_at=str(current['created_at']), reminder_key=fingerprint,
            recipient_ids=recipients))
        # 정상 반환은 신규 발행 또는 기존 published 확인을 뜻한다. 예외는 기억하지 않는다.
        completed_reminders.remember(identifier)
        return published
    finally:
        # DB 변경은 없으며 읽기 트랜잭션의 잠금만 해제한다.
        try:
            connection.rollback()
        finally:
            connection.close()


def try_remind(schedule_seq):
    """저장 완료 후 즉시 확인. 장애가 나도 일정 저장을 실패로 돌리지 않는다."""
    try:
        return bool(process_reminder(schedule_seq))
    except Exception:
        logger.exception('일정 %s 재알림 확인 실패; worker에서 재시도', schedule_seq)
        return False


def reminder_is_current(connection, event):
    loaded = load_state(connection, event['schedule_seq'])
    if loaded is None:
        return False
    current, fingerprint = loaded
    return (unassigned(current) and current['family_room_id'] == event['family_room_id']
            and str(current['created_at']) == event['schedule_created_at']
            and fingerprint == event.get('reminder_key'))


def check_reminders():
    connection = connect()
    try:
        with connection.cursor() as cursor:
            cursor.execute('''SELECT s.schedule_seq FROM create_schedule s
                JOIN family_room f ON f.family_room_id=s.family_room_id
                LEFT JOIN update_schedule h ON h.schedule_seq=s.schedule_seq
                    AND h.family_room_id=s.family_room_id
                    AND h.history_seq=(SELECT MAX(h2.history_seq) FROM update_schedule h2
                        WHERE h2.schedule_seq=s.schedule_seq AND h2.family_room_id=s.family_room_id)
                WHERE s.deleted_at IS NULL AND f.family_room_deleted_at IS NULL
                AND s.schedule_state='미완료' AND s.accepted_by IS NULL
                AND TIMESTAMP(CASE WHEN h.history_seq IS NULL THEN s.schedule_date ELSE h.schedule_date END,
                    CASE WHEN h.history_seq IS NULL THEN s.start_time ELSE h.updated_start_time END)
                    > CURRENT_TIMESTAMP
                AND TIMESTAMP(CASE WHEN h.history_seq IS NULL THEN s.schedule_date ELSE h.schedule_date END,
                    CASE WHEN h.history_seq IS NULL THEN s.start_time ELSE h.updated_start_time END)
                    <= DATE_ADD(CURRENT_TIMESTAMP, INTERVAL 72 HOUR)
                ORDER BY s.schedule_seq''')
            candidates = cursor.fetchall()
    finally:
        connection.close()
    return sum(try_remind(row['schedule_seq']) for row in candidates)
