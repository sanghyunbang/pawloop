-- ============================================================================
-- 43_media_chat_image.sql
-- media_objects.category 에 CHAT_IMAGE 를 더한다 — 이슈 #452 (채팅 말풍선 사진)
-- 대상: MySQL 8.x (운영/개발 공통)
--
-- ─────────────────────────────────────────────────
-- 무엇을 하나
--
--   ALTER TABLE media_objects
--     MODIFY category enum('CHAT_IMAGE','JOURNEY_IMAGE','POST_IMAGE','POST_VIDEO','PROFILE_IMAGE','REVIEW_IMAGE','WALK_IMAGE') NOT NULL
--
-- ─────────────────────────────────────────────────
-- 왜 ENUM 을 고치나 · 왜 이번엔 끝이 아니라 앞인가
--
-- Hibernate 가 `@Enumerated(STRING)` 을 MySQL 의 ENUM 컬럼으로 만든다(01_schema.sql). 코드에
-- 값(`UploadCategory.CHAT_IMAGE`)을 더하면 표도 그 값을 알아야 한다 — 모르면 채팅 사진을 올리는
-- 순간 "Data truncated for column 'category'" 로 500 이다.
--
-- 42 는 값을 **끝에** 더했다(InnoDB 가 표를 다시 쓰지 않는다). 이번엔 **알파벳 자리(맨 앞)** 에
-- 넣는다 — Hibernate 는 ENUM 값을 알파벳순으로 뽑으므로 01_schema.sql(새로 만드는 DB)의 순서가
-- 그렇고, 42 의 WALK_IMAGE 는 우연히 알파벳 끝이라 두 판단이 같았다. CHAT_IMAGE 는 앞이다.
-- 끝에 넣으면 이 표만 새 DB 와 `SHOW CREATE TABLE` 이 달라지고, 그 차이는 아무 검사도 잡지
-- 못한 채 남는다(`ddl-auto=validate` 는 ENUM 의 값 순서를 안 본다). 앞에 넣으면 InnoDB 가 표를
-- 한 번 다시 쓰지만, 이 표는 업로드 한 건에 행 하나(수백 행)라 밀리초다. 그동안 쓰기가 잠긴다 —
-- 새 코드 배포 **전**, 조용한 시간에 돌린다.
--
-- ─────────────────────────────────────────────────
-- 실행 순서
--
--   1. `media_objects` 표가 먼저다(01_schema.sql). 42(WALK_IMAGE)가 먼저 들어가 있어야 한다 —
--      없으면 시작하지 않는다(값 목록을 통째로 쓰므로 42 를 건너뛰면 WALK_IMAGE 가 빠진 채 굳는다).
--   2. 이 스크립트를 실행한다 — 새 애플리케이션을 배포하기 **전**.
--
-- **dev(`ddl-auto=update`)에서도 앱을 띄우기 전에 돌린다.** ddl-auto=update 는 ENUM 값을 안 더한다.
--
-- 멱등: 이미 있으면 지나간다.
--
-- ─────────────────────────────────────────────────
-- 되돌리기(DOWN)
--
--   CHAT_IMAGE 행이 하나라도 있으면 되돌릴 수 없다(값을 빼면 그 행이 '' 로 잘린다). 없으면:
--   ALTER TABLE media_objects
--     MODIFY category enum('JOURNEY_IMAGE','POST_IMAGE','POST_VIDEO','PROFILE_IMAGE','REVIEW_IMAGE','WALK_IMAGE') NOT NULL;
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

-- 42 가 먼저다 — 값 목록을 통째로 쓰므로 WALK_IMAGE 가 없는 표에 이 문장을 대면 그 값이 빠진다.
SET @stmt := IF(@col_type LIKE '%''WALK_IMAGE''%',
    'SELECT ''[0-3] WALK_IMAGE 있음 — 42 적용됨'' AS message',
    'CALL heattrip_migration_abort(''ABORT: category 에 WALK_IMAGE 가 없다. 42_media_walk_image.sql 을 먼저 돌려라.'')');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @already := IF(@col_type LIKE '%''CHAT_IMAGE''%', 1, 0);
SET @rows_before := (SELECT COUNT(*) FROM media_objects);

SELECT '[0] 사전 점검' AS section, @col_type AS category_type, @already AS already, @rows_before AS media_rows;


-- ── A. ENUM 에 값 더하기 — 01_schema.sql 과 글자까지 같은 순서로 ──────────
SET @stmt := IF(@already = 0,
    'ALTER TABLE media_objects MODIFY category enum(''CHAT_IMAGE'',''JOURNEY_IMAGE'',''POST_IMAGE'',''POST_VIDEO'',''PROFILE_IMAGE'',''REVIEW_IMAGE'',''WALK_IMAGE'') NOT NULL',
    'SELECT ''[A] CHAT_IMAGE 이미 있음'' AS message');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;


-- ── D. 사후 검증 ─────────────────────────────────────────
SET @d_type := (
    SELECT column_type FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'media_objects' AND column_name = 'category');
SET @d_has := IF(@d_type LIKE '%''CHAT_IMAGE''%', 1, 0);
SET @d_rows := (SELECT COUNT(*) FROM media_objects);

SELECT '[D] 사후 검증' AS section,
       @d_type AS category_type,
       @d_has  AS chat_image_expect_1,
       @d_rows AS media_rows_same;

SET @stmt := IF(@d_has = 1 AND @d_rows = @rows_before,
    'SELECT ''[D] 통과 — media_objects.category 에 CHAT_IMAGE · 행 수 그대로'' AS message',
    'CALL heattrip_migration_abort(''ABORT: 사후 검증 실패. 위 [D] 행의 숫자를 확인하라.'')');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

DROP PROCEDURE IF EXISTS heattrip_migration_abort;
