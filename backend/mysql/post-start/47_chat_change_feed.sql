-- ============================================================================
-- 47_chat_change_feed.sql
-- 채팅 변경 피드 — 이미 보낸 말이 바뀐 것을 폴링이 따라잡는 축 — ADR-0023 (#500)
-- 대상: MySQL 8.x (운영/개발 공통)
--
-- ───────────────────────────────────────
-- 무엇을 하나
--
--   ALTER TABLE chat_room    ADD COLUMN last_change_seq bigint NOT NULL DEFAULT 0
--   ALTER TABLE chat_message ADD COLUMN change_seq      bigint NULL
--                            ADD KEY idx_chat_change (room_id, change_seq)
--
-- ───────────────────────────────────────
-- 왜 또 하나의 번호인가
--
-- 델타 폴링은 `afterSeq` 보다 **큰 room_seq** 만 준다. 새 말은 그래서 오지만, 이미 보낸 말이 바뀌면
-- (소프트 삭제 · 앞으로의 반응) 번호가 늘지 않아 그 변화는 영영 안 온다 — 지금도 남이 지운 말이
-- 내 화면에 그대로 남아 있다(#197).
--
-- `room_seq` 를 다시 발급하는 길은 기각했다: 그 번호는 "방에 들어온 순서" 이고 미읽음이
-- `room.last_seq − member.last_read_seq` 뺄셈이라(ADR-0011 결정 2), 오래된 말에 변화 하나가 붙을
-- 때마다 그 말이 대화 맨 아래로 뛰고 모두의 미읽음이 1 늘어난다.
--
-- `updated_at` 시계도 기각했다 — 커서가 시각이 되면 서버 시각이 흔들리거나 같은 밀리초에 둘이
-- 바뀔 때 하나가 영영 안 온다. `room_seq` 를 만든 이유가 그대로 되풀이된다.
--
-- 그래서 **방마다 하나의 변경 카운터**다. 발급은 room_seq 와 같은 한 문장
-- (`UPDATE chat_room SET last_change_seq = LAST_INSERT_ID(last_change_seq + 1)`)이라 시계가 필요 없고,
-- 바뀐 행의 `change_seq` 에 그 번호를 찍는다. NULL 은 "한 번도 안 바뀐 말" 이다.
--
-- 인덱스는 `(room_id, change_seq)` — 델타가 "이 방에서 이 번호 뒤에 바뀐 것" 을 읽는 축 그대로다.
--
-- ───────────────────────────────────────
-- 실행 순서
--
--   1. `chat_room` · `chat_message` 가 먼저다(11_chat.sql · 01_schema.sql). 없으면 시작하지 않는다.
--   2. 이 스크립트를 실행한다 — 새 애플리케이션을 배포하기 **전**(prod 는 validate).
--
-- 멱등: 컬럼 · 인덱스가 이미 있으면 각각 지나간다.
--
-- ───────────────────────────────────────
-- 되돌리기(DOWN)
--
--   ALTER TABLE chat_message DROP KEY idx_chat_change;
--   ALTER TABLE chat_message DROP COLUMN change_seq;
--   ALTER TABLE chat_room    DROP COLUMN last_change_seq;
-- ============================================================================

-- ── 0. 사전 점검 ────────────────────────────────────────
SET NAMES utf8mb4;

DROP PROCEDURE IF EXISTS heattrip_migration_abort;
CREATE PROCEDURE heattrip_migration_abort(IN msg VARCHAR(128))
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = msg;

SET @has_room := (
    SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name = 'chat_room');
SET @has_msg := (
    SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name = 'chat_message');
SET @col_room := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'chat_room' AND column_name = 'last_change_seq');
SET @col_room_right := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'chat_room' AND column_name = 'last_change_seq'
      AND data_type = 'bigint' AND is_nullable = 'NO');
