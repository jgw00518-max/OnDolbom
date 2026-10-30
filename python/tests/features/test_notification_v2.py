"""V2 inbox filters do not alter B's existing all-types API."""
import unittest
from unittest.mock import MagicMock, patch
from fastapi import FastAPI
from fastapi.testclient import TestClient
from python.features.auth.firebase_auth import require_firebase_user
from python.features.schedules import notification_router as api


class NotificationV2Tests(unittest.TestCase):
    def test_scope_includes_automatic_expiry_and_urgent_notices(self):
        kinds = ['schedule_created', 'schedule_changed', 'schedule_reconfirm', 'schedule_recruitment',
                 'schedule_accepted', 'schedule_reconfirmed', 'schedule_deleted', 'schedule_reminder',
                 'schedule_withdrawn', 'schedule_reconfirm_expired', 'schedule_reconfirm_unanswered',
                 'schedule_reconfirm_unverified']
        with patch.object(api, '_visible', return_value={'read_at': None}) as visible:
            for kind in kinds:
                self.assertIsNotNone(api.visible_v2(None, 'user', {'notification_type': kind}))
            self.assertIsNotNone(api.visible_v2(None, 'user', {}))
            self.assertIsNotNone(api.visible_v2(None, 'user', {'notification_type': 'schedule_recruitment', 'request_history_seq': 12}))
            self.assertEqual(visible.call_count, len(kinds) + 2)
            self.assertIsNone(api.visible_v2(None, 'user', {'notification_type': 'unknown'}))
            self.assertEqual(visible.call_count, len(kinds) + 2)

    def test_filtered_page_advances_string_cursor_and_preserves_access_check(self):
        app = FastAPI()
        app.include_router(api.router)
        app.dependency_overrides[require_firebase_user] = lambda: {'uid': 'verified'}
        events = [{'notification_id': 'schedule_deleted_7_9'},
                  {'notification_id': 'schedule_changed_7_10'}]
        with TestClient(app) as client, patch.object(api, 'connect', return_value=MagicMock()), \
             patch.object(api, '_user_id', return_value='user'), \
             patch.object(api, 'list_notification_events', return_value=events), \
             patch.object(api, 'visible_v2', return_value=None) as visible:
            result = client.get('/schedule-notifications?scope=v2&limit=1').json()
            self.assertEqual(result, {'results': [], 'next_before_id': 'schedule_deleted_7_9'})
            visible.assert_called_once()


if __name__ == '__main__':
    unittest.main()
