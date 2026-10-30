"""통합 worker는 외부 DB·Firestore·FCM을 호출하지 않고 검증한다."""
import unittest
from threading import Event
from unittest.mock import MagicMock, patch
from python.features.schedules import reminder_worker as worker


class UnifiedWorkerTests(unittest.TestCase):
    def setUp(self):
        self.cleanup = self.enterContext(patch.object(worker, 'check_account_cleanup'))

    def test_once_starts_all_six_jobs_and_finishes(self):
        with patch('sys.argv', ['worker', '--once']), \
             patch.object(worker, 'check_reminders') as reminders, \
             patch.object(worker, 'check_push_notifications') as push, \
             patch.object(worker, 'check_chat_pushes') as chat, \
             patch.object(worker, 'check_expired_requests') as expiry, \
             patch.object(worker, 'retry_pending_notifications') as retry:
            worker.main()
        for action in [reminders, push, chat, expiry, retry, self.cleanup]:
            action.assert_called_once()

    def test_slow_expiry_does_not_block_chat_or_other_jobs(self):
        released, entered, chat_done = Event(), Event(), Event()
        def slow_expiry():
            entered.set()
            if not released.wait(2):
                raise AssertionError('다른 작업이 실행되지 않았습니다.')
        def chat():
            if not entered.wait(2):
                raise AssertionError('만료 검사가 병렬로 시작되지 않았습니다.')
            chat_done.set()
            released.set()
        with patch.object(worker, 'check_reminders'), \
             patch.object(worker, 'check_push_notifications'), \
             patch.object(worker, 'check_chat_pushes', side_effect=chat), \
             patch.object(worker, 'check_expired_requests', side_effect=slow_expiry), \
             patch.object(worker, 'retry_pending_notifications'):
            threads = worker._start_jobs(Event(), True)
            for thread in threads:
                thread.join(timeout=3)
        self.assertTrue(entered.is_set())
        self.assertTrue(chat_done.is_set())
        self.assertFalse(any(thread.is_alive() for thread in threads))

    def test_failed_job_does_not_stop_remaining_jobs(self):
        with patch('sys.argv', ['worker', '--once']), \
             patch.object(worker, 'check_reminders', side_effect=ValueError('offline')), \
             patch.object(worker, 'check_push_notifications') as push, \
             patch.object(worker, 'check_chat_pushes') as chat, \
             patch.object(worker, 'check_expired_requests') as expiry, \
             patch.object(worker, 'retry_pending_notifications') as retry, \
             self.assertLogs(level='ERROR'):
            worker.main()
        for action in [push, chat, expiry, retry]:
            action.assert_called_once()

    def test_adaptive_push_delay_is_preserved_and_errors_back_off(self):
        stop = MagicMock()
        stop.is_set.return_value = False
        stop.wait.side_effect = [False, False, False, True]
        action = MagicMock(side_effect=[0, 0, ValueError('offline'), 1])
        with self.assertLogs(level='ERROR'):
            worker._run_job('push', action, 5, stop, adaptive=True)
        self.assertEqual([call.args[0] for call in stop.wait.call_args_list], [10, 15, 15, 5])

    def test_stopped_worker_does_not_start_another_query(self):
        stop = Event(); stop.set()
        action = MagicMock()
        worker._run_job('chat', action, 5, stop)
        action.assert_not_called()

    def test_fixed_rate_expiry_keeps_one_minute_cadence(self):
        stop = MagicMock()
        stop.is_set.return_value = False
        stop.wait.return_value = True
        with patch.object(worker, 'monotonic', side_effect=[100, 107]):
            worker._run_job('expiry', MagicMock(), 60, stop, fixed_rate=True)
        stop.wait.assert_called_once_with(53)

    def test_ctrl_c_signals_all_threads_to_stop(self):
        thread = MagicMock()
        thread.is_alive.return_value = True
        thread.join.side_effect = [KeyboardInterrupt(), None]
        with patch('sys.argv', ['worker']), patch.object(worker, '_start_jobs', return_value=[thread]) as start:
            worker.main()
        self.assertTrue(start.call_args.args[0].is_set())
        self.assertEqual(thread.join.call_count, 2)


if __name__ == '__main__': unittest.main()
