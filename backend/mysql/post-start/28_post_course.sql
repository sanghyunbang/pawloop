-- ============================================================================
-- 28_post_course.sql
-- 글에 코스를 붙인다 — 이슈 #339
-- 대상: MySQL 8.x (운영/개발 공통)
--
-- ─────────────────────────────────────────────────
-- 무엇을 하나
--
--   ALTER TABLE post ADD COLUMN course_id bigint NULL
--   ALTER TABLE post ADD CONSTRAINT fk_post_course ... ON DELETE SET NULL
--
-- "산책로 후기" 게시판의 글이 자기 코스를 물고 다니게 하는 컬럼 하나다. 지금은 글에 경로를
-- 붙일 방법이 없어서, 새 코스를 개척해도 글과 기록이 흩어진다.
--
-- ─────────────────────────────────────────────────
-- 왜 SET NULL 인가
--
-- 코스를 지웠다고 글까지 사라지면 안 된다. 글은 사람이 쓴 문장이고 코스는 거기 붙은 그림이다.
-- 코스가 사라지면 그림만 빠지고 글은 남는다. (walk 를 지워도 코스가 남는 27_course.sql 과
-- 같은 판단이다.)
--
-- 붙일 수 있는 코스는 **내 것이면서 공개된 것**뿐이다. 그 판정은 서버가 한다
-- (`walk.CourseAttachment`) — DB 는 참조만 지킨다. 비공개로 되돌리면 글에서도 그림이
-- 사라진다(응답이 공개 코스만 싣는다).
--
-- ─────────────────────────────────────────────────
-- 실행 순서
--
--   1. 07_post.sql(post) · 27_course.sql(course) 이 먼저 돌아 있어야 한다.
--   2. 이 스크립트를 실행한다 — 새 애플리케이션을 배포하기 **전**(prod 는 validate).
--
-- 멱등: 컬럼·FK 가 이미 있으면 지나간다. 있는데 모양이 다르면 멈춘다.
--
-- ─────────────────────────────────────────────────
-- 되돌리기(DOWN)
--
--   ALTER TABLE post DROP FOREIGN KEY fk_post_course;
--   ALTER TABLE post DROP COLUMN course_id;
--
-- 글은 남고 붙어 있던 코스 연결만 사라진다.
-- ============================================================================


-- ── 0. 사전 점검 ─────────────────────────────────────────
SET NAMES utf8mb4;

DROP PROCEDURE IF EXISTS heattrip_migration_abort;
CREATE PROCEDURE heattrip_migration_abort(IN msg VARCHAR(128))
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = msg;

SET @has_post := (
    SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name = 'post');
SET @has_course := (
    SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name = 'course');

SET @stmt := IF(@has_post = 1 AND @has_course = 1,
    'SELECT ''[0-1] post · course 확인'' AS message',
    'CALL heattrip_migration_abort(''ABORT: post 또는 course 표가 없다. 07_post.sql · 27_course.sql 을 먼저 돌려라.'')');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @col_exists := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'post' AND column_name = 'course_id');
SET @col_right := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'post' AND column_name = 'course_id'
      AND data_type = 'bigint' AND is_nullable = 'YES');

SET @stmt := IF(@col_exists = 0 OR @col_right = 1,
    'SELECT ''[0-2] course_id 점검'' AS message',
    'CALL heattrip_migration_abort(''ABORT: post.course_id 가 이미 있는데 bigint NULL 허용이 아니다. 사람이 확인하라.'')');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @rows_before := (SELECT COUNT(*) FROM post);

SELECT '[0] 사전 점검' AS section, @col_exists AS course_id_already, @rows_before AS post_rows;


-- ── A. 컬럼 ──────────────────────────────────────────────
SET @stmt := IF(@col_exists = 0,
    'ALTER TABLE post ADD COLUMN course_id bigint NULL',
    'SELECT ''[A] course_id 이미 있음'' AS message');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;


-- ── B. FK · 인덱스 ───────────────────────────────────────
SET @fk_exists := (
    SELECT COUNT(*) FROM information_schema.referential_constraints
    WHERE constraint_schema = DATABASE() AND constraint_name = 'fk_post_course');

SET @stmt := IF(@fk_exists = 0,
    'ALTER TABLE post ADD CONSTRAINT fk_post_course FOREIGN KEY (course_id) REFERENCES course (id) ON DELETE SET NULL',
    'SELECT ''[B] fk_post_course 이미 있음'' AS message');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;


-- ── D. 사후 검증 ─────────────────────────────────────────
SET @d_col := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'post' AND column_name = 'course_id'
      AND data_type = 'bigint' AND is_nullable = 'YES');
-- 코스를 지웠다고 글이 사라지면 안 된다. CASCADE 로 들어가면 코스 하나를 지우다 글 여럿이 날아간다.
SET @d_fk := (
    SELECT COUNT(*) FROM information_schema.referential_constraints
    WHERE constraint_schema = DATABASE() AND constraint_name = 'fk_post_course'
      AND delete_rule = 'SET NULL');
SET @d_rows := (SELECT COUNT(*) FROM post);
SET @d_linked := (SELECT COUNT(*) FROM post WHERE course_id IS NOT NULL);

SELECT '[D] 사후 검증' AS section,
       @d_col    AS course_id_bigint_nullable_expect_1,
       @d_fk     AS fk_post_course_set_null_expect_1,
       @d_rows   AS post_rows_same,
       @d_linked AS rows_with_course_info;

SET @stmt := IF(@d_col = 1 AND @d_fk = 1 AND @d_rows = @rows_before,
    'SELECT ''[D] 통과 — post.course_id bigint NULL · fk_post_course SET NULL · 행 수 그대로'' AS message',
    'CALL heattrip_migration_abort(''ABORT: 사후 검증 실패. 위 [D] 행의 숫자를 확인하라.'')');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

DROP PROCEDURE IF EXISTS heattrip_migration_abort;
