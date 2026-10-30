"""재활성화는 인증된 본인 계정만 DB 시각의 30일 경계 안에서 처리한다."""
import unittest
from unittest.mock import MagicMock, patch
from fastapi import HTTPException
from python.features.auth import router as api

class ReactivationTests(unittest.TestCase):
    def test_only_eligible_account_can_be_reactivated(self):
        for changed, expected in [(1, 200), (0, 410)]:
            with self.subTest(changed=changed):
                connection = MagicMock()
                cursor = connection.cursor.return_value.__enter__.return_value
                cursor.rowcount = changed
                with patch.object(api, 'connect', return_value=connection), patch.object(api, '_find_profile', return_value={'user_id': 'me', 'withdrawn_at': 'date'}):
                    if expected == 200:
                        self.assertEqual(api.reactivate_account({'uid': 'uid'}), {'result': 'OK'})
                        connection.commit.assert_called_once()
                    else:
                        with self.assertRaises(HTTPException) as error: api.reactivate_account({'uid': 'uid'})
                        self.assertEqual(error.exception.status_code, 410)
                        connection.rollback.assert_called_once()
                    self.assertIn('INTERVAL 30 DAY', cursor.execute.call_args.args[0])
                    self.assertEqual(cursor.execute.call_args.args[1], ('me',))
                connection.close.assert_called_once()

    def test_active_account_is_idempotent(self):
        connection = MagicMock()
        with patch.object(api, 'connect', return_value=connection), patch.object(api, '_find_profile', return_value={'user_id': 'me', 'withdrawn_at': None}):
            self.assertEqual(api.reactivate_account({'uid': 'uid'}), {'result': 'OK'})
        connection.cursor.return_value.__enter__.return_value.execute.assert_not_called()
