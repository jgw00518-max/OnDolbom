"""실제 Firebase·DB를 변경하지 않는 채팅 인증·권한·저장·WebSocket 테스트."""
import time
import unittest
from datetime import datetime
from unittest.mock import MagicMock, patch

import pymysql
from fastapi import HTTPException
from fastapi.testclient import TestClient
from starlette.websockets import WebSocketDisconnect

from python.main import app
from python.features.chats import router as chat
from python.features.chats.connection_manager import manager

REQUEST_ID = 'b87782b2-2e2f-43af-a617-cff3735083bb'
MESSAGE = {'type': 'message', 'client_message_id': REQUEST_ID, 'content': '안녕하세요 😀'}


def row():
    return {'chat_seq': 7, 'family_room_id': 'room-a', 'user_id': 'db-user',
            'author_name': '김가족',
            'chat_content': MESSAGE['content'], 'client_message_id': REQUEST_ID,
            'sent_at': datetime(2026, 10, 25, 18), 'live_chat_updated_at': None}


class ChatTests(unittest.TestCase):
    def setUp(self):
        self.client = self.enterContext(TestClient(app))
        self.db = MagicMock()
        self.cursor = self.db.cursor.return_value.__enter__.return_value
        self.connect = self.enterContext(patch.object(chat, 'connect', return_value=self.db))
        self.addCleanup(app.dependency_overrides.clear)
        self.addCleanup(manager.rooms.clear)

    def user(self):
        app.dependency_overrides[chat.get_current_user_id] = lambda: 'db-user'

    def session(self):
        return self.enterContext(patch.object(chat, '_session', return_value=('db-user', time.time() + 3600)))

    def open_socket(self, room='room-a'):
        ws = self.enterContext(self.client.websocket_connect('/chats/ws/' + room))
        ws.send_json({'type': 'auth', 'token': 'test-token'})
        self.assertEqual(ws.receive_json()['type'], 'ready')
        return ws

    def test_missing_http_token_rejected_without_db(self):
        response = self.client.get('/chats/messages?family_room_id=room-a', headers={'X-User-Id': 'forged'})
        self.assertEqual(response.status_code, 401)
        self.connect.assert_not_called()

    def test_uid_mapping_is_exact_and_withdrawal_is_rejected(self):
        self.cursor.fetchone.return_value = {'user_id': 'db-user', 'withdrawn_at': None}
        self.assertEqual(chat.get_current_user_id({'uid': 'Firebase-UID'}), 'db-user')
        self.assertIn('BINARY user_firebase_uid', self.cursor.execute.call_args.args[0])
        self.assertEqual(self.cursor.execute.call_args.args[1], ('Firebase-UID', 'Firebase-UID'))
        self.db.close.assert_called_once()
        for user in (None, {'user_id': 'db-user', 'withdrawn_at': '2026-10-25'}):
            self.cursor.fetchone.return_value = user
            with self.assertRaises(HTTPException) as caught:
                chat.get_current_user_id({'uid': 'Firebase-UID'})
            self.assertEqual(caught.exception.status_code, 403)

    def test_history_checks_membership_and_uses_cursor_without_images(self):
        self.user()
        self.cursor.fetchone.return_value = {'participate_seq': 1}
        self.cursor.fetchall.return_value = [row(), {**row(), 'chat_seq': 6}]
        response = self.client.get('/chats/messages?family_room_id=room-a&before_id=9&limit=1')
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()['next_before_id'], 7)
        self.assertEqual(response.json()['results'][0]['author_name'], '김가족')
        membership, query = self.cursor.execute.call_args_list
        for condition in ('is_active = 1', 'left_at IS NULL', 'withdrawn_at IS NULL', 'family_room_deleted_at IS NULL'):
            self.assertIn(condition, membership.args[0])
        self.assertEqual(query.args[1], ('room-a', 9, 2))
        self.assertNotIn('chat_image', query.args[0])
        self.assertIn('u.name FROM `user` AS u WHERE u.user_id = live_chat.user_id', query.args[0])
        self.db.close.assert_called_once()

    def test_history_reconnect_queries_ascending_and_scopes_room(self):
        self.user()
        self.cursor.fetchone.return_value = {'participate_seq': 1}
        self.cursor.fetchall.return_value = [row(), {**row(), 'chat_seq': 8}]
        response = self.client.get('/chats/messages?family_room_id=room-a&after_id=0&limit=1')
        self.assertEqual(response.json()['next_after_id'], 7)
        sql, params = self.cursor.execute.call_args.args
        self.assertIn('chat_seq > %s', sql)
        self.assertIn('ORDER BY chat_seq ASC', sql)
        self.assertEqual(params, ('room-a', 0, 2))

    def test_nonmember_cannot_read_history(self):
        self.user()
        self.cursor.fetchone.return_value = None
        self.assertEqual(self.client.get('/chats/messages?family_room_id=other').status_code, 403)
        self.assertEqual(self.cursor.execute.call_count, 1)

    def test_invalid_cursors_do_not_query_messages(self):
        self.user()
        for query in ('limit=101', 'before_id=-1', 'before_id=1&after_id=0'):
            self.assertEqual(self.client.get('/chats/messages?family_room_id=room-a&' + query).status_code, 422)
        self.connect.assert_not_called()

    def test_save_commits_server_author_before_return_and_closes(self):
        self.cursor.fetchone.side_effect = [{'participate_seq': 1}, None, row()]
        self.cursor.lastrowid = 7
        result, duplicate = chat._save('room-a', 'db-user', chat.MessageCreate.model_validate(MESSAGE))
        self.assertFalse(duplicate)
        self.assertEqual(result['chat_seq'], 7)
        self.assertEqual(result['author_name'], '김가족')
        calls = self.cursor.execute.call_args_list
        self.assertIn('FOR UPDATE', calls[0].args[0])
        self.assertEqual(calls[2].args[1], ('room-a', 'db-user', MESSAGE['content'], REQUEST_ID))
        self.assertIn('AS author_name', calls[1].args[0])
        self.assertIn('AS author_name', calls[3].args[0])
        self.db.commit.assert_called_once()
        self.db.rollback.assert_not_called()
        self.db.close.assert_called_once()

    def test_retry_returns_original_without_inserting_again(self):
        self.cursor.fetchone.side_effect = [{'participate_seq': 1}, {**row(), 'live_chat_deleted_at': None}]
        result, duplicate = chat._save('room-a', 'db-user', chat.MessageCreate.model_validate(MESSAGE))
        self.assertTrue(duplicate)
        self.assertEqual(result['chat_seq'], 7)
        self.assertEqual(self.cursor.execute.call_count, 2)
        self.db.commit.assert_called_once()

    def test_reused_request_id_with_changed_content_is_conflict(self):
        self.cursor.fetchone.side_effect = [{'participate_seq': 1}, {**row(), 'live_chat_deleted_at': None}]
        with self.assertRaises(HTTPException) as caught:
            chat._save('room-a', 'db-user', chat.MessageCreate.model_validate({**MESSAGE, 'content': '다른 내용'}))
        self.assertEqual(caught.exception.status_code, 409)
        self.db.commit.assert_not_called()
        self.db.rollback.assert_called_once()

    def test_database_error_rolls_back_and_hides_details(self):
        self.cursor.execute.side_effect = pymysql.OperationalError(2006, 'private')
        with self.assertRaises(HTTPException) as caught:
            chat._save('room-a', 'db-user', chat.MessageCreate.model_validate(MESSAGE))
        self.assertEqual(caught.exception.status_code, 503)
        self.assertNotIn('private', caught.exception.detail)
        self.db.rollback.assert_called_once()
        self.db.close.assert_called_once()

    def test_websocket_session_validates_token_user_and_room(self):
        self.cursor.fetchone.side_effect = [{'user_id': 'db-user', 'withdrawn_at': None}, {'participate_seq': 1}]
        with patch.object(chat, 'verify_firebase_token', return_value={'uid': 'verified', 'exp': time.time() + 60}) as verify:
            self.assertEqual(chat._session('id-token', 'room-a')[0], 'db-user')
        verify.assert_called_once_with('id-token')
        self.assertEqual(self.cursor.execute.call_args.args[1], ('room-a', 'db-user'))

    def test_expired_websocket_token_never_reaches_db(self):
        with patch.object(chat, 'verify_firebase_token', return_value={'uid': 'verified', 'exp': time.time() - 1}):
            with self.assertRaises(HTTPException) as caught:
                chat._session('expired', 'room-a')
        self.assertEqual(caught.exception.status_code, 401)
        self.connect.assert_not_called()

    def test_first_frame_must_authenticate(self):
        with self.client.websocket_connect('/chats/ws/room-a') as ws:
            ws.send_json(MESSAGE)
            with self.assertRaises(WebSocketDisconnect) as caught:
                ws.receive_json()
            self.assertEqual(caught.exception.code, 4400)
        self.connect.assert_not_called()

    def test_invalid_token_and_nonmember_cannot_join(self):
        for status, code in ((401, 4401), (403, 4403), (503, 1013)):
            with patch.object(chat, '_session', side_effect=HTTPException(status, 'denied')):
                with self.client.websocket_connect('/chats/ws/room-a') as ws:
                    ws.send_json({'type': 'auth', 'token': 'bad'})
                    with self.assertRaises(WebSocketDisconnect) as caught:
                        ws.receive_json()
                    self.assertEqual(caught.exception.code, code)

    def test_socket_message_is_broadcast_only_within_room_after_save(self):
        self.session()
        with patch.object(chat, '_save', return_value=(row(), False)) as save:
            sender = self.open_socket()
            receiver = self.open_socket()
            other_room = self.open_socket('room-b')
            sender.send_json(MESSAGE)
            self.assertEqual(sender.receive_json()['message']['chat_seq'], 7)
            self.assertEqual(receiver.receive_json()['message']['chat_content'], MESSAGE['content'])
            save.assert_called_once()
            # 다른 공간의 응답에 앞 공간의 메시지가 섞이지 않는지 확인한다.
            save.return_value = ({**row(), 'family_room_id': 'room-b'}, True)
            other_room.send_json(MESSAGE)
            self.assertEqual(other_room.receive_json()['message']['family_room_id'], 'room-b')

    def test_invalid_and_forged_message_does_not_save(self):
        self.session()
        with patch.object(chat, '_save') as save:
            ws = self.open_socket()
            for message in ({**MESSAGE, 'content': '  '}, {**MESSAGE, 'content': 'a' * 4001}, {**MESSAGE, 'user_id': 'forged'}, {**MESSAGE, 'client_message_id': 'invalid'}):
                ws.send_json(message)
                self.assertEqual(ws.receive_json()['status'], 422)
            save.assert_not_called()

    def test_retry_only_acknowledges_sender(self):
        self.session()
        with patch.object(chat, '_save', return_value=(row(), True)):
            ws = self.open_socket()
            ws.send_json(MESSAGE)
            self.assertTrue(ws.receive_json()['duplicate'])

    def test_failed_save_does_not_broadcast(self):
        self.session()
        with patch.object(chat, '_save', side_effect=HTTPException(503, 'failed')), patch.object(manager, 'broadcast') as broadcast:
            ws = self.open_socket()
            ws.send_json(MESSAGE)
            with self.assertRaises(WebSocketDisconnect) as caught:
                ws.receive_json()
            self.assertEqual(caught.exception.code, 1013)
            broadcast.assert_not_called()

    def test_receiving_peer_losing_membership_is_disconnected(self):
        session = self.session()
        with patch.object(chat, '_save', return_value=(row(), False)):
            sender = self.open_socket()
            receiver = self.open_socket()
            calls = 0
            def access(token, room):
                nonlocal calls
                calls += 1
                # 발신자의 전송 전 확인만 통과시키고 수신 직전 검사는 거절한다.
                if calls == 1:
                    return 'db-user', time.time() + 60
                raise HTTPException(403, 'left')
            session.side_effect = access
            sender.send_json(MESSAGE)
            with self.assertRaises(WebSocketDisconnect) as caught:
                receiver.receive_json()
            self.assertEqual(caught.exception.code, 4403)

    def test_malformed_or_binary_json_is_closed_without_saving(self):
        self.session()
        with patch.object(chat, '_save') as save:
            for binary in (False, True):
                with self.client.websocket_connect('/chats/ws/room-a') as ws:
                    if binary:
                        ws.send_bytes(b'not-json')
                    else:
                        ws.send_text('{invalid')
                    with self.assertRaises(WebSocketDisconnect) as caught:
                        ws.receive_json()
                    self.assertEqual(caught.exception.code, 4400)
            save.assert_not_called()

    def test_oversized_frame_is_rejected(self):
        with self.client.websocket_connect('/chats/ws/room-a') as ws:
            ws.send_text('x' * 65537)
            with self.assertRaises(WebSocketDisconnect) as caught:
                ws.receive_json()
            self.assertEqual(caught.exception.code, 1009)
        self.connect.assert_not_called()

    def test_idle_socket_is_closed_at_token_expiry_and_removed(self):
        with patch.object(chat, '_session', return_value=('db-user', time.time() + 0.1)):
            with self.client.websocket_connect('/chats/ws/room-a') as ws:
                ws.send_json({'type': 'auth', 'token': 'expires-soon'})
                self.assertEqual(ws.receive_json()['type'], 'ready')
                with self.assertRaises(WebSocketDisconnect) as caught:
                    ws.receive_json()
                self.assertEqual(caught.exception.code, 4401)
        self.assertNotIn('room-a', manager.rooms)
