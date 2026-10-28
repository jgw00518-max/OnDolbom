import unittest
from unittest.mock import MagicMock, patch
from fastapi import FastAPI, HTTPException
from fastapi.testclient import TestClient
from google.api_core.exceptions import ServiceUnavailable
from python.features.activity import router as activity, receipts
from python.features.auth.firebase_auth import require_firebase_user


class ActivityTests(unittest.TestCase):
    def setUp(self):
        activity.badge_cache.invalidate('firebase-a')
        app = FastAPI()
        app.include_router(activity.router)
        app.dependency_overrides[require_firebase_user] = lambda: {'uid': 'firebase-a'}
        self.client = TestClient(app)

    def test_badges_cache_and_force_still_verify_identity(self):
        with patch.object(activity, 'connect'), \
             patch.object(activity, 'current_user', return_value='mysql-a') as identity, \
             patch.object(activity, 'invite_count', return_value=1), \
             patch.object(activity, 'notification_count', return_value=2) as count, \
             patch.object(activity, 'notice_count', return_value=3), \
             patch.object(activity, 'inquiry_count', return_value=4):
            self.assertEqual(self.client.get('/activity/badges').status_code, 200)
            self.client.get('/activity/badges')
            self.assertEqual(count.call_count, 1)
            self.assertEqual(identity.call_count, 2)
            self.client.get('/activity/badges?force=true')
            self.assertEqual(count.call_count, 2)

    def test_successful_read_invalidates_cache(self):
        loader = MagicMock(return_value={'notifications': 1})
        activity.badge_cache.load('firebase-a', loader)
        with patch.object(receipts, 'mark_read'):
            activity.save_receipt({'uid': 'firebase-a'}, 'notice', ['a', 'b'], 'token')
        activity.badge_cache.load('firebase-a', loader)
        self.assertEqual(loader.call_count, 2)

    def test_requires_auth_before_database(self):
        self.client.app.dependency_overrides.clear()
        with patch.object(activity, 'connect') as connect:
            self.assertEqual(self.client.get('/activity/badges').status_code, 401)
            connect.assert_not_called()

    def test_counts_use_verified_identity_and_partial_failure_is_not_zero(self):
        connection = MagicMock()
        with patch.object(activity, 'connect', return_value=connection), \
             patch.object(activity, 'current_user', return_value='mysql-a'), \
             patch.object(activity, 'invite_count', return_value=2) as invites, \
             patch.object(activity, 'notification_count', side_effect=ServiceUnavailable('private')), \
             patch.object(activity, 'notice_count', return_value=3) as notices, \
             patch.object(activity, 'inquiry_count', return_value=1) as inquiries:
            self.assertEqual(self.client.get('/activity/badges').json(),
                             {'invites': 2, 'notifications': None, 'notices': 3, 'inquiries': 1})
            invites.assert_called_once_with(connection, 'mysql-a')
            notices.assert_called_once_with(connection, 'firebase-a')
            inquiries.assert_called_once_with(connection, 'mysql-a', 'firebase-a')
            connection.close.assert_called_once()

    def test_invites_filter_expiry_deleted_and_recipient_email_without_writes(self):
        connection = MagicMock()
        cursor = connection.cursor.return_value.__enter__.return_value
        cursor.fetchone.return_value = {'count': 2}
        self.assertEqual(activity.invite_count(connection, 'mysql-a'), 2)
        sql, args = cursor.execute.call_args.args
        for condition in ['INTERVAL 7 DAY', 'invite_deleted_at IS NULL', 'family_room_deleted_at IS NULL', 'sender.withdrawn_at IS NULL', 'recipient.user_email']:
            self.assertIn(condition, sql)
        self.assertEqual(args, ('mysql-a', '대기'))
        self.assertNotIn('UPDATE', sql)

    def test_multiple_answers_count_as_one_inquiry_and_new_answer_changes_token(self):
        connection = MagicMock()
        rows = [{'question_seq': 4, 'answer_seq': 1, 'answer_content': 'one', 'answered_at': '2026-10-27'},
                {'question_seq': 4, 'answer_seq': 2, 'answer_content': 'two', 'answered_at': '2026-10-27'}]
        connection.cursor.return_value.__enter__.return_value.fetchall.return_value = rows
        with patch.object(receipts, 'unread_count', return_value=1) as count:
            self.assertEqual(activity.inquiry_count(connection, 'mysql-a', 'firebase-a'), 1)
            items = count.call_args.args[1]
            self.assertEqual(len(items), 1)
            self.assertNotEqual(next(iter(items.values())), receipts.answer_token(rows[:1]))

    def test_notification_count_scans_all_pages_and_excludes_read_and_inaccessible(self):
        first = [{'schedule_seq': i, 'notification_id': str(i)} for i in range(200, 100, -1)]
        with patch.object(activity, 'list_notification_events', side_effect=[first, [{'schedule_seq': 100, 'notification_id': '100'}]]), \
             patch.object(activity, '_visible', side_effect=lambda c, u, e: None if e['schedule_seq'] == 100 else {'read_at': None if e['schedule_seq'] % 2 else 'read'}):
            self.assertEqual(activity.notification_count(MagicMock(), 'mysql-a'), 50)
            self.assertEqual(activity.list_notification_events.call_args_list[1].args[1], '101')

    def test_same_schedule_events_have_independent_unread_receipts(self):
        events = [{'notification_id': '7', 'schedule_seq': 7},
                  {'notification_id': 'schedule_changed_7_9', 'schedule_seq': 7},
                  {'notification_id': 'schedule_reconfirm_7_10', 'schedule_seq': 7}]
        with patch.object(activity, 'list_notification_events', return_value=events), \
             patch.object(activity, '_visible', side_effect=[{'read_at': 'read'}, {'read_at': None}, {'read_at': None}]):
            self.assertEqual(activity.notification_count(MagicMock(), 'mysql-a'), 2)

    def test_notice_read_uses_composite_key_and_only_displayed_version(self):
        row = {'admin_id': 'admin', 'notice_id': 'n', 'notice_content': 'shown'}
        token = receipts.notice_token(row)
        with patch.object(activity, 'read_notices', return_value=row), patch.object(receipts, 'mark_read') as mark:
            self.assertEqual(self.client.post('/activity/notices/admin/n/read', json={'token': token}).status_code, 200)
            mark.assert_called_once_with('firebase-a', receipts.receipt_key('notice', ['admin', 'n']), token)
            mark.reset_mock()
            self.assertEqual(self.client.post('/activity/notices/admin/n/read', json={'token': '0' * 64}).status_code, 409)
            mark.assert_not_called()

    def test_cannot_read_another_users_answer(self):
        with patch.object(activity, 'inquiry_detail', side_effect=HTTPException(404)), patch.object(receipts, 'mark_read') as mark:
            self.assertEqual(self.client.post('/activity/inquiries/99/read', json={'token': '0' * 64}).status_code, 404)
            mark.assert_not_called()

    def test_receipt_comparison_ignores_deleted_and_compares_versions(self):
        client = MagicMock()
        snapshots = []
        for key, token in [('read', 'version'), ('changed', 'old')]:
            snap = MagicMock()
            snap.id = key
            snap.to_dict.return_value = {'token': token}
            snapshots.append(snap)
        client.get_all.return_value = snapshots
        with patch.object(receipts, 'collection') as collection, patch.object(receipts.firestore, 'client', return_value=client), patch.object(receipts, 'get_firebase_app'):
            self.assertEqual(receipts.unread_count('user-a', {'read': 'version', 'changed': 'new', 'missing': 'new'}), 2)
            self.assertEqual(collection.call_args.args, ('user-a',))


if __name__ == '__main__':
    unittest.main()
