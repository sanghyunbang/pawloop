-- ============================================================================
-- 27_course.sql
-- 내가 걸은 길을 코스로 남긴다 — 이슈 #339
-- 대상: MySQL 8.x (운영/개발 공통)
--
-- ─────────────────────────────────────────────────
-- 무엇을 하나
--
--   CREATE TABLE course (...)
--
-- 산책 기록(`walk.path`)에서 **시작·끝을 잘라 낸 선**을 이름과 함께 남기는 표다. 지금 내가
-- 걸은 길은 나에게만 보이고, 커뮤니티의 "산책로 후기" 게시판에 붙일 방법이 없다. 공공데이터
-- 산책로(두루누비)는 해안·접경에 몰려 있어 동네 길을 말해 주지 못한다.
--
-- ─────────────────────────────────────────────────
-- 왜 walk 를 가리키기만 하지 않고 선을 베끼나
--
-- 코스는 산책 기록의 **다른 것**이다. 산책은 "그날 내가 걸었다" 이고 코스는 "여기를 이렇게
-- 걸으면 좋다" 다. 그래서 (1) 시작·끝 100m 를 잘라 낸 선이 들어간다 — 집 앞이 그대로 남으면
-- 공개할 수 없다, (2) 산책을 지워도 코스는 남아야 한다(`fk_course_walk ... ON DELETE SET NULL`).
-- 선을 베끼지 않고 walk 를 참조만 하면 이 둘이 성립하지 않는다.
--
-- ─────────────────────────────────────────────────
-- 컬럼
--
--   user_id     누구 것인가. 탈퇴하면 함께 사라진다(CASCADE) — 코스는 그 사람의 글이다
--   walk_id     어느 산책에서 왔나. 산책을 지워도 코스는 남는다(SET NULL)
--   name        코스 이름 60자
--   note        한 줄 소개 200자
--   tags        반려견 관점 셋을 콤마로 — leash|poopbag|shade. 표를 새로 만들지 않는다:
--               값이 셋으로 닫혀 있고, 늘어날 때 그때 나눈다(지금 나누면 조인만 는다)
--   path        잘라 낸 선. NOT NULL 이다 — 선 없는 코스는 코스가 아니다
--   distance_m  잘라 낸 뒤의 길이. 화면이 이 값을 그대로 쓴다
--   visibility  private|public. **기본은 private** — 공개는 사용자가 명시적으로 하는 일이다
--
-- SPATIAL INDEX 는 만들지 않는다. walk 와 같은 이유다(ADR-0015) — 이 표를 공간으로 묻는
-- 질의가 없다. "이웃 코스" 는 공개 목록을 받아 **기기에서** 거리를 잰다(A안 #235).
--
-- ─────────────────────────────────────────────────
-- 실행 순서
--
--   1. 01_users.sql · 12_walk.sql 이 먼저 돌아 있어야 한다. 없으면 시작하지 않는다.
--   2. 이 스크립트를 실행한다 — 새 애플리케이션을 배포하기 **전**(prod 는 validate).
--
-- 멱등: 표가 이미 있으면 지나간다. 있는데 컬럼이 모자라면 고치지 않고 멈춘다 — 누가 손으로
-- 만든 것이라 사람이 봐야 한다.
--
-- ─────────────────────────────────────────────────
-- 되돌리기(DOWN)
--
--   DROP TABLE course;
--
-- 값을 잃는다 — 사람들이 만든 코스가 전부 사라진다. 되돌리기 전에 앱을 먼저 내린다.
-- ============================================================================


-- ── 0. 사전 점검 ─────────────────────────────────────────
SET NAMES utf8mb4;

DROP PROCEDURE IF EXISTS heattrip_migration_abort;
CREATE PROCEDURE heattrip_migration_abort(IN msg VARCHAR(128))
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = msg;

SET @has_users := (
    SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name = 'users');
SET @has_walk := (
    SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name = 'walk');

SET @stmt := IF(@has_users = 1 AND @has_walk = 1,
    'SELECT ''[0-1] users · walk 확인'' AS message',
    'CALL heattrip_migration_abort(''ABORT: users 또는 walk 표가 없다. 01_users.sql · 12_walk.sql 을 먼저 돌려라.'')');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @has_course := (
    SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name = 'course');

-- 이미 있으면 컬럼이 다 있는지만 본다. 모자라면 멈춘다 — 반쪽짜리 표에 앱을 붙이면
-- validate 가 부팅에서 죽거나, 더 나쁘게는 죽지 않고 엉뚱한 값을 읽는다.
SET @cols := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'course'
      AND column_name IN ('id','user_id','walk_id','name','note','tags','path',
                          'distance_m','duration_s','visibility','created_at'));

