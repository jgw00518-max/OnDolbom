"""일정 변경 항목과 재수락 응답 기한을 계산한다."""

from datetime import datetime, time, timedelta


def has_schedule_time_changed(current: dict, changed: dict) -> bool:
    # 조회한 시간 문자열과 입력받은 time 값을 같은 형식으로 비교한다.
    def as_time(value):
        return value if isinstance(value, time) else time.fromisoformat(value)

    return (
        current["schedule_date"] != changed["schedule_date"]
        or as_time(current["start_time"]) != as_time(changed["start_time"])
        or as_time(current["end_time"]) != as_time(changed["end_time"])
    )


def get_reconfirm_deadline(requested_at: datetime, schedule_date, start_time, *, now=None):
    # 최초 요청 시각은 기한 계산에, DB 현재 시각은 긴급 전환에 사용한다.
    if not isinstance(start_time, time):
        start_time = time.fromisoformat(start_time)
    starts_at = datetime.combine(schedule_date, start_time)
    if starts_at - (now if now is not None else requested_at) <= timedelta(hours=24):
        return {"is_urgent": True, "response_due_at": None}
    return {
        "is_urgent": False,
        "response_due_at": min(requested_at + timedelta(hours=24),
                               starts_at - timedelta(hours=24)),
    }
