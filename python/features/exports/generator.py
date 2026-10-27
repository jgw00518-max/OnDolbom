"""레코드를 한 건씩 읽고 임시 디스크에 HTML·이미지 ZIP을 생성한다."""

from contextlib import closing
from html import escape
from io import BytesIO
from shutil import copyfileobj
from tempfile import TemporaryFile
from zipfile import ZIP_DEFLATED, ZipFile

from PIL import Image


class ExportImageError(ValueError):
    """저장된 첨부 이미지를 읽을 수 없어 완전한 파일을 생성하지 못했다."""


def _image_extension(data) -> str:
    try:
        if not data:
            raise ValueError("Missing export image")
        with Image.open(BytesIO(data)) as picture:
            extension = {"JPEG": "jpg", "PNG": "png", "WEBP": "webp"}.get(picture.format)
            if extension is None:
                raise ValueError("Unsupported export image")
            picture.verify()
        return extension
    except (OSError, ValueError, SyntaxError, Image.DecompressionBombError) as error:
        raise ExportImageError("Invalid stored image") from error


def _text(value) -> str:
    return escape(str(value) if value is not None else "", quote=True)


def _start(title: str) -> str:
    return f'''<!doctype html><html lang="ko"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; img-src 'self'; style-src 'unsafe-inline'">
<title>{_text(title)}</title><style>
body {{font-family:sans-serif;max-width:900px;margin:24px auto;padding:0 16px;line-height:1.6}}
article {{border-bottom:1px solid #ccc;padding:16px 0}}
.content {{white-space:pre-wrap;overflow-wrap:anywhere}} img {{max-width:100%;height:auto}}
</style></head><body><h1>{_text(title)}</h1>'''


def write_records(archive: ZipFile, scope: str, rows, include_images: bool) -> int:
    """HTML은 별도 임시 파일에 기록하여 ZIP 이미지 항목과 동시에 열지 않는다."""
    title = "메모" if scope == "memos" else "채팅"
    count = 0
    with TemporaryFile(mode="w+b") as document:
        document.write((_start(title) + '<p><a href="index.html">내보내기 안내</a></p>').encode("utf-8"))
        for count, row in enumerate(rows, 1):
            deleted = bool(row.get("is_deleted"))
            content = "삭제된 메시지입니다." if deleted else row.get("content")
            updated = " · 수정됨" if not deleted and row.get("updated_at") else ""
            block = (f'<article><h2>{_text(row.get("author_name") or "이름 없는 가족")}</h2>'
                     f'<p>{_text(row.get("recorded_at"))}{updated}</p>'
                     f'<div class="content">{_text(content)}</div>')
            if not deleted and row.get("has_image"):
                if include_images:
                    data = row.get("image")
                    extension = _image_extension(data)
                    path = f"images/{scope}_{count}.{extension}"
                    archive.writestr(path, data)
                    block += f'<p><img src="{path}" alt="첨부 이미지" loading="lazy"></p>'
                else:
                    block += "<p>이미지 첨부됨 — 내보내기에서 제외</p>"
            document.write((block + "</article>").encode("utf-8"))
        if count == 0:
            document.write("<p>선택한 기간에 기록이 없습니다.</p>".encode("utf-8"))
        document.write(b"</body></html>")
        document.seek(0)
        with archive.open(f"{scope}.html", "w", force_zip64=True) as target:
            copyfileobj(document, target)
    return count


def build_archive(output, data, room, sources) -> dict[str, int]:
    """sources는 선택한 범위별 레코드 iterator를 지연 생성한다."""
    counts = {}
    with ZipFile(output, "w", compression=ZIP_DEFLATED, allowZip64=True) as archive:
        for scope in ("memos", "chats"):
            if scope in data.scopes:
                with closing(sources(scope)) as rows:
                    counts[scope] = write_records(archive, scope, rows, data.include_images)
        index = (_start("온돌봄 메모·채팅 내보내기")
                 + f'<p>공간: {_text(room.get("care_recipient_name") or data.family_room_id)}</p>'
                 + f'<p>기간: {data.start_date} ~ {data.end_date} (양 끝 날짜 포함)</p>'
                 + f'<p>조회 기준 시각: {_text(room["snapshot_at"])} (DB 저장 시각 기준)</p>'
                 + f'<p>이미지 포함: {"예" if data.include_images else "아니요"}</p>'
                 + '<p>투약 정보·투약일지 데이터는 포함하지 않습니다. '
                   '메모·채팅 본문에 직접 작성한 투약 관련 내용은 그대로 포함됩니다.</p>'
                 + '<p>작성 시각 기준으로 조회하며, 수정된 기록은 조회 기준 시점의 본문을 담습니다. '
                   '삭제된 메모는 제외하고 삭제된 채팅은 삭제 안내만 담습니다.</p><ul>')
        for scope, count in counts.items():
            title = "메모" if scope == "memos" else "채팅"
            index += f'<li><a href="{scope}.html">{title}</a>: {count}건</li>'
        archive.writestr("index.html", index + "</ul></body></html>")
    output.seek(0)
    return counts
