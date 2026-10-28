"""API 서버가 자동 실행한다. 단독 실행도 가능하며 --once는 한 번만 검사한다."""
import argparse
import logging
from time import monotonic, sleep
from python.features.schedules.reminders import check_reminders
from python.features.notifications.push import check_push_notifications


def next_push_interval(current, pending):
    """빈 큐는 5→10→15초로 늦추고, 작업이 있으면 즉시 5초로 복귀한다."""
    return 5 if pending else min(current + 5, 15)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--once', action='store_true', help='한 번 확인하고 종료')
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO)
    next_reminder_check = 0
    next_push_check = 0
    push_interval = 5
    try:
        while True:
            started = monotonic()
            try:
                if started >= next_reminder_check:
                    logging.info('72시간 재알림 신규 발행: %s건', check_reminders())
                    next_reminder_check = monotonic() + 60
            except Exception:
                logging.exception('재알림 대상 조회 실패; 다음 주기에 재시도')
                next_reminder_check = monotonic() + 60
            if monotonic() >= next_push_check:
                try:
                    pending = check_push_notifications()
                    push_interval = next_push_interval(push_interval, pending)
                except Exception:
                    # 장애 중 빠르게 반복 조회하지 않고 최대 대기 간격을 적용한다.
                    logging.error('푸시 큐 조회 실패; 15초 후 재시도')
                    push_interval = 15
                next_push_check = monotonic() + push_interval
            if args.once:
                return
            # 재알림의 60초 주기는 푸시 큐의 대기 간격과 별도로 유지한다.
            sleep(max(0, min(next_push_check, next_reminder_check) - monotonic()))
    except KeyboardInterrupt:
        logging.info('72시간 재알림 확인 종료')


if __name__ == '__main__':
    main()
