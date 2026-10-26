"""관리자 웹과 공유하는 공지의 사용자 조회 API. 쓰기 API는 제공하지 않는다."""
from fastapi import APIRouter, Depends, HTTPException, Query
from pymysql import MySQLError
from python.database import connect
from python.features.auth.firebase_auth import require_firebase_user

router = APIRouter(prefix="/notices", tags=["notices"], dependencies=[Depends(require_firebase_user)])
FIELDS = "admin_id, notice_id, notice_title, notice_content, notice_created_at, notice_updated_at"


def read_notices(admin_id=None, notice_id=None, limit=30, offset=0):
    connection = None
    try:
        connection = connect()
        with connection.cursor() as cursor:
            if notice_id is None:
                cursor.execute(f"""SELECT {FIELDS} FROM create_notice
                    WHERE notice_deleted_at IS NULL
                    ORDER BY notice_created_at DESC, admin_id, notice_id LIMIT %s OFFSET %s""", (limit + 1, offset))
                rows = cursor.fetchall()
                return {"items": rows[:limit], "has_more": len(rows) > limit}
            # 공지의 실제 키는 admin_id + notice_id이므로 두 값을 함께 사용한다.
            cursor.execute(f"""SELECT {FIELDS} FROM create_notice
                WHERE admin_id=%s AND notice_id=%s AND notice_deleted_at IS NULL""", (admin_id, notice_id))
            row = cursor.fetchone()
            if row is None:
                raise HTTPException(404, "공지를 찾을 수 없습니다.")
            return row
    except (MySQLError, ValueError):
        raise HTTPException(503, "공지를 불러오지 못했습니다.") from None
    finally:
        if connection is not None:
            connection.close()


@router.get("")
def notice_list(limit: int = Query(30, ge=1, le=100), offset: int = Query(0, ge=0)):
    return read_notices(limit=limit, offset=offset)


@router.get("/{admin_id}/{notice_id}")
def notice_detail(admin_id: str, notice_id: str):
    return read_notices(admin_id, notice_id)
