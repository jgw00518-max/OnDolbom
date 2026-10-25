"""HTTP 이력 조회와 첫 메시지 Firebase 인증을 사용하는 공간별 WebSocket 채팅."""
import asyncio
import json
import time
from typing import Literal
from uuid import UUID

import pymysql
from fastapi import APIRouter, Depends, HTTPException, Query, WebSocket
from fastapi.encoders import jsonable_encoder
from pydantic import BaseModel, ConfigDict, Field, ValidationError
from starlette.concurrency import run_in_threadpool
from starlette.websockets import WebSocketDisconnect

from python.database import connect
from python.features.auth.firebase_auth import require_firebase_user, verify_firebase_token
from python.features.chats.connection_manager import ChatConnection, manager

router = APIRouter(prefix='/chats', tags=['채팅'])


class Authenticate(BaseModel):
    model_config = ConfigDict(extra='forbid')
    type: Literal['auth']
    token: str = Field(min_length=1, max_length=8192)


class MessageCreate(BaseModel):
    model_config = ConfigDict(extra='forbid', str_strip_whitespace=True)
    type: Literal['message']
    client_message_id: UUID
    content: str = Field(min_length=1, max_length=4000)


def _user_id(cursor, claims):
    cursor.execute('''SELECT user_id, withdrawn_at FROM `user`
        WHERE user_firebase_uid = %s AND BINARY user_firebase_uid = BINARY %s LIMIT 1''',
                   (claims['uid'], claims['uid']))
    row = cursor.fetchone()
    if row is None or row['withdrawn_at'] is not None:
        raise HTTPException(403, '등록된 미탈퇴 사용자만 이용할 수 있습니다.')
    return row['user_id']


def get_current_user_id(claims: dict = Depends(require_firebase_user)) -> str:
    connection = None
    try:
        connection = connect()
        with connection.cursor() as cursor:
            return _user_id(cursor, claims)
    except (pymysql.MySQLError, ValueError):
        raise HTTPException(503, '채팅 사용자 정보를 확인하지 못했습니다.') from None
    finally:
        if connection is not None:
            connection.close()


def _membership(cursor, room_id, user_id, *, lock=False):
    sql = '''SELECT p.participate_seq FROM participate p
        JOIN family_room f ON f.family_room_id = p.family_room_id
        JOIN `user` u ON u.user_id = p.user_id
        WHERE p.family_room_id = %s AND p.user_id = %s
          AND p.is_active = 1 AND p.left_at IS NULL
          AND f.family_room_deleted_at IS NULL AND u.withdrawn_at IS NULL
        LIMIT 1'''
    if lock:
        sql += ' FOR UPDATE'
    cursor.execute(sql, (room_id, user_id))
    if cursor.fetchone() is None:
        raise HTTPException(403, '현재 참여 중인 가족 공간의 채팅만 이용할 수 있습니다.')


# 이미지 BLOB는 텍스트 채팅 조회·전송에 포함하지 않는다.
_COLUMNS = '''chat_seq, family_room_id, user_id, chat_content, sent_at,
    client_message_id, live_chat_updated_at'''


@router.get('/messages')
def list_messages(
    family_room_id: str = Query(min_length=1, max_length=50),
    before_id: int | None = Query(default=None, gt=0),
    after_id: int | None = Query(default=None, ge=0),
    limit: int = Query(default=30, ge=1, le=100),
    current_user_id: str = Depends(get_current_user_id),
):
    """기본은 최신순, after_id는 재연결 누락 복구를 위해 오래된 순으로 반환한다."""
    if before_id is not None and after_id is not None:
        raise HTTPException(422, 'before_id와 after_id는 함께 사용할 수 없습니다.')
    connection = None
    try:
        connection = connect()
        with connection.cursor() as cursor:
            _membership(cursor, family_room_id, current_user_id)
            sql = f'''SELECT {_COLUMNS} FROM live_chat
                WHERE family_room_id = %s AND live_chat_deleted_at IS NULL'''
            params = [family_room_id]
            if before_id is not None:
                sql += ' AND chat_seq < %s'
                params.append(before_id)
            if after_id is not None:
                sql += ' AND chat_seq > %s'
                params.append(after_id)
            sql += ' ORDER BY chat_seq ' + ('ASC' if after_id is not None else 'DESC') + ' LIMIT %s'
            cursor.execute(sql, (*params, limit + 1))
            rows = cursor.fetchall()
        has_more = len(rows) > limit
        page = rows[:limit]
        return {
            'results': page, 'has_more': has_more,
            'next_before_id': page[-1]['chat_seq'] if has_more and after_id is None else None,
            'next_after_id': page[-1]['chat_seq'] if has_more and after_id is not None else None,
        }
    except (pymysql.MySQLError, ValueError):
        raise HTTPException(503, '채팅 이력을 조회하지 못했습니다.') from None
    finally:
        if connection is not None:
            connection.close()


def _session(token, room_id):
    claims = verify_firebase_token(token)
    expires_at = claims.get('exp')
    if not isinstance(expires_at, (int, float)) or expires_at <= time.time():
        raise HTTPException(401, '로그인 토큰이 만료되었습니다.')
    connection = None
    try:
        connection = connect()
        with connection.cursor() as cursor:
            user_id = _user_id(cursor, claims)
            _membership(cursor, room_id, user_id)
        return user_id, expires_at
    except (pymysql.MySQLError, ValueError):
        raise HTTPException(503, '채팅 접근 권한을 확인하지 못했습니다.') from None
    finally:
        if connection is not None:
            connection.close()


