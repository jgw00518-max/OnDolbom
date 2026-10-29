"""개인 알림 삭제의 권한·페이징·기존 읽음 보존을 외부 호출 없이 검증한다."""
import unittest
from unittest.mock import MagicMock, patch
from fastapi import FastAPI
from fastapi.testclient import TestClient
from python.features.auth.firebase_auth import require_firebase_user
from python.features.schedules import notification_router as api
from python.features.notifications import store


class NotificationDeletionTests(unittest.TestCase):
    def setUp(self):
        app = FastAPI()
        app.include_router(api.router)
        app.dependency_overrides[require_firebase_user] = lambda: {'uid': 'verified'}
        self.client = TestClient(app)
        self.addCleanup(self.client.close)
        self.conn = MagicMock()
        self.enterContext(patch.object(api, 'connect', return_value=self.conn))
        self.enterContext(patch.object(api, '_user_id', return_value='owner'))
        self.cache = self.enterContext(patch.object(api.badge_cache, 'invalidate'))

    def test_bulk_traverses_unloaded_pages_and_only_visible_events(self):
        first = [{'notification_id': str(i)} for i in range(100)]
        listing = self.enterContext(patch.object(api, 'list_notification_events', side_effect=[first, [{'notification_id': 'last'}]]))
        self.enterContext(patch.object(api, 'visible_v2', side_effect=lambda conn, user, e: None if e['notification_id'] == '0' else e))
        hide = self.enterContext(patch.object(store, 'hide_many'))
        result = self.client.delete('/schedule-notifications')
        self.assertEqual(result.status_code, 200)
        self.assertEqual(result.json()['count'], 100)
        ids, user = hide.call_args.args
        self.assertEqual(user, 'owner')
        self.assertIn('last', ids); self.assertNotIn('0', ids)
        self.assertEqual(listing.call_args_list[1].args, ('owner', '99', 100))
        self.cache.assert_called_once_with('verified')

    def test_individual_delete_uses_verified_owner(self):
        required = self.enterContext(patch.object(api, '_required', return_value={}))
        hide = self.enterContext(patch.object(store, 'hide_many'))
        self.assertEqual(self.client.delete('/schedule-notifications/a').status_code, 200)
        required.assert_called_once_with(self.conn, 'owner', 'a')
        hide.assert_called_once_with(['a'], 'owner')

    def test_foreign_pending_or_missing_event_is_rejected(self):
        hide = self.enterContext(patch.object(store, 'hide_many'))
        for event in [None, {'status': 'pending', 'recipient_ids': ['owner']},
                      {'status': 'published', 'recipient_ids': ['other']}]:
            with patch.object(store, 'get_event', return_value=event):
                self.assertEqual(self.client.delete('/schedule-notifications/foreign').status_code, 404)
        hide.assert_not_called()
        self.cache.assert_not_called()

    def test_delete_failure_does_not_report_success(self):
        self.enterContext(patch.object(api, 'list_notification_events', return_value=[{'notification_id': 'a'}]))
        self.enterContext(patch.object(api, 'visible_v2', side_effect=lambda c, u, e: e))
        self.enterContext(patch.object(store, 'hide_many', side_effect=ValueError('offline')))
        self.assertEqual(self.client.delete('/schedule-notifications').status_code, 503)
        self.cache.assert_called_once_with('verified')

    def test_deleted_receipt_hides_only_its_owner_and_keeps_same_read_count(self):
        event = dict(status='published', recipient_ids=['owner', 'family'], schedule_seq=7,
                     family_room_id='space', schedule_created_at='stamp', created_at='now')
        cursor = self.conn.cursor.return_value.__enter__.return_value
        cursor.fetchone.return_value = {'created_at': 'stamp'}
        with patch.object(store, 'inbox_state', side_effect=lambda identifier, user:
                          {'read_at': 'first', 'deleted_at': 'hidden'} if user == 'owner' else {'read_at': 'first'}) as read:
            self.assertIsNone(api._visible(self.conn, 'owner', event))
            self.assertEqual(api._visible(self.conn, 'family', event)['read_at'], 'first')
            self.assertEqual(read.call_count, 2)

    def test_hide_batches_preserve_read_fields_and_never_delete_common_event(self):
        target = MagicMock()
        with patch.object(store, 'collection', return_value=target):
            store.hide_many([str(i) for i in range(401)], 'owner')
        self.assertEqual(target._client.batch.call_count, 2)
        batch = target._client.batch.return_value
        self.assertEqual(batch.set.call_count, 401)
        for call in batch.set.call_args_list:
            self.assertEqual(set(call.args[1]), {'deleted_at'})
            self.assertTrue(call.kwargs['merge'])
        target.document.return_value.delete.assert_not_called()
        self.assertEqual(batch.commit.call_count, 2)

    def test_hidden_page_still_returns_cursor_to_next_page(self):
        events = [{'notification_id': 'hidden'}, {'notification_id': 'next'}]
        self.enterContext(patch.object(api, 'list_notification_events', return_value=events))
        self.enterContext(patch.object(api, 'visible_v2', return_value=None))
        result = self.client.get('/schedule-notifications?scope=v2&limit=1')
        self.assertEqual(result.json(), {'results': [], 'next_before_id': 'hidden'})





    def test_read_all_skips_read_and_hidden_and_scans_all_pages(self):
        first = [{'notification_id': str(i), 'read_at': 'old' if i == 0 else None} for i in range(100)]
        self.enterContext(patch.object(api, 'list_notification_events', side_effect=[first, [{'notification_id': 'last'}]]))
        self.enterContext(patch.object(api, 'visible_v2', side_effect=lambda c, u, e: None if e['notification_id'] == '1' else e))
        save = self.enterContext(patch.object(store, 'mark_many_read'))
        result = self.client.post('/schedule-notifications/read-all')
        self.assertEqual(result.status_code, 200)
        self.assertEqual(result.json()['count'], 99)
        ids, owner = save.call_args.args
        self.assertEqual(owner, 'owner')
        self.assertNotIn('0', ids)
        self.assertNotIn('1', ids)
        self.assertIn('last', ids)
        self.cache.assert_called_once_with('verified')

    def test_read_all_failure_invalidates_cache_without_success(self):
        self.enterContext(patch.object(api, 'list_notification_events', return_value=[{'notification_id': 'a'}]))
        self.enterContext(patch.object(api, 'visible_v2', side_effect=lambda c, u, e: e))
        self.enterContext(patch.object(store, 'mark_many_read', side_effect=ValueError('offline')))
        self.assertEqual(self.client.post('/schedule-notifications/read-all').status_code, 503)
        self.cache.assert_called_once_with('verified')

    def test_read_batches_merge_only_personal_read_field(self):
        target = MagicMock()
        with patch.object(store, 'collection', return_value=target):
            store.mark_many_read([str(i) for i in range(401)], 'owner')
        self.assertEqual(target._client.batch.call_count, 2)
        for call in target._client.batch.return_value.set.call_args_list:
            self.assertEqual(set(call.args[1]), {'read_at'})
            self.assertTrue(call.kwargs['merge'])


class NotificationRouteOrderTests(unittest.TestCase):
    def test_real_schedule_router_routes_bulk_and_single_delete_to_notifications(self):
        from python.features.schedules.router import router
        app = FastAPI()
        app.include_router(router)
        app.dependency_overrides[require_firebase_user] = lambda: {'uid': 'verified'}
        # 실제 라우터 조합으로 검사해야 동적 일정 경로와의 충돌을 잡을 수 있다.
        with patch.object(api, '_run', return_value={'count': 0}) as action, TestClient(app) as client:
            for path in ('/schedules/schedule-notifications', '/schedules/schedule-notifications/event_1'):
                with self.subTest(path=path):
                    action.reset_mock()
                    self.assertEqual(client.delete(path).status_code, 200)
                    action.assert_called_once()
            action.reset_mock()
            self.assertEqual(client.post('/schedules/schedule-notifications/read-all').status_code, 200)
            action.assert_called_once()
