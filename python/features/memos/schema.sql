-- 기존 memo/user의 키 타입·정렬 규칙과 일치시킨다. 기존 테이블·집계는 변경하지 않는다.
CREATE TABLE IF NOT EXISTS memo_like (
    memo_id VARCHAR(50) NOT NULL,
    family_room_id VARCHAR(50) NOT NULL,
    memo_author_id VARCHAR(50) NOT NULL,
    user_id VARCHAR(50) NOT NULL,
    liked_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    PRIMARY KEY (memo_id, family_room_id, memo_author_id, user_id),
    KEY ix_memo_like_user (user_id),
    CONSTRAINT fk_memo_like_memo
        FOREIGN KEY (memo_id, family_room_id, memo_author_id)
        REFERENCES memo (memo_id, family_room_id, user_id)
        ON DELETE RESTRICT ON UPDATE RESTRICT,
    CONSTRAINT fk_memo_like_user
        FOREIGN KEY (user_id) REFERENCES `user` (user_id)
        ON DELETE RESTRICT ON UPDATE RESTRICT
) ENGINE=InnoDB DEFAULT CHARACTER SET utf8mb3 COLLATE utf8mb3_general_ci;
