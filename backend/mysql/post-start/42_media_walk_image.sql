-- ============================================================================
-- 42_media_walk_image.sql
-- media_objects.category 에 WALK_IMAGE 를 더한다 — 이슈 #450 (산책 중 찍은 사진)
-- 대상: MySQL 8.x (운영/개발 공통)
--
-- ─────────────────────────────────────────────────
-- 무엇을 하나
--
--   ALTER TABLE media_objects
--     MODIFY category enum('JOURNEY_IMAGE','POST_IMAGE','POST_VIDEO','PROFILE_IMAGE','REVIEW_IMAGE','WALK_IMAGE') NOT NULL
--
-- ─────────────────────────────────────────────────
-- 왜 ENUM 을 고치나
--
-- Hibernate 가 `@Enumerated(STRING)` 을 MySQL 의 ENUM 컬럼으로 만든다(01_schema.sql). 코드에
-- 값(`UploadCategory.WALK_IMAGE`)을 더하면 표도 그 값을 알아야 한다 — 모르면 산책 사진을 올리는
-- 순간 "Data truncated for column 'category'" 로 500 이다. 값을 **끝에** 더하면 InnoDB 는 표를 다시
-- 쓰지 않는다(메타데이터만 바뀐다). 순서를 바꾸거나 값을 빼면 다시 쓴다 — 그래서 끝에 더한다.
--
-- ─────────────────────────────────────────────────
-- 실행 순서
--
--   1. `media_objects` 표가 먼저다(감정 여행 시절부터 있던 표, 01_schema.sql). 없으면 시작하지 않는다.
--   2. 이 스크립트를 실행한다 — 새 애플리케이션을 배포하기 **전**.
--
-- **dev(`ddl-auto=update`)에서도 앱을 띄우기 전에 돌린다.** ddl-auto=update 는 ENUM 값을 안 더한다.
--
-- 멱등: 이미 있으면 지나간다.
--
-- ─────────────────────────────────────────────────
-- 되돌리기(DOWN)
--
--   WALK_IMAGE 행이 하나라도 있으면 되돌릴 수 없다(값을 빼면 그 행이 '' 로 잘린다). 없으면:
--   ALTER TABLE media_objects
--     MODIFY category enum('JOURNEY_IMAGE','POST_IMAGE','POST_VIDEO','PROFILE_IMAGE','REVIEW_IMAGE') NOT NULL;
-- ============================================================================

-- ── 0. 사전 점검 ────────────────────────────────────────
SET NAMES utf8mb4;

DROP PROCEDURE IF EXISTS heattrip_migration_abort;
CREATE PROCEDURE heattrip_migration_abort(IN msg VARCHAR(128))
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = msg;

SET @has_table := (
    SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name = 'media_objects');

SET @stmt := IF(@has_table = 1,
    'SELECT ''[0-1] media_objects 확인'' AS message',
    'CALL heattrip_migration_abort(''ABORT: media_objects 표가 없다. 01_schema.sql 을 먼저 돌려라.'')');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @col_type := (
    SELECT column_type FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'media_objects' AND column_name = 'category');

-- 컬럼이 ENUM 이 아니면(누가 VARCHAR 로 바꿨으면) 사람이 확인한다 — 조용히 덮지 않는다.
SET @stmt := IF(@col_type IS NOT NULL AND @col_type LIKE 'enum(%',
    'SELECT ''[0-2] category 는 ENUM'' AS message',
    'CALL heattrip_migration_abort(''ABORT: media_objects.category 가 ENUM 이 아니다. 사람이 확인하라.'')');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @already := IF(@col_type LIKE '%''WALK_IMAGE''%', 1, 0);
SET @rows_before := (SELECT COUNT(*) FROM media_objects);

SELECT '[0] 사전 점검' AS section, @col_type AS category_type, @already AS already, @rows_before AS media_rows;


-- ── A. ENUM 에 값 더하기 ──────────────────────────────────
SET @stmt := IF(@already = 0,
    'ALTER TABLE media_objects MODIFY category enum(''JOURNEY_IMAGE'',''POST_IMAGE'',''POST_VIDEO'',''PROFILE_IMAGE'',''REVIEW_IMAGE'',''WALK_IMAGE'') NOT NULL',
    'SELECT ''[A] WALK_IMAGE 이미 있음'' AS message');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;


-- ── D. 사후 검증 ─────────────────────────────────────────
SET @d_type := (
    SELECT column_type FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'media_objects' AND column_name = 'category');
SET @d_has := IF(@d_type LIKE '%''WALK_IMAGE''%', 1, 0);
SET @d_rows := (SELECT COUNT(*) FROM media_objects);

SELECT '[D] 사후 검증' AS section,
       @d_type AS category_type,
       @d_has  AS walk_image_expect_1,
       @d_rows AS media_rows_same;

SET @stmt := IF(@d_has = 1 AND @d_rows = @rows_before,
    'SELECT ''[D] 통과 — media_objects.category 에 WALK_IMAGE · 행 수 그대로'' AS message',
    'CALL heattrip_migration_abort(''ABORT: 사후 검증 실패. 위 [D] 행의 숫자를 확인하라.'')');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

DROP PROCEDURE IF EXISTS heattrip_migration_abort;
