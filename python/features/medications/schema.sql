-- 기존 작성자·체크 시간·투약 내용은 유지한다.
ALTER TABLE medication_log
    ADD COLUMN confirmed_by_user_id VARCHAR(50) NULL AFTER medication_confirmed_at,
    ADD KEY ix_medication_confirmed_by (confirmed_by_user_id),
    ADD CONSTRAINT fk_medication_confirmed_by
        FOREIGN KEY (confirmed_by_user_id) REFERENCES `user` (user_id)
        ON DELETE RESTRICT ON UPDATE RESTRICT;
