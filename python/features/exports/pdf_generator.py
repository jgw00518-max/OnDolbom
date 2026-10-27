"""서버에 포함한 한글 폰트로 메모·채팅을 한 PDF에 순차 배치한다."""

from collections import deque
from contextlib import closing
from html import escape
from io import BytesIO
from pathlib import Path
from threading import Lock
from unicodedata import normalize

from reportlab.lib.colors import HexColor
from reportlab.lib.pagesizes import A4
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.units import mm
from reportlab.lib.utils import ImageReader
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.pdfdoc import PDFError
from reportlab.pdfbase.ttfonts import TTFont, TTFError
from reportlab.pdfgen.canvas import Canvas
from reportlab.platypus import Paragraph

from python.features.exports.generator import ExportImageError, _image_extension

_font_lock = Lock()
_regular = "OndolbomNanumGothic"
_bold = "OndolbomNanumGothicBold"
_font_dir = Path(__file__).with_name("fonts")


class PdfGenerationError(RuntimeError):
    """폰트·문서 렌더링 오류를 API의 안전한 메시지로 변환한다."""


def _register_fonts():
    with _font_lock:
        for name, filename in ((_regular, "NanumGothic-Regular.ttf"), (_bold, "NanumGothic-Bold.ttf")):
            if name not in pdfmetrics.getRegisteredFontNames():
                pdfmetrics.registerFont(TTFont(name, str(_font_dir / filename)))


class _Document:
    def __init__(self, output):
        self.canvas = Canvas(output, pagesize=A4, pageCompression=1)
        self.canvas.setTitle("온돌봄 메모·채팅 내보내기")
        self.canvas.setAuthor("온돌봄")
        self.width, self.height = A4
        self.left = 20 * mm
        self.bottom = 22 * mm
        self.top = self.height - 26 * mm
        self.body_width = self.width - self.left * 2
        self.y = self.top
        self.replaced = False
        self.current_section = "안내"
        self.styles = {
            "title": ParagraphStyle("title", fontName=_bold, fontSize=21, leading=29, wordWrap="CJK", textColor=HexColor("#AD5B32")),
            "heading": ParagraphStyle("heading", fontName=_bold, fontSize=15, leading=22, wordWrap="CJK", textColor=HexColor("#875634")),
            "author": ParagraphStyle("author", fontName=_bold, fontSize=11, leading=17, wordWrap="CJK"),
            "body": ParagraphStyle("body", fontName=_regular, fontSize=10, leading=16, wordWrap="CJK", allowWidows=1, allowOrphans=1),
            "meta": ParagraphStyle("meta", fontName=_regular, fontSize=9, leading=14, wordWrap="CJK", textColor=HexColor("#666666")),
        }
        self._header()

    def _header(self):
        self.canvas.setFont(_regular, 8)
        self.canvas.setFillColor(HexColor("#875634"))
        self.canvas.drawString(self.left, self.height - 15 * mm, "온돌봄 / 메모·채팅 내보내기")
        self.canvas.drawRightString(self.width - self.left, self.height - 15 * mm, self.current_section)
        self.canvas.setStrokeColor(HexColor("#E8DFD7"))
        self.canvas.line(self.left, self.height - 18 * mm, self.width - self.left, self.height - 18 * mm)

    def _footer(self):
        self.canvas.setFont(_regular, 8)
        self.canvas.setFillColor(HexColor("#666666"))
        self.canvas.drawRightString(self.width - self.left, 13 * mm, f"{self.canvas.getPageNumber()} 페이지")

    def _page(self):
        self._footer()
        self.canvas.showPage()
        self.y = self.top
        self._header()

    def ensure(self, height):
        if self.y - height < self.bottom:
            self._page()

    def section(self, title, number, *, new_page=False):
        """구역별 새 페이지·배너·PDF 책갈피로 경계를 표시한다."""
        self.current_section = title
        if new_page:
            self._page()
        height = 54
        self.canvas.setFillColor(HexColor("#FFF3E9"))
        self.canvas.roundRect(self.left, self.y - height, self.body_width, height, 8, fill=1, stroke=0)
        self.canvas.setFillColor(HexColor("#AD5B32"))
        self.canvas.rect(self.left, self.y - height + 8, 3, height - 16, fill=1, stroke=0)
        self.canvas.setFont(_bold, 18)
        self.canvas.drawString(self.left + 16, self.y - 34, f"{number:02d}  {title}")
        key = f"section-{number}"
        self.canvas.bookmarkPage(key)
        self.canvas.addOutlineEntry(title, key, level=0)
        self.y -= height + 20

    def _text(self, value, font):
        text = normalize("NFC", str(value) if value is not None else "")
        glyphs = pdfmetrics.getFont(font).face.charToGlyph
        parts = []
        for char in text.replace("\r\n", "\n").replace("\r", "\n").replace("\t", "    "):
            if char == "\n" or (ord(char) >= 32 and ord(char) in glyphs):
                parts.append(char)
            else:
                self.replaced = True
                parts.append(f"[U+{ord(char):04X}]")
        # 본문을 마크업으로 해석하거나 외부 이미지·링크를 읽지 않는다.
        return escape("".join(parts), quote=False).replace("\n", "<br/>") or "&#160;"

    def paragraph(self, text, style="body", after=7):
        style = self.styles[style]
        pending = deque([Paragraph(self._text(text, style.fontName), style)])
        while pending:
            paragraph = pending.popleft()
            available = max(0, self.y - self.bottom)
            _, height = paragraph.wrap(self.body_width, available)
            if height <= available:
                paragraph.drawOn(self.canvas, self.left, self.y - height)
                self.y -= height
                continue
            pieces = paragraph.split(self.body_width, available)
            if not pieces:
                self._page()
                pending.appendleft(paragraph)
            else:
                pending.extendleft(reversed(pieces))
        self.y -= after

    def image(self, data):
        _image_extension(data)
        try:
            picture = ImageReader(BytesIO(data))
            width, height = picture.getSize()
            scale = min(self.body_width / width, 105 * mm / height, 1)
            width, height = width * scale, height * scale
            self.ensure(height + 10)
            self.canvas.drawImage(picture, self.left, self.y - height, width=width, height=height, mask="auto")
            self.y -= height + 10
        except (OSError, ValueError) as error:
            raise ExportImageError("Invalid PDF image") from error

    def rule(self):
        self.ensure(12)
        self.canvas.setStrokeColor(HexColor("#E8DFD7"))
        self.canvas.line(self.left, self.y, self.width - self.left, self.y)
        self.y -= 12

    def finish(self):
        self._footer()
        self.canvas.save()


