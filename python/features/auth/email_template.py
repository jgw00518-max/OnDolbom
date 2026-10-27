"""초대 메일과 같은 색감을 사용하는 인증번호 메일. 외부 이미지 없이 표시한다."""
from html import escape


def verification_message(code: str, purpose: str) -> tuple[str, str]:
    signup = purpose == "signup"
    label = "회원가입 이메일 인증" if signup else "비밀번호 재설정"
    heading = "온돌봄의 가족이<br>되어주세요." if signup else "새 비밀번호로<br>안전하게 시작하세요."
    description = (
        "온돌봄과 함께할 준비가 거의 끝났어요.<br>아래 인증번호를 앱에 입력하면 이메일 확인이 완료됩니다."
        if signup else
        "비밀번호 재설정을 요청하셨나요?<br>아래 인증번호를 앱에 입력한 후 새 비밀번호를 설정해 주세요."
    )
    # 일반 텍스트도 함께 제공해 HTML을 표시하지 않는 메일 앱에서 코드를 확인할 수 있다.
    text = f"온돌봄 {label}\n\n인증번호: {code}\n10분 안에 온돌봄 앱에 입력해 주세요.\n본인이 요청하지 않았다면 이 메일을 무시해 주세요.\n인증번호는 다른 사람에게 알려주지 마세요.\n\n가족의 마음을 잇는 따뜻한 돌봄\n온돌봄"
    safe_code = escape(code)
    # 이메일 앱 호환성을 위해 table 배치와 inline style을 사용한다.
    html = f"""<!DOCTYPE html>
<html lang="ko"><head><meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>온돌봄 {label}</title></head>
<body style="margin:0;padding:0;background-color:#FFF8F1;font-family:Arial,'Apple SD Gothic Neo','Malgun Gothic',sans-serif;color:#403C39;">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="table-layout:fixed;background-color:#FFF8F1;">
<tr><td align="center" style="padding:32px 16px;">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="table-layout:fixed;max-width:560px;background-color:#FFFFFF;border:1px solid #E8DFD7;border-radius:20px;">
<tr><td style="padding:28px;background-color:#FFEBD9;border-radius:20px 20px 0 0;">
<p style="margin:0;color:#99522F;font-size:24px;font-weight:bold;">온돌봄</p>
<p style="margin:8px 0 0;color:#756B60;font-size:13px;line-height:1.6;">가족과 함께하는 따뜻한 돌봄</p>
</td></tr>
<tr><td style="padding:32px 28px 24px;">
<p style="margin:0 0 14px;color:#71815F;font-size:13px;font-weight:bold;letter-spacing:1px;">{label}</p>
<h1 style="margin:0 0 20px;color:#403C39;font-size:25px;line-height:1.5;">{heading}</h1>
<p style="margin:0;color:#756B60;font-size:15px;line-height:1.9;">{description}</p>
</td></tr>
<tr><td style="padding:0 28px 24px;">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background-color:#F3F6EF;border:1px solid #E8EDE1;border-radius:14px;">
<tr><td align="center" style="padding:26px 12px;">
<p style="margin:0 0 16px;color:#526345;font-size:14px;font-weight:bold;">이메일 인증번호</p>
<p style="margin:0;color:#99522F;font-family:'Courier New',monospace;font-size:36px;line-height:1.4;font-weight:bold;letter-spacing:6px;white-space:nowrap;">{safe_code}</p>
<p style="margin:16px 0 0;color:#756B60;font-size:13px;line-height:1.7;">발송 후 <strong style="color:#99522F;">10분</strong> 동안 사용할 수 있어요.</p>
</td></tr></table>
</td></tr>
<tr><td style="padding:0 28px 24px;">
<p style="margin:0;color:#403C39;font-size:14px;font-weight:bold;">앱으로 돌아가 인증번호를 입력해 주세요.</p>
<p style="margin:8px 0 0;color:#756B60;font-size:13px;line-height:1.8;">인증번호를 다시 요청했다면 가장 최근에 받은 번호를 입력해 주세요.</p>
</td></tr>
<tr><td style="padding:0 28px 28px;">
<table role="presentation" width="100%" cellpadding="0" cellspacing="0" style="background-color:#FFF5EC;border-radius:12px;">
<tr><td style="padding:16px;color:#99522F;font-size:13px;line-height:1.8;">
<strong>안전한 이용을 위해 확인해 주세요</strong><br>
인증번호는 다른 사람에게 알려주지 마세요.<br>본인이 요청하지 않았다면 이 메일을 무시해 주세요.
</td></tr></table>
</td></tr>
<tr><td align="center" style="padding:24px;border-top:1px solid #E8DFD7;">
<p style="margin:0;color:#756B60;font-size:13px;line-height:1.8;">가족의 마음을 잇는 따뜻한 돌봄</p>
<p style="margin:8px 0 0;color:#99522F;font-size:16px;font-weight:bold;">온돌봄</p>
</td></tr>
</table></td></tr></table></body></html>"""
    return text, html