SET @col_msg := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'chat_message' AND column_name = 'change_seq');
SET @col_msg_right := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'chat_message' AND column_name = 'change_seq'
      AND data_type = 'bigint' AND is_nullable = 'YES');
SET @idx_exists := (
    SELECT COUNT(DISTINCT index_name) FROM information_schema.statistics
    WHERE table_schema = DATABASE() AND table_name = 'chat_message' AND index_name = 'idx_chat_change');

SELECT '[0] 사전 점검' AS section,
       @has_room  AS chat_room_table_expect_1,
       @has_msg   AS chat_message_table_expect_1,
       @col_room  AS last_change_seq_already,
       @col_msg   AS change_seq_already,
       @idx_exists AS idx_already;

SET @stmt := IF(@has_room = 1 AND @has_msg = 1,
    'SELECT ''[0-1] chat_room · chat_message 확인'' AS message',
    'CALL heattrip_migration_abort(''ABORT: chat_room 이나 chat_message 가 없다 — 11_chat.sql 을 먼저 돌려라.'')');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- 같은 이름의 컬럼이 다른 모양으로 있으면(사람이 손으로 만든 것) 멈춘다.
SET @stmt := IF((@col_room = 0 OR @col_room_right = 1) AND (@col_msg = 0 OR @col_msg_right = 1),
    'SELECT ''[0-2] 두 컬럼이 없거나 모양이 맞다'' AS message',
    'CALL heattrip_migration_abort(''ABORT: last_change_seq/change_seq 가 있는데 모양이 다르다. 사람이 확인하라.'')');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;


-- ── A. 방의 발급 카운터 ──────────────────────────────────
-- 기본값 0 이라 쌓인 방은 "아직 아무것도 안 바뀐 방" 으로 시작한다.
SET @stmt := IF(@col_room = 0,
    'ALTER TABLE chat_room ADD COLUMN last_change_seq bigint NOT NULL DEFAULT 0',
    'SELECT ''[A] last_change_seq 이미 있음'' AS message');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- ── B. 메시지의 변경 번호 ────────────────────────────────
-- NULL = 한 번도 안 바뀐 말. 쌓인 메시지는 전부 NULL 이라 델타가 옛 말을 새로 흘리지 않는다.
SET @stmt := IF(@col_msg = 0,
    'ALTER TABLE chat_message ADD COLUMN change_seq bigint NULL',
    'SELECT ''[B] change_seq 이미 있음'' AS message');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- ── C. 인덱스 ────────────────────────────────────────────
SET @stmt := IF(@idx_exists = 0,
    'ALTER TABLE chat_message ADD KEY idx_chat_change (room_id, change_seq)',
    'SELECT ''[C] idx_chat_change 이미 있음'' AS message');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;


-- ── D. 사후 검증 ─────────────────────────────────────────
SET @d_room := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'chat_room' AND column_name = 'last_change_seq'
      AND data_type = 'bigint' AND is_nullable = 'NO' AND column_default = '0');
SET @d_msg := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'chat_message' AND column_name = 'change_seq'
      AND data_type = 'bigint' AND is_nullable = 'YES');
SET @d_idx := (
    SELECT COUNT(*) FROM information_schema.statistics
    WHERE table_schema = DATABASE() AND table_name = 'chat_message' AND index_name = 'idx_chat_change');

SELECT '[D] 사후 검증' AS section,
       @d_room AS last_change_seq_default_0_expect_1,
       @d_msg  AS change_seq_expect_1,
       @d_idx  AS idx_columns_expect_2;

SET @stmt := IF(@d_room = 1 AND @d_msg = 1 AND @d_idx = 2,
    'SELECT ''[D] 통과 — last_change_seq · change_seq · idx_chat_change(room_id, change_seq)'' AS message',
    'CALL heattrip_migration_abort(''ABORT: 사후 검증 실패. 위 [D] 행의 숫자를 확인하라.'')');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

DROP PROCEDURE IF EXISTS heattrip_migration_abort;
