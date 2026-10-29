"""알림 담당자 한 명이 실행하는 통합 worker. --once는 작업별 한 번 검사 후 종료한다."""
import argparse
import logging
from threading import Event, Thread
from time import monotonic
from python.features.schedules.reminders import check_reminders
from python.features.notifications.push import check_push_notifications
from python.features.chats.push_outbox import check_chat_pushes
from python.features.schedules.reconfirm_expiry_worker import (
    check_expired_requests,
    retry_pending_notifications,
)


def next_push_interval(current, pending):
    """빈 큐는 5→10→15초로 늦추고, 작업이 있으면 즉시 5초로 복귀한다."""
    return 5 if pending else min(current + 5, 15)


def _run_job(name, action, interval, stop, *, once=False, adaptive=False, fixed_rate=False):
    """작업마다 연결·대기 주기를 분리한다. 같은 작업을 겹쳐 실행하지 않는다."""
    delay = interval
    while not stop.is_set():
        started = monotonic()
        try:
            result = action()
            if adaptive:
                delay = next_push_interval(delay, result)
        except Exception:
            logging.exception('%s 실패; 다음 주기에 재시도', name)
            if adaptive:
                # 장애 시 기존 푸시 검사와 같이 15초를 기다려 Firestore 반복 조회를 제한한다.
                delay = 15
        if once:
            return
        wait = max(0, delay - (monotonic() - started)) if fixed_rate else delay
        # sleep 대신 Event를 기다려 Ctrl+C 종료 시 긴 주기 작업도 즉시 깨운다.
        if stop.wait(wait):
            return


def _start_jobs(stop, once):
    jobs = [
        ('72시간 재알림', check_reminders, 60, False, False),
        ('일정 푸시', check_push_notifications, 5, True, False),
        ('채팅 푸시', check_chat_pushes, 5, False, False),
        ('재수락 만료·미확인', check_expired_requests, 60, False, True),
        ('미발행 알림 재시도', retry_pending_notifications, 60, False, True),
    ]
    threads = []
    for name, action, interval, adaptive, fixed_rate in jobs:
        # 각 작업은 자체 DB 연결을 사용한다. 지연·장애가 다른 작업의 실행을 막지 않는다.
        thread = Thread(target=_run_job, name=name, daemon=True,
                        args=(name, action, interval, stop),
                        kwargs={'once': once, 'adaptive': adaptive, 'fixed_rate': fixed_rate})
        thread.start()
        threads.append(thread)
    return threads


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--once', action='store_true', help='모든 작업을 한 번씩 확인하고 종료')
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO)
    stop = Event()
    threads = []
    logging.info('통합 알림 worker 시작: 재알림·일정/채팅 푸시·재수락 만료·미발행 재시도')
    try:
        threads = _start_jobs(stop, args.once)
        while any(thread.is_alive() for thread in threads):
            for thread in threads:
                thread.join(timeout=0.2)
    except KeyboardInterrupt:
        logging.info('통합 알림 worker 종료 요청')
    finally:
        stop.set()
        # 실행 중인 I/O에 최대 5초의 공통 종료 시간을 준다. 프로세스 종료 후 자식은 남지 않는다.
        deadline = monotonic() + 5
        for thread in threads:
            thread.join(timeout=max(0, deadline - monotonic()))
        logging.info('통합 알림 worker 종료')


if __name__ == '__main__':
    main()
