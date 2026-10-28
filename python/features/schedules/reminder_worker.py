"""API 서버가 자동 실행한다. 단독 실행도 가능하며 --once는 한 번만 검사한다."""
import argparse
import logging
from time import monotonic, sleep
from python.features.schedules.reminders import check_reminders
from python.features.notifications.push import check_push_notifications


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--once', action='store_true', help='한 번 확인하고 종료')
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO)
    next_reminder_check = 0
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
            try:
                check_push_notifications()
            except Exception:
                logging.error('푸시 큐 조회 실패; 다음 검사에서 재시도')
            if args.once:
                return
            sleep(max(0, 5 - (monotonic() - started)))
    except KeyboardInterrupt:
        logging.info('72시간 재알림 확인 종료')


if __name__ == '__main__':
    main()
