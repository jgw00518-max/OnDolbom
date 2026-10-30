"""채팅 읽음 위치와 미읽음 수. 사용자 ID는 인증된 API에서만 전달한다."""
from fastapi import HTTPException
from python.database import connect


def initialize(cursor, participate_seq, room_id):
    # 재초대도 새 참여 행을 사용하므로 이전 참여의 읽음 상태를 이어 쓰지 않는다.
    cursor.execute("""INSERT INTO chat_read_status (participate_seq,last_read_chat_seq,last_read_at)
        SELECT %s,COALESCE(MAX(chat_seq),0),CURRENT_TIMESTAMP FROM live_chat WHERE family_room_id=%s
        ON DUPLICATE KEY UPDATE participate_seq=chat_read_status.participate_seq""", (participate_seq,room_id))


def unread_counts(user_id):
    c=connect()
    try:
        with c.cursor() as q:
            q.execute("""SELECT p.family_room_id,COUNT(m.chat_seq) AS unread_count
                FROM participate p JOIN family_room f ON f.family_room_id=p.family_room_id
                JOIN `user` u ON u.user_id=p.user_id
                LEFT JOIN chat_read_status r ON r.participate_seq=p.participate_seq
                LEFT JOIN live_chat m ON m.family_room_id=p.family_room_id
                    AND m.chat_seq>COALESCE(r.last_read_chat_seq,0) AND m.user_id<>p.user_id
                    AND m.live_chat_deleted_at IS NULL
                WHERE p.user_id=%s AND p.is_active=1 AND p.left_at IS NULL
                    AND f.family_room_deleted_at IS NULL AND u.withdrawn_at IS NULL
                GROUP BY p.family_room_id""", (user_id,))
            return {r['family_room_id']:int(r['unread_count']) for r in q.fetchall()}
    finally:c.close()


def mark_read(room_id,user_id,chat_seq):
    c=connect()
    try:
        with c.cursor() as q:
            # 메시지 저장·초대·탈퇴와 같은 순서로 잠가 참여 종료와 경합하지 않는다.
            q.execute("""SELECT family_room_id FROM family_room WHERE family_room_id=%s
                AND family_room_deleted_at IS NULL FOR UPDATE""",(room_id,))
            if q.fetchone() is None:raise HTTPException(403,'이용할 수 없는 돌봄 공간입니다.')
            q.execute("""SELECT p.participate_seq FROM participate p JOIN `user` u ON u.user_id=p.user_id
                WHERE p.family_room_id=%s AND p.user_id=%s AND p.left_at IS NULL
                AND p.is_active=1 AND u.withdrawn_at IS NULL FOR UPDATE""",(room_id,user_id))
            member=q.fetchone()
            if member is None:raise HTTPException(403,'현재 참여 중인 돌봄 공간만 읽음 처리할 수 있습니다.')
            if chat_seq:
                q.execute('SELECT chat_seq FROM live_chat WHERE family_room_id=%s AND chat_seq=%s LIMIT 1',(room_id,chat_seq))
                if q.fetchone() is None:raise HTTPException(422,'이 공간의 메시지 번호를 확인해 주세요.')
            # 여러 기기의 늦은 요청이 읽음 위치를 뒤로 되돌리지 못하게 한다.
            q.execute("""INSERT INTO chat_read_status (participate_seq,last_read_chat_seq,last_read_at)
                VALUES (%s,%s,CURRENT_TIMESTAMP) ON DUPLICATE KEY UPDATE
                last_read_at=IF(VALUES(last_read_chat_seq)>last_read_chat_seq,CURRENT_TIMESTAMP,last_read_at),
                last_read_chat_seq=GREATEST(last_read_chat_seq,VALUES(last_read_chat_seq))""",
                (member['participate_seq'],chat_seq))
            q.execute('SELECT last_read_chat_seq FROM chat_read_status WHERE participate_seq=%s',(member['participate_seq'],))
            result=q.fetchone()['last_read_chat_seq']
        c.commit()
        return {'last_read_chat_seq':result}
    except Exception:
        c.rollback();raise
    finally:c.close()
