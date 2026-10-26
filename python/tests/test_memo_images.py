"""실제 DB 변경 없이 메모 단일 이미지와 원자적 저장·접근 권한을 검증한다."""
from io import BytesIO
import unittest
from unittest.mock import MagicMock, patch

from fastapi.testclient import TestClient
from PIL import Image
import pymysql

from python.features.memos.images import MAX_IMAGE_BYTES
from python.features.memos.router import get_current_user_id
from python.main import app


def photo():
    output = BytesIO()
    Image.new("RGBA", (4, 3), (255, 0, 0, 128)).save(output, "PNG")
    return output.getvalue()


class MemoImageTests(unittest.TestCase):
    def setUp(self):
        self.client = TestClient(app)
        self.addCleanup(self.client.close)
        self.db = MagicMock()
        self.cursor = self.db.cursor.return_value.__enter__.return_value
        self.cursor.fetchone.return_value = {"participate_seq": 1}
        self.cursor.fetchall.return_value = [{"user_id": "user-a"}]
        app.dependency_overrides[get_current_user_id] = lambda: "user-a"
        self.addCleanup(app.dependency_overrides.pop, get_current_user_id, None)
        self.connect = self.enterContext(patch("python.features.memos.router.connect", return_value=self.db))

    def save(self, operation="insert", files=None, **fields):
        data = {"family_room_id": "room-a", "memo_content": "  사진과 내용  ", **fields}
        method, path = ("POST", "/memos/insert-with-image") if operation == "insert" else (
            "PATCH", "/memos/update-with-image/memo-1")
        return self.client.request(method, path, data=data, files=files)

    def test_insert_and_replace_save_text_and_one_normalized_image_in_one_commit(self):
        for operation in ("insert", "update"):
            with self.subTest(operation=operation):
                self.db.reset_mock()
                response = self.save(operation, files={"image": ("photo.png", photo(), "image/png")})
                self.assertEqual(response.status_code, 201 if operation == "insert" else 200)
                sql, params = self.cursor.execute.call_args.args
                self.assertIn("memo_image", sql)
                self.assertIn("사진과 내용", params)
                data = next(value for value in params if isinstance(value, bytes))
                with Image.open(BytesIO(data)) as image:
                    self.assertEqual(image.format, "JPEG")
                    self.assertEqual(image.size, (4, 3))
                    self.assertEqual(dict(image.getexif()), {})
                self.db.commit.assert_called_once()
                self.db.rollback.assert_not_called()
                self.db.close.assert_called_once()

    def test_update_can_keep_or_remove_existing_image(self):
        for remove in (False, True):
            with self.subTest(remove=remove):
                self.db.reset_mock()
                response = self.save("update", remove_image=str(remove).lower())
                self.assertEqual(response.status_code, 200)
                sql, params = self.cursor.execute.call_args.args
                if remove:
                    self.assertIn("memo_image = %s", sql)
                    self.assertIsNone(params[1])
                else:
                    self.assertNotIn("memo_image", sql)
                self.db.commit.assert_called_once()

    def test_swagger_exposes_optional_single_binary_file_for_insert_and_update(self):
        schema = self.client.get("/openapi.json").json()
        for path, method in (("/memos/insert-with-image", "post"),
                             ("/memos/update-with-image/{memo_id}", "patch")):
            with self.subTest(path=path):
                body = schema["paths"][path][method]["requestBody"]["content"]["multipart/form-data"]["schema"]
                model = schema["components"]["schemas"][body["$ref"].split("/")[-1]]
                field = model["properties"]["image"]
                self.assertEqual(field["type"], "string")
                self.assertEqual(field["format"], "binary")
                self.assertNotIn("anyOf", field)
                self.assertNotIn("items", field)
                self.assertNotIn("image", model.get("required", []))

    def test_both_upload_routes_reject_repeated_image_fields(self):
        for operation in ("insert", "update"):
            with self.subTest(operation=operation):
                response = self.save(operation, files=[
                    ("image", ("a.png", photo(), "image/png")),
                    ("image", ("b.png", photo(), "image/png")),
                ])
                self.assertEqual(response.status_code, 422)
                self.assertEqual(response.json()["detail"], "이미지는 한 장만 첨부할 수 있습니다.")
        self.connect.assert_not_called()

    def test_rejects_multiple_invalid_oversized_images_and_conflicting_removal(self):
        invalid = [
            ({"image": ("fake.jpg", b"not an image", "image/jpeg")}, {}, 422),
            ({"image": ("empty.jpg", b"", "image/jpeg")}, {}, 422),
            ([ ("image", ("a.png", photo(), "image/png")),
               ("image", ("b.png", photo(), "image/png")) ], {}, 422),
            ({"image": ("large.jpg", b"x" * (MAX_IMAGE_BYTES + 1), "image/jpeg")}, {}, 413),
            ({"image": ("a.png", photo(), "image/png")}, {"remove_image": "true"}, 422),
            ({"image": ("a.png", photo(), "image/png")}, {"memo_content": "   "}, 422),
        ]
        for files, fields, expected in invalid:
            with self.subTest(expected=expected, fields=fields):
                response = self.save("update", files=files, **fields)
                self.assertEqual(response.status_code, expected, response.text)
        self.connect.assert_not_called()

    def test_rejects_excessive_dimensions(self):
        with patch("python.features.memos.images.MAX_IMAGE_PIXELS", 5):
            response = self.save(files={"image": ("a.png", photo(), "image/png")})
        self.assertEqual(response.status_code, 422)
        self.connect.assert_not_called()

    def test_upload_requires_auth_membership_and_ownership(self):
        self.cursor.fetchone.return_value = None
        self.assertEqual(self.save(files={"image": ("a.png", photo())}).status_code, 403)
        self.cursor.fetchone.return_value = {"participate_seq": 1}
        self.cursor.fetchall.return_value = [{"user_id": "other-user"}]
        self.assertEqual(self.save("update", files={"image": ("a.png", photo())}).status_code, 403)
        self.cursor.fetchall.return_value = []
        self.assertEqual(self.save("update", files={"image": ("a.png", photo())}).status_code, 404)
        self.db.commit.assert_not_called()
        app.dependency_overrides.pop(get_current_user_id)
        self.connect.reset_mock()
        self.assertEqual(self.save(files={"image": ("a.png", photo())}).status_code, 401)
        self.assertEqual(self.client.get(
            "/memos/image/memo-1?family_room_id=room-a&author_user_id=user-a").status_code, 401)
        self.connect.assert_not_called()

    def test_image_read_checks_room_and_composite_memo_identity(self):
        data = photo()
        self.cursor.fetchone.side_effect = [{"1": 1}, {"memo_image": data}]
        response = self.client.get("/memos/image/memo-1?family_room_id=room-a&author_user_id=other-user")
        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.content, data)
        self.assertEqual(response.headers["content-type"], "image/png")
        self.assertEqual(response.headers["cache-control"], "private, no-store")
        membership, lookup = self.cursor.execute.call_args_list
        self.assertEqual(membership.args[1], ("room-a", "user-a"))
        self.assertEqual(lookup.args[1], ("memo-1", "room-a", "other-user"))
        self.assertIn("m.memo_deleted_at IS NULL", lookup.args[0])
        self.assertIn("f.family_room_deleted_at IS NULL", lookup.args[0])
        self.db.close.assert_called_once()

    def test_image_read_rejects_nonmembers_missing_and_deleted_images(self):
        for rows, status in (([None], 403), ([{"1": 1}, None], 404),
                             ([{"1": 1}, {"memo_image": None}], 404)):
            with self.subTest(status=status):
                self.db.reset_mock()
                self.cursor.fetchone.side_effect = rows
                response = self.client.get("/memos/image/memo-1?family_room_id=room-a&author_user_id=user-a")
                self.assertEqual(response.status_code, status)
                self.db.close.assert_called_once()

    def test_image_write_or_commit_failure_rolls_back_text_and_image(self):
        for operation in ("insert", "update"):
            for stage in ("write", "commit"):
                with self.subTest(operation=operation, stage=stage):
                    self.db.reset_mock()
                    self.cursor.execute.side_effect = None
                    self.db.commit.side_effect = None
                    error = pymysql.OperationalError(2006, "private database details")
                    if stage == "write":
                        self.cursor.execute.side_effect = [None] * (1 if operation == "insert" else 2) + [error]
                    else:
                        self.db.commit.side_effect = error
                    with self.assertLogs("python.features.memos.router", level="ERROR"):
                        response = self.save(operation, files={"image": ("a.png", photo())})
                    self.assertEqual(response.status_code, 500)
                    self.assertNotIn("private database details", response.text)
                    self.db.rollback.assert_called_once()
                    self.db.close.assert_called_once()

    def test_list_only_returns_image_presence_without_blob(self):
        self.cursor.fetchall.return_value = [{"memo_id": "memo-1", "has_image": 1}]
        response = self.client.get("/memos/select?family_room_id=room-a")
        self.assertEqual(response.json()["results"][0]["has_image"], 1)
        sql = self.cursor.execute.call_args.args[0]
        self.assertIn("(m.memo_image IS NOT NULL) AS has_image", sql)
        self.assertNotIn("m.memo_image,", sql)


if __name__ == "__main__":
    unittest.main()
