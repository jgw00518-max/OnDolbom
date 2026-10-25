-- 기존 live_chat 테이블용. 관리자 도구에서 한 번만 적용한다.
-- API는 이 파일을 자동 실행하지 않는다. 기존 메시지는 NULL 요청 ID로 보존한다.
ALTER TABLE live_chat
  ADD COLUMN client_message_id VARCHAR(36) CHARACTER SET ascii COLLATE ascii_bin NULL,
  ADD UNIQUE KEY uq_live_chat_request (family_room_id, user_id, client_message_id),
  MODIFY COLUMN chat_content TEXT CHARACTER SET utf8mb4 NULL;
