"""단일 이미지 채팅의 HTTP 계약, 권한, 재전송, WebSocket 전달 검증."""
import hashlib
from io import BytesIO
import time
import unittest
from unittest.mock import AsyncMock, MagicMock, patch

from fastapi import HTTPException, UploadFile
from fastapi.testclient import TestClient
from PIL import Image
import pymysql

from python.main import app
from python.features.chats import router as chat
from python.features.chats.connection_manager import manager
from python.features.memos.images import MAX_IMAGE_BYTES, read_image
from python.tests.test_chats import MESSAGE, REQUEST_ID, row


def photo(color='red', fmt='PNG'):
    stream = BytesIO()
    Image.new('RGB', (4, 3), color).save(stream, fmt)
    return stream.getvalue()


class ChatImageTests(unittest.TestCase):
    def setUp(self):
        self.client = self.enterContext(TestClient(app))
        self.db = MagicMock()
        self.cursor = self.db.cursor.return_value.__enter__.return_value
        self.cursor.lastrowid = 7
        self.saved = {**row(), 'chat_content': '사진 설명', 'has_image': 1}
        self.cursor.fetchone.side_effect = [{'participate_seq': 1}, None, self.saved.copy()]
        self.connect = self.enterContext(patch.object(chat, 'connect', return_value=self.db))
        app.dependency_overrides[chat.get_current_user_id] = lambda: 'db-user'
        self.addCleanup(app.dependency_overrides.pop, chat.get_current_user_id, None)
        self.addCleanup(manager.rooms.clear)
        self.broadcast = self.enterContext(patch.object(manager, 'broadcast', new_callable=AsyncMock))

    def send(self, *, files=None, fields=None):
        return self.client.post('/chats/messages/with-image', data={
            'family_room_id': 'room-a', 'client_message_id': REQUEST_ID,
            'content': '  사진 설명  ', **(fields or {}),
        }, files=files if files is not None else {'image': ('photo.png', photo(), 'image/png')})

    def image(self, query='family_room_id=room-a', seq='7'):
        return self.client.get(f'/chats/messages/{seq}/image?{query}')

    def reset_rows(self, rows):
        self.db.reset_mock()
        self.cursor.execute.side_effect = None
        self.db.commit.side_effect = None
        self.cursor.fetchone.side_effect = rows

    def test_upload_normalizes_image_saves_atomically_then_broadcasts_metadata_only(self):
        async def delivered(room_id, payload, authorize):
            self.db.commit.assert_called_once()
            self.assertEqual(room_id, 'room-a')
            self.assertEqual(payload['message']['has_image'], 1)
            self.assertNotIn('chat_image', payload['message'])
            self.assertTrue(callable(authorize))
        self.broadcast.side_effect = delivered
        response = self.send()
        self.assertEqual(response.status_code, 201, response.text)
        self.assertEqual(response.json()['message']['author_name'], '김가족')
        self.assertFalse(response.json()['duplicate'])
        member, duplicate, insert, result, outbox = self.cursor.execute.call_args_list
        self.assertEqual(member.args[1], ('room-a', 'db-user'))
        self.assertIn('FOR UPDATE', member.args[0])
        self.assertIn('chat_image', insert.args[0])
        self.assertEqual(insert.args[1][:4], ('room-a', 'db-user', '사진 설명', REQUEST_ID))
        with Image.open(BytesIO(insert.args[1][4])) as image:
            self.assertEqual(image.format, 'JPEG')
            self.assertEqual(image.size, (4, 3))
            self.assertEqual(dict(image.getexif()), {})
        self.assertNotIn('image_digest', response.json()['message'])
        self.assertEqual(result.args[1], (7, 'room-a', 'db-user'))
        self.assertIn('INSERT INTO chat_push_outbox',outbox.args[0])
        self.assertEqual(outbox.args[1],(7,'room-a','db-user'))
        self.broadcast.assert_awaited_once()
        self.db.rollback.assert_not_called()
        self.db.close.assert_called_once()

    def test_image_only_message_and_whitespace_caption_are_allowed(self):
        self.saved['chat_content'] = ''
        self.cursor.fetchone.side_effect = [{'participate_seq': 1}, None, self.saved.copy()]
        response = self.send(fields={'content': '   '})
        self.assertEqual(response.status_code, 201)
        self.assertEqual(self.cursor.execute.call_args_list[2].args[1][2], '')
        self.assertEqual(response.json()['message']['chat_content'], '')

    def test_caption_can_be_omitted_and_non_image_form_items_cannot_repeat(self):
        response = self.client.post('/chats/messages/with-image', data={
            'family_room_id': 'room-a', 'client_message_id': REQUEST_ID,
        }, files={'image': ('photo.png', photo(), 'image/png')})
        self.assertEqual(response.status_code, 201)
        self.assertEqual(self.cursor.execute.call_args_list[2].args[1][2], '')
        self.reset_rows([])
        response = self.client.post('/chats/messages/with-image', files=[
            ('image', ('photo.png', photo(), 'image/png')),
            ('family_room_id', (None, 'room-a')),
            ('family_room_id', (None, 'room-b')),
            ('client_message_id', (None, REQUEST_ID)),
        ])
        self.assertEqual(response.status_code, 422)
        self.cursor.execute.assert_not_called()

    def test_single_binary_file_is_required_in_swagger(self):
        schema = self.client.get('/openapi.json').json()
        body = schema['paths']['/chats/messages/with-image']['post']['requestBody']['content']['multipart/form-data']['schema']
        model = schema['components']['schemas'][body['$ref'].split('/')[-1]]
        field = model['properties']['image']
        self.assertEqual(field['type'], 'string')
        self.assertEqual(field['format'], 'binary')
        self.assertNotIn('items', field)
        self.assertIn('image', model['required'])
        self.assertNotIn('content', model['required'])

    def test_multiple_missing_invalid_animated_or_oversized_images_are_rejected(self):
        animation = BytesIO()
        Image.new('RGB', (3, 3), 'red').save(animation, 'WEBP', save_all=True,
            append_images=[Image.new('RGB', (3, 3), 'blue')], duration=100, loop=0)
        for files, status in (
            ([('image', ('a.png', photo(), 'image/png')), ('image', ('b.png', photo(), 'image/png'))], 422),
            ({'image': ('bad.jpg', b'not-an-image', 'image/jpeg')}, 422),
            ({'image': ('big.jpg', b'x' * (MAX_IMAGE_BYTES + 1), 'image/jpeg')}, 413),
            ({'image': ('animation.webp', animation.getvalue(), 'image/webp')}, 422),
            ({'image': ('photo.gif', photo(fmt='GIF'), 'image/gif')}, 422),
            ({}, 422),
        ):
            with self.subTest(status=status):
                self.assertEqual(self.send(files=files).status_code, status)
        self.connect.assert_not_called()
        self.broadcast.assert_not_awaited()

    def test_invalid_fields_and_forged_author_are_rejected_without_db(self):
        for fields in ({'family_room_id': ' '}, {'family_room_id': 'x' * 51},
                       {'client_message_id': 'invalid'}, {'content': 'a' * 4001},
                       {'user_id': 'forged'}, {'sent_at': 'forged'}):
            with self.subTest(fields=fields):
                self.assertEqual(self.send(fields=fields).status_code, 422)
        self.connect.assert_not_called()
        self.broadcast.assert_not_awaited()

    def test_unauthenticated_upload_and_image_get_do_not_connect(self):
        app.dependency_overrides.pop(chat.get_current_user_id)
        self.assertEqual(self.send().status_code, 401)
        self.assertEqual(self.image().status_code, 401)
        self.connect.assert_not_called()

    def test_nonmember_cannot_upload_or_fetch_image(self):
        for operation in (self.send, self.image):
            self.reset_rows([None])
            self.assertEqual(operation().status_code, 403)
            self.assertEqual(self.cursor.execute.call_count, 1)
            self.db.commit.assert_not_called()
            self.db.close.assert_called_once()
        self.broadcast.assert_not_awaited()

    def test_identical_retry_returns_original_without_insert_or_broadcast(self):
        normalized = read_image([UploadFile(file=BytesIO(photo()), filename='photo.png')])
        self.cursor.fetchone.side_effect = [{'participate_seq': 1}, {
            **self.saved, 'live_chat_deleted_at': None,
            'image_digest': hashlib.sha256(normalized).hexdigest(),
        }]
        response = self.send()
        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.json()['duplicate'])
        self.assertEqual(response.json()['message']['chat_seq'], 7)
        self.assertNotIn('image_digest', response.json()['message'])
        self.assertEqual(self.cursor.execute.call_count, 2)
        self.db.commit.assert_called_once()
        self.broadcast.assert_not_awaited()

    def test_changed_image_caption_deleted_message_and_text_id_reuse_are_conflicts(self):
        normalized = read_image([UploadFile(file=BytesIO(photo()), filename='photo.png')])
        original = {**self.saved, 'live_chat_deleted_at': None,
                    'image_digest': hashlib.sha256(normalized).hexdigest()}
        for changes in ({'image_digest': 'different'}, {'chat_content': '다른 내용'},
                        {'live_chat_deleted_at': '2026-10-26'}, {'image_digest': None, 'has_image': 0}):
            with self.subTest(changes=changes):
                self.reset_rows([{'participate_seq': 1}, {**original, **changes}])
                self.assertEqual(self.send().status_code, 409)
                self.db.rollback.assert_called_once()
                self.db.commit.assert_not_called()
        self.broadcast.assert_not_awaited()

    def test_websocket_text_cannot_reuse_an_image_message_id(self):
        self.cursor.fetchone.side_effect = [{'participate_seq': 1}, {
            **row(), 'has_image': 1, 'image_digest': 'stored-image-digest', 'live_chat_deleted_at': None,
        }]
        with self.assertRaises(HTTPException) as caught:
            chat._save('room-a', 'db-user', chat.MessageCreate.model_validate(MESSAGE))
        self.assertEqual(caught.exception.status_code, 409)
        self.db.rollback.assert_called_once()

    def test_image_get_checks_room_and_deleted_record_and_returns_private_bytes(self):
        for data, media_type in ((photo(), 'image/png'), (photo(fmt='JPEG'), 'image/jpeg'),
                                 (photo(fmt='WEBP'), 'image/webp')):
            with self.subTest(media_type=media_type):
                self.reset_rows([{'participate_seq': 1}, {'chat_image': data}])
                response = self.image()
                self.assertEqual(response.status_code, 200)
                self.assertEqual(response.content, data)
                self.assertEqual(response.headers['content-type'], media_type)
                self.assertEqual(response.headers['cache-control'], 'private, no-store')
                self.assertEqual(response.headers['x-content-type-options'], 'nosniff')
                sql, params = self.cursor.execute.call_args.args
                self.assertIn('live_chat_deleted_at IS NULL', sql)
                self.assertIn('chat_image IS NOT NULL', sql)
                self.assertEqual(params, (7, 'room-a'))
                self.db.close.assert_called_once()

    def test_missing_deleted_wrong_room_or_unusable_image_returns_404(self):
        for record in (None, {'chat_image': b'not-an-image'}):
            self.reset_rows([{'participate_seq': 1}, record])
            self.assertEqual(self.image().status_code, 404)
        for seq in ('0', '-1', 'invalid'):
            self.assertEqual(self.image(seq=seq).status_code, 422)

    def test_image_get_database_error_is_sanitized_and_connection_closed(self):
        self.cursor.execute.side_effect = pymysql.OperationalError(2006, 'private database details')
        response = self.image()
        self.assertEqual(response.status_code, 503)
        self.assertNotIn('private database details', response.text)
        self.db.close.assert_called_once()

    def test_database_errors_rollback_do_not_broadcast_or_expose_details(self):
        for stage in ('connect', 'membership', 'duplicate', 'insert', 'result', 'commit'):
            with self.subTest(stage=stage):
                self.reset_rows([{'participate_seq': 1}, None, self.saved.copy()])
                self.connect.side_effect = None
                error = pymysql.OperationalError(2006, 'private database details')
                if stage == 'connect':
                    self.connect.side_effect = error
                elif stage == 'commit':
                    self.db.commit.side_effect = error
                else:
                    self.cursor.execute.side_effect = [None] * ('membership', 'duplicate', 'insert', 'result').index(stage) + [error]
                response = self.send()
                self.assertEqual(response.status_code, 503)
                self.assertNotIn('private database details', response.text)
                if stage != 'connect':
                    self.db.rollback.assert_called_once()
                    self.db.close.assert_called_once()
        self.broadcast.assert_not_awaited()

    def test_delivery_failure_after_commit_still_returns_saved_message(self):
        self.broadcast.side_effect = RuntimeError('delivery failed')
        with self.assertLogs(chat.logger, level='ERROR'):
            response = self.send()
        self.assertEqual(response.status_code, 201)
        self.db.commit.assert_called_once()
        self.db.rollback.assert_not_called()

    def test_http_image_is_delivered_to_existing_websocket_connections(self):
        self.broadcast.side_effect = manager.__class__.broadcast.__get__(manager)
        with patch.object(chat, '_session', return_value=('db-user', time.time() + 3600)):
            with self.client.websocket_connect('/chats/ws/room-a') as ws:
                ws.send_json({'type': 'auth', 'token': 'test-token'})
                self.assertEqual(ws.receive_json()['type'], 'ready')
                response = self.send()
                self.assertEqual(response.status_code, 201)
                event = ws.receive_json()
                self.assertEqual(event, response.json())
                self.assertEqual(event['message']['has_image'], 1)
                self.assertNotIn('chat_image', event['message'])

    def test_upload_does_not_deliver_to_a_peer_who_has_left(self):
        from starlette.websockets import WebSocketDisconnect
        self.broadcast.side_effect = manager.__class__.broadcast.__get__(manager)
        with patch.object(chat, '_session', return_value=('db-user', time.time() + 3600)) as session:
            with self.client.websocket_connect('/chats/ws/room-a') as ws:
                ws.send_json({'type': 'auth', 'token': 'test-token'})
                self.assertEqual(ws.receive_json()['type'], 'ready')
                session.side_effect = HTTPException(403, 'left')
                self.assertEqual(self.send().status_code, 201)
                with self.assertRaises(WebSocketDisconnect) as caught:
                    ws.receive_json()
                self.assertEqual(caught.exception.code, 4403)


if __name__ == '__main__':
    unittest.main()
