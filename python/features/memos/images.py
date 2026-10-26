"""메모 한 장 첨부의 크기·실제 형식 검증과 JPEG 정규화."""
from io import BytesIO

from fastapi import HTTPException, UploadFile
from PIL import Image, ImageOps, UnidentifiedImageError

MAX_IMAGE_BYTES = 5 * 1024 * 1024
MAX_IMAGE_PIXELS = 20_000_000


def read_image(files: list[UploadFile] | None, remove_image: bool = False) -> bytes | None:
    if not files:
        return None
    if len(files) != 1:
        raise HTTPException(422, "이미지는 한 장만 첨부할 수 있습니다.")
    if remove_image:
        raise HTTPException(422, "이미지 첨부와 제거를 동시에 요청할 수 없습니다.")
    data = files[0].file.read(MAX_IMAGE_BYTES + 1)
    if len(data) > MAX_IMAGE_BYTES:
        raise HTTPException(413, "이미지는 5MB 이하로 첨부해 주세요.")
    try:
        with Image.open(BytesIO(data)) as source:
            if source.format not in {"JPEG", "PNG", "WEBP"}:
                raise HTTPException(422, "JPG, PNG, WEBP 이미지만 첨부할 수 있습니다.")
            if source.width * source.height > MAX_IMAGE_PIXELS:
                raise HTTPException(422, "이미지 해상도가 너무 큽니다.")
            if getattr(source, "n_frames", 1) != 1:
                raise HTTPException(422, "움직이는 이미지는 첨부할 수 없습니다.")
            source.verify()
        with Image.open(BytesIO(data)) as source:
            oriented = ImageOps.exif_transpose(source)
            oriented.thumbnail((2560, 2560))
            rgba = oriented.convert("RGBA")
            # 투명 영역은 흰색으로 합성하고 EXIF·위치 정보 등은 저장하지 않는다.
            image = Image.new("RGB", rgba.size, "white")
            image.paste(rgba, mask=rgba.getchannel("A"))
            output = BytesIO()
            image.save(output, format="JPEG", quality=85)
            result = output.getvalue()
            if len(result) > MAX_IMAGE_BYTES:
                raise HTTPException(413, "이미지는 5MB 이하로 첨부해 주세요.")
            return result
    except (UnidentifiedImageError, OSError, SyntaxError, ValueError,
            Image.DecompressionBombError) as error:
        raise HTTPException(422, "올바른 이미지 파일을 첨부해 주세요.") from error
