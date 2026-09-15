-- ============================================================================
-- 48_chat_reaction.sql
-- 채팅 반응(공감) — 말풍선 아래 한 줄 — #452 · ADR-0023(#500) 셋째 줄
-- 대상: MySQL 8.x (운영/개발 공통)
--
-- ───────────────────────────────────────
-- 무엇을 하나
--
--   CREATE TABLE chat_message_reaction (
--     id, message_id, user_id, kind, created_at,
--     UNIQUE uq_chat_reaction (message_id, user_id, kind),
--     FOREIGN KEY fk_chat_reaction_message (message_id) → chat_message(id) ON DELETE CASCADE)
--
-- ───────────────────────────────────────
-- 왜 이 모양인가
--
-- **`user_id` 에 FK 가 없다.** chat 은 사용자를 id 로만 안다(ADR-0011 결정 4) — `chat_message`
-- 도 `chat_room_member` 도 `users` 로 FK 를 내지 않는다. 걸면 탈퇴 경로가 DB 삭제 순서에 묶이고,
-- CASCADE 면 탈퇴 한 번에 남의 대화에 남은 반응이 사라진다. 탈퇴한 사람의 반응은 그 사람의 말과
-- 같은 규칙으로 남는다(처리방침 §3 — 보낸 것은 받은 사람의 대화방에 남는다).
--
-- **`message_id` 는 CASCADE 다.** 말 자체가 운영 정리로 사라지면 그 말에 붙은 반응은 남을 이유가
-- 없다. 소프트 삭제(톰스톤)는 이 FK 와 무관하다 — 그때는 서버가 반응 행을 지운다(지운 말에
-- "5명이 공감" 이 남으면 지운 사람에게 지워지지 않은 것이나 같다).
--
-- **유니크가 (message_id, user_id, kind) 셋이다.** 한 사람이 한 말에 여러 종류를 누를 수 있다 —
-- 커뮤니티 반응과 같은 판단이다(ADR-0016 결정 2): 좁혔다가 넓히는 것은 계약의 파괴적 변경이고,
-- 넓혔다가 좁히는 것은 행을 지우는 마이그레이션이라 **넓은 쪽이 되돌리기 싸다**. 이 유니크가
-- 멱등 삽입(`ON DUPLICATE KEY UPDATE id = id`)을 딛는 자리이기도 하다.
--
-- **CHECK 를 안 건다.** 종류는 제품이 늘릴 수 있는 목록이고 계약의 `ChatReactionKind` 가 단일
-- 출처다(커뮤니티 `reaction` 과 같은 이유). 값이 늘 때마다 마이그레이션이 따라오면 그 자체가 비용이다.
--
-- **집계용 인덱스를 따로 안 만든다.** 세는 축이 `message_id` 인데 그것이 `uq_chat_reaction` 의
-- 왼쪽 접두라 그 인덱스로 끝난다. 커뮤니티가 `idx_reaction_user` 를 둔 것은 `users` FK 의
-- SET NULL 이 훑는 자리가 필요해서였고, 여기는 그 FK 자체가 없다.
--
-- ───────────────────────────────────────
-- 실행 순서
--
--   1. `chat_message` 가 먼저다(11_chat.sql · 01_schema.sql). 없으면 시작하지 않는다.
--   2. 이 스크립트를 실행한다 — 새 애플리케이션을 배포하기 **전**(prod 는 validate).
--
-- 멱등: 표가 이미 있으면 지나간다. 이름 없는 유니크·FK 로 만들어진 표(dev 에서 앱을 먼저 띄운
-- 모양)는 사후 검증이 멈춰 세운다 — 조용히 지나가면 유니크도 CASCADE 도 없는 표가 남는다.
--
-- ───────────────────────────────────────
-- 되돌리기(DOWN)
--
--   DROP TABLE chat_message_reaction;
-- ============================================================================

-- ── 0. 사전 점검 ────────────────────────────────────────
SET NAMES utf8mb4;

DROP PROCEDURE IF EXISTS heattrip_migration_abort;
CREATE PROCEDURE heattrip_migration_abort(IN msg VARCHAR(128))
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = msg;

SET @has_msg := (
    SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name = 'chat_message');
SET @has_table := (
    SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name = 'chat_message_reaction');

SELECT '[0] 사전 점검' AS section,
       @has_msg   AS chat_message_table_expect_1,
       @has_table AS chat_message_reaction_already;

SET @stmt := IF(@has_msg = 1,
    'SELECT ''[0-1] chat_message 확인'' AS message',
    'CALL heattrip_migration_abort(''ABORT: chat_message 가 없다 — 11_chat.sql 을 먼저 돌려라.'')');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;


-- ── A. 반응 표 ──────────────────────────────────────────
-- 쌓인 방·말은 반응이 하나도 없는 상태로 시작한다 — 채울 것이 없다.
SET @stmt := IF(@has_table = 0, '
    CREATE TABLE chat_message_reaction (
      id bigint NOT NULL AUTO_INCREMENT,
      message_id bigint NOT NULL,
      user_id bigint NOT NULL,
      kind varchar(20) NOT NULL,
      created_at datetime(6) NOT NULL,
      PRIMARY KEY (id),
      UNIQUE KEY uq_chat_reaction (message_id, user_id, kind),
      CONSTRAINT fk_chat_reaction_message FOREIGN KEY (message_id)
        REFERENCES chat_message (id) ON DELETE CASCADE
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4',
    'SELECT ''[A] chat_message_reaction 이미 있음'' AS message');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;


-- ── D. 사후 검증 ─────────────────────────────────────────
SET @d_cols := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'chat_message_reaction'
      AND column_name IN ('id', 'message_id', 'user_id', 'kind', 'created_at'));
SET @d_uq := (
    SELECT COUNT(*) FROM information_schema.statistics
    WHERE table_schema = DATABASE() AND table_name = 'chat_message_reaction'
      AND index_name = 'uq_chat_reaction' AND non_unique = 0);
SET @d_fk := (
    SELECT COUNT(*) FROM information_schema.referential_constraints
    WHERE constraint_schema = DATABASE() AND table_name = 'chat_message_reaction'
      AND constraint_name = 'fk_chat_reaction_message' AND delete_rule = 'CASCADE');
SET @d_out := (
    SELECT COUNT(*) FROM information_schema.referential_constraints
    WHERE constraint_schema = DATABASE() AND table_name = 'chat_message_reaction'
      AND referenced_table_name <> 'chat_message');

SELECT '[D] 사후 검증' AS section,
       @d_cols AS columns_expect_5,
       @d_uq   AS uq_chat_reaction_columns_expect_3,
       @d_fk   AS fk_cascade_expect_1,
       @d_out  AS fk_out_of_chat_expect_0;

SET @stmt := IF(@d_cols = 5 AND @d_uq = 3 AND @d_fk = 1 AND @d_out = 0,
    'SELECT ''[D] 통과 — chat_message_reaction · uq_chat_reaction · fk_chat_reaction_message(CASCADE)'' AS message',
    'CALL heattrip_migration_abort(''ABORT: 사후 검증 실패. 위 [D] 행의 숫자를 확인하라.'')');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

DROP PROCEDURE IF EXISTS heattrip_migration_abort;
