"""30일간 복구 가능한 계정 비활성화. 실제 개인정보 정리는 전용 worker가 담당한다."""
import logging
from fastapi import HTTPException
from pymysql import MySQLError
from python.database import connect
from python.features.activity.cache import badge_cache

logger = logging.getLogger(__name__)


def withdraw_account(claims):
    uid = claims['uid']
    connection = connect()
    rooms = []
    try:
        with connection.cursor() as cursor:
            cursor.execute("""SELECT user_id FROM `user` WHERE user_firebase_uid=%s
                AND BINARY user_firebase_uid=BINARY %s LIMIT 1""", (uid, uid))
            user = cursor.fetchone()
            if user is None:
                raise HTTPException(404, '등록된 회원 정보가 없습니다.')
            user_id = user['user_id']
            cursor.execute("""SELECT DISTINCT p.family_room_id FROM participate p
                JOIN family_room f ON f.family_room_id=p.family_room_id
                WHERE p.user_id=%s AND p.left_at IS NULL AND f.family_room_deleted_at IS NULL
                ORDER BY p.family_room_id""", (user_id,))
            rooms = [r['family_room_id'] for r in cursor.fetchall()]
            # 역할 이전·강퇴와 동일하게 공간부터 잠근다. 모든 공간의 변경을 함께 확정한다.
            for room in rooms:
                cursor.execute('SELECT family_room_id FROM family_room WHERE family_room_id=%s FOR UPDATE', (room,))
                cursor.fetchone()
            cursor.execute('SELECT withdrawn_at FROM `user` WHERE user_id=%s FOR UPDATE', (user_id,))
            saved = cursor.fetchone()
            if saved['withdrawn_at'] is None:
                cursor.execute("""SELECT p.family_room_id,p.is_representative FROM participate p
                    JOIN family_room f ON f.family_room_id=p.family_room_id
                    WHERE p.user_id=%s AND p.left_at IS NULL AND f.family_room_deleted_at IS NULL
                    ORDER BY p.family_room_id FOR UPDATE""", (user_id,))
                members = cursor.fetchall()
                if any(r['is_representative'] == 1 for r in members):
                    raise HTTPException(409, '주보호자를 이전하거나 돌봄 공간을 삭제한 후 탈퇴해 주세요.')
                if sorted({r['family_room_id'] for r in members}) != rooms:
                    raise HTTPException(409, '참여 공간이 변경되었습니다. 다시 시도해 주세요.')
                # 유예기간 동안 프로필·공간 참여·담당 일정과 Firebase 계정을 그대로 보존한다.
                # 재요청으로 날짜를 갱신해 30일 기한을 연장하지 않는다.
                cursor.execute("UPDATE `user` SET withdrawn_at=CURRENT_TIMESTAMP WHERE user_id=%s AND withdrawn_at IS NULL", (user_id,))
        connection.commit()
    except (HTTPException, MySQLError, ValueError):
        connection.rollback()
        raise
    finally:
        connection.close()
    badge_cache.invalidate(uid)
    return {'result': 'OK', 'rooms': rooms, 'user_id': user_id}
