import unittest
from unittest.mock import MagicMock, patch
from python.features.activity import router as api


class CareMenuBadgesTest(unittest.TestCase):
    def test_same_scan_groups_only_unread_visible_events_by_room(self):
        events = [dict(notification_id='memo', notification_type='memo_created', family_room_id='a'),
                  dict(notification_id='med', notification_type='medication_created', family_room_id='b'),
                  dict(notification_id='schedule', notification_type='schedule_urgent', family_room_id='a'),
                  dict(notification_id='read', notification_type='memo_created', family_room_id='a'),
                  dict(notification_id='join', notification_type='member_joined', family_room_id='a')]
        menu = {}
        with patch.object(api, 'list_notification_events', return_value=events) as fetch, patch.object(api, '_visible', side_effect=lambda c,u,e: dict(e, read_at='time' if e['notification_id']=='read' else None)):
            self.assertEqual(api.notification_count(MagicMock(), 'user', menu), 4)
        self.assertEqual(menu, {'a': {'memos': ['memo'], 'schedules': ['schedule']}, 'b': {'medications': ['med']}})
        fetch.assert_called_once()

    def test_mark_only_snapshot_ids_with_matching_room_category_and_permission(self):
        events = {
            'ok': dict(family_room_id='room', notification_type='memo_created'),
            'other-room': dict(family_room_id='elsewhere', notification_type='memo_created'),
            'other-menu': dict(family_room_id='room', notification_type='medication_created'),
            'forbidden': dict(family_room_id='room', notification_type='memo_created'),
        }
        with patch.object(api, 'connect'), patch.object(api, 'current_user', return_value='user'), patch.object(api.store, 'get_event', side_effect=events.get) as get, patch.object(api, '_visible', side_effect=lambda c,u,e: dict(read_at=None) if e is events['ok'] else None), patch.object(api.store, 'mark_many_read') as mark:
            result = api.read_care_menu('room', 'memos', api.CareMenuReceipt(notification_ids=list(events)), {'uid':'uid'})
        self.assertEqual(result['count'], 1)
        mark.assert_called_once_with(['ok'], 'user')
        self.assertEqual(get.call_count, 4)  # 목록 진입 후 새로 도착한 미지정 알림은 조회·읽음 처리하지 않는다.
