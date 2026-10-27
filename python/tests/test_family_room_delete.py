"""공간 삭제 시 원본 보존·주보호자 권한·중복 요청·채팅 연결 종료를 검증한다."""

from datetime import datetime
import time
import unittest
from unittest.mock import AsyncMock, MagicMock, patch

import pymysql
from fastapi import HTTPException
from fastapi.testclient import TestClient
from starlette.websockets import WebSocketDisconnect

from python.features.family_room import router as rooms
from python.features.chats.connection_manager import ConnectionManager
from python.features.chats import router as chats
from python.main import app


STAMP = datetime(2026, 10, 27, 17, 30)


class FamilyRoomDeleteTests(unittest.TestCase):
    def setUp(self):
        self.client = self.enterContext(TestClient(app))
        self.addCleanup(app.dependency_overrides.clear)
        app.dependency_overrides[rooms.get_current_user_id] = lambda: "guardian"
        self.db = MagicMock()
        self.cursor = self.db.cursor.return_value.__enter__.return_value
        self.cursor.fetchone.side_effect = [
            {"family_room_deleted_at": None},
            {"participate_seq": 1, "is_representative": 1},
            {"family_room_deleted_at": STAMP},
        ]
        self.connect = self.enterContext(patch.object(rooms, "connect", return_value=self.db))
        self.close_room = self.enterContext(patch.object(rooms.chat_manager, "close_room", new_callable=AsyncMock))

    def delete(self, room="room-a"):
        return self.client.delete(f"/family-room/{room}")

    def test_guardian_soft_deletes_only_space_timestamp_and_closes_after_commit(self):
        async def close_after_commit(*args, **kwargs):
            self.db.commit.assert_called_once()
            self.db.close.assert_called_once()
        self.close_room.side_effect = close_after_commit
        response = self.delete()
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json(), {"result": "OK", "family_room_id": "room-a",
                         "family_room_deleted_at": STAMP.isoformat(), "already_deleted": False})
        calls = self.cursor.execute.call_args_list
        self.assertIn("FOR UPDATE", calls[0].args[0])
        self.assertEqual(calls[0].args[1], ("room-a",))
        self.assertEqual(calls[1].args[1], ("room-a", "guardian"))
        for condition in ("p.is_active = 1", "p.left_at IS NULL", "u.withdrawn_at IS NULL", "FOR UPDATE"):
            self.assertIn(condition, calls[1].args[0])
        writes = [call.args[0] for call in calls if call.args[0].lstrip().startswith(("UPDATE", "DELETE", "INSERT"))]
        self.assertEqual(len(writes), 1)
        self.assertIn("UPDATE family_room", writes[0])
        self.assertIn("SET family_room_deleted_at = CURRENT_TIMESTAMP", writes[0])
        self.assertNotIn("is_active", writes[0])
        self.assertNotIn("left_at", writes[0])
        self.close_room.assert_awaited_once_with("room-a", code=4403)
        self.db.rollback.assert_not_called()

    def test_repeat_preserves_timestamp_without_updating_data(self):
        self.cursor.fetchone.side_effect = [
            {"family_room_deleted_at": STAMP}, {"participate_seq": 1, "is_representative": 1},
        ]
        response = self.delete()
        self.assertEqual(response.status_code, 200)
        self.assertTrue(response.json()["already_deleted"])
        self.assertEqual(response.json()["family_room_deleted_at"], STAMP.isoformat())
        self.assertEqual(self.cursor.execute.call_count, 2)
        self.db.commit.assert_called_once()
        self.close_room.assert_awaited_once()

    def test_missing_token_cannot_connect(self):
        app.dependency_overrides.clear()
        self.assertEqual(self.delete().status_code, 401)
        self.connect.assert_not_called()
        self.close_room.assert_not_awaited()

    def test_nonmember_or_general_family_cannot_delete_even_deleted_space(self):
        for deleted in (None, STAMP):
            for member in (None, {"participate_seq": 2, "is_representative": 0}):
                with self.subTest(deleted=deleted, member=member):
                    self.cursor.fetchone.side_effect = [{"family_room_deleted_at": deleted}, member]
                    self.assertEqual(self.delete().status_code, 403)
        self.db.commit.assert_not_called()
        self.close_room.assert_not_awaited()

    def test_unknown_space_is_404_and_no_connection_is_closed(self):
        self.cursor.fetchone.side_effect = [None]
        self.assertEqual(self.delete().status_code, 404)
        self.db.rollback.assert_called_once()
        self.db.close.assert_called_once()
        self.close_room.assert_not_awaited()

    def test_invalid_room_id_is_rejected_without_database_work(self):
        for value in ("%20", "a" * 51):
            self.assertEqual(self.delete(value).status_code, 422)
        self.connect.assert_not_called()

    def test_database_failures_roll_back_without_closing_chats_or_leaking_details(self):
        for statement in range(4):
            with self.subTest(statement=statement):
                self.cursor.execute.side_effect = [None] * statement + [pymysql.OperationalError(2006, "private-db")]
                self.cursor.fetchone.side_effect = [
                    {"family_room_deleted_at": None}, {"participate_seq": 1, "is_representative": 1},
                ]
                response = self.delete()
                self.assertEqual(response.status_code, 503)
                self.assertNotIn("private-db", response.text)
        self.db.commit.assert_not_called()
        self.assertEqual(self.db.rollback.call_count, 4)
        self.assertEqual(self.db.close.call_count, 4)
        self.close_room.assert_not_awaited()

    def test_commit_failure_does_not_close_live_chats(self):
        self.db.commit.side_effect = pymysql.OperationalError(2006, "private-db")
        self.assertEqual(self.delete().status_code, 503)
        self.db.rollback.assert_called_once()
        self.close_room.assert_not_awaited()