def build_pdf(output, data, room, sources) -> dict[str, int]:
    """선택 범위만 읽는다. 레코드 목록을 별도로 적재하지 않고 페이지에 순서대로 그린다."""
    try:
        _register_fonts()
        doc = _Document(output)
        doc.section("안내", 1)
        doc.paragraph("메모·채팅 내보내기", "title", after=13)
        doc.paragraph(f'공간: {room.get("care_recipient_name") or data.family_room_id}', "author")
        doc.paragraph(f"기간: {data.start_date} ~ {data.end_date} (양 끝 날짜 포함)", "meta")
        doc.paragraph(f'조회 기준 시각: {room["snapshot_at"]} (DB 저장 시각 기준)', "meta")
        doc.paragraph(f'이미지 포함: {"예" if data.include_images else "아니요"}', "meta")
        doc.paragraph("투약 정보·투약일지 데이터는 포함하지 않습니다. 메모·채팅 본문에 직접 작성한 투약 관련 내용은 그대로 포함됩니다.", "meta")
        doc.paragraph("작성 시각 기준으로 조회하며 수정된 기록은 조회 기준 시점의 본문을 담습니다. 삭제된 메모는 제외하고 삭제된 채팅은 삭제 안내만 담습니다.", "meta", after=16)
        section_titles = ["안내"] + [title for scope, title in (("memos", "메모"), ("chats", "채팅")) if scope in data.scopes]
        doc.paragraph("문서 구성", "author")
        doc.paragraph(" / ".join(f"{number:02d} {title}" for number, title in enumerate(section_titles, 1)), "meta")
        counts = {}
        section_number = 1
        for scope in ("memos", "chats"):
            if scope not in data.scopes:
                continue
            title = "메모" if scope == "memos" else "채팅"
            section_number += 1
            doc.section(title, section_number, new_page=True)
            count = 0
            with closing(sources(scope)) as rows:
                for count, row in enumerate(rows, 1):
                    doc.ensure(60)
                    deleted = bool(row.get("is_deleted"))
                    doc.paragraph(f'{count}. {row.get("author_name") or "이름 없는 가족"}', "author", after=3)
                    updated = " / 수정됨" if not deleted and row.get("updated_at") else ""
                    doc.paragraph(f'{row.get("recorded_at") or ""}{updated}', "meta")
                    doc.paragraph("삭제된 메시지입니다." if deleted else row.get("content"))
                    if not deleted and row.get("has_image"):
                        if data.include_images:
                            doc.image(row.get("image"))
                        else:
                            doc.paragraph("이미지 첨부됨 - 내보내기에서 제외", "meta")
                    doc.rule()
            counts[scope] = count
            if count == 0:
                doc.paragraph("선택한 기간에 기록이 없습니다.")
            doc.paragraph(f"{title} 총 {count}건", "meta", after=18)
        if doc.replaced:
            doc.paragraph("표시 안내: 폰트에 없는 이모지·특수 문자는 [U+문자코드]로 표시했습니다.", "meta")
        doc.finish()
        output.seek(0)
        return counts
    except ExportImageError:
        raise
    except (OSError, ValueError, TTFError, PDFError) as error:
        raise PdfGenerationError("PDF rendering failed") from error
