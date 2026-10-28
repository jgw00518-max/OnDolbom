from datetime import datetime
from unittest import TestCase
from unittest.mock import MagicMock, patch
from fastapi.testclient import TestClient
from google.api_core.exceptions import PermissionDenied
from python.main import app
from python.features.auth.firebase_auth import require_firebase_user
from python.features.notifications import store
from python.features.notifications.schedule_notifications import prepare_schedule_notifications, publish_schedule_notifications

BASE = 'python.features.notifications.'


class NotificationTests(TestCase):
    def setUp(self):
        self.client = TestClient(app)
        self.connection = MagicMock()
        self.cursor = self.connection.cursor.return_value.__enter__.return_value
        self.cursor.fetchone.return_value = {'user_id': 'internal'}
        app.dependency_overrides[require_firebase_user] = lambda: {'uid': 'verified'}

    def tearDown(self):
        app.dependency_overrides.clear()
        self.client.close()

    def test_missing_token_rejected_before_db(self):
        app.dependency_overrides.clear()
        with patch(BASE + 'router.connect') as connect:
            self.assertEqual(self.client.get('/notifications').status_code, 401)
            connect.assert_not_called()

    def test_list_uses_verified_owner_and_advances_filtered_cursor(self):
        with patch(BASE + 'router.connect', return_value=self.connection), patch(
                BASE + 'store.list_events', return_value=[{'schedule_seq': 3}, {'schedule_seq': 2}]) as listing:
            response = self.client.get('/notifications?user_id=foreign&limit=1')
        self.assertEqual(response.json(), {'results': [], 'next_before_id': 3})
        listing.assert_called_once_with('internal', None, 2)
        self.connection.close.assert_called_once()

    def test_firestore_failure_is_not_empty_success(self):
        with patch(BASE + 'router.connect', return_value=self.connection), patch(
                BASE + 'store.list_events', side_effect=PermissionDenied('private details')):
            response = self.client.get('/notifications')
        self.assertEqual(response.status_code, 503)
        self.assertNotIn('private details', response.text)

    def test_foreign_and_pending_notifications_cannot_be_read(self):
        for event in ({'status': 'published', 'recipient_ids': ['other']},
                      {'status': 'pending', 'recipient_ids': ['internal']}):
            with patch(BASE + 'router.connect', return_value=self.connection), patch(
                    BASE + 'store.get_event', return_value=event), patch(BASE + 'store.mark_read') as mark:
                self.assertEqual(self.client.post('/notifications/7/read').status_code, 404)
                mark.assert_not_called()

    def test_current_membership_is_checked_for_detail(self):
        event = dict(status='published', recipient_ids=['internal'], schedule_seq=7,
                     family_room_id='space', schedule_created_at='stamp')
        self.cursor.fetchone.side_effect = [{'user_id': 'internal'}, None]
        with patch(BASE + 'router.connect', return_value=self.connection), patch(BASE + 'store.get_event', return_value=event):
            self.assertEqual(self.client.get('/notifications/7/schedule').status_code, 404)
        sql, params = self.cursor.execute.call_args.args
        self.assertIn('p.left_at IS NULL', sql)
        self.assertIn('s.deleted_at IS NULL', sql)
        self.assertEqual(params, (7, 'space', 'internal'))

    def test_prepare_freezes_all_current_family_without_committing(self):
        stamp = datetime(2026, 10, 23)
        self.cursor.fetchone.return_value = dict(family_room_id='space', created_at=stamp, created_by='creator')
        self.cursor.fetchall.return_value = [{'user_id': 'creator'}, {'user_id': 'family'}]
        with patch(BASE + 'store.prepare') as prepare:
            prepare_schedule_notifications(self.connection, 7)
        self.assertEqual(prepare.call_args.args[0]['recipient_ids'], ['creator', 'family'])
        self.assertEqual(prepare.call_args.args[0]['actor_id'], 'creator')
        self.connection.commit.assert_not_called()
        self.assertIn('u.withdrawn_at IS NULL', self.cursor.execute.call_args.args[0])

    def test_rollback_schedule_never_publishes(self):
        self.cursor.fetchone.return_value = None
        with patch(BASE + 'schedule_notifications.connect', return_value=self.connection), patch(BASE + 'store.publish') as publish:
            self.assertFalse(publish_schedule_notifications(7))
            publish.assert_not_called()
        self.connection.close.assert_called_once()

    def test_prepare_retry_preserves_audience(self):
        transaction, ref = MagicMock(), MagicMock()
        ref.get.return_value.exists = True
        ref.get.return_value.to_dict.return_value = dict(family_room_id='space', schedule_created_at='stamp', recipient_ids=['old'])
        store._prepare(transaction, ref, dict(family_room_id='space', schedule_created_at='stamp', recipient_ids=['new']))
        transaction.create.assert_not_called()
        transaction.update.assert_not_called()

    def test_repeat_read_preserves_first_timestamp(self):
        transaction, ref = MagicMock(), MagicMock()
        ref.get.return_value.exists = True
        store._mark_read(transaction, ref)
        transaction.create.assert_not_called()
        ref.get.return_value.exists = False
        store._mark_read(transaction, ref)
        transaction.create.assert_called_once()

    def test_only_matching_committed_event_publishes(self):
        transaction, ref = MagicMock(), MagicMock()
        ref.get.return_value.exists = True
        ref.get.return_value.to_dict.return_value = dict(status='pending', schedule_created_at='stamp')
        self.assertFalse(store._publish(transaction, ref, 'other'))
        transaction.update.assert_not_called()
        self.assertTrue(store._publish(transaction, ref, 'stamp'))
        transaction.update.assert_called_once()
