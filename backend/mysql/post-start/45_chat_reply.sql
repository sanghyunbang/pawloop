-- ============================================================================
-- 45_chat_reply.sql
-- 채팅 답장(인용) — 메시지가 같은 방의 어떤 메시지에 대한 답인지 — 이슈 #452
-- 대상: MySQL 8.x (운영/개발 공통)
--
-- ───────────────────────────────────────
-- 무엇을 하나
--
--   ALTER TABLE chat_message
--     ADD COLUMN reply_to_id bigint NULL
--     ADD KEY idx_chat_reply_to (reply_to_id)
--     ADD CONSTRAINT fk_chat_reply_to FOREIGN KEY (reply_to_id) REFERENCES chat_message (id) ON DELETE SET NULL
--
-- ───────────────────────────────────────
-- 왜 컬럼 하나인가
--
-- 카카오톡의 답장은 "어느 말에 대한 답" 하나다 — 스레드가 아니다. 원문의 내용은 저장하지 않는다:
-- 응답이 그때그때 원문을 읽어 미리보기(보낸 사람 · 첫 줄)를 만든다. 원문이 소프트 삭제되면
-- 미리보기가 "삭제된 메시지" 가 되고, 하드 삭제(운영 정리)되면 SET NULL 로 답장만 남는다.
-- 원문은 **같은 방**의 메시지여야 한다 — 서버(ChatRoomService#postMessage)가 400 으로 막는다.
--
-- ───────────────────────────────────────
-- 실행 순서
--
--   1. `chat_message` 가 먼저다(11_chat.sql · 01_schema.sql). 없으면 시작하지 않는다.
--   2. 이 스크립트를 실행한다 — 새 애플리케이션을 배포하기 **전**(prod 는 validate).
--
-- 멱등: 컬럼 · 인덱스 · FK 가 이미 있으면 각각 지나간다.
--
-- ───────────────────────────────────────
-- 되돌리기(DOWN)
--
--   ALTER TABLE chat_message DROP FOREIGN KEY fk_chat_reply_to;
--   ALTER TABLE chat_message DROP KEY idx_chat_reply_to;
--   ALTER TABLE chat_message DROP COLUMN reply_to_id;
-- ============================================================================

-- ── 0. 사전 점검 ────────────────────────────────────────
SET NAMES utf8mb4;

DROP PROCEDURE IF EXISTS heattrip_migration_abort;
CREATE PROCEDURE heattrip_migration_abort(IN msg VARCHAR(128))
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = msg;

SET @has_msg := (
    SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name = 'chat_message');
SET @col_exists := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'chat_message' AND column_name = 'reply_to_id');
SET @col_right := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'chat_message' AND column_name = 'reply_to_id'
      AND data_type = 'bigint' AND is_nullable = 'YES');
SET @idx_exists := (
    SELECT COUNT(DISTINCT index_name) FROM information_schema.statistics
    WHERE table_schema = DATABASE() AND table_name = 'chat_message' AND index_name = 'idx_chat_reply_to');
SET @fk_exists := (
    SELECT COUNT(*) FROM information_schema.referential_constraints
    WHERE constraint_schema = DATABASE() AND constraint_name = 'fk_chat_reply_to');

SELECT '[0] 사전 점검' AS section,
       @has_msg    AS chat_message_table_expect_1,
       @col_exists AS reply_to_id_already,
       @idx_exists AS idx_already,
       @fk_exists  AS fk_already;

SET @stmt := IF(@has_msg = 1,
    'SELECT ''[0-1] chat_message 확인'' AS message',
    'CALL heattrip_migration_abort(''ABORT: chat_message 표가 없다 — 11_chat.sql 을 먼저 돌려라.'')');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- 같은 이름의 컬럼이 다른 모양으로 있으면(사람이 손으로 만든 것) 멈춘다.
SET @stmt := IF(@col_exists = 0 OR @col_right = 1,
    'SELECT ''[0-2] reply_to_id 없거나 모양이 맞다'' AS message',
    'CALL heattrip_migration_abort(''ABORT: reply_to_id 가 있는데 bigint NULL 이 아니다.'')');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;


-- ── A. 컬럼 ──────────────────────────────────────────────
SET @stmt := IF(@col_exists = 0,
    'ALTER TABLE chat_message ADD COLUMN reply_to_id bigint NULL',
    'SELECT ''[A] reply_to_id 이미 있음'' AS message');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- ── B. 인덱스 ────────────────────────────────────────────
SET @stmt := IF(@idx_exists = 0,
    'ALTER TABLE chat_message ADD KEY idx_chat_reply_to (reply_to_id)',
    'SELECT ''[B] idx_chat_reply_to 이미 있음'' AS message');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- ── C. FK ─────────────────────────────────────────────────
SET @stmt := IF(@fk_exists = 0,
    'ALTER TABLE chat_message ADD CONSTRAINT fk_chat_reply_to FOREIGN KEY (reply_to_id) REFERENCES chat_message (id) ON DELETE SET NULL',
    'SELECT ''[C] fk_chat_reply_to 이미 있음'' AS message');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;


-- ── D. 사후 검증 ─────────────────────────────────────────
SET @d_col := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'chat_message' AND column_name = 'reply_to_id'
      AND data_type = 'bigint' AND is_nullable = 'YES');
SET @d_idx := (
    SELECT COUNT(DISTINCT index_name) FROM information_schema.statistics
    WHERE table_schema = DATABASE() AND table_name = 'chat_message' AND index_name = 'idx_chat_reply_to');
SET @d_fk := (
    SELECT COUNT(*) FROM information_schema.referential_constraints
    WHERE constraint_schema = DATABASE() AND constraint_name = 'fk_chat_reply_to' AND delete_rule = 'SET NULL');

SELECT '[D] 사후 검증' AS section,
       @d_col AS reply_to_id_expect_1,
       @d_idx AS idx_expect_1,
       @d_fk  AS fk_set_null_expect_1;

SET @stmt := IF(@d_col = 1 AND @d_idx = 1 AND @d_fk = 1,
    'SELECT ''[D] 통과 — reply_to_id · idx_chat_reply_to · fk_chat_reply_to(SET NULL)'' AS message',
    'CALL heattrip_migration_abort(''ABORT: 사후 검증 실패. 위 [D] 행의 숫자를 확인하라.'')');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

DROP PROCEDURE IF EXISTS heattrip_migration_abort;
