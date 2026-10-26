"""좋아요 최초 등록·재요청·인증·권한·원자적 집계와 취소 API 부재 검증."""
import unittest
from unittest.mock import MagicMock, patch

from fastapi import HTTPException
from fastapi.testclient import TestClient
import pymysql

from python.features.memos.router import get_current_user_id
from python.main import app


class MemoLikeTests(unittest.TestCase):
    def setUp(self):
        self.client = TestClient(app)
        self.addCleanup(self.client.close)
        self.db = MagicMock()
        self.cursor = self.db.cursor.return_value.__enter__.return_value
        self.cursor.fetchone.side_effect = [{"participate_seq": 1}, {"likes": 3}, None]
        app.dependency_overrides[get_current_user_id] = lambda: "liker-a"
        self.addCleanup(app.dependency_overrides.pop, get_current_user_id, None)
        self.connect = self.enterContext(patch("python.features.memos.router.connect", return_value=self.db))
        self.payload = {"family_room_id": "room-a", "author_user_id": "author-a"}

    def like(self, payload=None, memo_id="memo-1"):
        return self.client.post(f"/memos/like/{memo_id}", json=self.payload if payload is None else payload,
                                headers={"X-User-Id": "forged"})

    def test_first_like_uses_authenticated_user_and_atomically_increments_count(self):
        response = self.like()
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json(), {
            "result": "OK", "memo_id": "memo-1", "likes": 4,
            "is_liked": True, "already_liked": False,
        })
        membership, memo, existing, insert, update = self.cursor.execute.call_args_list
        self.assertEqual(membership.args[1], ("room-a", "liker-a"))
        for condition in ("p.is_active = 1", "p.left_at IS NULL", "u.withdrawn_at IS NULL",
                          "f.family_room_deleted_at IS NULL", "FOR UPDATE"):
            self.assertIn(condition, membership.args[0])
        self.assertEqual(memo.args[1], ("memo-1", "room-a", "author-a"))
        self.assertIn("FOR UPDATE", memo.args[0])
        self.assertIn("memo_deleted_at IS NULL", memo.args[0])
        self.assertEqual(existing.args[1], ("memo-1", "room-a", "author-a", "liker-a"))
        self.assertIn("FOR UPDATE", existing.args[0])
        self.assertEqual(insert.args[1], existing.args[1])
        self.assertIn("INSERT INTO memo_like", insert.args[0])
        self.assertEqual(update.args[1], memo.args[1])
        self.assertIn("likes = COALESCE(likes, 0) + 1", update.args[0])
        self.assertNotIn("memo_updated_at", update.args[0])
        self.db.commit.assert_called_once()
        self.db.rollback.assert_not_called()
        self.db.close.assert_called_once()

    def test_repeated_like_returns_success_without_inserting_or_incrementing(self):
        self.cursor.fetchone.side_effect = [{"participate_seq": 1}, {"likes": 4}, {"1": 1}]
        response = self.like()
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["likes"], 4)
        self.assertTrue(response.json()["already_liked"])
        self.assertEqual(self.cursor.execute.call_count, 3)
        self.db.commit.assert_called_once()
        self.db.close.assert_called_once()

    def test_author_can_like_their_own_memo(self):
        self.payload["author_user_id"] = "liker-a"
        self.assertEqual(self.like().status_code, 200)
        self.assertEqual(self.cursor.execute.call_args_list[3].args[1],
                         ("memo-1", "room-a", "liker-a", "liker-a"))

    def test_nonmember_or_missing_deleted_or_other_room_memo_is_denied(self):
        for rows, status, queries in (([None], 403, 1),
                                     ([{"participate_seq": 1}, None], 404, 2)):
            with self.subTest(status=status):
                self.db.reset_mock()
                self.cursor.fetchone.side_effect = rows
                self.assertEqual(self.like().status_code, status)
                self.assertEqual(self.cursor.execute.call_count, queries)
                self.db.commit.assert_not_called()
                self.db.rollback.assert_called_once()
                self.db.close.assert_called_once()

    def test_invalid_input_cannot_spoof_liker_or_count(self):
        invalid = ({}, {"family_room_id": "room-a"},
                   {**self.payload, "family_room_id": " "},
                   {**self.payload, "author_user_id": "a" * 51},
                   {**self.payload, "author_user_id": None},
                   {**self.payload, "user_id": "forged"},
                   {**self.payload, "likes": 100},
                   {**self.payload, "is_liked": False})
        for payload in invalid:
            with self.subTest(fields=list(payload)):
                self.assertEqual(self.like(payload).status_code, 422)
        for identifier in ("x" * 51, "%20"):
            self.assertEqual(self.like(memo_id=identifier).status_code, 422)
        self.connect.assert_not_called()

    def test_missing_or_invalid_token_never_connects(self):
        app.dependency_overrides.pop(get_current_user_id)
        self.assertEqual(self.like().status_code, 401)
        with patch("python.features.auth.firebase_auth.verify_firebase_token",
                   side_effect=HTTPException(401, "invalid token")):
            response = self.client.post("/memos/like/memo-1", json=self.payload,
                                        headers={"Authorization": "Bearer invalid"})
        self.assertEqual(response.status_code, 401)
        self.connect.assert_not_called()

    def test_verified_firebase_user_becomes_liker(self):
        app.dependency_overrides.pop(get_current_user_id)
        auth_db = MagicMock()
        auth_db.cursor.return_value.__enter__.return_value.fetchone.return_value = {
            "user_id": "verified-liker", "withdrawn_at": None,
        }
        self.connect.side_effect = [auth_db, self.db]
        with patch("python.features.auth.firebase_auth.verify_firebase_token", return_value={"uid": "verified-uid"}):
            response = self.client.post("/memos/like/memo-1", json=self.payload,
                                        headers={"Authorization": "Bearer valid"})
        self.assertEqual(response.status_code, 200)
        self.assertEqual(self.cursor.execute.call_args_list[3].args[1][-1], "verified-liker")
        auth_db.close.assert_called_once()

    def test_failure_at_each_stage_rolls_back_and_hides_details(self):
        for stage in ("connect", "membership", "memo", "existing", "insert", "update", "commit"):
            with self.subTest(stage=stage):
                self.db.reset_mock()
                self.cursor.fetchone.side_effect = [{"participate_seq": 1}, {"likes": 0}, None]
                self.cursor.execute.side_effect = None
                self.db.commit.side_effect = None
                self.connect.side_effect = None
                error = pymysql.OperationalError(2006, "private database details")
                if stage == "connect":
                    self.connect.side_effect = error
                elif stage == "commit":
                    self.db.commit.side_effect = error
                else:
                    position = ("membership", "memo", "existing", "insert", "update").index(stage)
                    self.cursor.execute.side_effect = [None] * position + [error]
                with self.assertLogs("python.features.memos.router", level="ERROR"):
                    response = self.like()
                self.assertEqual(response.status_code, 500)
                self.assertNotIn("private database details", response.text)
                if stage != "connect":
                    self.db.rollback.assert_called_once()
                    self.db.close.assert_called_once()

    def test_list_returns_current_users_like_state(self):
        self.cursor.fetchone.side_effect = [{"participate_seq": 1}]
        self.cursor.fetchall.return_value = [{"memo_id": "memo-1", "likes": 1, "is_liked": 1}]
        response = self.client.get("/memos/select?family_room_id=room-a")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["results"][0]["is_liked"], 1)
        sql, values = self.cursor.execute.call_args.args
        self.assertIn("ml.memo_author_id = m.user_id AND ml.user_id = %s", sql)
        self.assertEqual(values, ("liker-a", "room-a", 20, 0))

    def test_no_like_cancellation_or_toggle_endpoint(self):
        for method in ("DELETE", "PATCH", "PUT"):
            response = self.client.request(method, "/memos/like/memo-1", json=self.payload)
            self.assertEqual(response.status_code, 405)
        self.connect.assert_not_called()


if __name__ == "__main__":
    unittest.main()
