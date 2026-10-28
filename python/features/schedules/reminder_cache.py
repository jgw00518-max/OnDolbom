"""Firestore에서 발행 완료가 확인된 일정 버전만 기억한다."""
from collections import OrderedDict
from threading import RLock
from time import monotonic


class CompletedReminders:
    def __init__(self, capacity=4096, ttl=72 * 3600, clock=monotonic):
        self.capacity, self.ttl, self.clock = capacity, ttl, clock
        self._entries = OrderedDict()
        self._lock = RLock()

    def contains(self, identifier):
        with self._lock:
            expires = self._entries.get(identifier)
            if expires is None:
                return False
            if expires <= self.clock():
                self._entries.pop(identifier, None)
                return False
            self._entries.move_to_end(identifier)
            return True

    def remember(self, identifier):
        with self._lock:
            self._entries[identifier] = self.clock() + self.ttl
            self._entries.move_to_end(identifier)
            # 서버를 오래 켜도 메모리 사용량이 일정 개수 이상 증가하지 않게 한다.
            while len(self._entries) > self.capacity:
                self._entries.popitem(last=False)


completed_reminders = CompletedReminders()
