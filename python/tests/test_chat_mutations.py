"""채팅 본문 수정·전체 삭제·변경 조회와 기존 전송 중복 방지 검증."""
from datetime import datetime
import time
import unittest
from unittest.mock import AsyncMock, MagicMock, patch

from fastapi.testclient import TestClient
import pymysql

from python.main import app
from python.features.chats import router as chat
from python.features.chats.connection_manager import manager
from python.tests.test_chats import MESSAGE, row


class ChatMutationTests(unittest.TestCase):
    def setUp(self):
        self.client = self.enterContext(TestClient(app))
        self.db = MagicMock()
        self.cursor = self.db.cursor.return_value.__enter__.return_value
        self.connect = self.enterContext(patch.object(chat, 'connect', return_value=self.db))
        self.broadcast = self.enterContext(patch.object(manager, 'broadcast', new_callable=AsyncMock))
        app.dependency_overrides[chat.get_current_user_id] = lambda: 'db-user'
        self.addCleanup(app.dependency_overrides.pop, chat.get_current_user_id, None)
        self.addCleanup(manager.rooms.clear)
        self.original = {**row(), 'live_chat_deleted_at': None}
        self.edited = {**self.original, 'chat_content': '수정한 내용',
                       'live_chat_updated_at': datetime(2026, 10, 26, 18, 1)}
        self.deleted = {**self.original, 'live_chat_deleted_at': datetime(2026, 10, 26, 18, 2)}
        self.reset_rows([{'participate_seq': 1}, self.original.copy(), self.edited.copy()])

    def reset_rows(self, rows):
        self.db.reset_mock()
        self.cursor.fetchone.side_effect = rows
        self.cursor.execute.side_effect = None
        self.connect.side_effect = None
        self.db.commit.side_effect = None

    def edit(self, payload=None, seq='7'):
        return self.client.patch(f'/chats/messages/{seq}', json=payload if payload is not None else {
            'family_room_id': 'room-a', 'content': '  수정한 내용  '})

    def delete(self, seq='7', query='family_room_id=room-a'):
        return self.client.delete(f'/chats/messages/{seq}?{query}')

    def test_edit_checks_active_author_locks_then_commits_and_broadcasts(self):
        async def delivered(room_id, payload, authorize):
            self.db.commit.assert_called_once()
            self.assertEqual(room_id, 'room-a')
            self.assertEqual(payload['action'], 'updated')
            self.assertTrue(callable(authorize))
        self.broadcast.side_effect = delivered
        response = self.edit()
        self.assertEqual(response.status_code, 200, response.text)
        body = response.json()
        self.assertEqual(body['message']['chat_content'], '수정한 내용')
        self.assertEqual(body['message']['live_chat_updated_at'], '2026-10-26T18:01:00')
        self.assertFalse(body['message']['is_deleted'])
        self.assertTrue(body['changed'])
        member, target, update, result = self.cursor.execute.call_args_list
        self.assertEqual(member.args[1], ('room-a', 'db-user'))
        for condition in ('p.is_active = 1', 'p.left_at IS NULL', 'u.withdrawn_at IS NULL',
                          'f.family_room_deleted_at IS NULL', 'FOR UPDATE'):
            self.assertIn(condition, member.args[0])
        self.assertIn('FOR UPDATE', target.args[0])
        self.assertEqual(target.args[1], (7, 'room-a'))
        self.assertEqual(update.args[1], ('수정한 내용', 7, 'room-a', 'db-user'))
        self.assertIn('live_chat_deleted_at IS NULL', update.args[0])
        self.assertNotIn('chat_image', update.args[0])
        self.assertNotIn('client_message_id', update.args[0])
        self.assertNotIn('sent_at', update.args[0])
        self.assertEqual(result.args[1], (7, 'room-a'))
        self.db.rollback.assert_not_called()
        self.db.close.assert_called_once()
        self.broadcast.assert_awaited_once()

    def test_image_caption_can_be_cleared_without_removing_image(self):
        self.reset_rows([{'participate_seq': 1}, {**self.original, 'has_image': 1},
                         {**self.edited, 'has_image': 1, 'chat_content': ''}])
        response = self.edit({'family_room_id': 'room-a', 'content': '   '})
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()['message']['has_image'], 1)
        self.assertEqual(response.json()['message']['chat_content'], '')
        update = self.cursor.execute.call_args_list[2]
        self.assertNotIn('chat_image', update.args[0])
        self.assertEqual(update.args[1][0], '')

    def test_plain_text_message_cannot_be_empty(self):
        response = self.edit({'family_room_id': 'room-a', 'content': '  '})
        self.assertEqual(response.status_code, 422)
        self.assertEqual(self.cursor.execute.call_count, 2)
        self.db.rollback.assert_called_once()
        self.broadcast.assert_not_awaited()

    def test_same_content_is_noop_without_timestamp_change_or_broadcast(self):
        self.reset_rows([{'participate_seq': 1}, self.edited.copy()])
        response = self.edit()
        self.assertEqual(response.status_code, 200)
        self.assertFalse(response.json()['changed'])
        self.assertEqual(self.cursor.execute.call_count, 2)
        self.db.commit.assert_called_once()
        self.broadcast.assert_not_awaited()

    def test_delete_is_soft_whole_message_and_response_hides_original_and_image(self):
        self.reset_rows([{'participate_seq': 1}, {**self.original, 'has_image': 1},
                         {**self.deleted, 'has_image': 1}])
        response = self.delete()
        self.assertEqual(response.status_code, 200)
        body = response.json()
        self.assertEqual(body['action'], 'deleted')
        self.assertFalse(body['already_deleted'])
        self.assertTrue(body['message']['is_deleted'])
        self.assertEqual(body['message']['chat_content'], '삭제된 메시지입니다.')
        self.assertEqual(body['message']['has_image'], 0)
        self.assertEqual(body['message']['live_chat_deleted_at'], '2026-10-26T18:02:00')
        self.assertNotIn(self.original['chat_content'], response.text)
        sql, params = self.cursor.execute.call_args_list[2].args
        self.assertIn('SET live_chat_deleted_at = CURRENT_TIMESTAMP', sql)
        self.assertNotIn('DELETE FROM', sql)
        self.assertNotIn('chat_image', sql)
        self.assertNotIn('chat_content', sql)
        self.assertEqual(params, (7, 'room-a', 'db-user'))
        self.db.commit.assert_called_once()
        self.broadcast.assert_awaited_once()

    def test_repeat_delete_succeeds_but_edit_of_deleted_message_is_conflict(self):
        self.reset_rows([{'participate_seq': 1}, self.deleted.copy()])
        response = self.delete()
        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.json()['already_deleted'])
        self.assertEqual(self.cursor.execute.call_count, 2)
        self.broadcast.assert_not_awaited()
        self.reset_rows([{'participate_seq': 1}, self.deleted.copy()])
        self.assertEqual(self.edit().status_code, 409)
        self.db.rollback.assert_called_once()
        self.db.commit.assert_not_called()

    def test_nonmembers_missing_or_other_room_records_and_other_authors_are_rejected(self):
        for operation in (self.edit, self.delete):
            for rows, status in (([None], 403), ([{'participate_seq': 1}, None], 404),
                                 ([{'participate_seq': 1, 'is_representative': 1},
                                   {**self.original, 'user_id': 'other-family'}], 403)):
                with self.subTest(operation=operation.__name__, status=status):
                    self.reset_rows(rows)
                    self.assertEqual(operation().status_code, status)
                    self.db.rollback.assert_called_once()
                    self.db.commit.assert_not_called()
                    self.db.close.assert_called_once()
        self.broadcast.assert_not_awaited()

    def test_unauthenticated_mutation_and_refresh_do_not_connect(self):
        app.dependency_overrides.pop(chat.get_current_user_id)
        self.assertEqual(self.edit().status_code, 401)
        self.assertEqual(self.delete().status_code, 401)
        self.assertEqual(self.client.post('/chats/messages/refresh', json={
            'family_room_id': 'room-a', 'message_ids': [7]}).status_code, 401)
        self.connect.assert_not_called()

    def test_invalid_payload_cannot_change_image_author_or_request_id(self):
        base = {'family_room_id': 'room-a', 'content': '본문'}
        for payload in ({}, {**base, 'family_room_id': ' '}, {**base, 'content': None},
                        {**base, 'content': 'x' * 4001}, {**base, 'image': 'file'},
                        {**base, 'remove_image': True}, {**base, 'user_id': 'forged'},
                        {**base, 'client_message_id': 'forged'}):
            with self.subTest(payload=payload):
                self.assertEqual(self.edit(payload).status_code, 422)
        for seq in ('0', '-1', 'invalid'):
            self.assertEqual(self.edit(seq=seq).status_code, 422)
            self.assertEqual(self.delete(seq=seq).status_code, 422)
        self.assertEqual(self.delete(query='family_room_id= ').status_code, 422)
        self.connect.assert_not_called()

    def test_history_and_bulk_refresh_return_redacted_deletion_tombstones(self):
        self.cursor.fetchone.side_effect = None
        self.cursor.fetchone.return_value = {'participate_seq': 1}
        self.cursor.fetchall.return_value = [self.edited.copy(), {**self.deleted, 'chat_seq': 8, 'has_image': 1}]
        history = self.client.get('/chats/messages?family_room_id=room-a').json()
        self.assertEqual(history['results'][1]['chat_content'], '삭제된 메시지입니다.')
        self.assertEqual(history['results'][1]['has_image'], 0)
        self.assertTrue(history['results'][1]['is_deleted'])
        response = self.client.post('/chats/messages/refresh', json={
            'family_room_id': 'room-a', 'message_ids': [9, 8, 7, 7]})
        self.assertEqual(response.status_code, 200)
        body = response.json()
        self.assertEqual(body['missing_ids'], [9])
        self.assertEqual(body['results'][0]['chat_content'], '수정한 내용')
        self.assertEqual(body['results'][1]['chat_content'], '삭제된 메시지입니다.')
        sql, params = self.cursor.execute.call_args.args
        self.assertIn('chat_seq IN (%s, %s, %s)', sql)
        self.assertEqual(params, ('room-a', 7, 8, 9))
        self.assertNotIn('chat_image,', sql)

    def test_refresh_is_bounded_authenticated_and_scoped_to_active_room(self):
        for payload in ({'family_room_id': 'room-a', 'message_ids': []},
                        {'family_room_id': 'room-a', 'message_ids': list(range(1, 102))},
                        {'family_room_id': 'room-a', 'message_ids': [-1]},
                        {'family_room_id': 'room-a', 'message_ids': [1], 'user_id': 'forged'}):
            self.assertEqual(self.client.post('/chats/messages/refresh', json=payload).status_code, 422)
        self.connect.assert_not_called()
        self.reset_rows([None])
        self.assertEqual(self.client.post('/chats/messages/refresh', json={
            'family_room_id': 'room-a', 'message_ids': [7]}).status_code, 403)
        self.assertEqual(self.cursor.execute.call_count, 1)

    def test_old_send_retry_after_edit_or_delete_does_not_restore_or_recreate_message(self):
        for original in (self.edited, self.deleted):
            self.reset_rows([{'participate_seq': 1}, original.copy()])
            with self.assertRaises(chat.HTTPException) as caught:
                chat._save('room-a', 'db-user', chat.MessageCreate.model_validate(MESSAGE))
            self.assertEqual(caught.exception.status_code, 409)
            self.assertEqual(self.cursor.execute.call_count, 2)
            self.db.commit.assert_not_called()

    def test_failure_rolls_back_and_does_not_broadcast_or_expose_details(self):
        for operation in (self.edit, self.delete):
            for stage in ('connect', 'member', 'target', 'update', 'result', 'commit'):
                with self.subTest(operation=operation.__name__, stage=stage):
                    self.reset_rows([{'participate_seq': 1}, self.original.copy(), self.edited.copy()])
                    error = pymysql.OperationalError(2006, 'private database details')
                    if stage == 'connect':
                        self.connect.side_effect = error
                    elif stage == 'commit':
                        self.db.commit.side_effect = error
                    else:
                        self.cursor.execute.side_effect = [None] * ('member', 'target', 'update', 'result').index(stage) + [error]
                    response = operation()
                    self.assertEqual(response.status_code, 503)
                    self.assertNotIn('private database details', response.text)
                    if stage != 'connect':
                        self.db.rollback.assert_called_once()
                        self.db.close.assert_called_once()
        self.broadcast.assert_not_awaited()

    def test_committed_edit_stays_successful_if_broadcast_fails(self):
        self.broadcast.side_effect = RuntimeError('delivery failed')
        with self.assertLogs(chat.logger, level='ERROR'):
            self.assertEqual(self.edit().status_code, 200)
        self.db.commit.assert_called_once()
        self.db.rollback.assert_not_called()

    def test_existing_websocket_receives_updated_and_deleted_message_snapshots(self):
        self.broadcast.side_effect = manager.__class__.broadcast.__get__(manager)
        with patch.object(chat, '_session', return_value=('db-user', time.time() + 3600)):
            with self.client.websocket_connect('/chats/ws/room-a') as ws:
                ws.send_json({'type': 'auth', 'token': 'test-token'})
                self.assertEqual(ws.receive_json()['type'], 'ready')
                edited = self.edit()
                self.assertEqual(ws.receive_json(), edited.json())
                self.reset_rows([{'participate_seq': 1}, self.edited.copy(), self.deleted.copy()])
                deleted = self.delete()
                self.assertEqual(ws.receive_json(), deleted.json())
                self.assertTrue(deleted.json()['message']['is_deleted'])


if __name__ == '__main__':
    unittest.main()
