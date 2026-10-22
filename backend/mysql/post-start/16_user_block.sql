-- ============================================================================
-- 16_user_block.sql — chat_block 을 user_block 으로 옮긴다 (이슈 #166)
--
-- 왜 이름을 바꾸나
--
-- 가리기는 **처음부터 사람 단위**였다. 계약의 경로에 방 id 가 없고, 컬럼도 넷
-- (blocker_user_id·blocked_user_id·created_at·id)에 UNIQUE 하나뿐이다. 채팅 안에 있었던
-- 것은 채팅이 그것을 처음 필요로 했기 때문이지 채팅의 것이어서가 아니다.
--
-- 커뮤니티가 같은 가리기를 쓰게 되면서 chat_block 이라는 이름이 거짓이 됐다.
-- ADR-0016 이 "차단은 옮길 것이 표가 아니라 **패키지 위치**뿐이다" 라고 진단해 뒀고,
-- 여기서 그 진단대로 옮긴다.
--
-- 왜 지금인가
--
-- **이름을 바꾸는 것이 공짜인 마지막 시점이다.** 배포된 클라이언트가 없고 이 표가
-- 0행이다(2026-09-03 dev 실측). 행이 쌓인 뒤에 옮기면 같은 일이 데이터 이관이 된다.
--
-- 무엇을 하나
--
--   chat_block → user_block 으로 RENAME. 인덱스 이름도 uq_chat_block → uq_user_block.
--
-- 실행
--
--   mysql -u root -p heat_trip_db < mysql/post-start/16_user_block.sql
--
-- 멱등하다 — 이미 옮겨졌으면 아무것도 안 한다. 표가 애초에 없으면(새 DB 를 정본으로
-- 세운 경우) 그것도 정상이다 — 01_schema.sql 이 user_block 으로 만든다.
--
-- 되돌리기
--
--   RENAME TABLE user_block TO chat_block;
--   ALTER TABLE chat_block RENAME INDEX uq_user_block TO uq_chat_block;
--
-- 데이터는 안 잃는다. RENAME 은 행을 건드리지 않는다.
-- ============================================================================

SET NAMES utf8mb4;

DROP PROCEDURE IF EXISTS heattrip_migration_abort;
CREATE PROCEDURE heattrip_migration_abort(IN msg VARCHAR(128) CHARACTER SET utf8mb4)
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = msg;

-- ── 0. 사전 점검 ────────────────────────────────────────────────────────────
-- 둘 다 있으면 멈춘다. 어느 쪽이 정본인지 모르는 채로 한쪽을 지우면 안 된다.

SET @has_old := (
    SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name = 'chat_block');
SET @has_new := (
    SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name = 'user_block');

SELECT '[0] 사전 점검' AS section, @has_old AS chat_block, @has_new AS user_block;

SET @stmt := IF(@has_old = 1 AND @has_new = 1,
    'CALL heattrip_migration_abort(''ABORT: chat_block 과 user_block 이 둘 다 있다. 어느 쪽이 정본인지 사람이 정해야 한다.'')',
    'SELECT ''[0] 통과'' AS message');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- ── A. 옮긴다 ──────────────────────────────────────────────────────────────

SET @stmt := IF(@has_old = 1 AND @has_new = 0,
    'RENAME TABLE chat_block TO user_block',
    'DO 0');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- 인덱스 이름도 함께. 안 바꾸면 SHOW CREATE TABLE 에 uq_chat_block 이 남아 정본과 갈린다.
--
-- **COUNT(DISTINCT index_name) 이어야 한다.** information_schema.statistics 는 인덱스의
-- 컬럼마다 한 행이라, 두 컬럼짜리 uq_chat_block 은 COUNT(*) 가 2 다. 예전에는 `= 1` 로
-- 견줘서 이 문장이 한 번도 안 돌았고, 그 뒤 사후 검증이 uq_user_block 을 못 찾아 멈췄다 —
-- 표 이름은 이미 바뀐 채로. 로컬 dev DB 에서 2026-09-05 에 실제로 그렇게 멈췄다.
SET @has_old_index := (
    SELECT COUNT(DISTINCT index_name) FROM information_schema.statistics
    WHERE table_schema = DATABASE() AND table_name = 'user_block'
      AND index_name = 'uq_chat_block');

SET @stmt := IF(@has_old_index = 1,
    'ALTER TABLE user_block RENAME INDEX uq_chat_block TO uq_user_block',
    'DO 0');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SELECT '[A] 이름 변경' AS section,
       IF(@has_old = 1 AND @has_new = 0, '옮김', '건너뜀 — 이미 옮겨졌거나 표가 없다') AS result;

-- ── D. 사후 검증 ───────────────────────────────────────────────────────────
-- 표가 애초에 없었으면(새 DB) 검증할 것도 없다. 있었으면 옮겨져 있어야 한다.

SET @d_old_gone := (
    SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name = 'chat_block');

SET @d_index := (
    SELECT COUNT(*) FROM information_schema.statistics
    WHERE table_schema = DATABASE() AND table_name = 'user_block'
      AND index_name = 'uq_user_block');

SELECT '[D] 사후 검증' AS section, @d_old_gone AS chat_block_0, @d_index AS uq_user_block;

SET @stmt := IF(@d_old_gone = 0 AND (@has_old = 0 OR @d_index > 0),
    'SELECT ''[D] 통과'' AS message',
    'CALL heattrip_migration_abort(''ABORT: 사후 검증 실패. 위 [D] 행의 숫자를 확인하라.'')');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

DROP PROCEDURE IF EXISTS heattrip_migration_abort;
