"""실패한 발행 재시도: python -m python.features.notifications.retry_pending"""
from python.features.notifications.store import collection
from python.features.notifications.schedule_notifications import publish_schedule_notifications
from google.cloud.firestore_v1.base_query import FieldFilter


def main():
    # rollback된 일정은 발행하지 않는다. pending은 앱 목록에서 보이지 않는다.
    for snapshot in collection().where(filter=FieldFilter('status', '==', 'pending')).stream(timeout=10):
        try:
            identifier = snapshot.to_dict()['schedule_seq']
            print(identifier, 'published' if publish_schedule_notifications(identifier) else 'pending')
        except Exception:
            print(snapshot.id, 'retry failed')  # 계정 키·내부 오류는 출력하지 않는다.


if __name__ == '__main__':
    main()
