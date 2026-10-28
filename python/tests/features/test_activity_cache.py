import unittest
from unittest.mock import Mock
from python.features.activity.cache import BadgeCache


class CacheTests(unittest.TestCase):
    def test_identity_expiry_force_and_copy(self):
        now = [0]
        cache = BadgeCache(clock=lambda: now[0])
        load = Mock(return_value={'notifications': 2})
        first = cache.load('a', load)
        first['notifications'] = 99
        self.assertEqual(cache.load('a', load)['notifications'], 2)
        self.assertEqual(load.call_count, 1)
        cache.load('b', load)
        cache.load('a', load, force=True)
        self.assertEqual(load.call_count, 3)
        now[0] = 60
        cache.load('a', load)
        self.assertEqual(load.call_count, 4)

    def test_invalidation_and_failed_results(self):
        cache = BadgeCache()
        load = Mock(return_value={'notifications': 2})
        cache.load('a', load)
        cache.invalidate('a')
        cache.load('a', load)
        self.assertEqual(load.call_count, 2)
        partial = Mock(return_value={'notifications': None})
        cache.load('a', partial, force=True)
        cache.load('a', partial)
        self.assertEqual(partial.call_count, 2)
        with self.assertRaises(ValueError):
            cache.load('a', Mock(side_effect=ValueError()), force=True)
        cache.load('a', load)
        self.assertEqual(load.call_count, 3)

    def test_capacity_is_bounded(self):
        cache = BadgeCache(capacity=1)
        load = Mock(return_value={'notifications': 1})
        cache.load('a', load)
        cache.load('b', load)
        cache.load('a', load)
        self.assertEqual(load.call_count, 3)
