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


def get_reconfirm_deadline(requested_at: datetime, schedule_date, start_time):
    # requested_at은 서버의 DB 기준 시각을 전달한다. PC의 현재 시각을 사용하지 않는다.
    if not isinstance(start_time, time):
        start_time = time.fromisoformat(start_time)

    starts_at = datetime.combine(schedule_date, start_time)
    remaining = starts_at - requested_at

    # 정확히 12시간 남은 경우도 긴급 변경이다. 자동 만료 기한은 두지 않는다.
    if remaining <= timedelta(hours=12):
        return {"is_urgent": True, "response_due_at": None}

    return {
        "is_urgent": False,
        "response_due_at": min(
            requested_at + timedelta(hours=24),
            starts_at - timedelta(hours=12),
        ),
    }
