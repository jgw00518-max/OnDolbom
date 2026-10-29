import os
import smtplib
import ssl
from email.message import EmailMessage
from email.utils import formataddr
from pathlib import Path

from dotenv import dotenv_values


# 초대받은 가족에게 안내 메일을 보낸다.
def send_invite_email(invite_email: str):
    # python/.env를 읽고, 환경변수가 있으면 우선 적용한다.
    env_file = Path(__file__).resolve().parents[2] / ".env"
    settings = {**dotenv_values(env_file), **os.environ}

    smtp_host = settings.get("SMTP_HOST")
    smtp_user = settings.get("SMTP_USER")
    smtp_password = settings.get("SMTP_PASSWORD")
    from_name = settings.get("SMTP_FROM_NAME", "온돌봄")

    if not smtp_host or not smtp_user or not smtp_password:
        raise ValueError("메일 발송 설정을 확인해 주세요.")

    smtp_port = int(settings.get("SMTP_PORT", "465"))

    # 메일 제목·발신자·수신자·본문을 작성한다.
    message = EmailMessage()
    message["Subject"] = "[온돌봄] 돌봄 공간 초대가 도착했습니다."
    message["From"] = formataddr((from_name, smtp_user))
    message["To"] = invite_email

    message.set_content(
        "가족과 함께하는 돌봄, 온돌봄\n\n"
        "돌봄 공간 초대가 도착했어요.\n"
        "초대는 발송 후 7일 동안 유효합니다. 만료되면 초대한 가족에게 재요청해 주세요.\n"
        "온돌봄에서 가족들과 돌봄 일정을 나누고,\n"
        "소중한 일상을 함께 챙겨보세요.\n\n"
        "[돌봄 공간 참여 방법]\n\n"
        "1. 온돌봄이 처음이라면, 이 메일을 받은 이메일 주소로\n"
        "   회원가입해 주세요.\n"
        "   이미 회원이라면 해당 이메일 주소로 로그인해 주세요.\n\n"
        "2. 공간 목록의 '받은 초대'에서 초대를 확인해 주세요.\n\n"
        "3. 초대를 수락하면 돌봄 공간에 참여할 수 있어요.\n\n"
        "꼭 초대 메일을 받은 이메일 주소로 가입·로그인해 주세요.\n"
        "다른 이메일 주소로 이용하면 초대를 확인할 수 없어요.\n\n"
        "가족의 마음을 잇는 따뜻한 돌봄\n"
        "온돌봄"
    )
        # HTML을 지원하는 메일 앱에서는 편지 카드 형태로 표시한다.
    message.add_alternative(
        """
        <!DOCTYPE html>
        <html lang="ko">
        <head>
          <meta charset="UTF-8">
          <meta name="viewport" content="width=device-width, initial-scale=1.0">
          <title>온돌봄 돌봄 공간 초대</title>
        </head>
        <body style="margin:0; padding:0; background-color:#FFF8F1;
                     font-family:Arial,'Apple SD Gothic Neo','Malgun Gothic',sans-serif;
                     color:#403C39;">
          <table role="presentation" width="100%" cellpadding="0" cellspacing="0"
                 style="background-color:#FFF8F1;">
            <tr>
              <td align="center" style="padding:32px 16px;">
                <table role="presentation" width="100%" cellpadding="0" cellspacing="0"
                       style="max-width:560px; background-color:#FFFFFF;
                              border:1px solid #E8DFD7; border-radius:20px;">
                  <tr>
                    <td style="padding:28px 28px 22px; background-color:#FFEBD9;
                               border-radius:20px 20px 0 0;">
                      <p style="margin:0; color:#99522F; font-size:24px;
                                font-weight:bold;">
                        온돌봄
                      </p>
                      <p style="margin:8px 0 0; color:#756B60; font-size:13px;
                                line-height:1.6;">
                        가족과 함께하는 따뜻한 돌봄
                      </p>
                    </td>
                  </tr>

                  <tr>
                    <td style="padding:32px 28px 24px;">
                      <p style="margin:0 0 14px; color:#71815F; font-size:13px;
                                font-weight:bold; letter-spacing:1px;">
                        돌봄 공간 초대장
                      </p>
                      <h1 style="margin:0 0 20px; font-size:25px;
                                 line-height:1.5; color:#403C39;">
                        함께 돌볼 돌봄 공간에<br>
                        초대받으셨어요.
                      </h1>
                      <p style="margin:0; font-size:15px; line-height:1.9;
                                color:#756B60;">
                        혼자 챙기던 돌봄을 가족과 함께 나눠보세요.<br>
                        일정을 나누고 서로의 소식을 전하며<br>
                        소중한 일상을 함께 챙길 수 있어요.
                      </p>
                    </td>
                  </tr>

                  <tr>
                    <td style="padding:0 28px 28px;">
                      <table role="presentation" width="100%"
                             cellpadding="0" cellspacing="0"
                             style="background-color:#F3F6EF; border-radius:14px;">
                        <tr>
                          <td style="padding:24px;">
                            <p style="margin:0 0 20px; font-size:16px;
                                      font-weight:bold; color:#526345;">
                              돌봄 공간에 참여하는 방법
                            </p>

                            <p style="margin:0 0 6px; font-size:15px;
                                      font-weight:bold; color:#403C39;">
                              01. 회원가입 또는 로그인
                            </p>
                            <p style="margin:0 0 20px; font-size:14px;
                                      line-height:1.8; color:#756B60;">
                              온돌봄이 처음이라면 이 메일을 받은 이메일
                              주소로 회원가입해 주세요.<br>
                              이미 회원이라면 해당 이메일 주소로
                              로그인해 주세요.
                            </p>

                            <p style="margin:0 0 6px; font-size:15px;
                                      font-weight:bold; color:#403C39;">
                              02. 받은 초대 확인
                            </p>
                            <p style="margin:0 0 20px; font-size:14px;
                                      line-height:1.8; color:#756B60;">
                              공간 목록에서 ‘받은 초대’를 열어
                              도착한 초대를 확인해 주세요.
                            </p>

                            <p style="margin:0 0 6px; font-size:15px;
                                      font-weight:bold; color:#403C39;">
                              03. 초대 수락하고 함께하기
                            </p>
                            <p style="margin:0; font-size:14px;
                                      line-height:1.8; color:#756B60;">
                              초대를 수락하면 돌봄 공간에 참여해
                              함께 돌봄을 시작할 수 있어요.
                            </p>
                          </td>
                        </tr>
                      </table>
                    </td>
                  </tr>

                  <tr>
                    <td style="padding:0 28px 30px;">
                      <p style="margin:0; padding:16px;
                                background-color:#FFF5EC; border-radius:12px;
                                color:#99522F; font-size:13px; line-height:1.8;">
                        <strong>초대 유효기간은 발송 후 7일입니다.</strong><br>
                        만료되면 초대한 가족에게 새 초대를 요청해 주세요.<br><br>
                        <strong>가입 전 확인해 주세요</strong><br>
                        꼭 초대 메일을 받은 이메일 주소로 가입·로그인해 주세요.
                        다른 이메일 주소로 이용하면 초대를 확인할 수 없어요.
                      </p>
                    </td>
                  </tr>

                  <tr>
                    <td align="center"
                        style="padding:24px; border-top:1px solid #E8DFD7;">
                      <p style="margin:0; color:#756B60; font-size:13px;
                                line-height:1.8;">
                        가족의 마음을 잇는 따뜻한 돌봄
                      </p>
                      <p style="margin:8px 0 0; color:#99522F; font-size:16px;
                                font-weight:bold;">
                        온돌봄
                      </p>
                    </td>
                  </tr>
                </table>
              </td>
            </tr>
          </table>
        </body>
        </html>
        """,
        subtype="html",
    )

    # 암호화된 연결로 Gmail에 로그인하고 메일을 보낸다.
    with smtplib.SMTP_SSL(
        smtp_host,
        smtp_port,
        context=ssl.create_default_context(),
        timeout=15,
    ) as server:
        server.login(smtp_user, smtp_password)
        server.send_message(message)