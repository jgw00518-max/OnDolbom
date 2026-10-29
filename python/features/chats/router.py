"""HTTP 이력 조회와 첫 메시지 Firebase 인증을 사용하는 공간별 WebSocket 채팅."""
import asyncio
import json
import hashlib
import logging
import time
from typing import Annotated, Literal
from uuid import UUID

import pymysql
from fastapi import APIRouter, Depends, File, Form, HTTPException, Path, Query, Request, Response, UploadFile, WebSocket
from fastapi.encoders import jsonable_encoder
from fastapi.responses import JSONResponse
from pydantic import BaseModel, ConfigDict, Field, ValidationError
from starlette.concurrency import run_in_threadpool
from starlette.websockets import WebSocketDisconnect

from python.database import connect
from python.features.chats import read_status
from python.features.auth.firebase_auth import require_firebase_user, verify_firebase_token
from python.features.chats.connection_manager import ChatConnection, manager
from python.features.memos.images import read_image

router = APIRouter(prefix='/chats', tags=['채팅'])
logger = logging.getLogger(__name__)


class Authenticate(BaseModel):
    model_config = ConfigDict(extra='forbid')
    type: Literal['auth']
    token: str = Field(min_length=1, max_length=8192)


class MessageCreate(BaseModel):
    model_config = ConfigDict(extra='forbid', str_strip_whitespace=True)
    type: Literal['message']
    client_message_id: UUID
    content: str = Field(min_length=1, max_length=4000)


class ImageMessageCreate(MessageCreate):
    type: Literal['message'] = 'message'
    content: str = Field(default='', max_length=4000)


class MessageUpdate(BaseModel):
    model_config = ConfigDict(extra='forbid', str_strip_whitespace=True)
    family_room_id: str = Field(min_length=1, max_length=50)
    content: str = Field(max_length=4000)


class MessageRefresh(BaseModel):
    model_config = ConfigDict(extra='forbid', str_strip_whitespace=True)
    family_room_id: str = Field(min_length=1, max_length=50)
    message_ids: list[Annotated[int, Field(gt=0)]] = Field(min_length=1, max_length=100)


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
        raise HTTPException(403, '현재 참여 중인 돌봄 공간의 채팅만 이용할 수 있습니다.')


# 이력·실시간 전달에는 이미지 존재 여부만 포함하고 BLOB는 별도로 조회한다.
_COLUMNS = '''chat_seq, family_room_id, user_id, chat_content, sent_at,
    client_message_id, live_chat_updated_at, live_chat_deleted_at,
    (chat_image IS NOT NULL) AS has_image,
    (SELECT u.name FROM `user` AS u WHERE u.user_id = live_chat.user_id) AS author_name'''


def _public_message(row):
    result = dict(row)
    result['is_deleted'] = result.get('live_chat_deleted_at') is not None
    if result['is_deleted']:
        result['chat_content'] = '삭제된 메시지입니다.'
        result['has_image'] = 0
    return result


class ChatRead(BaseModel):
    model_config = ConfigDict(extra='forbid')
    family_room_id: str = Field(min_length=1,max_length=50)
    chat_seq: int = Field(ge=0,strict=True)


@router.get('/unread')
def chat_unread(current_user_id: str = Depends(get_current_user_id)):
    try:
        return {'counts':read_status.unread_counts(current_user_id)}
    except (pymysql.MySQLError,ValueError):
        raise HTTPException(503,'채팅 미읽음 수를 조회하지 못했습니다.') from None


@router.post('/read')
def chat_read(data: ChatRead,current_user_id: str = Depends(get_current_user_id)):
    try:
        return read_status.mark_read(data.family_room_id,current_user_id,data.chat_seq)
    except (pymysql.MySQLError,ValueError):
        raise HTTPException(503,'채팅 읽음 처리를 완료하지 못했습니다.') from None


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
            sql = f'''SELECT {_COLUMNS} FROM live_chat WHERE family_room_id = %s'''
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
        page = [_public_message(row) for row in rows[:limit]]
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


@router.post('/messages/refresh')
def refresh_messages(data: MessageRefresh, current_user_id: str = Depends(get_current_user_id)):
    """재연결 시 이미 불러온 메시지의 수정·삭제를 최대 100개씩 다시 조회한다."""
    connection = None
    try:
        connection = connect()
        with connection.cursor() as cursor:
            _membership(cursor, data.family_room_id, current_user_id)
            ids = sorted(set(data.message_ids))
            placeholders = ', '.join(['%s'] * len(ids))
            cursor.execute(f'''SELECT {_COLUMNS} FROM live_chat
                WHERE family_room_id = %s AND chat_seq IN ({placeholders}) ORDER BY chat_seq ASC''',
                           (data.family_room_id, *ids))
            rows = [_public_message(row) for row in cursor.fetchall()]
        found = {row['chat_seq'] for row in rows}
        return {'results': rows, 'missing_ids': [seq for seq in ids if seq not in found]}
    except (pymysql.MySQLError, ValueError):
        raise HTTPException(503, '채팅 변경사항을 조회하지 못했습니다.') from None
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


