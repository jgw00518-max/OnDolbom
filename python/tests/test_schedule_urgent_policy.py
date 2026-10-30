import unittest
from datetime import date, datetime, timedelta
from unittest.mock import MagicMock, patch
from python.features.schedules.reconfirm_policy import get_reconfirm_deadline
from python.features.schedules import reconfirm_expiry as expiry
from python.features.schedules import urgent_reconfirm as phone
from python.features.schedules import urgent_schedule as urgent

START = datetime(2026, 11, 5, 12)

def deadline(hours, now=None):
    return get_reconfirm_deadline(START-timedelta(hours=hours), START.date(), '12:00:00', now=now)

def request(hours=30):
    return dict(requested_at=START-timedelta(hours=hours), request_history_seq=8,
                current=dict(schedule_date=START.date(), start_time='12:00:00'))

class PolicyTests(unittest.TestCase):
    def test_general_deadline_30_hours(self):
        self.assertEqual(deadline(30)['response_due_at'], START-timedelta(hours=24))

    def test_general_deadline_72_hours(self):
        self.assertEqual(deadline(72)['response_due_at'], START-timedelta(hours=48))

    def test_exact_24_and_12_are_urgent_without_expiry(self):
        for hours in [24, 12, 1]:
            self.assertEqual(deadline(hours), dict(is_urgent=True, response_due_at=None))
        self.assertFalse(deadline(24.0001)['is_urgent'])

    def test_pending_request_transitions_using_current_time(self):
        self.assertTrue(deadline(30, START-timedelta(hours=24))['is_urgent'])
        self.assertFalse(deadline(30, START-timedelta(hours=24, seconds=1))['is_urgent'])

    def expiry_at(self, now):
        conn = MagicMock()
        conn.cursor.return_value.__enter__.return_value.fetchone.side_effect = [
            {'family_room_id':'r'}, {'accepted_by':'member', 'schedule_state':'미완료'}, {'server_now':now}]
        with patch.object(expiry, 'get_pending_reconfirm_request', return_value=request()):
            return expiry.get_expired_reconfirm_request(conn, 1, 'r')

    def test_boundary_prefers_urgent_to_release(self):
        self.assertIsNone(self.expiry_at(START-timedelta(hours=24)))

    def test_general_unanswered_releases_before_urgent(self):
        conn = MagicMock()
        conn.cursor.return_value.__enter__.return_value.fetchone.side_effect = [
            {'family_room_id':'r'}, {'accepted_by':'member', 'schedule_state':'미완료'},
            {'server_now':START-timedelta(hours=47)}]
        with patch.object(expiry, 'get_pending_reconfirm_request', return_value=request(72)):
            self.assertIsNotNone(expiry.get_expired_reconfirm_request(conn, 1, 'r'))

    def test_phone_at_boundary_but_no_started_unverified_notice(self):
        for now, expected in [(START-timedelta(hours=24), True),
                              (START-timedelta(hours=25), False), (START, False)]:
            conn = MagicMock()
            conn.cursor.return_value.__enter__.return_value.fetchone.side_effect = [
                {'family_room_id':'r'}, {'accepted_by':'m','schedule_state':'미완료','created_at':START},
                {'server_now':now}]
            with patch.object(phone, 'get_pending_reconfirm_request', return_value=request()):
                self.assertEqual(phone.get_urgent_unverified_request(conn, 1, 'r') is not None, expected)

    def test_unassigned_urgent_boundary_and_exclusions(self):
        row = dict(schedule_date=START.date(), start_time='12:00:00',
                   server_now=START-timedelta(hours=24), deleted_at=None,
                   accepted_by=None, schedule_state='미완료')
        self.assertTrue(urgent.is_urgent(row))
        for change in [dict(server_now=START-timedelta(hours=25)), dict(server_now=START),
                       dict(accepted_by='m'), dict(deleted_at=START), dict(schedule_state='완료')]:
            self.assertFalse(urgent.is_urgent(dict(row, **change)))

    def test_atomic_single_publication(self):
        transaction, ref = MagicMock(), MagicMock()
        ref.get.return_value.exists = False
        self.assertTrue(urgent._publish_once(transaction, ref, {'recipient_ids':['m']}))
        ref.get.return_value.exists = True
        self.assertFalse(urgent._publish_once(transaction, ref, {}))
        transaction.create.assert_called_once()

    def test_urgent_recruitment_reuses_single_event(self):
        event = {'schedule_seq':1, 'notification_id':'recruit_1', 'actor_id':'cancelled'}
        for result in [True, False]:
            with patch.object(urgent,'process_urgent_schedule',return_value=result) as process, \
                 patch.object(urgent,'collection') as collection:
                self.assertTrue(urgent.redirect_urgent_recruitment(event))
                process.assert_called_once_with(1, expected_event=event)
                collection.return_value.document.return_value.update.assert_called_once()

    def test_cancelling_member_excluded_and_current_family_resolved_under_lock(self):
        conn = MagicMock()
        cursor = conn.cursor.return_value.__enter__.return_value
        cursor.fetchone.side_effect = [{'family_room_id':'r'}, {'family_room_id':'r'}]
        cursor.fetchall.side_effect = [
            [dict(history_seq=9, changed_by='member', update_accepted_by=None),
             dict(history_seq=8, changed_by='guardian', update_accepted_by='member')],
            [{'user_id':'guardian'}, {'user_id':'member'}, {'user_id':'other'}]]
        current = dict(schedule_seq=1, family_room_id='r', created_at=START,
                       schedule_date=START.date(), start_time='12:00:00',
                       server_now=START-timedelta(hours=24), deleted_at=None,
                       accepted_by=None, schedule_state='미완료')
        publish = MagicMock(return_value=True)
        with patch.object(urgent, 'connect', return_value=conn), \
             patch.object(urgent, 'load_state', return_value=(current, 'version')) as load, \
             patch.object(urgent, 'collection'), \
             patch.object(urgent.firestore, 'transactional', return_value=publish), \
             patch.object(urgent, 'completed', urgent.CompletedReminders()):
            self.assertTrue(urgent.process_urgent_schedule(1))
        payload = publish.call_args.args[2]
        self.assertEqual(payload['recipient_ids'], ['guardian','other'])
        self.assertEqual(payload['actor_id'], 'member')
        load.assert_called_once_with(conn, 1, lock=True)
        conn.rollback.assert_called_once()
        conn.close.assert_called_once()

    def test_phone_published_request_not_sent_twice(self):
        conn = MagicMock()
        with patch.object(phone,'connect',return_value=conn), \
             patch.object(phone,'get_urgent_unverified_request',return_value={'request':request()}), \
             patch.object(phone,'prepare_urgent_reconfirm_notification',return_value='phone_8'), \
             patch.object(phone,'get_event',return_value={'status':'published'}), \
             patch.object(phone,'publish_urgent_reconfirm_notification') as publish:
            result = phone.process_urgent_reconfirm_notice(1,'r')
        self.assertFalse(result['notified'])
        self.assertTrue(result['already_published'])
        publish.assert_not_called()

if __name__ == '__main__':
    unittest.main()
