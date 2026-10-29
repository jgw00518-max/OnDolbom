"""모의 DB·SMTP로 만료 초대의 권한과 새 초대 발송을 검증한다."""
import unittest
from unittest.mock import MagicMock, patch
import smtplib
from fastapi import HTTPException
from python.features.invites import router as invites


class InviteResendTests(unittest.TestCase):
    user = dict(user_id='sender', user_email='sender@example.com')

    def connection(self, status='만료', expired=True, member=None, pending=None):
        connection = MagicMock()
        cursor = connection.cursor.return_value.__enter__.return_value
        cursor.fetchone.side_effect = [dict(family_room_id='room'),
            dict(family_room_id='room', invite_email='family@example.com',
                 invite_status=status, expired=expired), member, pending]
        return connection, cursor

    def test_expired_invitation_creates_new_id_and_sends_email(self):
        for status in ['만료', '대기']:
            connection, cursor = self.connection(status=status)
            with patch.object(invites, 'connect', return_value=connection), \
                 patch.object(invites, 'check_inviter') as permission, \
                 patch.object(invites, 'uuid4', return_value='new-id'), \
                 patch.object(invites, 'send_invite_email') as mail:
                result = invites.resend_invite('old-id', self.user)
            self.assertEqual(result['invite_id'], 'new-id')
            self.assertTrue(result['email_sent'])
            self.assertEqual(result['invite_status'], '대기')
            permission.assert_called_once_with(connection, 'room', 'sender')
            mail.assert_called_once_with('family@example.com')
            inserts = [call for call in cursor.execute.call_args_list if 'INSERT INTO invite' in call.args[0]]
            self.assertEqual(inserts[0].args[1], ('new-id', 'room', 'sender', 'family@example.com', '발송대기'))
            self.assertEqual(connection.commit.call_count, 2)
            connection.close.assert_called_once()

    def test_only_original_sender_can_request(self):
        connection = MagicMock()
        cursor = connection.cursor.return_value.__enter__.return_value
        cursor.fetchone.return_value = None
        with patch.object(invites, 'connect', return_value=connection), \
             patch.object(invites, 'send_invite_email') as mail:
            with self.assertRaises(HTTPException) as error:
                invites.resend_invite('foreign', self.user)
        self.assertEqual(error.exception.status_code, 404)
        self.assertIn('inviter_id=%s', cursor.execute.call_args.args[0])
        self.assertEqual(cursor.execute.call_args.args[1], ('foreign', 'sender'))
        mail.assert_not_called()
        connection.rollback.assert_called_once()

    def test_former_guardian_cannot_resend(self):
        connection, _ = self.connection()
        with patch.object(invites, 'connect', return_value=connection), \
             patch.object(invites, 'check_inviter', side_effect=HTTPException(403, 'role')), \
             patch.object(invites, 'send_invite_email') as mail:
            with self.assertRaises(HTTPException) as error:
                invites.resend_invite('old-id', self.user)
        self.assertEqual(error.exception.status_code, 403)
        mail.assert_not_called()

    def test_nonexpired_or_processed_invitation_is_rejected(self):
        for status in ['대기', '수락', '거절', '취소', '발송실패', '발송대기']:
            connection, _ = self.connection(status=status, expired=False)
            with patch.object(invites, 'connect', return_value=connection), \
                 patch.object(invites, 'check_inviter'), patch.object(invites, 'send_invite_email') as mail:
                with self.assertRaises(HTTPException) as error:
                    invites.resend_invite('old-id', self.user)
            self.assertEqual(error.exception.status_code, 409)
            mail.assert_not_called()
            connection.commit.assert_not_called()

    def test_existing_member_or_pending_new_invite_blocks_duplicate(self):
        for changes in [dict(member={'participate_seq': 1}), dict(pending={'invite_id': 'new-id'})]:
            connection, _ = self.connection(**changes)
            with patch.object(invites, 'connect', return_value=connection), \
                 patch.object(invites, 'check_inviter'), patch.object(invites, 'send_invite_email') as mail:
                with self.assertRaises(HTTPException) as error:
                    invites.resend_invite('old-id', self.user)
            self.assertEqual(error.exception.status_code, 409)
            mail.assert_not_called()
            connection.commit.assert_not_called()

    def test_mail_failure_keeps_new_record_failed_and_old_expired(self):
        connection, cursor = self.connection()
        with patch.object(invites, 'connect', return_value=connection), \
             patch.object(invites, 'check_inviter'), patch.object(invites, 'uuid4', return_value='new-id'), \
             patch.object(invites, 'send_invite_email', side_effect=smtplib.SMTPException('offline')):
            result = invites.resend_invite('old-id', self.user)
        self.assertFalse(result['email_sent'])
        self.assertEqual(result['invite_status'], '발송실패')
        self.assertEqual(cursor.execute.call_args.args[1], ('발송실패', 'new-id', '발송대기'))

    def test_lists_return_expiry_and_server_resend_permission(self):
        connection = MagicMock()
        cursor = connection.cursor.return_value.__enter__.return_value
        cursor.fetchall.return_value = []
        with patch.object(invites, 'connect', return_value=connection):
            invites.get_sent_invites(self.user)
        sql = cursor.execute.call_args.args[0]
        for condition in ['INTERVAL 7 DAY', 'AS expires_at', 'AS can_resend',
                          'i.inviter_id = p.user_id', 'NOT EXISTS', '발송대기']:
            self.assertIn(condition, sql)


if __name__ == '__main__':
    unittest.main()
