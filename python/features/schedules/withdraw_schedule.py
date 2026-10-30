"""일정 담당 가족의 참여 철회. 공간 참여 탈퇴와 구분한다."""
import logging
from fastapi import HTTPException
from python.database import connect
from python.features.schedules.delete_schedule import get_schedule_for_delete
from python.features.schedules.change_notifications import prepare_change
from python.features.notifications.store import get_event, publish

logger = logging.getLogger(__name__)


def prepare_withdrawal_notifications(conn, schedule, history_seq, actor_id):
    with conn.cursor() as cursor:
        cursor.execute("""SELECT p.user_id, p.is_representative, u.name
            FROM participate p JOIN `user` u ON u.user_id=p.user_id
            WHERE p.family_room_id=%s AND p.left_at IS NULL
            AND u.withdrawn_at IS NULL""", (schedule['family_room_id'],))
        members = cursor.fetchall()
        cursor.execute('SELECT updated_at FROM update_schedule WHERE history_seq=%s', (history_seq,))
        updated_at = cursor.fetchone()['updated_at']
    guardians = list({m['user_id'] for m in members if m['is_representative'] == 1})
    if not guardians:
        raise ValueError('현재 주보호자를 확인하지 못했습니다.')
    actor_name = next(m['name'] for m in members if m['user_id'] == actor_id)
    payload = dict(schedule_seq=schedule['schedule_seq'], history_seq=history_seq,
        family_room_id=schedule['family_room_id'],
        schedule_created_at=str(schedule['created_at']), history_updated_at=str(updated_at),
        former_assignee_id=actor_id, actor_id=actor_id, actor_name=actor_name,
        reason='participation_withdrawal')
    # 직접 참여를 취소한 사람에게는 본인의 작업 알림을 보내지 않는다.
    # 주보호자 본인이 철회했거나 혼자 있는 공간이면 수신자 없는 이벤트도 만들지 않는다.
    targets = [
        ('schedule_withdrawn', [user for user in guardians if user != actor_id]),
        ('schedule_recruitment', list({m['user_id'] for m in members if m['user_id'] != actor_id})),
    ]
    return [prepare_change(dict(payload, notification_type=kind, recipient_ids=recipients))
            for kind, recipients in targets if recipients]



def publish_withdrawal_notification(identifier):
    event = get_event(identifier)
    if not event or event.get('status') not in ('pending', 'published'):
        return False
    kind = event.get('notification_type')
    if kind == 'schedule_recruitment' and event.get('status') == 'pending':
        from python.features.schedules.urgent_schedule import redirect_urgent_recruitment
        redirected = redirect_urgent_recruitment(event)
        if redirected is not None:
            return redirected
    if (kind not in ('schedule_withdrawn', 'schedule_recruitment')
            or event.get('notification_id') != identifier
            or event.get('reason') != 'participation_withdrawal'
            or identifier != f"{kind}_{event['schedule_seq']}_{event['history_seq']}"):
        return False
    conn = connect()
    try:
        with conn.cursor() as cursor:
            cursor.execute("""SELECT s.created_at, s.accepted_by, h.updated_at, h.changed_by,
                    (SELECT MAX(h2.history_seq) FROM update_schedule h2
                     WHERE h2.schedule_seq=s.schedule_seq AND h2.family_room_id=s.family_room_id) AS latest_history_seq
                FROM create_schedule s JOIN family_room f ON f.family_room_id=s.family_room_id
                JOIN update_schedule h ON h.schedule_seq=s.schedule_seq
                  AND h.family_room_id=s.family_room_id
                WHERE s.schedule_seq=%s AND s.family_room_id=%s AND h.history_seq=%s
                  AND s.deleted_at IS NULL AND f.family_room_deleted_at IS NULL
                  AND h.update_accepted_by IS NULL AND h.update_accepted_at IS NULL""",
                (event['schedule_seq'], event['family_room_id'], event['history_seq']))
            saved = cursor.fetchone()
        if (not saved or str(saved['created_at']) != event.get('schedule_created_at')
                or str(saved['updated_at']) != event.get('history_updated_at')
                or saved['changed_by'] != event.get('former_assignee_id')
                or not event.get('recipient_ids')):
            return False
        if kind == 'schedule_recruitment' and (
                saved['accepted_by'] is not None or saved['latest_history_seq'] != event['history_seq']):
            return False
        # 주보호자에게 전달하는 철회 사실은 새 배정 후에도 유효하다.
        return publish(identifier, str(saved['created_at']))
    finally:
        conn.close()


def withdraw_schedule(conn, schedule_seq, user_id, expected_history_seq, expected_accepted_at):
    from python.features.schedules.router import insert_schedule_history
    with conn.cursor() as cursor:
        cursor.execute('SELECT family_room_id FROM create_schedule WHERE schedule_seq=%s AND deleted_at IS NULL', (schedule_seq,))
        base = cursor.fetchone()
        if base is None:
            raise HTTPException(404, '일정이 없거나 삭제되었습니다.')
        # 다른 일정 변경과 동일하게 공간 → 일정 순서로 잠근다.
        cursor.execute("""SELECT family_room_id FROM family_room
            WHERE family_room_id=%s AND family_room_deleted_at IS NULL FOR UPDATE""", (base['family_room_id'],))
        if cursor.fetchone() is None:
            raise HTTPException(403, '이용할 수 없는 가족 공간입니다.')
        schedule = get_schedule_for_delete(conn, schedule_seq, base['family_room_id'])
        cursor.execute("""SELECT p.user_id FROM participate p JOIN `user` u ON u.user_id=p.user_id
            WHERE p.family_room_id=%s AND p.user_id=%s AND p.left_at IS NULL
            AND u.withdrawn_at IS NULL FOR UPDATE""", (base['family_room_id'], user_id))
        if cursor.fetchone() is None:
            raise HTTPException(403, '현재 참여 중인 가족만 이용할 수 있습니다.')
        if schedule['deleted_at'] is not None:
            raise HTTPException(404, '삭제된 일정입니다.')
        if schedule['accepted_by'] != user_id:
            raise HTTPException(409, '현재 담당 가족만 참여를 철회할 수 있습니다. 다시 조회해 주세요.')
        if schedule['schedule_state'] != '미완료':
            raise HTTPException(409, '미완료 일정만 참여를 철회할 수 있습니다.')
        if (schedule['history_seq'] != expected_history_seq
                or schedule['accepted_at'] != expected_accepted_at):
            raise HTTPException(409, '일정이 변경되었습니다. 최신 내용을 확인해 주세요.')
        # 대기 중에는 기존 재수락 거절 흐름을 사용한다.
        if schedule['history_seq'] is not None:
            cursor.execute('SELECT update_accepted_by, update_accepted_at FROM update_schedule WHERE history_seq=%s', (schedule['history_seq'],))
            latest = cursor.fetchone()
            if latest['update_accepted_by'] == user_id and latest['update_accepted_at'] is None:
                raise HTTPException(409, '재수락 요청 중에는 거절 버튼을 이용해 주세요.')
        cursor.execute("""UPDATE create_schedule SET accepted_by=NULL, accepted_at=NULL
            WHERE schedule_seq=%s AND accepted_by=%s AND deleted_at IS NULL""", (schedule_seq, user_id))
        if cursor.rowcount != 1:
            raise HTTPException(409, '일정 상태가 변경되었습니다. 다시 조회해 주세요.')
    history_seq = insert_schedule_history(conn, schedule_seq, schedule['family_room_id'], user_id, schedule)
    identifiers = prepare_withdrawal_notifications(conn, schedule, history_seq, user_id)
    return history_seq, identifiers