def _save(room_id, user_id, message, image_data=None):
    connection = None
    try:
        connection = connect()
        with connection.cursor() as cursor:
            # 공간 행을 함께 잠그므로 같은 공간의 채팅 commit 순서와 ID 순서를 맞춘다.
            _membership(cursor, room_id, user_id, lock=True)
            request_id = str(message.client_message_id)
            cursor.execute(f'''SELECT {_COLUMNS},
                SHA2(chat_image, 256) AS image_digest FROM live_chat
                WHERE family_room_id = %s AND user_id = %s AND client_message_id = %s LIMIT 1''',
                           (room_id, user_id, request_id))
            row = cursor.fetchone()
            duplicate = row is not None
            if duplicate:
                digest = row.pop('image_digest', None)
                expected_digest = hashlib.sha256(image_data).hexdigest() if image_data is not None else None
                if (row['live_chat_deleted_at'] is not None
                        or row['chat_content'] != message.content or digest != expected_digest):
                    raise HTTPException(409, '이미 다른 내용으로 사용한 메시지 ID입니다.')
            else:
                image_column = ', chat_image' if image_data is not None else ''
                image_value = ', %s' if image_data is not None else ''
                params = (room_id, user_id, message.content, request_id)
                if image_data is not None:
                    params += (image_data,)
                cursor.execute(f'''INSERT INTO live_chat
                    (family_room_id, user_id, chat_content, client_message_id{image_column})
                    VALUES (%s, %s, %s, %s{image_value})''', params)
                cursor.execute(f'''SELECT {_COLUMNS} FROM live_chat
                    WHERE chat_seq = %s AND family_room_id = %s AND user_id = %s''',
                               (cursor.lastrowid, room_id, user_id))
                row = cursor.fetchone()
                if row is None:
                    raise HTTPException(503, '저장한 메시지를 확인하지 못했습니다.')
        if not duplicate:
            # 메시지와 푸시 대기를 함께 확정한다. 동일 UUID 재전송은 새 작업을 만들지 않는다.
            with connection.cursor() as cursor:
                cursor.execute("""INSERT INTO chat_push_outbox (chat_seq,family_room_id,user_id)
                    VALUES (%s,%s,%s)""", (row['chat_seq'],room_id,user_id))
        connection.commit()
        return _public_message(row), duplicate
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


async def _single_chat_image(
    request: Request,
    image: UploadFile = File(json_schema_extra={'format': 'binary'}),
):
    form = await request.form()
    allowed = {'family_room_id', 'client_message_id', 'content', 'image'}
    if set(form.keys()) - allowed:
        raise HTTPException(422, '허용되지 않은 채팅 입력 항목입니다.')
    if len(form.getlist('image')) != 1:
        raise HTTPException(422, '이미지는 한 장만 첨부할 수 있습니다.')
    if any(len(form.getlist(key)) > 1 for key in allowed - {'image'}):
        raise HTTPException(422, '같은 입력 항목을 여러 번 보낼 수 없습니다.')
    return image


async def _authorize_peer(peer, room_id):
    identity, _ = await run_in_threadpool(_session, peer.token, room_id)
    if identity != peer.user_id:
        raise HTTPException(401, '로그인 계정이 변경되었습니다.')


async def _publish(room_id, payload):
    try:
        await manager.broadcast(room_id, payload, lambda peer: _authorize_peer(peer, room_id))
    except Exception:
        # 저장 성공과 전달 성공을 분리한다. 전달에 실패한 기록은 이력 조회로 복구한다.
        logger.exception('채팅 메시지 실시간 전달 실패')


def _change_message(room_id, user_id, seq, *, content=None, delete=False):
    connection = None
    try:
        connection = connect()
        with connection.cursor() as cursor:
            _membership(cursor, room_id, user_id, lock=True)
            key = (seq, room_id)
            target_sql = f'''SELECT {_COLUMNS} FROM live_chat
                WHERE chat_seq = %s AND family_room_id = %s LIMIT 1'''
            cursor.execute(target_sql + ' FOR UPDATE', key)
            row = cursor.fetchone()
            if row is None:
                raise HTTPException(404, '채팅 메시지를 찾을 수 없습니다.')
            if row['user_id'] != user_id:
                raise HTTPException(403, '본인이 보낸 채팅만 수정하거나 삭제할 수 있습니다.')
            deleted = row['live_chat_deleted_at'] is not None
            if not delete and deleted:
                raise HTTPException(409, '삭제된 메시지는 수정할 수 없습니다.')
            if not delete and not content and not row['has_image']:
                raise HTTPException(422, '텍스트 메시지 내용은 비울 수 없습니다.')
            changed = not deleted if delete else row['chat_content'] != content
            if changed:
                if delete:
                    cursor.execute('''UPDATE live_chat SET live_chat_deleted_at = CURRENT_TIMESTAMP
                        WHERE chat_seq = %s AND family_room_id = %s AND user_id = %s
                          AND live_chat_deleted_at IS NULL''', (*key, user_id))
                else:
                    cursor.execute('''UPDATE live_chat
                        SET chat_content = %s, live_chat_updated_at = CURRENT_TIMESTAMP
                        WHERE chat_seq = %s AND family_room_id = %s AND user_id = %s
                          AND live_chat_deleted_at IS NULL''', (content, *key, user_id))
                cursor.execute(target_sql, key)
                row = cursor.fetchone()
                if row is None:
                    raise HTTPException(503, '변경된 채팅 메시지를 확인하지 못했습니다.')
        connection.commit()
        return _public_message(row), changed
    except HTTPException:
        if connection is not None:
            connection.rollback()
        raise
    except (pymysql.MySQLError, ValueError):
        if connection is not None:
            connection.rollback()
        raise HTTPException(503, '채팅 메시지를 변경하지 못했습니다.') from None
    finally:
        if connection is not None:
            connection.close()


