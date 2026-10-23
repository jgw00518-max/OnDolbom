"""실제 DB 없이 메모 인증 연결·공간 권한·연결 정리를 확인한다."""

import unittest
from datetime import datetime
from unittest.mock import MagicMock, patch
from uuid import UUID

import pymysql
from fastapi.testclient import TestClient

from python.auth import get_current_user_id
from python.main import app


class MemoTests(unittest.TestCase):
    def setUp(self):
        self.client = TestClient(app)
        self.db = MagicMock()
        self.cursor = self.db.cursor.return_value.__enter__.return_value
        self.cursor.fetchone.return_value = {"1": 1}
        app.dependency_overrides[get_current_user_id] = lambda: "user-a"

    def tearDown(self):
        app.dependency_overrides.pop(get_current_user_id, None)
        self.client.close()

    def test_unauthenticated_read_and_write_do_not_connect(self):
        app.dependency_overrides.pop(get_current_user_id)
        with patch("python.features.memos.router.connect") as connect:
            response = self.client.get(
                "/memos/select?family_room_id=room-a&user_id=user-a",
                headers={"Authorization": "Bearer user-a", "X-User-Id": "user-a"},
            )
            self.assertEqual(response.status_code, 401)
            response = self.client.post("/memos/insert", json={
                "family_room_id": "room-a", "user_id": "user-a", "memo_content": "메모",
            })
            self.assertEqual(response.status_code, 401)
            connect.assert_not_called()

    def test_insert_ignores_forged_author_and_uses_authenticated_identity(self):
        with patch("python.features.memos.router.connect", return_value=self.db):
            response = self.client.post("/memos/insert", json={
                "family_room_id": "room-a", "user_id": "forged-author", "memo_content": "메모",
            })
        self.assertEqual(response.status_code, 201)
        membership, insert = self.cursor.execute.call_args_list
        self.assertEqual(membership.args[1], ("room-a", "user-a"))
        self.assertEqual(insert.args[1][2], "user-a")

    def test_nonmember_cannot_read_memos(self):
        self.cursor.fetchone.return_value = None
        with patch("python.features.memos.router.connect", return_value=self.db):
            response = self.client.get("/memos/select?family_room_id=room-b")
        self.assertEqual(response.status_code, 403)
        self.assertEqual(self.cursor.execute.call_count, 1)
        self.db.close.assert_called_once()

    def test_insert_for_active_member_commits_once(self):
        self.cursor.fetchone.return_value = {"participate_seq": 1}
        with patch("python.features.memos.router.connect", return_value=self.db):
            response = self.client.post("/memos/insert", json={
                "family_room_id": "room-a",
                "memo_content": "  저녁 식사 후 산책했습니다.  ",
            })
        self.assertEqual(response.status_code, 201)
        body = response.json()
        self.assertEqual(body["result"], "OK")
        self.assertEqual(UUID(body["memo_id"]).version, 4)
        membership, insert = self.cursor.execute.call_args_list
        self.assertEqual(membership.args[1], ("room-a", "user-a"))
        for condition in (
            "p.is_active = 1", "p.left_at IS NULL",
            "f.family_room_deleted_at IS NULL", "u.withdrawn_at IS NULL",
            "FOR UPDATE",
        ):
            self.assertIn(condition, membership.args[0])
        self.assertEqual(insert.args[1], (
            body["memo_id"], "room-a", "user-a", "저녁 식사 후 산책했습니다.", 0,
        ))
        self.db.commit.assert_called_once()
        self.db.rollback.assert_not_called()
        self.db.close.assert_called_once()

    def test_insert_without_active_membership_is_denied(self):
        self.cursor.fetchone.return_value = None
        with patch("python.features.memos.router.connect", return_value=self.db):
            response = self.client.post("/memos/insert", json={
                "family_room_id": "other-room", "user_id": "user-a",
                "memo_content": "메모",
            })
        self.assertEqual(response.status_code, 403)
        self.assertEqual(self.cursor.execute.call_count, 1)
        self.db.commit.assert_not_called()
        self.db.rollback.assert_called_once()
        self.db.close.assert_called_once()

    def test_insert_rejects_missing_blank_and_oversized_fields(self):
        valid = {"family_room_id": "room-a", "user_id": "user-a", "memo_content": "메모"}
        invalid = [
            {key: value for key, value in valid.items() if key != "memo_content"},
            {**valid, "family_room_id": "   "},
            {**valid, "memo_content": " \n\t "},
            {**valid, "memo_content": "가" * 10001},
        ]
        for payload in invalid:
            with self.subTest(fields=list(payload)), patch(
                "python.features.memos.router.connect"
            ) as connect:
                response = self.client.post("/memos/insert", json=payload)
                self.assertEqual(response.status_code, 422)
                connect.assert_not_called()

    def test_insert_failure_rolls_back_and_hides_database_details(self):
        self.cursor.fetchone.return_value = {"participate_seq": 1}
        self.cursor.execute.side_effect = [
            None, pymysql.OperationalError(2006, "private database details"),
        ]
        with patch("python.features.memos.router.connect", return_value=self.db), \
                self.assertLogs("python.features.memos.router", level="ERROR"):
            response = self.client.post("/memos/insert", json={
                "family_room_id": "room-a", "user_id": "user-a", "memo_content": "메모",
            })
        self.assertEqual(response.status_code, 500)
        self.assertNotIn("private database details", response.text)
        self.db.commit.assert_not_called()
        self.db.rollback.assert_called_once()
        self.db.close.assert_called_once()

    def test_room_memos_are_returned_for_authenticated_member(self):
        self.cursor.fetchall.return_value = [
            {"memo_id": "memo-1", "family_room_id": "room-a",
             "user_id": "another-member", "memo_content": "산책 완료",
             "likes": 0, "written_at": datetime(2026, 10, 23, 10, 0),
             "memo_updated_at": None}
        ]
        with patch("python.features.memos.router.connect", return_value=self.db):
            response = self.client.get(
                "/memos/select?family_room_id=room-a&limit=10&offset=20"
            )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["results"][0]["user_id"], "another-member")
        self.assertEqual(
            response.json()["results"][0]["written_at"], "2026-10-23T10:00:00"
        )
        self.assertEqual(
            self.cursor.execute.call_args.args[1], ("room-a", 10, 20)
        )
        self.assertEqual(self.cursor.execute.call_count, 2)
        sql = self.cursor.execute.call_args.args[0]
        self.assertIn("m.family_room_id = %s", sql)
        self.assertIn("m.memo_deleted_at IS NULL", sql)
        self.assertIn("f.family_room_deleted_at IS NULL", sql)
        self.db.close.assert_called_once()

    def test_space_id_is_required(self):
        with patch("python.features.memos.router.connect") as connect:
            response = self.client.get("/memos/select")
        self.assertEqual(response.status_code, 422)
        connect.assert_not_called()

    def test_empty_room_returns_empty_list(self):
        self.cursor.fetchall.return_value = []
        with patch("python.features.memos.router.connect", return_value=self.db):
            response = self.client.get("/memos/select?family_room_id=room-a")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json(), {"results": []})

    def test_invalid_pagination_does_not_connect(self):
        for query in ("limit=101", "limit=0", "offset=-1"):
            with self.subTest(query=query), patch(
                "python.features.memos.router.connect"
            ) as connect:
                response = self.client.get(
                    f"/memos/select?family_room_id=room-a&{query}"
                )
                self.assertEqual(response.status_code, 422)
                connect.assert_not_called()

    def test_database_error_hides_details_and_closes_connection(self):
        self.cursor.execute.side_effect = pymysql.OperationalError(
            2006, "private database details"
        )
        with patch("python.features.memos.router.connect", return_value=self.db), \
                self.assertLogs("python.features.memos.router", level="ERROR"):
            response = self.client.get("/memos/select?family_room_id=room-a")
        self.assertEqual(response.status_code, 500)
        self.assertNotIn("private database details", response.text)
        self.db.close.assert_called_once()


if __name__ == "__main__":
    unittest.main()
