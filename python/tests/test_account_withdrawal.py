"""30일 유예 비활성화는 실제 Firebase·DB를 호출하지 않는다."""
import unittest
from unittest.mock import MagicMock, patch
from fastapi import HTTPException
from python.features.auth import withdrawal as service

class WithdrawalTests(unittest.TestCase):
    def setup_case(self, *, representative=False, already=False):
        connection = MagicMock()
        cursor = connection.cursor.return_value.__enter__.return_value
        cursor.fetchone.side_effect = [{'user_id': 'me'}, {'family_room_id': 'room'}, {'withdrawn_at': 'old' if already else None}]
        cursor.fetchall.side_effect = [[{'family_room_id': 'room'}]] + ([] if already else [[{'family_room_id': 'room', 'is_representative': int(representative)}]])
        self.enterContext(patch.object(service, 'connect', return_value=connection))
        self.enterContext(patch.object(service.badge_cache, 'invalidate'))
        return connection, cursor

    def test_inactivation_only_sets_date_and_preserves_membership_and_profile(self):
        connection, cursor = self.setup_case()
        service.withdraw_account({'uid': 'uid'})
        writes = [call.args[0] for call in cursor.execute.call_args_list if call.args[0].strip().startswith('UPDATE')]
        self.assertEqual(len(writes), 1)
        self.assertIn('withdrawn_at=CURRENT_TIMESTAMP', writes[0])
        self.assertNotIn('user_email', writes[0])
        self.assertNotIn('participate', writes[0])
        connection.commit.assert_called_once()
        connection.close.assert_called_once()

    def test_guardian_is_blocked(self):
        connection, cursor = self.setup_case(representative=True)
        with self.assertRaises(HTTPException) as error: service.withdraw_account({'uid': 'uid'})
        self.assertEqual(error.exception.status_code, 409)
        connection.commit.assert_not_called()
        connection.rollback.assert_called_once()

    def test_repeated_request_never_extends_retention_date(self):
        connection, cursor = self.setup_case(already=True)
        service.withdraw_account({'uid': 'uid'})
        self.assertFalse(any(call.args[0].strip().startswith('UPDATE') for call in cursor.execute.call_args_list))