@router.patch('/messages/{chat_seq}')
async def update_message(
    data: MessageUpdate,
    chat_seq: int = Path(gt=0),
    current_user_id: str = Depends(get_current_user_id),
):
    """작성자 본인이 텍스트만 수정한다. 첨부 이미지는 유지한다."""
    row, changed = await run_in_threadpool(
        _change_message, data.family_room_id, current_user_id, chat_seq, content=data.content)
    payload = {'type': 'message', 'action': 'updated', 'message': jsonable_encoder(row), 'changed': changed}
    if changed:
        await _publish(data.family_room_id, payload)
    return payload


@router.delete('/messages/{chat_seq}')
async def delete_message(
    chat_seq: int = Path(gt=0),
    family_room_id: str = Query(min_length=1, max_length=50, pattern=r'\S'),
    current_user_id: str = Depends(get_current_user_id),
):
    """작성자 본인이 메시지 전체를 소프트 삭제한다. 반복 요청은 성공으로 처리한다."""
    row, changed = await run_in_threadpool(
        _change_message, family_room_id, current_user_id, chat_seq, delete=True)
    payload = {'type': 'message', 'action': 'deleted', 'message': jsonable_encoder(row),
               'already_deleted': not changed}
    if changed:
        await _publish(family_room_id, payload)
    return payload


@router.post('/messages/with-image', status_code=201)
async def create_image_message(
    family_room_id: str = Form(min_length=1, max_length=50),
    client_message_id: UUID = Form(),
    content: str = Form(default='', max_length=4000),
    image: UploadFile = Depends(_single_chat_image),
    current_user_id: str = Depends(get_current_user_id),
):
    """한 장의 이미지와 선택적 텍스트를 저장한다. 같은 UUID 재요청은 원본을 반환한다."""
    room_id = family_room_id.strip()
    if not room_id:
        raise HTTPException(422, '돌봄 공간 ID를 확인해 주세요.')
    message = ImageMessageCreate(client_message_id=client_message_id, content=content)
    image_data = await run_in_threadpool(read_image, [image])
    row, duplicate = await run_in_threadpool(_save, room_id, current_user_id, message, image_data)
    payload = {'type': 'message', 'message': jsonable_encoder(row), 'duplicate': duplicate}
    if not duplicate:
        await _publish(room_id, payload)
    return JSONResponse(payload, status_code=200 if duplicate else 201)


@router.get('/messages/{chat_seq}/image')
def get_message_image(
    chat_seq: int = Path(gt=0),
    family_room_id: str = Query(min_length=1, max_length=50),
    current_user_id: str = Depends(get_current_user_id),
):
    """현재 돌봄 공간 참여자에게만 삭제되지 않은 메시지의 이미지를 반환한다."""
    connection = None
    try:
        connection = connect()
        with connection.cursor() as cursor:
            _membership(cursor, family_room_id, current_user_id)
            cursor.execute('''SELECT chat_image FROM live_chat
                WHERE chat_seq = %s AND family_room_id = %s
                  AND live_chat_deleted_at IS NULL AND chat_image IS NOT NULL LIMIT 1''',
                           (chat_seq, family_room_id))
            row = cursor.fetchone()
            if row is None:
                raise HTTPException(404, '채팅 이미지가 없거나 삭제되었습니다.')
        data = bytes(row['chat_image'])
        # 새 첨부는 JPEG이며, 기존 BLOB의 PNG/WEBP도 지원한다.
        media_type = ('image/png' if data.startswith(b'\x89PNG\r\n\x1a\n') else
                      'image/webp' if data.startswith(b'RIFF') and data[8:12] == b'WEBP' else
                      'image/jpeg' if data.startswith(b'\xff\xd8\xff') else None)
        if media_type is None:
            raise HTTPException(404, '표시할 수 없는 채팅 이미지입니다.')
        return Response(data, media_type=media_type, headers={
            'Cache-Control': 'private, no-store', 'X-Content-Type-Options': 'nosniff',
        })
    except (pymysql.MySQLError, ValueError):
        raise HTTPException(503, '채팅 이미지를 조회하지 못했습니다.') from None
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
            raise HTTPException(422, '돌봄 공간 ID를 확인해 주세요.')
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
