"""공간 역할 이전 및 참여 종료·미완료 일정 배정 해제를 트랜잭션으로 처리한다."""
from fastapi import HTTPException
from pymysql import MySQLError
from python.database import connect
from python.features.notifications import space_events


def transfer_representative(room_id: str, actor_id: str, target_user_id: str) -> dict:
    """활성 주보호자와 일반 가족의 역할만 교체하고 참여·원본 기록은 보존한다."""
    connection = None
    try:
        connection = connect()
        with connection.cursor() as cursor:
            # 이전·탈퇴·강퇴·공간 삭제가 같은 공간을 동시에 바꾸지 않도록 공간부터 잠근다.
            cursor.execute("""SELECT family_room_id FROM family_room
                WHERE family_room_id=%s AND family_room_deleted_at IS NULL
                FOR UPDATE""", (room_id,))
            if cursor.fetchone() is None:
                raise HTTPException(404, '이용할 수 없는 돌봄 공간입니다.')
            # 전체 활성 참여를 잠가 기존 주보호자가 한 명인지도 검증한다.
            cursor.execute("""SELECT participate_seq,user_id,is_representative
                FROM participate WHERE family_room_id=%s
                AND left_at IS NULL AND is_active=1
                ORDER BY participate_seq FOR UPDATE""", (room_id,))
            members = cursor.fetchall()
            actor = next((row for row in members if row['user_id'] == actor_id), None)
            if actor is None or actor['is_representative'] != 1:
                raise HTTPException(403, '현재 주보호자만 권한을 이전할 수 있습니다.')
            if actor_id == target_user_id:
                raise HTTPException(409, '본인에게 주보호자를 이전할 수 없습니다.')
            representatives = [row for row in members if row['is_representative'] == 1]
            if len(representatives) != 1:
                raise HTTPException(409, '주보호자 정보가 일치하지 않습니다. 가족 목록을 다시 확인해 주세요.')
            target = next((row for row in members if row['user_id'] == target_user_id), None)
            if target is None or target['is_representative'] != 0:
                raise HTTPException(409, '현재 공간에 참여 중인 일반 가족에게만 이전할 수 있습니다.')
            # 계정 탈퇴와도 경합할 수 있으므로 두 계정의 최신 상태를 잠금 조회한다.
            # 여러 공간이 같은 사용자를 참조해도 계정 잠금 순서는 일관되게 유지한다.
            cursor.execute("""SELECT user_id,withdrawn_at FROM `user`
                WHERE user_id IN (%s,%s) ORDER BY user_id FOR UPDATE""",
                tuple(sorted((actor_id, target_user_id))))
            users = {row['user_id']: row for row in cursor.fetchall()}
            if actor_id not in users or users[actor_id]['withdrawn_at'] is not None:
                raise HTTPException(403, '이용 가능한 주보호자 계정이 아닙니다.')
            if target_user_id not in users or users[target_user_id]['withdrawn_at'] is not None:
                raise HTTPException(409, '이전받을 가족의 계정 상태가 변경되었습니다.')

            # is_active는 생성 컬럼이다. 역할만 바꾸고 두 UPDATE를 함께 확정한다.
            cursor.execute("""UPDATE participate SET is_representative=0
                WHERE participate_seq=%s AND family_room_id=%s AND user_id=%s
                AND is_representative=1 AND is_active=1 AND left_at IS NULL""",
                (actor['participate_seq'], room_id, actor_id))
            if cursor.rowcount != 1:
                raise HTTPException(409, '주보호자 정보가 변경되었습니다. 다시 확인해 주세요.')
            cursor.execute("""UPDATE participate SET is_representative=1
                WHERE participate_seq=%s AND family_room_id=%s AND user_id=%s
                AND is_representative=0 AND is_active=1 AND left_at IS NULL""",
                (target['participate_seq'], room_id, target_user_id))
            if cursor.rowcount != 1:
                raise HTTPException(409, '이전받을 가족의 참여 정보가 변경되었습니다.')
        notice = space_events.prepare(connection, room_id, actor_id, 'representative_transferred',
                                      target['participate_seq'], target_id=target_user_id)
        connection.commit()
        space_events.publish_safely(notice)
        return {
            'result': 'OK',
            'family_room_id': room_id,
            'previous_representative_user_id': actor_id,
            'representative_user_id': target_user_id,
        }
    except HTTPException:
        if connection is not None:
            connection.rollback()
        raise
    except (MySQLError, ValueError):
        if connection is not None:
            connection.rollback()
        raise HTTPException(503, '주보호자를 이전하지 못했습니다. 다시 시도해 주세요.') from None
    finally:
        if connection is not None:
            connection.close()


