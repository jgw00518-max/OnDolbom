-- 로컬/공유 DB 관리자가 한 번 적용. 기존 메시지와 참여는 삭제하지 않는다.
CREATE TABLE IF NOT EXISTS chat_read_status (
  participate_seq INT NOT NULL PRIMARY KEY,
  last_read_chat_seq INT NOT NULL DEFAULT 0,
  last_read_at DATETIME NULL,
  updated_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  CONSTRAINT fk_chat_read_participation FOREIGN KEY (participate_seq) REFERENCES participate(participate_seq)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;

CREATE TABLE IF NOT EXISTS chat_push_outbox (
  chat_seq INT NOT NULL,
  family_room_id VARCHAR(50) NOT NULL,
  user_id VARCHAR(50) NOT NULL,
  status VARCHAR(20) NOT NULL DEFAULT 'pending',
  attempts INT NOT NULL DEFAULT 0,
  next_attempt_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  lease_until DATETIME NULL,
  lease_token CHAR(32) NULL,
  created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (chat_seq,family_room_id,user_id),
  KEY ix_chat_push_pending (status,next_attempt_at),
  CONSTRAINT fk_chat_push_message FOREIGN KEY (chat_seq,family_room_id,user_id)
    REFERENCES live_chat(chat_seq,family_room_id,user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb3;

-- 최초 도입 시점의 과거 대화는 미읽음에 포함하지 않는다. 재실행해도 기존 커서는 덮어쓰지 않는다.
INSERT INTO chat_read_status (participate_seq,last_read_chat_seq,last_read_at)
SELECT p.participate_seq,COALESCE(MAX(m.chat_seq),0),CURRENT_TIMESTAMP
FROM participate p LEFT JOIN live_chat m ON m.family_room_id=p.family_room_id
WHERE p.left_at IS NULL AND p.is_active=1
GROUP BY p.participate_seq
ON DUPLICATE KEY UPDATE participate_seq=chat_read_status.participate_seq;
