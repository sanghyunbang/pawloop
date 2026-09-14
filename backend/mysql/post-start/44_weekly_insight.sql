-- ============================================================================
-- 44_weekly_insight.sql
-- AI 주간 요약의 캐시 — 이슈 #486
-- 대상: MySQL 8.x (운영/개발 공통)
--
-- ─────────────────────────────────────────────────
-- 무엇을 하나
--
--   CREATE TABLE weekly_insight (user_id, dog_id, week_start, input_hash, model, text, calls, generated_at)
--
-- ─────────────────────────────────────────────────
-- 왜 표인가
--
-- 통계 화면의 "AI 요약" 은 OpenAI 를 부른 문장이다. 돈이고 느리다. 같은 입력(같은 주 · 같은 산책들)에
-- 두 번 부르지 않으려면 "무엇으로 만들었나"(input_hash)와 "몇 번 다시 만들었나"(calls)가 재시작을
-- 넘어 남아야 한다. 메모리 캐시는 배포 한 번에 비고 그날 모든 사용자를 다시 부른다.
--
-- 사용자 · 아이 · 주(週)에 행 하나 — `uq_weekly_insight (user_id, dog_id, week_start)`. `dog_id` 는
-- 0 이 "모든 아이" 다. NULL 을 쓰면 MySQL 유니크가 NULL 끼리를 다르다고 보아 한 주에 행이 쌓인다.
--
-- `text` 가 NULL 인 행은 "만들었는데 버렸다"(출력에 입력에 없는 숫자 · 빈 답)이다. 그 주에 입력이
-- 그대로면 다시 부르지 않는다 — 같은 입력에 같은 실수를 반복할 이유가 없다.
--
-- 탈퇴하면 요약도 사라진다(`user_id` CASCADE) — 그 사람만 보는 문장이다. 좌표 · 장소 · 이름은 이
-- 표에도, 모델에 보내는 입력에도 없다.
--
-- ─────────────────────────────────────────────────
-- 실행 순서
--
--   1. `users` 가 먼저다(01_schema.sql). 없으면 시작하지 않는다.
--   2. 이 스크립트를 실행한다 — 새 애플리케이션을 배포하기 **전**. prod 는 `ddl-auto=validate` 라
--      표가 없으면 부팅이 죽는다.
--
-- **dev(`ddl-auto=update`)에서도 앱을 띄우기 전에 돌린다.** 안 돌리면 Hibernate 가 표를 자기 방식
-- (유니크 · FK 이름이 다르다)으로 만들고, 그 뒤 이 스크립트는 `IF NOT EXISTS` 로 지나가되 [D] 에서
-- 멈춰 세운다.
--
-- 멱등: 표가 이미 있으면 지나간다.
--
-- ─────────────────────────────────────────────────
-- 되돌리기(DOWN)
--
--   DROP TABLE weekly_insight;
--
-- 산책도 사람도 그대로다 — 이 표는 캐시일 뿐이고, 지우면 다음 요청이 다시 만든다(비용만 든다).
-- ============================================================================

-- ── 0. 사전 점검 ────────────────────────────────────────
SET NAMES utf8mb4;

-- SIGNAL 은 PREPARE 할 수 없어서 프로시저로 감싼다 — 38 · 40 과 같은 모양.
DROP PROCEDURE IF EXISTS heattrip_migration_abort;
CREATE PROCEDURE heattrip_migration_abort(IN msg VARCHAR(128))
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = msg;

SET @has_users := (
    SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name = 'users');
SET @has_insight := (
    SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name = 'weekly_insight');

SELECT '[0] 사전 점검' AS section,
       @has_users   AS users_table_expect_1,
       @has_insight AS weekly_insight_table_already;

-- users 가 없으면 FK 를 걸 곳이 없다.
SET @stmt := IF(@has_users = 1,
    'SELECT ''[0-1] users 확인'' AS message',
    'CALL heattrip_migration_abort(''ABORT: users 표가 없다 — 01_schema.sql 을 먼저 돌려라.'')');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;


-- ── A. 표 ────────────────────────────────────────────────
--
-- 컬럼 순서·타입은 `mysql/init/01_schema.sql` 과 **같아야 한다**. 그 파일은 엔티티에서 뽑은 것이고
-- prod 는 `ddl-auto=validate` 다.
CREATE TABLE IF NOT EXISTS `weekly_insight` (
  `calls` int NOT NULL,
  `week_start` date NOT NULL,
  `dog_id` bigint NOT NULL,
  `generated_at` datetime(6) NOT NULL,
  `id` bigint NOT NULL AUTO_INCREMENT,
  `user_id` bigint NOT NULL,
  `input_hash` varchar(64) NOT NULL,
  `model` varchar(64) NOT NULL,
  `text` text,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_weekly_insight` (`user_id`,`dog_id`,`week_start`),
  KEY `idx_weekly_insight_generated` (`generated_at`),
  CONSTRAINT `fk_weekly_insight_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;


-- ── D. 사후 검증 ─────────────────────────────────────────
--
-- **전체 컬럼 수를 안 센다** — 컬럼이 늘면 재실행이 깨진다. 이름으로 묻는다.
SET @d_cols := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'weekly_insight'
      AND column_name IN ('id','user_id','dog_id','week_start','input_hash','model','text','calls','generated_at'));

-- 탈퇴하면 요약도 사라진다 — CASCADE.
SET @d_cascade := (
    SELECT COUNT(*) FROM information_schema.referential_constraints
    WHERE constraint_schema = DATABASE()
      AND constraint_name = 'fk_weekly_insight_user'
      AND delete_rule = 'CASCADE');

-- 사용자 · 아이 · 주에 행 하나 — 캐시의 열쇠.
SET @d_unique := (
    SELECT COUNT(DISTINCT column_name) FROM information_schema.statistics
    WHERE table_schema = DATABASE() AND table_name = 'weekly_insight'
      AND index_name = 'uq_weekly_insight' AND non_unique = 0);

-- 하루 상한 · 정리 쿼리가 타는 날짜 인덱스.
SET @d_index := (
    SELECT COUNT(DISTINCT column_name) FROM information_schema.statistics
    WHERE table_schema = DATABASE() AND table_name = 'weekly_insight'
      AND index_name = 'idx_weekly_insight_generated');

SELECT '[D] 사후 검증' AS section,
       @d_cols    AS named_columns_expect_9,
       @d_cascade AS cascade_fk_expect_1,
       @d_unique  AS unique_columns_expect_3,
       @d_index   AS date_index_columns_expect_1;

-- Hibernate 가 먼저 만든 표(유니크 · FK 이름이 다르다)를 IF NOT EXISTS 가 조용히 지나쳤다면 여기서
-- 멈춘다 — 표를 지우고 다시 돌리든가, 이름을 맞추든가는 사람이 정한다.
SET @stmt := IF(@d_cols = 9 AND @d_cascade = 1 AND @d_unique = 3 AND @d_index = 1,
    'SELECT ''[D] 통과 — weekly_insight 표 · CASCADE · 유니크 · 날짜 인덱스'' AS message',
    'CALL heattrip_migration_abort(''ABORT: 사후 검증 실패. 위 [D] 행의 숫자를 확인하라.'')');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

DROP PROCEDURE IF EXISTS heattrip_migration_abort;