def end_membership(room_id, actor_id, participate_seq=None, *, connection=None, allow_inactive=False):
    # 회원 탈퇴는 모든 공간 종료와 계정 처리를 한 트랜잭션으로 묶는다.
    owns_connection = connection is None
    try:
        if owns_connection:
            connection = connect()
        with connection.cursor() as cursor:
            # 초대·일정 변경·공간 삭제와 같은 순서로 공간부터 잠근다.
            cursor.execute("""SELECT family_room_id FROM family_room WHERE family_room_id=%s
                AND family_room_deleted_at IS NULL FOR UPDATE""", (room_id,))
            if cursor.fetchone() is None:
                raise HTTPException(404, '이용할 수 없는 돌봄 공간입니다.')
            # allow_inactive는 인증 API 입력이 아니며 30일 경과 정리 worker만 사용한다.
            active_check = '' if allow_inactive else ' AND u.withdrawn_at IS NULL'
            cursor.execute("""SELECT p.participate_seq,p.user_id,p.is_representative
                FROM participate p JOIN `user` u ON u.user_id=p.user_id
                WHERE p.family_room_id=%s AND p.user_id=%s AND p.left_at IS NULL
                AND p.is_active=1""" + active_check + " FOR UPDATE", (room_id, actor_id))
            actor = cursor.fetchone()
            if actor is None:
                raise HTTPException(403, '현재 참여 중인 돌봄 공간만 이용할 수 있습니다.')
            if participate_seq is None:
                target = actor
                if actor['is_representative'] == 1:
                    raise HTTPException(409, '주보호자는 이전 후 공간에서 나갈 수 있습니다.')
            else:
                if actor['is_representative'] != 1:
                    raise HTTPException(403, '현재 주보호자만 가족을 강퇴할 수 있습니다.')
                # 사용자 ID만 받지 않고 참여 행 번호를 사용해 과거 참여 대상과 구분한다.
                cursor.execute("""SELECT participate_seq,user_id,is_representative FROM participate
                    WHERE participate_seq=%s AND family_room_id=%s
                    AND left_at IS NULL AND is_active=1 FOR UPDATE""", (participate_seq, room_id))
                target = cursor.fetchone()
                if target is None:
                    raise HTTPException(409, '이미 참여가 종료되었거나 가족 정보가 변경되었습니다.')
                if target['user_id'] == actor_id or target['is_representative'] == 1:
                    raise HTTPException(409, '본인 또는 주보호자는 강퇴할 수 없습니다.')

            cursor.execute("""SELECT schedule_seq,schedule_date,schedule_name,
                CAST(start_time AS CHAR) AS start_time,CAST(end_time AS CHAR) AS end_time,schedule_memo
                FROM create_schedule WHERE family_room_id=%s AND accepted_by=%s
                AND schedule_state='미완료' AND deleted_at IS NULL ORDER BY schedule_seq FOR UPDATE""",
                (room_id, target['user_id']))
            schedules = cursor.fetchall()
            for schedule in schedules:
                cursor.execute("""SELECT schedule_date,updated_schedule_name AS schedule_name,
                    CAST(updated_start_time AS CHAR) AS start_time,
                    CAST(updated_end_time AS CHAR) AS end_time,updated_schedule_memo AS schedule_memo
                    FROM update_schedule WHERE schedule_seq=%s AND family_room_id=%s
                    ORDER BY history_seq DESC LIMIT 1 FOR UPDATE""", (schedule['schedule_seq'], room_id))
                current = cursor.fetchone() or schedule
                # 최신 날짜·내용은 보존하고 배정·재수락 대기만 종료하는 새 이력을 남긴다.
                cursor.execute("""INSERT INTO update_schedule (schedule_seq,schedule_date,family_room_id,
                    changed_by,update_accepted_by,update_accepted_at,updated_schedule_name,
                    updated_start_time,updated_end_time,updated_schedule_memo)
                    VALUES (%s,%s,%s,%s,NULL,NULL,%s,%s,%s,%s)""",
                    (schedule['schedule_seq'], current['schedule_date'], room_id, actor_id,
                     current['schedule_name'], current['start_time'], current['end_time'], current['schedule_memo']))
                cursor.execute("""UPDATE create_schedule SET accepted_by=NULL,accepted_at=NULL
                    WHERE schedule_seq=%s AND family_room_id=%s AND accepted_by=%s
                    AND schedule_state='미완료' AND deleted_at IS NULL""",
                    (schedule['schedule_seq'], room_id, target['user_id']))
                if cursor.rowcount != 1:
                    raise ValueError('담당 배정이 변경되었습니다.')
            # is_active는 left_at에서 계산되는 생성 컬럼이므로 직접 갱신하지 않는다.
            cursor.execute("""UPDATE participate SET left_at=CURRENT_TIMESTAMP
                WHERE participate_seq=%s AND family_room_id=%s AND left_at IS NULL AND is_active=1""",
                (target['participate_seq'], room_id))
            if cursor.rowcount != 1:
                raise ValueError('참여 정보가 변경되었습니다.')
        if owns_connection:
            notice = space_events.prepare(connection, room_id, actor_id,
                'member_left' if participate_seq is None else 'member_removed',
                target['participate_seq'], target_id=target['user_id'])
            connection.commit()
            space_events.publish_safely(notice)
        return dict(result='OK',family_room_id=room_id,user_id=target['user_id'],
                    participate_seq=target['participate_seq'],released_schedules=len(schedules))
    except HTTPException:
        if owns_connection and connection is not None:
            connection.rollback()
        raise
    except (MySQLError, ValueError):
        if owns_connection and connection is not None:
            connection.rollback()
        raise HTTPException(503, '공간 참여 종료를 처리하지 못했습니다. 목록을 확인한 뒤 다시 시도해 주세요.') from None
    finally:
        if owns_connection and connection is not None:
            connection.close()