class CloseDeletedRoomTests(unittest.IsolatedAsyncioTestCase):
    async def test_closes_only_target_room_and_tolerates_one_failed_socket(self):
        manager = ConnectionManager()
        first, broken, other = AsyncMock(), AsyncMock(), AsyncMock()
        broken.close.side_effect = OSError("disconnected")
        manager.add("deleted", first)
        manager.add("deleted", broken)
        manager.add("retained", other)
        await manager.close_room("deleted")
        first.close.assert_awaited_once_with(4403)
        broken.close.assert_awaited_once_with(4403)
        other.close.assert_not_awaited()
        self.assertNotIn("deleted", manager.rooms)
        self.assertIn(other, manager.rooms["retained"])
        await manager.close_room("deleted")  # 중복 연결 정리도 안전하다.


class LiveDeletedRoomTests(unittest.TestCase):
    def test_delete_closes_existing_socket_blocks_reconnect_and_preserves_other_room(self):
        self.addCleanup(app.dependency_overrides.clear)
        self.addCleanup(rooms.chat_manager.rooms.clear)
        app.dependency_overrides[rooms.get_current_user_id] = lambda: "guardian"
        db = MagicMock()
        cursor = db.cursor.return_value.__enter__.return_value
        cursor.fetchone.side_effect = [
            {"family_room_deleted_at": None},
            {"participate_seq": 1, "is_representative": 1},
            {"family_room_deleted_at": STAMP},
        ]
        deleted = False

        def commit():
            nonlocal deleted
            deleted = True

        def session(token, room_id):
            if deleted and room_id == "room-a":
                raise HTTPException(403, "삭제된 공간")
            return "guardian", time.time() + 3600

        db.commit.side_effect = commit
        with patch.object(rooms, "connect", return_value=db), patch.object(chats, "_session", side_effect=session), TestClient(app) as client:
            with client.websocket_connect('/chats/ws/room-a') as target, client.websocket_connect('/chats/ws/room-b') as other:
                for socket in (target, other):
                    socket.send_json({'type': 'auth', 'token': 'verified'})
                    self.assertEqual(socket.receive_json()['type'], 'ready')
                self.assertEqual(client.delete('/family-room/room-a').status_code, 200)
                with self.assertRaises(WebSocketDisconnect) as caught:
                    target.receive_json()
                self.assertEqual(caught.exception.code, 4403)
                other.send_json({'type': 'unsupported'})
                self.assertEqual(other.receive_json()['status'], 422)
                with client.websocket_connect('/chats/ws/room-a') as retry:
                    retry.send_json({'type': 'auth', 'token': 'verified'})
                    with self.assertRaises(WebSocketDisconnect) as caught:
                        retry.receive_json()
                    self.assertEqual(caught.exception.code, 4403)


if __name__ == "__main__":
    unittest.main()
