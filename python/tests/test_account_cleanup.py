"""30일 정리는 DB·인증·Firestore를 모두 모킹하고 경계 재검증을 검사한다."""
import unittest
from unittest.mock import MagicMock, patch
from python.features.auth import account_cleanup as service

class CleanupTests(unittest.TestCase):
    def setup_case(self, user):
        connection = MagicMock()
        cursor = connection.cursor.return_value.__enter__.return_value
        cursor.fetchall.return_value = [{'family_room_id': 'room'}]
        cursor.fetchone.side_effect = [{'family_room_id': 'room'}, user]
        self.enterContext(patch.object(service, 'connect', return_value=connection))
        self.enterContext(patch.object(service.badge_cache, 'invalidate'))
        cloud = self.enterContext(patch.object(service, 'erase_cloud_identity'))
        leave = self.enterContext(patch.object(service, 'end_membership'))
        return connection, cursor, cloud, leave

    def test_before_deadline_or_reactivated_account_is_never_deleted(self):
        connection, cursor, cloud, leave = self.setup_case(None)
        self.assertFalse(service.purge_account('me'))
        cloud.assert_not_called(); leave.assert_not_called()
        self.assertIn('INTERVAL 30 DAY', cursor.execute.call_args.args[0])
        connection.close.assert_called_once()

    def test_expired_account_loses_identity_but_shared_record_keys_remain(self):
        connection, cursor, cloud, leave = self.setup_case({'user_firebase_uid': 'uid', 'user_email': 'me@example.com'})
        self.assertTrue(service.purge_account('me'))
        leave.assert_called_once_with('room', 'me', connection=connection, allow_inactive=True)
        cloud.assert_called_once_with('uid', 'me', 'me@example.com')
        self.assertIn('user_firebase_uid=NULL', cursor.execute.call_args.args[0])
        self.assertFalse(any('DELETE FROM `user`' in call.args[0] for call in cursor.execute.call_args_list))
        connection.commit.assert_called_once()

    def test_cloud_failure_rolls_back_mysql_for_later_retry(self):
        connection, cursor, cloud, leave = self.setup_case({'user_firebase_uid': 'uid', 'user_email': 'me@example.com'})
        cloud.side_effect = ValueError('offline')
        with self.assertRaises(ValueError): service.purge_account('me')
        connection.commit.assert_not_called(); connection.rollback.assert_called_once()
