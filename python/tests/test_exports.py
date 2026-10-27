"""실제 DB·Firebase 없이 ZIP 내용, 권한, 조회 범위, 자원 정리를 검증한다."""

import asyncio
from datetime import datetime
from io import BytesIO
from tempfile import TemporaryFile
import unittest
from unittest.mock import MagicMock, patch
from zipfile import ZipFile

import pymysql
from fastapi import HTTPException
from fastapi.testclient import TestClient
from PIL import Image

from python.features.exports import router as exports
from python.main import app


PAYLOAD = {"family_room_id": "room-a", "start_date": "2026-10-01", "end_date": "2026-10-27"}
ROOM = {"participate_seq": 1, "care_recipient_name": "김가족", "snapshot_at": datetime(2026, 10, 27, 12)}


def record(**changes):
    return {"content": "한글 메모 😀\n두 번째 줄", "recorded_at": datetime(2026, 10, 1),
            "updated_at": None, "author_name": "가족", "has_image": 0, **changes}


def image_bytes():
    output = BytesIO()
    Image.new("RGB", (2, 2), "red").save(output, format="JPEG")
    return output.getvalue()


class ExportTests(unittest.TestCase):
    def setUp(self):
        self.client = self.enterContext(TestClient(app))
        self.addCleanup(app.dependency_overrides.clear)
        app.dependency_overrides[exports.get_current_user_id] = lambda: "user-a"
        self.db = MagicMock()
        self.cursor = self.db.cursor.return_value.__enter__.return_value
        self.cursor.fetchone.return_value = ROOM
        self.cursor.__iter__.side_effect = lambda: iter([record()])
        self.connect = self.enterContext(patch.object(exports, "connect", return_value=self.db))
        self.files = []

        def create_file(*args, **kwargs):
            output = TemporaryFile(*args, **kwargs)
            self.files.append(output)
            return output

        self.enterContext(patch.object(exports, "TemporaryFile", side_effect=create_file))

    def request(self, **changes):
        return self.client.post("/exports/download", json={**PAYLOAD, **changes})

    def test_registered_download_returns_offline_zip_and_closes_resources(self):
        response = self.request()
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.headers["content-type"], "application/zip")
        self.assertEqual(int(response.headers["content-length"]), len(response.content))
        self.assertIn("ondolbom_20261001_20261027.zip", response.headers["content-disposition"])
        self.assertEqual(response.headers["cache-control"], "private, no-store")
        with ZipFile(BytesIO(response.content)) as archive:
            self.assertIsNone(archive.testzip())
            self.assertEqual(set(archive.namelist()), {"index.html", "memos.html", "chats.html"})
            self.assertIn("한글 메모 😀\n두 번째 줄", archive.read("memos.html").decode())
            index = archive.read("index.html").decode()
            self.assertIn("메모</a>: 1건", index)
            self.assertIn("투약 정보·투약일지 데이터는 포함하지 않습니다", index)
        self.db.commit.assert_not_called()
        self.db.rollback.assert_called()
        self.db.close.assert_called_once()
        self.assertTrue(self.files[0].closed)

    def test_missing_token_and_forged_header_cannot_connect(self):
        app.dependency_overrides.clear()
        response = self.client.post("/exports/download", json=PAYLOAD, headers={"X-User-Id": "forged"})
        self.assertEqual(response.status_code, 401)
        self.connect.assert_not_called()

    def test_auth_maps_exact_firebase_uid_and_rejects_withdrawn_user(self):
        self.cursor.fetchone.return_value = {"user_id": "user-a", "withdrawn_at": None}
        self.assertEqual(exports.get_current_user_id({"uid": "verified-UID"}), "user-a")
        sql, params = self.cursor.execute.call_args.args
        self.assertIn("BINARY user_firebase_uid", sql)
        self.assertEqual(params, ("verified-UID", "verified-UID"))
        for user in (None, {"user_id": "user-a", "withdrawn_at": datetime.now()}):
            self.cursor.fetchone.return_value = user
            with self.assertRaises(HTTPException) as caught:
                exports.get_current_user_id({"uid": "verified-UID"})
            self.assertEqual(caught.exception.status_code, 403)

    def test_nonmember_rejected_before_reading_records_or_creating_file(self):
        self.cursor.fetchone.return_value = None
        self.assertEqual(self.request().status_code, 403)
        self.assertEqual(self.files, [])
        self.assertFalse(any("FROM memo" in call.args[0] for call in self.cursor.execute.call_args_list))
        self.db.rollback.assert_called_once()
        self.db.close.assert_called_once()

    def test_current_member_check_supports_both_roles_and_rechecks_after_snapshot(self):
        self.assertEqual(self.request().status_code, 200)
        calls = self.cursor.execute.call_args_list
        memberships = [call for call in calls if "FROM participate" in call.args[0]]
        self.assertEqual(len(memberships), 2)
        for call in memberships:
            for condition in ("p.is_active = 1", "p.left_at IS NULL", "f.family_room_deleted_at IS NULL", "u.withdrawn_at IS NULL"):
                self.assertIn(condition, call.args[0])
            self.assertNotIn("is_representative", call.args[0])
            self.assertEqual(call.args[1], ("room-a", "user-a"))
        self.assertIn("REPEATABLE READ", calls[0].args[0])
        self.assertIn("CONSISTENT SNAPSHOT, READ ONLY", calls[1].args[0])

    def test_revoked_membership_after_generation_does_not_send_archive(self):
        self.cursor.fetchone.side_effect = [ROOM, None]
        response = self.request()
        self.assertEqual(response.status_code, 403)
        self.assertNotIn("PK", response.text)
        self.assertTrue(self.files[0].closed)

    def test_period_uses_exclusive_next_midnight_and_only_selected_scope(self):
        self.assertEqual(self.request(scopes=["memos"]).status_code, 200)
        queries = [call for call in self.cursor.execute.call_args_list if "FROM memo AS m" in call.args[0]]
        self.assertEqual(len(queries), 1)
        sql, params = queries[0].args
        self.assertEqual(params, ("room-a", datetime(2026, 10, 1), datetime(2026, 10, 28)))
        self.assertIn("m.written_at >= %s AND m.written_at < %s", sql)
        self.assertIn("m.memo_deleted_at IS NULL", sql)
        self.assertIn("ORDER BY m.written_at ASC, m.memo_id ASC, m.user_id ASC", sql)
        all_sql = " ".join(call.args[0] for call in self.cursor.execute.call_args_list)
        self.assertNotIn("FROM live_chat", all_sql)
        self.assertNotIn("medication", all_sql.lower())
        self.assertTrue(any(call.args == (pymysql.cursors.SSDictCursor,) for call in self.db.cursor.call_args_list))

    def test_chats_only_and_same_day_range(self):
        response = self.request(scopes=["chats"], start_date="2026-10-27")
        self.assertEqual(response.status_code, 200)
        with ZipFile(BytesIO(response.content)) as archive:
            self.assertEqual(set(archive.namelist()), {"index.html", "chats.html"})
        query = next(call for call in self.cursor.execute.call_args_list if "FROM live_chat" in call.args[0])
        self.assertEqual(query.args[1], ("room-a", datetime(2026, 10, 27), datetime(2026, 10, 28)))
        self.assertIn("CASE WHEN c.live_chat_deleted_at IS NULL THEN c.chat_content ELSE NULL END", query.args[0])

    def test_excluding_images_omits_blob_select_and_keeps_attachment_notice(self):
        self.cursor.__iter__.side_effect = lambda: iter([record(has_image=1)])
        response = self.request()
        self.assertEqual(response.status_code, 200)
        all_sql = " ".join(call.args[0] for call in self.cursor.execute.call_args_list)
        self.assertNotIn(" AS image", all_sql)
        self.assertIn("(m.memo_image IS NOT NULL) AS has_image", all_sql)
        with ZipFile(BytesIO(response.content)) as archive:
            self.assertFalse(any(name.startswith("images/") for name in archive.namelist()))
            self.assertIn("이미지 첨부됨", archive.read("memos.html").decode())

    def test_including_images_embeds_bytes_and_deleted_chat_never_leaks(self):
        picture = image_bytes()
        self.cursor.__iter__.side_effect = lambda: iter([
            record(has_image=1, image=picture),
            record(is_deleted=1, has_image=1, image=b"deleted-image-secret", content="deleted-text-secret"),
        ])
        response = self.request(scopes=["chats"], include_images=True)
        self.assertEqual(response.status_code, 200)
        with ZipFile(BytesIO(response.content)) as archive:
            self.assertEqual(archive.read("images/chats_1.jpg"), picture)
            self.assertNotIn("images/chats_2.jpg", archive.namelist())
            html = archive.read("chats.html").decode()
            self.assertIn("삭제된 메시지입니다.", html)
            self.assertNotIn("deleted-text-secret", html)
        sql = next(call.args[0] for call in self.cursor.execute.call_args_list if "FROM live_chat" in call.args[0])
        self.assertIn("CASE WHEN c.live_chat_deleted_at IS NULL THEN c.chat_image ELSE NULL END AS image", sql)

    def test_html_escapes_user_text_author_and_space_name(self):
        self.cursor.fetchone.return_value = {**ROOM, "care_recipient_name": '<script>alert("room")</script>'}
        self.cursor.__iter__.side_effect = lambda: iter([record(content='<script>alert("text")</script>', author_name='<img src=x onerror=alert(1)>')])
        response = self.request(scopes=["memos"])
        with ZipFile(BytesIO(response.content)) as archive:
            for name in ("index.html", "memos.html"):
                html = archive.read(name).decode()
                self.assertNotIn("<script>", html)
                self.assertIn("&lt;script&gt;", html)
            self.assertIn("&lt;img", archive.read("memos.html").decode())

    def test_empty_period_still_returns_valid_archive(self):
        self.cursor.__iter__.side_effect = lambda: iter([])
        response = self.request()
        self.assertEqual(response.status_code, 200)
        with ZipFile(BytesIO(response.content)) as archive:
            self.assertIn("선택한 기간에 기록이 없습니다", archive.read("chats.html").decode())
            self.assertIn("0건", archive.read("index.html").decode())

    def test_invalid_requests_do_not_open_database(self):
        invalid = [
            {"start_date": "2026-10-28"}, {"end_date": "9999-12-31"},
            {"start_date": "0999-12-31"}, {"end_date": "bad"}, {"family_room_id": " "},
            {"scopes": []}, {"scopes": ["memos", "memos"]}, {"scopes": ["medications"]},
            {"format": "docx"}, {"user_id": "forged"}, {"role": "representative"},
        ]
        for change in invalid:
            with self.subTest(change=change):
                self.assertEqual(self.request(**change).status_code, 422)
        self.connect.assert_not_called()

    def test_database_failure_returns_safe_error_and_closes_connection(self):
        self.cursor.__iter__.side_effect = pymysql.OperationalError(2006, "private-details")
        with self.assertLogs(exports.logger, level="ERROR"):
            response = self.request()
        self.assertEqual(response.status_code, 503)
        self.assertNotIn("private-details", response.text)
        self.assertTrue(self.files[0].closed)
        self.db.rollback.assert_called_once()
        self.db.close.assert_called_once()

    def test_corrupt_image_aborts_entire_file_and_cleans_up(self):
        self.cursor.__iter__.side_effect = lambda: iter([record(has_image=1, image=b"broken")])
        with self.assertLogs(exports.logger, level="ERROR"):
            response = self.request(include_images=True)
        self.assertEqual(response.status_code, 500)
        self.assertIn("이미지를 제외하고", response.json()["detail"])
        self.assertTrue(self.files[0].closed)

    def test_disk_failure_returns_safe_error_and_closes_connection(self):
        with patch.object(exports, "TemporaryFile", side_effect=OSError("private-path")), self.assertLogs(exports.logger, level="ERROR"):
            response = self.request()
        self.assertEqual(response.status_code, 500)
        self.assertNotIn("private-path", response.text)
        self.db.rollback.assert_called_once()
        self.db.close.assert_called_once()

    def test_auth_database_failure_is_unavailable_and_closes(self):
        self.cursor.execute.side_effect = pymysql.OperationalError(2006, "private-details")
        with self.assertRaises(HTTPException) as caught:
            exports.get_current_user_id({"uid": "verified-UID"})
        self.assertEqual(caught.exception.status_code, 503)
        self.assertNotIn("private-details", caught.exception.detail)
        self.db.close.assert_called_once()

    def test_retry_generates_again_without_database_writes(self):
        for _ in range(2):
            self.assertEqual(self.request().status_code, 200)
        self.assertEqual(len(self.files), 2)
        self.assertTrue(all(output.closed for output in self.files))
        for call in self.cursor.execute.call_args_list:
            self.assertFalse(call.args[0].lstrip().upper().startswith(("INSERT", "UPDATE", "DELETE", "CREATE", "ALTER")))

    def test_stream_failure_also_closes_temporary_file(self):
        output = TemporaryFile(mode="w+b")
        output.write(b"test")
        response = exports.ExportResponse(output, "test.zip")

        async def send(message):
            raise OSError("disconnected")

        async def receive():
            return {"type": "http.disconnect"}

        with self.assertRaises(Exception):
            asyncio.run(response({"type": "http", "asgi": {"spec_version": "2.4"}}, receive, send))
        self.assertTrue(output.closed)


if __name__ == "__main__":
    unittest.main()
