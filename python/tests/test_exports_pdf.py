"""실제 PDF를 열어 한글·페이지 분할·이미지·권한과 기존 조회 계약을 확인한다."""

from io import BytesIO
from tempfile import TemporaryFile
import unittest
from unittest.mock import MagicMock, patch

import pymysql
from fastapi.testclient import TestClient
from pypdf import PdfReader

from python.features.exports import pdf_generator, router as exports
from python.main import app
from python.tests.test_exports import PAYLOAD, ROOM, image_bytes, record


class PdfExportTests(unittest.TestCase):
    def setUp(self):
        self.client = self.enterContext(TestClient(app))
        self.addCleanup(app.dependency_overrides.clear)
        app.dependency_overrides[exports.get_current_user_id] = lambda: "user-a"
        self.db = MagicMock()
        self.cursor = self.db.cursor.return_value.__enter__.return_value
        self.cursor.fetchone.return_value = ROOM
        self.cursor.__iter__.side_effect = lambda: iter([record()])
        self.connect = self.enterContext(patch.object(exports, "connect", return_value=self.db))
        self.outputs = []

        def temporary(*args, **kwargs):
            output = TemporaryFile(*args, **kwargs)
            self.outputs.append(output)
            return output

        self.enterContext(patch.object(exports, "TemporaryFile", side_effect=temporary))

    def request(self, **changes):
        return self.client.post("/exports/download", json={**PAYLOAD, "format": "pdf", **changes})

    def pdf(self, **changes):
        response = self.request(**changes)
        self.assertEqual(response.status_code, 200, response.content[:500])
        self.assertEqual(response.headers["content-type"], "application/pdf")
        self.assertTrue(response.content.startswith(b"%PDF-"))
        self.assertIn("ondolbom_20261001_20261027.pdf", response.headers["content-disposition"])
        self.assertEqual(int(response.headers["content-length"]), len(response.content))
        self.assertEqual(response.headers["cache-control"], "private, no-store")
        self.assertTrue(self.outputs[-1].closed)
        return PdfReader(BytesIO(response.content))

    @staticmethod
    def text(reader):
        return "\n".join(page.extract_text() for page in reader.pages)

    @staticmethod
    def images(reader):
        return [obj.get_object() for page in reader.pages
                for obj in page["/Resources"].get("/XObject", {}).values()
                if obj.get_object().get("/Subtype") == "/Image"]

    def test_pdf_contains_korean_metadata_and_records_and_embeds_fonts(self):
        reader = self.pdf()
        text = self.text(reader)
        for expected in ("김가족", "2026-10-01", "2026-10-27", "한글 메모", "두 번째 줄", "메모 총 1건", "채팅 총 1건", "투약 정보·투약일지"):
            self.assertIn(expected, text)
        embedded = 0
        for font_ref in reader.pages[0]["/Resources"]["/Font"].values():
            font = font_ref.get_object()
            if "/FontDescriptor" in font:
                self.assertIn("/FontFile2", font["/FontDescriptor"])
                embedded += 1
        self.assertGreaterEqual(embedded, 2)
        self.assertIn("[U+1F600]", text)
        self.db.commit.assert_not_called()
        self.db.close.assert_called_once()

    def test_long_text_and_blank_lines_flow_across_pages(self):
        content = "첫 줄\n\n" + ("한글이 길어져도 줄바꿈과 페이지 분할이 되어야 합니다. " * 250) + "\n마지막 문장"
        self.cursor.__iter__.side_effect = lambda: iter([record(content=content)])
        reader = self.pdf(scopes=["memos"])
        self.assertGreater(len(reader.pages), 1)
        self.assertIn("마지막 문장", self.text(reader))
        self.assertNotIn("채팅 총", self.text(reader))
        for index, page in enumerate(reader.pages, 1):
            self.assertIn(f"{index} 페이지", page.extract_text())

    def test_guide_memos_and_chats_start_on_separate_pages_with_bookmarks(self):
        reader = self.pdf()
        self.assertEqual(len(reader.pages), 3)
        pages = [page.extract_text() for page in reader.pages]
        self.assertIn("01  안내", pages[0])
        self.assertIn("문서 구성", pages[0])
        self.assertNotIn("한글 메모", pages[0])
        self.assertIn("02  메모", pages[1])
        self.assertIn("메모 총 1건", pages[1])
        self.assertNotIn("채팅 총", pages[1])
        self.assertIn("03  채팅", pages[2])
        self.assertIn("채팅 총 1건", pages[2])
        self.assertEqual([entry.title for entry in reader.outline], ["안내", "메모", "채팅"])

    def test_single_scope_has_two_sections_and_empty_records_stay_separate(self):
        self.cursor.__iter__.side_effect = lambda: iter([])
        reader = self.pdf(scopes=["chats"])
        self.assertEqual(len(reader.pages), 2)
        self.assertEqual([entry.title for entry in reader.outline], ["안내", "채팅"])
        self.assertIn("02  채팅", reader.pages[1].extract_text())
        self.assertIn("채팅 총 0건", reader.pages[1].extract_text())
        self.assertNotIn("선택한 기간에 기록이 없습니다", reader.pages[0].extract_text())

    def test_image_inclusion_and_exclusion_match_query_and_pdf(self):
        self.cursor.__iter__.side_effect = lambda: iter([record(has_image=1, image=image_bytes())])
        included = self.pdf(include_images=True, scopes=["memos"])
        self.assertEqual(len(self.images(included)), 1)
        self.assertTrue(any("m.memo_image AS image" in call.args[0] for call in self.cursor.execute.call_args_list))
        self.cursor.execute.reset_mock()
        excluded = self.pdf(include_images=False, scopes=["memos"])
        self.assertEqual(len(self.images(excluded)), 0)
        self.assertIn("이미지 첨부됨 - 내보내기에서 제외", self.text(excluded))
        self.assertFalse(any(" AS image" in call.args[0] for call in self.cursor.execute.call_args_list))

    def test_deleted_chat_does_not_leak_original_or_image(self):
        self.cursor.__iter__.side_effect = lambda: iter([record(is_deleted=1, has_image=1, image=b"secret", content="삭제 원문 비밀")])
        reader = self.pdf(include_images=True, scopes=["chats"])
        self.assertIn("삭제된 메시지입니다.", self.text(reader))
        self.assertNotIn("삭제 원문 비밀", self.text(reader))
        self.assertEqual(self.images(reader), [])

    def test_empty_period_returns_readable_pdf_and_zero_counts(self):
        self.cursor.__iter__.side_effect = lambda: iter([])
        text = self.text(self.pdf())
        self.assertIn("선택한 기간에 기록이 없습니다.", text)
        self.assertIn("메모 총 0건", text)
        self.assertIn("채팅 총 0건", text)

    def test_user_text_is_literal_and_cannot_add_pdf_images_or_links(self):
        self.cursor.__iter__.side_effect = lambda: iter([record(content='<b>문자</b> <img src="https://example.invalid/private"> & 기호')])
        reader = self.pdf(scopes=["memos"])
        self.assertIn('<b>문자</b>', self.text(reader))
        self.assertIn("& 기호", self.text(reader))
        self.assertEqual(self.images(reader), [])
        self.assertFalse(any(page.get("/Annots") for page in reader.pages))

    def test_pdf_requires_token_and_membership_before_file_creation(self):
        app.dependency_overrides.clear()
        self.assertEqual(self.request().status_code, 401)
        self.connect.assert_not_called()
        app.dependency_overrides[exports.get_current_user_id] = lambda: "user-a"
        self.cursor.fetchone.return_value = None
        self.assertEqual(self.request().status_code, 403)
        self.assertEqual(self.outputs, [])

    def test_membership_is_rechecked_after_pdf_generation(self):
        self.cursor.fetchone.side_effect = [ROOM, None]
        self.assertEqual(self.request().status_code, 403)
        self.assertTrue(self.outputs[0].closed)

    def test_corrupt_image_returns_reason_and_can_retry_without_images(self):
        self.cursor.__iter__.side_effect = lambda: iter([record(has_image=1, image=b"broken")])
        with self.assertLogs(exports.logger, level="ERROR"):
            response = self.request(include_images=True)
        self.assertEqual(response.status_code, 500)
        self.assertIn("이미지를 제외하고", response.json()["detail"])
        self.assertTrue(self.outputs[0].closed)
        self.assertIn("이미지 첨부됨", self.text(self.pdf(include_images=False)))

    def test_font_error_returns_safe_failure_and_cleans_temporary_file(self):
        with patch.object(pdf_generator, "_register_fonts", side_effect=OSError("private-font-path")), self.assertLogs(exports.logger, level="ERROR"):
            response = self.request()
        self.assertEqual(response.status_code, 500)
        self.assertIn("PDF를 생성하지 못했습니다", response.json()["detail"])
        self.assertNotIn("private-font-path", response.text)
        self.assertTrue(self.outputs[0].closed)
        self.db.rollback.assert_called_once()

    def test_database_failure_remains_503_and_cleans_partial_pdf(self):
        self.cursor.__iter__.side_effect = pymysql.OperationalError(2006, "private-db-error")
        with self.assertLogs(exports.logger, level="ERROR"):
            response = self.request()
        self.assertEqual(response.status_code, 503)
        self.assertNotIn("private-db-error", response.text)
        self.assertTrue(self.outputs[0].closed)

    def test_openapi_documents_both_binary_formats(self):
        content = app.openapi()["paths"]["/exports/download"]["post"]["responses"]["200"]["content"]
        self.assertEqual(set(content), {"application/zip", "application/pdf"})


if __name__ == "__main__":
    unittest.main()
