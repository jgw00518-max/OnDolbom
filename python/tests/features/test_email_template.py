"""실제 이메일을 보내지 않고 인증 메일의 이름·본문·전송 구성을 검증한다."""
import unittest
from email.utils import parseaddr
from unittest.mock import patch

from python.features.auth.email_template import verification_message
from python.features.auth.password_reset import send_code


class EmailTemplateTests(unittest.TestCase):
    def test_signup_and_reset_preserve_code_in_both_body_formats(self):
        for purpose, label in (("signup", "회원가입"), ("password_reset", "비밀번호 재설정")):
            with self.subTest(purpose=purpose):
                text, html = verification_message("001234", purpose)
                for body in (text, html):
                    self.assertIn("001234", body)
                    self.assertIn(label, body)
                    self.assertIn("10분", body)
                self.assertIn('max-width:560px', html)
                self.assertNotIn('<script', html)
                self.assertNotIn('<img', html)

    def test_html_interpolation_is_escaped(self):
        _, html = verification_message('<b>123</b>', 'signup')
        self.assertIn('&lt;b&gt;123&lt;/b&gt;', html)
        self.assertNotIn('<b>123</b>', html)

    def test_sender_and_multipart_smtp_message(self):
        config = {'SMTP_FROM': 'sender@example.com', 'SMTP_HOST': 'smtp.example.com',
                  'SMTP_USER': 'sender@example.com', 'SMTP_PASSWORD': 'test-password',
                  'SMTP_PORT': '465', 'SMTP_SECURITY': 'ssl'}
        with patch('python.features.auth.password_reset.smtplib.SMTP_SSL') as smtp:
            send_code(config, 'receiver@example.com', '001234', purpose='signup')
            server = smtp.return_value.__enter__.return_value
            message = server.send_message.call_args.args[0]
            self.assertEqual(parseaddr(str(message['From'])), ('온돌봄', 'sender@example.com'))
            self.assertEqual(message['To'], 'receiver@example.com')
            self.assertEqual(message.get_content_type(), 'multipart/alternative')
            self.assertIn('001234', message.get_body(preferencelist=('plain',)).get_content())
            self.assertIn('001234', message.get_body(preferencelist=('html',)).get_content())
            server.login.assert_called_once_with('sender@example.com', 'test-password')


if __name__ == '__main__':
    unittest.main()
