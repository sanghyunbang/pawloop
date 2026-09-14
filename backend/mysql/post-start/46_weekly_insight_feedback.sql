-- ============================================================================
-- 46_weekly_insight_feedback.sql
-- AI 주간 요약에 👍/👎 — 요약이 도움이 됐는지 사용자가 한 번 누른다 — 이슈 #486 후속
-- 대상: MySQL 8.x (운영/개발 공통)
--
-- ───────────────────────────────────────
-- 무엇을 하나
--
--   ALTER TABLE weekly_insight
--     ADD COLUMN feedback    varchar(8)  NULL       -- 'up' | 'down' | NULL(안 누름)
--     ADD COLUMN feedback_at datetime(6) NULL
--     ADD CONSTRAINT ck_weekly_insight_feedback CHECK (feedback in ('up','down'))
--
-- ───────────────────────────────────────
-- 왜 같은 표의 컬럼 둘인가
--
-- 요약 하나(사용자 · 아이 · 주)에 평가 하나다 — 행이 이미 그 단위로 있으니 표를 더 만들 이유가
-- 없다. 문장이 다시 만들어지면(입력이 바뀌어 `calls` 가 오르면) 옛 문장에 대한 평가라 애플리케이션이
-- 지운다(`WeeklyInsight#regenerated`). 값은 둘뿐이라 CHECK 로 잠근다 — 앱이 다른 문자열을 보내면
-- 서버가 400 으로 막고, 그래도 들어오면 DB 가 막는다.
--
-- ───────────────────────────────────────
-- 실행 순서
--
--   1. `weekly_insight` 가 먼저다(44_weekly_insight.sql). 없으면 시작하지 않는다.
--   2. 이 스크립트를 실행한다 — 새 애플리케이션을 배포하기 **전**(prod 는 validate).
--
-- 멱등: 컬럼 · CHECK 가 이미 있으면 각각 지나간다.
--
-- ───────────────────────────────────────
-- 되돌리기(DOWN)
--
--   ALTER TABLE weekly_insight DROP CHECK ck_weekly_insight_feedback;
--   ALTER TABLE weekly_insight DROP COLUMN feedback_at;
--   ALTER TABLE weekly_insight DROP COLUMN feedback;
-- ============================================================================

-- ── 0. 사전 점검 ────────────────────────────────────────
SET NAMES utf8mb4;

DROP PROCEDURE IF EXISTS heattrip_migration_abort;
CREATE PROCEDURE heattrip_migration_abort(IN msg VARCHAR(128))
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = msg;

SET @has_table := (
    SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name = 'weekly_insight');
SET @col_feedback := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'weekly_insight' AND column_name = 'feedback');
SET @col_feedback_right := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'weekly_insight' AND column_name = 'feedback'
      AND data_type = 'varchar' AND character_maximum_length = 8 AND is_nullable = 'YES');
SET @col_at := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'weekly_insight' AND column_name = 'feedback_at');
SET @col_at_right := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'weekly_insight' AND column_name = 'feedback_at'
      AND data_type = 'datetime' AND is_nullable = 'YES');
SET @ck_exists := (
    SELECT COUNT(*) FROM information_schema.table_constraints
    WHERE table_schema = DATABASE() AND table_name = 'weekly_insight'
      AND constraint_type = 'CHECK' AND constraint_name = 'ck_weekly_insight_feedback');

SELECT '[0] 사전 점검' AS section,
       @has_table    AS weekly_insight_table_expect_1,
       @col_feedback AS feedback_already,
       @col_at       AS feedback_at_already,
       @ck_exists    AS check_already;

SET @stmt := IF(@has_table = 1,
    'SELECT ''[0-1] weekly_insight 확인'' AS message',
    'CALL heattrip_migration_abort(''ABORT: weekly_insight 표가 없다 — 44_weekly_insight.sql 을 먼저 돌려라.'')');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- 같은 이름의 컬럼이 다른 모양으로 있으면(사람이 손으로 만든 것) 멈춘다.
SET @stmt := IF((@col_feedback = 0 OR @col_feedback_right = 1) AND (@col_at = 0 OR @col_at_right = 1),
    'SELECT ''[0-2] feedback · feedback_at 없거나 모양이 맞다'' AS message',
    'CALL heattrip_migration_abort(''ABORT: feedback 컬럼이 있는데 varchar(8) NULL · datetime NULL 이 아니다. 사람이 확인하라.'')');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;


-- ── A. feedback ───────────────────────────────────────────
SET @stmt := IF(@col_feedback = 0,
    'ALTER TABLE weekly_insight ADD COLUMN feedback varchar(8) NULL',
    'SELECT ''[A] feedback 이미 있음'' AS message');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- ── B. feedback_at ────────────────────────────────────────
SET @stmt := IF(@col_at = 0,
    'ALTER TABLE weekly_insight ADD COLUMN feedback_at datetime(6) NULL',
    'SELECT ''[B] feedback_at 이미 있음'' AS message');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- ── C. CHECK ──────────────────────────────────────────────
SET @stmt := IF(@ck_exists = 0,
    'ALTER TABLE weekly_insight ADD CONSTRAINT ck_weekly_insight_feedback CHECK (feedback in (''up'',''down''))',
    'SELECT ''[C] ck_weekly_insight_feedback 이미 있음'' AS message');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;


-- ── D. 사후 검증 ─────────────────────────────────────────
SET @d_cols := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'weekly_insight'
      AND column_name IN ('feedback', 'feedback_at') AND is_nullable = 'YES');
SET @d_ck := (
    SELECT COUNT(*) FROM information_schema.table_constraints
    WHERE table_schema = DATABASE() AND table_name = 'weekly_insight'
      AND constraint_type = 'CHECK' AND constraint_name = 'ck_weekly_insight_feedback');

SELECT '[D] 사후 검증' AS section,
       @d_cols AS feedback_columns_expect_2,
       @d_ck   AS check_expect_1;

SET @stmt := IF(@d_cols = 2 AND @d_ck = 1,
    'SELECT ''[D] 통과 — feedback · feedback_at · ck_weekly_insight_feedback'' AS message',
    'CALL heattrip_migration_abort(''ABORT: 사후 검증 실패. 위 [D] 행의 숫자를 확인하라.'')');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

DROP PROCEDURE IF EXISTS heattrip_migration_abort;
