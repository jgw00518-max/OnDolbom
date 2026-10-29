-- 기간으로 등록한 약을 다른 등록 건과 혼동하지 않고 묶어서 삭제하기 위한 식별자.
-- 기존 행은 NULL로 유지해 과거 기록을 임의로 묶지 않는다. 한 번만 적용한다.
ALTER TABLE medication_log
    ADD COLUMN medication_series_id CHAR(32) NULL,
    ADD KEY ix_medication_series_date (family_room_id, medication_series_id, medication_date);
