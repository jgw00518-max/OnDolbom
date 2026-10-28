"""API 서버가 자동 실행한다. 단독 실행도 가능하며 --once는 한 번만 검사한다."""
import argparse
import logging
from time import monotonic, sleep
from python.features.schedules.reminders import check_reminders


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--once', action='store_true', help='한 번 확인하고 종료')
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO)
    try:
        while True:
            started = monotonic()
            try:
                logging.info('72시간 재알림 신규 발행: %s건', check_reminders())
            except Exception:
                logging.exception('재알림 대상 조회 실패; 다음 주기에 재시도')
            if args.once:
                return
            sleep(max(0, 60 - (monotonic() - started)))
    except KeyboardInterrupt:
        logging.info('72시간 재알림 확인 종료')


if __name__ == '__main__':
    main()
