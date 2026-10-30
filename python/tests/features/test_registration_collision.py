"""숫자 일정 번호 재사용으로 등록이 롤백되던 문제를 외부 호출 없이 검증한다."""
import unittest
from unittest.mock import MagicMock, patch

from python.features.notifications import store, schedule_notifications as notifications
from python.features.schedules import reconfirm_expiry_worker as worker
from python.features.schedules import router as schedules


def payload(room='current', stamp='created'):
    return dict(schedule_seq=7, family_room_id=room, schedule_created_at=stamp,
                actor_id='owner', recipient_ids=['owner', 'family'])


class RegistrationCollisionTests(unittest.TestCase):
    def test_unused_numeric_id_keeps_existing_contract(self):
        transaction, ref = MagicMock(), MagicMock(id='7')
        ref.get.return_value.exists = False
        store._prepare(transaction, ref, payload())
        saved = transaction.create.call_args.args[1]
        self.assertEqual(saved['recipient_ids'], ['family'])
        ref.parent.document.assert_not_called()

    def test_old_numeric_event_is_preserved_and_new_schedule_uses_versioned_id(self):
        transaction, ref = MagicMock(), MagicMock(id='7')
        ref.get.return_value.exists = True
        ref.get.return_value.to_dict.return_value = payload('another-room', 'old')
        target = ref.parent.document.return_value
        target.id = store.registration_identifier(payload())
        target.get.return_value.exists = False
        store._prepare(transaction, ref, payload())
        ref.parent.document.assert_called_once_with(target.id)
        created_ref, saved = transaction.create.call_args.args
        self.assertIs(created_ref, target)
        self.assertEqual(saved['notification_id'], target.id)
        self.assertEqual(saved['notification_type'], 'schedule_created')
        self.assertEqual(saved['recipient_ids'], ['family'])
        transaction.update.assert_not_called()
        transaction.delete.assert_not_called()

    def test_repeat_collision_preserves_existing_versioned_audience_and_receipts(self):
        transaction, ref = MagicMock(), MagicMock(id='7')
        ref.get.return_value.exists = True
        ref.get.return_value.to_dict.return_value = payload('old-room', 'old')
        target = ref.parent.document.return_value
        target.id = store.registration_identifier(payload())
        target.get.return_value.exists = True
        target.get.return_value.to_dict.return_value = {**payload(), 'recipient_ids': ['first-family']}
        store._prepare(transaction, ref, payload())
        transaction.create.assert_not_called()
        transaction.update.assert_not_called()

    def test_identity_uses_room_and_creation_time_not_number_alone(self):
        self.assertNotEqual(store.registration_identifier(payload()),
                            store.registration_identifier(payload('another-room')))
        self.assertNotEqual(store.registration_identifier(payload()),
                            store.registration_identifier(payload(stamp='another-time')))

    def test_committed_schedule_publishes_only_matching_version(self):
        conn = MagicMock()
        conn.cursor.return_value.__enter__.return_value.fetchone.return_value = dict(
            created_at='created', family_room_id='current')
        version = store.registration_identifier(payload())
        for old_matches in (True, False):
            with self.subTest(old_matches=old_matches), \
                 patch.object(notifications, 'connect', return_value=conn), \
                 patch.object(store, 'get_event', side_effect=lambda identifier:
                     payload() if identifier == version or old_matches else payload('other-room')), \
                 patch.object(store, 'publish', return_value=True) as publish:
                self.assertTrue(notifications.publish_schedule_notifications(7))
                publish.assert_called_once_with('7' if old_matches else version, 'created')

    def test_old_pending_document_never_publishes_a_reused_schedule_number(self):
        conn = MagicMock()
        conn.cursor.return_value.__enter__.return_value.fetchone.return_value = dict(
            created_at='created', family_room_id='current')
        with patch.object(notifications, 'connect', return_value=conn), \
             patch.object(store, 'get_event', return_value=payload('old-room', 'old')), \
             patch.object(store, 'publish') as publish:
            self.assertFalse(notifications.publish_schedule_notifications(7, identifier='7'))
        publish.assert_not_called()
        conn.close.assert_called_once()

    def test_worker_recovers_versioned_registration_document(self):
        saved = {**payload(), 'notification_type': 'schedule_created', 'status': 'pending'}
        snapshot = MagicMock(id=store.registration_identifier(saved))
        snapshot.to_dict.return_value = saved
        with patch.object(worker, 'collection') as collection, \
             patch.object(worker, 'publish_schedule_notifications', return_value=True) as publish:
            collection.return_value.where.return_value.stream.return_value = [snapshot]
            worker.retry_pending_notifications()
        publish.assert_called_once_with(7, identifier=snapshot.id)

    def test_registration_commits_when_old_notification_uses_the_same_number(self):
        conn = MagicMock()
        cursor = conn.cursor.return_value.__enter__.return_value
        cursor.lastrowid = 7
        cursor.fetchone.return_value = dict(family_room_id='current', created_at='created',
                                           created_by='owner', within_reminder_window=0)
        cursor.fetchall.return_value = [{'user_id': 'owner'}, {'user_id': 'family'}]
        with patch.object(schedules, 'connect', return_value=conn), \
             patch.object(schedules, 'check_representative'), \
             patch.object(schedules, 'check_schedule_overlap'), \
             patch.object(schedules, 'publish_schedule_notifications', return_value=True), \
             patch.object(schedules, 'try_remind', return_value=False), \
             patch.object(schedules, 'try_urgent_schedule', return_value=False), \
             patch.object(store, 'collection') as collection, \
             patch.object(store.firestore, 'transactional', side_effect=lambda f: f):
            ref = collection.return_value.document.return_value
            ref.id = '7'
            ref.get.return_value.exists = True
            ref.get.return_value.to_dict.return_value = payload('old-room', 'old')
            target = ref.parent.document.return_value
            target.id = store.registration_identifier(payload())
            target.get.return_value.exists = False
            result = schedules.create_schedule(schedules.ScheduleCreate(
                family_room_id='current', schedule_date='2099-01-01',
                start_time='10:00', end_time='11:00', schedule_name='등록 검증'), 'owner')
        self.assertEqual(result['schedule_seq'], 7)
        self.assertTrue(result['notification_published'])
        conn.commit.assert_called_once()
        conn.rollback.assert_not_called()
        conn.close.assert_called_once()
