"""MySQL 채팅 푸시 대기 작업. 여러 worker는 임대 토큰과 기존 기기별 발송 기록을 공유한다."""
import logging
from uuid import uuid4
from python.database import connect
from python.features.notifications.push import dispatch_event, digest

logger=logging.getLogger(__name__)


def visible_chat(connection,user_id,event):
    # 대기 중 읽음 처리·탈퇴·강퇴·메시지 삭제·계정 변경이 발생해도 발송 직전에 재검사한다.
    with connection.cursor() as q:
        q.execute("""SELECT m.chat_seq FROM live_chat m JOIN family_room f ON f.family_room_id=m.family_room_id
            JOIN participate p ON p.family_room_id=m.family_room_id AND p.user_id=%s
            JOIN `user` u ON u.user_id=p.user_id
            LEFT JOIN chat_read_status r ON r.participate_seq=p.participate_seq
            WHERE m.chat_seq=%s AND m.family_room_id=%s AND m.user_id=%s AND m.user_id<>%s
                AND m.live_chat_deleted_at IS NULL AND f.family_room_deleted_at IS NULL
                AND p.left_at IS NULL AND p.is_active=1 AND u.withdrawn_at IS NULL
                AND p.joined_at<=m.sent_at AND COALESCE(r.last_read_chat_seq,0)<m.chat_seq LIMIT 1""",
            (user_id,event['chat_seq'],event['family_room_id'],event['user_id'],user_id))
        if q.fetchone() is None:return None
    return {'notification_type':'chat_message'}


def claim_job():
    c=connect()
    try:
        with c.cursor() as q:
            q.execute("""SELECT chat_seq,family_room_id,user_id,attempts FROM chat_push_outbox
                WHERE status IN ('pending','processing') AND next_attempt_at<=CURRENT_TIMESTAMP
                    AND (lease_until IS NULL OR lease_until<=CURRENT_TIMESTAMP)
                ORDER BY created_at,chat_seq LIMIT 1 FOR UPDATE SKIP LOCKED""")
            job=q.fetchone()
            if job is None:return None
            key=(job['chat_seq'],job['family_room_id'],job['user_id'])
            if job['attempts']>=5:
                q.execute("""UPDATE chat_push_outbox SET status='failed',lease_until=NULL,lease_token=NULL
                    WHERE chat_seq=%s AND family_room_id=%s AND user_id=%s""",key)
                c.commit();return None
            token=uuid4().hex
            q.execute("""UPDATE chat_push_outbox SET status='processing',attempts=attempts+1,
                lease_until=DATE_ADD(CURRENT_TIMESTAMP,INTERVAL 2 MINUTE),lease_token=%s
                WHERE chat_seq=%s AND family_room_id=%s AND user_id=%s""",(token,*key))
        c.commit()
        return {**job,'attempts':job['attempts']+1,'lease_token':token}
    except Exception:
        c.rollback();raise
    finally:c.close()


def finish_job(job,complete):
    c=connect()
    try:
        with c.cursor() as q:
            status='done' if complete else 'failed' if job['attempts']>=5 else 'pending'
            delay=min(30*2**(job['attempts']-1),600)
            # 만료된 worker의 늦은 결과가 새 처리권을 덮어쓰지 못하게 한다.
            q.execute("""UPDATE chat_push_outbox SET status=%s,lease_until=NULL,lease_token=NULL,
                next_attempt_at=DATE_ADD(CURRENT_TIMESTAMP,INTERVAL %s SECOND)
                WHERE chat_seq=%s AND family_room_id=%s AND user_id=%s AND lease_token=%s""",
                (status,delay,job['chat_seq'],job['family_room_id'],job['user_id'],job['lease_token']))
        c.commit()
    except Exception:
        c.rollback();raise
    finally:c.close()


def process_job(job):
    c=connect()
    try:
        with c.cursor() as q:
            q.execute("""SELECT DISTINCT p.user_id FROM participate p
                JOIN `user` u ON u.user_id=p.user_id
                WHERE p.family_room_id=%s AND p.user_id<>%s AND p.is_active=1
                    AND p.left_at IS NULL AND u.withdrawn_at IS NULL""", (job['family_room_id'],job['user_id']))
            recipients=[r['user_id'] for r in q.fetchall()]
    finally:c.close()
    identifier=f"chat_{job['chat_seq']}_{digest(job['family_room_id']+'|'+job['user_id'])[:16]}"
    # 메시지별 Firestore 알림 문서는 만들지 않고 기존 기기 등록·발송 기록만 재사용한다.
    return dispatch_event(identifier,{**job,'notification_type':'chat_message','recipient_ids':recipients},
                          visible_loader=visible_chat,finish_event=False)


def check_chat_pushes(limit=20):
    count=0
    for _ in range(limit):
        job=claim_job()
        if job is None:break
        count+=1
        try:
            complete=bool(process_job(job))
        except Exception:
            logger.warning('채팅 푸시 처리 실패; 다음 주기에 재시도')
            complete=False
        finish_job(job,complete)
    return count