SET @stmt := IF(@has_course = 0 OR @cols = 11,
    'SELECT ''[0-2] course 점검'' AS message',
    'CALL heattrip_migration_abort(''ABORT: course 표가 이미 있는데 컬럼이 모자라다. 사람이 확인하라.'')');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SELECT '[0] 사전 점검' AS section, @has_course AS course_already;


-- ── A. 표 ────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS `course` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `user_id` bigint NOT NULL,
  `walk_id` bigint DEFAULT NULL,
  `name` varchar(60) NOT NULL,
  `note` varchar(200) DEFAULT NULL,
  `tags` varchar(60) DEFAULT NULL,
  `path` linestring /*!80003 SRID 4326 */ NOT NULL,
  `distance_m` int NOT NULL,
  `duration_s` int NOT NULL,
  `visibility` varchar(10) NOT NULL DEFAULT 'private',
  `created_at` datetime(6) NOT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_course_user` (`user_id`,`created_at`),
  KEY `idx_course_public` (`visibility`,`created_at`),
  KEY `fk_course_walk` (`walk_id`),
  CONSTRAINT `fk_course_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_course_walk` FOREIGN KEY (`walk_id`) REFERENCES `walk` (`id`) ON DELETE SET NULL,
  CONSTRAINT `ck_course_visibility` CHECK (`visibility` in ('private','public'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;


-- ── D. 사후 검증 ─────────────────────────────────────────
SET @d_table := (
    SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name = 'course');
SET @d_cols := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'course'
      AND column_name IN ('id','user_id','walk_id','name','note','tags','path',
                          'distance_m','duration_s','visibility','created_at'));
SET @d_fk_user := (
    SELECT COUNT(*) FROM information_schema.referential_constraints
    WHERE constraint_schema = DATABASE() AND constraint_name = 'fk_course_user'
      AND delete_rule = 'CASCADE');
-- 산책을 지워도 코스는 남아야 한다. 이 규칙이 CASCADE 로 들어가면 기록을 지운 사람이
-- 자기 코스까지 잃는다.
SET @d_fk_walk := (
    SELECT COUNT(*) FROM information_schema.referential_constraints
    WHERE constraint_schema = DATABASE() AND constraint_name = 'fk_course_walk'
      AND delete_rule = 'SET NULL');
SET @d_path_notnull := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'course'
      AND column_name = 'path' AND is_nullable = 'NO');

SELECT '[D] 사후 검증' AS section,
       @d_table        AS course_table_expect_1,
       @d_cols         AS columns_expect_11,
       @d_fk_user      AS fk_user_cascade_expect_1,
       @d_fk_walk      AS fk_walk_set_null_expect_1,
       @d_path_notnull AS path_not_null_expect_1;

SET @stmt := IF(@d_table = 1 AND @d_cols = 11 AND @d_fk_user = 1 AND @d_fk_walk = 1 AND @d_path_notnull = 1,
    'SELECT ''[D] 통과 — course 표 · FK 둘(users CASCADE · walk SET NULL) · path NOT NULL'' AS message',
    'CALL heattrip_migration_abort(''ABORT: 사후 검증 실패. 위 [D] 행의 숫자를 확인하라.'')');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

DROP PROCEDURE IF EXISTS heattrip_migration_abort;
