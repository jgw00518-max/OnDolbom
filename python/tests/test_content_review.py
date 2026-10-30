"""이름·메모 변경 비교는 응답 이력과 시간 변경을 구분한다."""
import unittest
from python.features.schedules.content_review import content_change


def snapshot(seq, name='원래 이름', memo='원래 메모', start='15:00:00'):
    return dict(history_seq=seq, schedule_name=name, schedule_memo=memo,
                schedule_date='2026-10-30', start_time=start, end_time='18:00:00')


class ContentReviewTests(unittest.TestCase):
    def test_acceptance_without_content_change_does_not_create_notice(self):
        self.assertIsNone(content_change([snapshot(0), snapshot(1)]))

    def test_text_changes_preserve_each_unseen_baseline(self):
        result = content_change([snapshot(0), snapshot(2, name='새 이름'),
                                 snapshot(3, name='새 이름', memo='새 메모')])
        self.assertEqual(result['version'], '3')
        self.assertEqual(result['changes'][0]['before']['schedule_name'], '원래 이름')
        self.assertEqual(result['changes'][1]['before']['schedule_memo'], '원래 메모')

    def test_response_keeps_content_change_version(self):
        result = content_change([snapshot(0), snapshot(2, memo='새 메모'),
                                 snapshot(3, memo='새 메모')])
        self.assertEqual(result['version'], '2')

    def test_time_change_clears_old_text_notice(self):
        result = content_change([snapshot(0), snapshot(2, memo='새 메모'),
                                 snapshot(3, memo='새 메모', start='14:00:00')])
        self.assertIsNone(result)

    def test_text_change_during_pending_compares_to_latest_time(self):
        result = content_change([snapshot(0), snapshot(2, start='14:00:00'),
                                 snapshot(3, memo='새 메모', start='14:00:00')])
        self.assertEqual(result['before']['start_time'], '14:00:00')
        self.assertEqual(result['before']['schedule_memo'], '원래 메모')
