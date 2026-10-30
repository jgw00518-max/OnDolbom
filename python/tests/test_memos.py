"""실제 DB 없이 메모 인증 연결·공간 권한·연결 정리를 확인한다."""

import unittest
from datetime import datetime
from unittest.mock import MagicMock, patch
from uuid import UUID

import pymysql
from fastapi.testclient import TestClient

from python.features.memos.router import get_current_user_id
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
                headers={"X-User-Id": "user-a"},
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
            {**valid, "memo_content": "가" * 2001},
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
             "user_id": "another-member", "author_name": "김가족", "memo_content": "산책 완료",
             "likes": 0, "written_at": datetime(2026, 10, 23, 10, 0),
             "memo_updated_at": None}
        ]
        with patch("python.features.memos.router.connect", return_value=self.db):
            response = self.client.get(
                "/memos/select?family_room_id=room-a&limit=10&offset=20"
            )
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["results"][0]["user_id"], "another-member")
        self.assertEqual(response.json()["results"][0]["author_name"], "김가족")
        self.assertEqual(
            response.json()["results"][0]["written_at"], "2026-10-23T10:00:00"
        )
        self.assertEqual(
            self.cursor.execute.call_args.args[1], ("user-a", "room-a", 10, 20)
        )
        self.assertEqual(self.cursor.execute.call_count, 2)
        sql = self.cursor.execute.call_args.args[0]
        self.assertIn("m.family_room_id = %s", sql)
        self.assertIn("m.memo_deleted_at IS NULL", sql)
        self.assertIn("f.family_room_deleted_at IS NULL", sql)
        self.assertIn("LEFT JOIN `user` AS u ON u.user_id = m.user_id", sql)
        self.assertIn("u.name AS author_name", sql)
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


