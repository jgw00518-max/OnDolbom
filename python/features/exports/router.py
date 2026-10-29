"""작업 테이블 없이 현재 참여 공간의 메모·채팅을 ZIP 또는 PDF로 반환한다."""

import logging
from contextlib import suppress
from datetime import date, datetime, time, timedelta
from tempfile import TemporaryFile
from typing import Literal

import pymysql
from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, ConfigDict, Field, model_validator

from python.database import connect
from python.features.auth.firebase_auth import require_firebase_user
from python.features.exports.generator import ExportImageError, build_archive
from python.features.exports.pdf_generator import PdfGenerationError, build_pdf

router = APIRouter(prefix="/exports", tags=["메모·채팅 내보내기"])
logger = logging.getLogger(__name__)


class ExportRequest(BaseModel):
    model_config = ConfigDict(extra="forbid", str_strip_whitespace=True)

    family_room_id: str = Field(min_length=1, max_length=50)
    start_date: date
    end_date: date
    scopes: list[Literal["memos", "chats"]] = Field(
        default_factory=lambda: ["memos", "chats"], min_length=1, max_length=2,
    )
    include_images: bool = False
    format: Literal["html_zip", "pdf"] = "html_zip"

    @model_validator(mode="after")
    def validate_range(self):
        if self.start_date > self.end_date:
            raise ValueError("시작일은 종료일보다 늦을 수 없습니다.")
        if self.start_date < date(1000, 1, 1) or self.end_date >= date.max:
            raise ValueError("지원하지 않는 날짜 범위입니다.")
        if len(set(self.scopes)) != len(self.scopes):
            raise ValueError("내보낼 범위를 중복 선택할 수 없습니다.")
        return self


def get_current_user_id(claims: dict = Depends(require_firebase_user)) -> str:
    connection = None
    try:
        connection = connect()
        with connection.cursor() as cursor:
            cursor.execute('''SELECT user_id, withdrawn_at FROM `user`
                WHERE user_firebase_uid = %s AND BINARY user_firebase_uid = BINARY %s LIMIT 1''',
                           (claims["uid"], claims["uid"]))
            user = cursor.fetchone()
        if user is None or user["withdrawn_at"] is not None:
            raise HTTPException(403, "등록된 미탈퇴 사용자만 이용할 수 있습니다.")
        return user["user_id"]
    except (pymysql.MySQLError, ValueError):
        raise HTTPException(503, "사용자 정보를 확인하지 못했습니다.") from None
    finally:
        if connection is not None:
            connection.close()


def _membership(connection, room_id: str, user_id: str):
    with connection.cursor() as cursor:
        cursor.execute('''SELECT p.participate_seq, f.care_recipient_name,
                CURRENT_TIMESTAMP AS snapshot_at
            FROM participate AS p
            JOIN family_room AS f ON f.family_room_id = p.family_room_id
            JOIN `user` AS u ON u.user_id = p.user_id
            WHERE p.family_room_id = %s AND p.user_id = %s
              AND p.is_active = 1 AND p.left_at IS NULL
              AND f.family_room_deleted_at IS NULL AND u.withdrawn_at IS NULL
            LIMIT 1''', (room_id, user_id))
        room = cursor.fetchone()
    if room is None:
        raise HTTPException(403, "현재 참여 중인 돌봄 공간의 기록만 내보낼 수 있습니다.")
    return room


def _records(connection, data: ExportRequest, scope: str):
    # SSCursor로 BLOB를 포함한 전체 결과를 메모리에 한꺼번에 적재하지 않는다.
    start = datetime.combine(data.start_date, time.min)
    end = datetime.combine(data.end_date + timedelta(days=1), time.min)
    if scope == "memos":
        image = ", m.memo_image AS image" if data.include_images else ""
        sql = f'''SELECT m.memo_content AS content, m.written_at AS recorded_at,
                m.memo_updated_at AS updated_at, u.name AS author_name,
                (m.memo_image IS NOT NULL) AS has_image{image}
            FROM memo AS m LEFT JOIN `user` AS u ON u.user_id = m.user_id
            WHERE m.family_room_id = %s AND m.memo_deleted_at IS NULL
              AND m.written_at >= %s AND m.written_at < %s
            ORDER BY m.written_at ASC, m.memo_id ASC, m.user_id ASC'''
    else:
        # 소프트 삭제한 원문과 사진은 애플리케이션으로도 가져오지 않는다.
        image = (", CASE WHEN c.live_chat_deleted_at IS NULL THEN c.chat_image ELSE NULL END AS image"
                 if data.include_images else "")
        sql = f'''SELECT
                CASE WHEN c.live_chat_deleted_at IS NULL THEN c.chat_content ELSE NULL END AS content,
                c.sent_at AS recorded_at, c.live_chat_updated_at AS updated_at,
                u.name AS author_name, (c.live_chat_deleted_at IS NOT NULL) AS is_deleted,
                (c.live_chat_deleted_at IS NULL AND c.chat_image IS NOT NULL) AS has_image{image}
            FROM live_chat AS c LEFT JOIN `user` AS u ON u.user_id = c.user_id
            WHERE c.family_room_id = %s AND c.sent_at >= %s AND c.sent_at < %s
            ORDER BY c.sent_at ASC, c.chat_seq ASC'''
    with connection.cursor(pymysql.cursors.SSDictCursor) as cursor:
        cursor.execute(sql, (data.family_room_id, start, end))
        yield from cursor


