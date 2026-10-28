"""배지 숫자 전용 프로세스 메모리 캐시. 권한 판정에는 사용하지 않는다."""
from collections import OrderedDict
from threading import RLock
from time import monotonic


class BadgeCache:
    def __init__(self, ttl=60, capacity=512, clock=monotonic):
        self.ttl, self.capacity, self.clock = ttl, capacity, clock
        self._items = OrderedDict()
        self._lock = RLock()
        # 같은 계정의 중복 조회를 합치고, 읽음 처리와 계산 결과 저장의 경합을 막는다.
        self._stripes = [RLock() for _ in range(64)]

    def load(self, uid, loader, force=False):
        with self._stripes[hash(uid) % len(self._stripes)]:
            with self._lock:
                entry = self._items.get(uid)
                if not force and entry and entry[0] > self.clock():
                    self._items.move_to_end(uid)
                    return dict(entry[1])
                self._items.pop(uid, None)
            result = loader()
            # 부분 장애의 None을 캐시하지 않아 복구 후 바로 재조회할 수 있게 한다.
            if all(value is not None for value in result.values()):
                with self._lock:
                    self._items[uid] = (self.clock() + self.ttl, dict(result))
                    while len(self._items) > self.capacity:
                        self._items.popitem(last=False)
            return result

    def invalidate(self, uid):
        with self._stripes[hash(uid) % len(self._stripes)], self._lock:
            self._items.pop(uid, None)


badge_cache = BadgeCache()