class MemoMutationTests(unittest.TestCase):
    def setUp(self):
        self.client = TestClient(app)
        self.addCleanup(self.client.close)
        self.db = MagicMock()
        self.cursor = self.db.cursor.return_value.__enter__.return_value
        self.cursor.fetchone.return_value = {"participate_seq": 1}
        self.cursor.fetchall.return_value = [{"user_id": "user-a"}]
        app.dependency_overrides[get_current_user_id] = lambda: "user-a"
        self.addCleanup(app.dependency_overrides.pop, get_current_user_id, None)

    def request(self, operation):
        if operation == "update":
            return self.client.patch("/memos/update/memo-1", json={
                "family_room_id": "room-a", "memo_content": "  수정된 내용  ",
            }, headers={"X-User-Id": "forged"})
        return self.client.delete(
            "/memos/delete/memo-1?family_room_id=room-a&user_id=forged",
            headers={"X-User-Id": "forged"},
        )

    def test_author_can_update_or_soft_delete(self):
        for operation in ("update", "delete"):
            with self.subTest(operation=operation), patch(
                "python.features.memos.router.connect", return_value=self.db,
            ):
                self.db.reset_mock()
                response = self.request(operation)
                self.assertEqual(response.status_code, 200)
                self.assertEqual(response.json(), {"result": "OK", "memo_id": "memo-1"})
                membership, lookup, mutation = self.cursor.execute.call_args_list
                self.assertEqual(membership.args[1], ("room-a", "user-a"))
                for condition in ("p.is_active = 1", "p.left_at IS NULL",
                                  "f.family_room_deleted_at IS NULL",
                                  "u.withdrawn_at IS NULL", "FOR UPDATE"):
                    self.assertIn(condition, membership.args[0])
                self.assertEqual(lookup.args[1], ("memo-1", "room-a"))
                self.assertIn("memo_deleted_at IS NULL", lookup.args[0])
                self.assertIn("FOR UPDATE", lookup.args[0])
                self.assertIn("user_id = %s", mutation.args[0])
                self.assertIn("memo_deleted_at IS NULL", mutation.args[0])
                if operation == "update":
                    self.assertEqual(mutation.args[1], ("수정된 내용", "memo-1", "room-a", "user-a"))
                    self.assertIn("memo_updated_at = CURRENT_TIMESTAMP", mutation.args[0])
                    self.assertNotIn("written_at =", mutation.args[0])
                    self.assertNotIn("likes =", mutation.args[0])
                else:
                    self.assertEqual(mutation.args[1], ("memo-1", "room-a", "user-a"))
                    self.assertIn("SET memo_deleted_at = CURRENT_TIMESTAMP", mutation.args[0])
                self.db.commit.assert_called_once()
                self.db.rollback.assert_not_called()
                self.db.close.assert_called_once()

    def test_unauthenticated_mutations_do_not_connect(self):
        app.dependency_overrides.pop(get_current_user_id)
        with patch("python.features.memos.router.connect") as connect:
            for operation in ("update", "delete"):
                self.assertEqual(self.request(operation).status_code, 401)
            connect.assert_not_called()

    def test_nonmember_other_author_and_missing_memo_cannot_mutate(self):
        cases = (
            (None, [{"user_id": "user-a"}], 403, 1),
            ({"participate_seq": 1}, [{"user_id": "other-user"}], 403, 2),
            # 다른 공간의 메모·삭제된 메모도 이 조회에서 제외된다.
            ({"participate_seq": 1}, [], 404, 2),
        )
        for operation in ("update", "delete"):
            for membership, memos, status, query_count in cases:
                with self.subTest(operation=operation, status=status, membership=membership), patch(
                    "python.features.memos.router.connect", return_value=self.db,
                ):
                    self.db.reset_mock()
                    self.cursor.fetchone.return_value = membership
                    self.cursor.fetchall.return_value = memos
                    self.assertEqual(self.request(operation).status_code, status)
                    self.assertEqual(self.cursor.execute.call_count, query_count)
                    self.db.commit.assert_not_called()
                    self.db.rollback.assert_called_once()
                    self.db.close.assert_called_once()

    def test_invalid_update_and_delete_inputs_do_not_connect(self):
        valid = {"family_room_id": "room-a", "memo_content": "메모"}
        invalid = (
            {}, {"family_room_id": "room-a"},
            {**valid, "family_room_id": " "},
            {**valid, "family_room_id": "a" * 51},
            {**valid, "memo_content": " \n\t "},
            {**valid, "memo_content": None},
            {**valid, "memo_content": "가" * 2001},
            {**valid, "user_id": "other-user"},
            {**valid, "likes": 100},
        )
        with patch("python.features.memos.router.connect") as connect:
            for payload in invalid:
                with self.subTest(payload_keys=list(payload)):
                    self.assertEqual(self.client.patch(
                        "/memos/update/memo-1", json=payload,
                    ).status_code, 422)
            for query in ("", "?family_room_id=", "?family_room_id=%20", "?family_room_id=" + "a" * 51):
                self.assertEqual(self.client.delete("/memos/delete/memo-1" + query).status_code, 422)
            for identifier in ("a" * 51, "%20"):
                self.assertEqual(self.client.patch(
                    f"/memos/update/{identifier}", json=valid,
                ).status_code, 422)
                self.assertEqual(self.client.delete(
                    f"/memos/delete/{identifier}?family_room_id=room-a",
                ).status_code, 422)
            connect.assert_not_called()

    def test_database_failures_roll_back_and_hide_details(self):
        for operation in ("update", "delete"):
            # 연결·참여 조회·메모 조회·변경·commit 실패를 각각 검증한다.
            for stage in ("connect", "membership", "lookup", "mutation", "commit"):
                with self.subTest(operation=operation, stage=stage):
                    self.db.reset_mock(return_value=False, side_effect=True)
                    self.cursor.execute.side_effect = None
                    self.db.commit.side_effect = None
                    error = pymysql.OperationalError(2006, "private database details")
                    if stage in ("membership", "lookup", "mutation"):
                        position = ("membership", "lookup", "mutation").index(stage)
                        self.cursor.execute.side_effect = [None] * position + [error]
                    elif stage == "commit":
                        self.db.commit.side_effect = error
                    with patch("python.features.memos.router.connect", **(
                        {"side_effect": error} if stage == "connect" else {"return_value": self.db}
                    )), self.assertLogs("python.features.memos.router", level="ERROR"):
                        response = self.request(operation)
                    self.assertEqual(response.status_code, 500)
                    self.assertNotIn("private database details", response.text)
                    if stage != "connect":
                        self.db.rollback.assert_called_once()
                        self.db.close.assert_called_once()


if __name__ == "__main__":
    unittest.main()