def _save(room_id, user_id, message):
    connection = None
    try:
        connection = connect()
        with connection.cursor() as cursor:
            # 공간 행을 함께 잠그므로 같은 공간의 채팅 commit 순서와 ID 순서를 맞춘다.
            _membership(cursor, room_id, user_id, lock=True)
            request_id = str(message.client_message_id)
            cursor.execute(f'''SELECT {_COLUMNS}, live_chat_deleted_at FROM live_chat
                WHERE family_room_id = %s AND user_id = %s AND client_message_id = %s LIMIT 1''',
                           (room_id, user_id, request_id))
            row = cursor.fetchone()
            duplicate = row is not None
            if duplicate:
                if row['live_chat_deleted_at'] is not None or row['chat_content'] != message.content:
                    raise HTTPException(409, '이미 다른 내용으로 사용한 메시지 ID입니다.')
                row.pop('live_chat_deleted_at', None)
            else:
                cursor.execute('''INSERT INTO live_chat
                    (family_room_id, user_id, chat_content, client_message_id)
                    VALUES (%s, %s, %s, %s)''',
                               (room_id, user_id, message.content, request_id))
                cursor.execute(f'''SELECT {_COLUMNS} FROM live_chat
                    WHERE chat_seq = %s AND family_room_id = %s AND user_id = %s''',
                               (cursor.lastrowid, room_id, user_id))
                row = cursor.fetchone()
                if row is None:
                    raise HTTPException(503, '저장한 메시지를 확인하지 못했습니다.')
        connection.commit()
        return row, duplicate
    except HTTPException:
        if connection is not None:
            connection.rollback()
        raise
    except (pymysql.MySQLError, ValueError):
        if connection is not None:
            connection.rollback()
        raise HTTPException(503, '메시지를 저장하지 못했습니다.') from None
    finally:
        if connection is not None:
            connection.close()


async def _receive(socket):
    try:
        text = await socket.receive_text()
    except KeyError:
        raise HTTPException(422, '텍스트 JSON 메시지만 지원합니다.') from None
    if len(text.encode('utf-8')) > 65536:
        raise HTTPException(413, '메시지 크기가 너무 큽니다.')
    return json.loads(text)


@router.websocket('/ws/{family_room_id}')
async def chat_socket(socket: WebSocket, family_room_id: str):
    await socket.accept()
    peer = None
    try:
        if not 1 <= len(family_room_id) <= 50:
            raise HTTPException(422, '가족 공간 ID를 확인해 주세요.')
        first = Authenticate.model_validate(await asyncio.wait_for(_receive(socket), timeout=10))
        user_id, expires_at = await run_in_threadpool(_session, first.token, family_room_id)
        peer = ChatConnection(socket, first.token, user_id, expires_at)
        await peer.send({'type': 'ready', 'user_id': user_id, 'family_room_id': family_room_id})
        manager.add(family_room_id, peer)

        async def authorize(target):
            identity, _ = await run_in_threadpool(_session, target.token, family_room_id)
            if identity != target.user_id:
                raise HTTPException(401, '로그인 계정이 변경되었습니다.')

        while True:
            remaining = peer.expires_at - time.time()
            if remaining <= 0:
                raise HTTPException(401, '로그인 토큰이 만료되었습니다. 다시 연결해 주세요.')
            try:
                data = await asyncio.wait_for(_receive(socket), timeout=min(30, remaining))
            except TimeoutError:
                # 조용한 연결도 만료·폐기·참여 종료 여부를 주기적으로 확인한다.
                if peer.expires_at <= time.time():
                    raise HTTPException(401, '로그인 토큰이 만료되었습니다. 다시 연결해 주세요.')
                await authorize(peer)
                await peer.send({'type': 'ping'})
                continue
            await authorize(peer)
            if data == {'type': 'pong'}:
                continue
            try:
                message = MessageCreate.model_validate(data)
            except ValidationError:
                await peer.send({'type': 'error', 'status': 422, 'detail': '메시지 ID와 1~4,000자 텍스트를 보내 주세요.'})
                continue
            try:
                row, duplicate = await run_in_threadpool(_save, family_room_id, user_id, message)
            except HTTPException as error:
                if error.status_code != 409:
                    raise
                await peer.send({'type': 'error', 'status': 409, 'detail': error.detail})
                continue
            payload = {'type': 'message', 'message': jsonable_encoder(row), 'duplicate': duplicate}
            if duplicate:
                await peer.send(payload)
            else:
                await manager.broadcast(family_room_id, payload, authorize)
    except WebSocketDisconnect:
        pass
    except (ValidationError, json.JSONDecodeError, UnicodeError):
        await socket.close(code=4400)
    except TimeoutError:
        await socket.close(code=4408)
    except HTTPException as error:
        code = {401: 4401, 403: 4403, 413: 1009, 422: 4400}.get(error.status_code, 1013)
        try:
            await socket.close(code=code)
        except (RuntimeError, WebSocketDisconnect):
            pass
    except (RuntimeError, OSError):
        # 이미 종료된 연결에는 추가 응답을 보내지 않는다.
        pass
    finally:
        if peer is not None:
            manager.remove(family_room_id, peer)