class ExportResponse(StreamingResponse):
    """전송 완료·실패·연결 종료 시에도 익명 임시 파일을 닫는다."""

    def __init__(self, output, filename: str, media_type: str = "application/zip"):
        self.output = output
        size = output.seek(0, 2)
        output.seek(0)
        super().__init__(self._chunks(), media_type=media_type, headers={
            "Content-Disposition": f'attachment; filename="{filename}"',
            "Content-Length": str(size),
            "Cache-Control": "private, no-store",
            "X-Content-Type-Options": "nosniff",
        })

    def _chunks(self):
        while chunk := self.output.read(64 * 1024):
            yield chunk

    async def __call__(self, scope, receive, send):
        try:
            await super().__call__(scope, receive, send)
        finally:
            self.output.close()


@router.post("/download", response_class=StreamingResponse,
             responses={200: {"content": {
                 content_type: {"schema": {"type": "string", "format": "binary"}}
                 for content_type in ("application/zip", "application/pdf")
             }}})
def download_export(data: ExportRequest, user_id: str = Depends(get_current_user_id)):
    """선택 기간의 ZIP/PDF를 반환한다. 재요청 시 다시 생성하며 이력은 저장하지 않는다."""
    connection = None
    output = None
    try:
        connection = connect()
        with connection.cursor() as cursor:
            cursor.execute("SET TRANSACTION ISOLATION LEVEL REPEATABLE READ")
            cursor.execute("START TRANSACTION WITH CONSISTENT SNAPSHOT, READ ONLY")
        room = _membership(connection, data.family_room_id, user_id)
        output = TemporaryFile(mode="w+b")
        builder = build_pdf if data.format == "pdf" else build_archive
        builder(output, data, room, lambda scope: _records(connection, data, scope))
        connection.rollback()  # 읽기 스냅샷 종료. 데이터 쓰기·commit은 없다.
        _membership(connection, data.family_room_id, user_id)  # 새 트랜잭션에서 현재 권한 재확인
        extension, media_type = ("pdf", "application/pdf") if data.format == "pdf" else ("zip", "application/zip")
        response = ExportResponse(
            output, f"ondolbom_{data.start_date:%Y%m%d}_{data.end_date:%Y%m%d}.{extension}", media_type,
        )
        output = None  # 응답 객체로 파일 소유권 이전
        return response
    except HTTPException:
        raise
    except ExportImageError:
        logger.exception("내보내기 첨부 이미지 처리 실패")
        raise HTTPException(500, "첨부 이미지를 처리하지 못했습니다. 이미지를 제외하고 다시 요청해 주세요.") from None
    except PdfGenerationError:
        logger.exception("PDF 문서 생성 실패")
        raise HTTPException(500, "PDF를 생성하지 못했습니다. 잠시 후 다시 요청해 주세요.") from None
    except (pymysql.MySQLError, ValueError):
        logger.exception("메모·채팅 내보내기 실패")
        raise HTTPException(503, "기록을 조회하지 못했습니다. 잠시 후 다시 요청해 주세요.") from None
    except OSError:
        logger.exception("내보내기 임시 파일 생성 실패")
        raise HTTPException(500, "파일을 생성하지 못했습니다. 잠시 후 다시 요청해 주세요.") from None
    finally:
        if output is not None:
            output.close()
        if connection is not None:
            try:
                with suppress(pymysql.MySQLError):
                    connection.rollback()
            finally:
                connection.close()
