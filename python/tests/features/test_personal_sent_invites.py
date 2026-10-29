"""주보호자 이전 후에도 보낸 초대는 발신자 본인 기준이다."""
import unittest
from unittest.mock import MagicMock, patch
from python.features.invites import router as invites


class PersonalSentInvitesTests(unittest.TestCase):
    def test_sender_identity_filters_listing_and_expiration(self):
        for sender in ('test1-id', 'test3-id'):
            with self.subTest(sender=sender):
                conn = MagicMock()
                cursor = conn.cursor.return_value.__enter__.return_value
                cursor.fetchall.return_value = []
                with patch.object(invites, 'connect', return_value=conn):
                    self.assertEqual(invites.get_sent_invites({'user_id': sender}), {'results': []})
                expire, listing = cursor.execute.call_args_list
                self.assertEqual(expire.args[1], ('만료', sender, '대기'))
                self.assertEqual(listing.args[1], (sender,))
                for query in (expire.args[0], listing.args[0]):
                    where = query.split('WHERE p.user_id = %s')[-1]
                    self.assertIn('i.inviter_id = p.user_id', where)
                    self.assertNotIn('p.is_representative = 1', where)
                    self.assertIn('p.left_at IS NULL', where)
                self.assertIn('p.is_representative = 1', listing.args[0].split('FROM invite AS i')[0])
                self.assertIn('AS can_cancel', listing.args[0])
                self.assertIn('AS can_resend', listing.args[0])
                conn.commit.assert_called_once()
                conn.close.assert_called_once()

    def test_failure_does_not_leave_expiration_update_uncommitted(self):
        from pymysql import OperationalError
        conn = MagicMock()
        conn.cursor.return_value.__enter__.return_value.execute.side_effect = OperationalError(2006, 'failed')
        from fastapi import HTTPException
        with patch.object(invites, 'connect', return_value=conn):
            with self.assertRaises(HTTPException) as error:
                invites.get_sent_invites({'user_id': 'test3'})
        self.assertEqual(error.exception.status_code, 503)
        conn.rollback.assert_called_once()
        conn.close.assert_called_once()
