"""공간 참여 종료와 미완료 일정 배정 해제를 하나의 트랜잭션으로 처리한다."""
from fastapi import HTTPException
from pymysql import MySQLError
from python.database import connect


def end_membership(room_id, actor_id, participate_seq=None):
    connection = None
    try:
        connection = connect()
        with connection.cursor() as cursor:
            # 초대·일정 변경·공간 삭제와 같은 순서로 공간부터 잠근다.
            cursor.execute("""SELECT family_room_id FROM family_room WHERE family_room_id=%s
                AND family_room_deleted_at IS NULL FOR UPDATE""", (room_id,))
            if cursor.fetchone() is None:
                raise HTTPException(404, '이용할 수 없는 가족 공간입니다.')
            cursor.execute("""SELECT p.participate_seq,p.user_id,p.is_representative
                FROM participate p JOIN `user` u ON u.user_id=p.user_id
                WHERE p.family_room_id=%s AND p.user_id=%s AND p.left_at IS NULL
                AND p.is_active=1 AND u.withdrawn_at IS NULL FOR UPDATE""", (room_id, actor_id))
            actor = cursor.fetchone()
            if actor is None:
                raise HTTPException(403, '현재 참여 중인 가족 공간만 이용할 수 있습니다.')
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
        connection.commit()
        return dict(result='OK',family_room_id=room_id,user_id=target['user_id'],
                    participate_seq=target['participate_seq'],released_schedules=len(schedules))
    except HTTPException:
        if connection is not None:
            connection.rollback()
        raise
    except (MySQLError, ValueError):
        if connection is not None:
            connection.rollback()
        raise HTTPException(503, '공간 참여 종료를 처리하지 못했습니다. 목록을 확인한 뒤 다시 시도해 주세요.') from None
    finally:
        if connection is not None:
            connection.close()
