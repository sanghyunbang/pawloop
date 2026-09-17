-- ============================================================================
-- 39_post_media.sql
-- 커뮤니티 글에 사진·동영상을 붙인다 — 이슈 #429
-- 대상: MySQL 8.x (운영/개발 공통)
--
-- ─────────────────────────────────────────────────
-- 무엇을 하나
--
--   ALTER TABLE media_objects
--     MODIFY category  enum(+ 'POST_IMAGE', 'POST_VIDEO')
--     ADD    status    varchar(10) NOT NULL   -- 'pending' | 'ready'
--     ADD    poster_key varchar(512) NULL     -- 영상 썸네일의 S3 키
--     ADD    width, height, duration_ms int NULL
--     ADD    CHECK ck_media_status
--     ADD    INDEX idx_media_orphan (ref_type, created_at)
--
-- **표를 새로 안 만든다.** `media_objects` 가 `ref_type`·`ref_id` 로 어느 도메인에나 붙게
-- 만들어져 있고 업로드·삭제·URL 조립이 다 있다. 글에 사진을 붙이는 데 필요한 것은
-- "어느 글의 것인가"(이미 있다)와 아래 다섯 컬럼뿐이다.
--
-- ─────────────────────────────────────────────────
-- status 가 왜 필요한가 — 영상은 서버를 안 지난다
--
-- 사진은 서버가 받아 S3 에 놓지만(multipart), 영상은 **앱이 S3 에 직접** 올린다 —
-- `api.pawloop.app` 앞의 Cloudflare 무료 요금제가 요청 본문을 100MB 까지만 받기 때문이다.
-- 그러면 "자리는 잡았는데 아직 안 올라온" 상태가 생긴다. 그것이 `pending` 이다.
-- 앱이 다 올렸다고 알리면 서버가 S3 에 실제 크기·형식을 묻고 `ready` 로 바꾼다.
-- `pending` 인 것은 글에 붙지 않는다.
--
-- 사진·영상 컬럼을 **한 스크립트**에 넣는 이유: 운영 반영이 손이라(#412 A-1) 두 번
-- 돌리게 하지 않는다. 영상 API 는 다음 PR 이지만 자리는 여기서 함께 판다.
--
-- ─────────────────────────────────────────────────
-- category 는 DB enum 이다 — 그래서 MODIFY 다
--
-- Hibernate 가 `@Enumerated(STRING)` 을 MySQL `enum(...)` 으로 뽑았다(정본 01_schema.sql).
-- 값을 더하려면 컬럼 타입 자체를 바꿔야 하고, **순서는 알파벳순이어야 한다** — Hibernate 가
-- 상수를 알파벳순으로 정렬해 뽑고(2026-09-13 실측 — 선언 순서가 아니다), `SchemaDdlDriftTest`
-- 가 `column_type` 문자열을 그대로 비교한다. 옛 셋이 우연히 알파벳순이라 지금까지 몰랐다.
--
-- 순서가 바뀌면 MySQL 이 표를 다시 쓰지만(끝에 붙이는 것만 즉시다) **값은 이름으로 옮긴다** —
-- 있는 행의 PROFILE_IMAGE 는 그대로 PROFILE_IMAGE 다. 사후 검증이 행 수를 잰다.
--
-- ─────────────────────────────────────────────────
-- 붙지 않은 것은 하루 뒤 거둔다 — 그 인덱스가 idx_media_orphan 이다
--
-- 올려 놓고 글을 안 쓴 사진은 `ref_type IS NULL` 인 채로 남는다. 야간 잡이
-- `ref_type IS NULL AND created_at < 어제` 를 묻고 S3 와 함께 지운다. **POST_* 카테고리만**
-- 거둔다 — 감정 여행 시절의 행(JOURNEY_IMAGE 등)은 건드리지 않는다.
--
-- ─────────────────────────────────────────────────
-- 실행 순서
--
--   `media_objects` 가 있어야 한다(정본 01_schema.sql). 앞선 post-start 에 안 기댄다.
--   새 애플리케이션을 배포하기 **전**에 돌린다.
--
-- **dev(`ddl-auto=update`)에서 앱을 먼저 띄웠으면** Hibernate 가 컬럼을 CHECK 없이 더해
-- 두고, `status` 는 NOT NULL 인데 DEFAULT 가 없어 기존 행이 '' 로 채워져 있다. 이 스크립트는
-- 그 상태를 **고친다** — 빈 값을 'ready' 로 채우고 CHECK 를 건다(38 처럼 멈추지 않는다.
-- 표를 새로 만드는 것이 아니라 있는 표를 넓히는 것이라 고칠 수 있다).
--
-- 멱등: 조각마다 있는지 보고 없는 것만 더한다. 두 번 돌려도 그대로다.
--
-- ─────────────────────────────────────────────────
-- 되돌리기(DOWN)
--
--   ALTER TABLE media_objects
--     DROP CHECK ck_media_status,
--     DROP INDEX idx_media_orphan,
--     DROP COLUMN status, DROP COLUMN poster_key,
--     DROP COLUMN width, DROP COLUMN height, DROP COLUMN duration_ms;
--   -- category 의 enum 은 POST_* 행이 하나라도 있으면 못 줄인다. 행을 먼저 지운다.
--
-- **S3 객체는 안 지워진다.** 글에 붙은 사진이 있는 채로 되돌리면 그 파일은 버킷에 남는다.
-- ============================================================================


-- ── 0. 사전 점검 ─────────────────────────────────────────
SET NAMES utf8mb4;

DROP PROCEDURE IF EXISTS heattrip_migration_abort;
CREATE PROCEDURE heattrip_migration_abort(IN msg VARCHAR(128))
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = msg;

SET @has_table := (
    SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name = 'media_objects');

SET @stmt := IF(@has_table = 1,
    'SELECT ''[0-1] media_objects 확인'' AS message',
    'CALL heattrip_migration_abort(''ABORT: media_objects 표가 없다. 정본 01_schema.sql 을 먼저 적용하라.'')');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @category_type := (
    SELECT IFNULL(MAX(column_type), '') FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'media_objects' AND column_name = 'category');

SET @stmt := IF(@category_type LIKE 'enum(%',
    'SELECT ''[0-2] category 가 enum 이다'' AS message',
    'CALL heattrip_migration_abort(''ABORT: media_objects.category 가 enum 이 아니다. 사람이 확인하라.'')');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @has_status   := (SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'media_objects' AND column_name = 'status');
SET @has_poster   := (SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'media_objects' AND column_name = 'poster_key');
SET @has_width    := (SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'media_objects' AND column_name = 'width');
SET @has_height   := (SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'media_objects' AND column_name = 'height');
SET @has_duration := (SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'media_objects' AND column_name = 'duration_ms');
SET @has_check    := (SELECT COUNT(*) FROM information_schema.table_constraints
    WHERE table_schema = DATABASE() AND table_name = 'media_objects'
      AND constraint_type = 'CHECK' AND constraint_name = 'ck_media_status');
SET @has_index    := (SELECT COUNT(*) FROM information_schema.statistics
    WHERE table_schema = DATABASE() AND table_name = 'media_objects' AND index_name = 'idx_media_orphan');
SET @has_video    := IF(@category_type LIKE '%POST_VIDEO%', 1, 0);
SET @rows_before  := (SELECT COUNT(*) FROM media_objects);

SELECT '[0] 사전 점검' AS section,
       @has_status   AS status_already,
       @has_poster   AS poster_key_already,
       @has_check    AS check_already,
       @has_index    AS index_already,
       @has_video    AS category_widened_already,
       @rows_before  AS media_rows;


-- ── A. category enum 을 넓힌다 ───────────────────────────
--
-- 순서는 알파벳순이다 — Hibernate 가 그렇게 뽑는다(머리말 참조). 정본 01_schema.sql 과 글자 그대로 같다.
SET @stmt := IF(@has_video = 1,
    'SELECT ''[A] category 이미 넓음 — 지나간다'' AS message',
    'ALTER TABLE `media_objects`
       MODIFY COLUMN `category` enum(''JOURNEY_IMAGE'',''POST_IMAGE'',''POST_VIDEO'',''PROFILE_IMAGE'',''REVIEW_IMAGE'') NOT NULL');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;


-- ── B. 컬럼 다섯 ─────────────────────────────────────────
--
-- status 는 DEFAULT 로 넣고 있는 행을 채운 뒤 DEFAULT 를 뗀다 — 남기면 새로 세운 DB(정본)와
-- 갈리고 `validate` 는 그 차이를 안 잡는다(36 과 같은 판단).
SET @stmt := IF(@has_status = 1,
    'SELECT ''[B-1] status 이미 있음'' AS message',
    'ALTER TABLE `media_objects` ADD COLUMN `status` varchar(10) NOT NULL DEFAULT ''ready''');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- Hibernate 가 먼저 만든 컬럼은 DEFAULT 없이 NOT NULL 이라 기존 행이 '' 이다. 채운다.
UPDATE `media_objects` SET `status` = 'ready' WHERE `status` IS NULL OR `status` = '';

ALTER TABLE `media_objects` ALTER COLUMN `status` DROP DEFAULT;

SET @stmt := IF(@has_poster = 1,
    'SELECT ''[B-2] poster_key 이미 있음'' AS message',
    'ALTER TABLE `media_objects` ADD COLUMN `poster_key` varchar(512) DEFAULT NULL');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @stmt := IF(@has_width = 1,
    'SELECT ''[B-3] width 이미 있음'' AS message',
    'ALTER TABLE `media_objects` ADD COLUMN `width` int DEFAULT NULL');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @stmt := IF(@has_height = 1,
    'SELECT ''[B-4] height 이미 있음'' AS message',
    'ALTER TABLE `media_objects` ADD COLUMN `height` int DEFAULT NULL');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @stmt := IF(@has_duration = 1,
    'SELECT ''[B-5] duration_ms 이미 있음'' AS message',
    'ALTER TABLE `media_objects` ADD COLUMN `duration_ms` int DEFAULT NULL');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;


-- ── C. CHECK 와 인덱스 ───────────────────────────────────
--
-- **Hibernate 의 update 도 prod 의 validate 도 CHECK 는 안 본다.** 여기서 안 걸면 아무
-- 데서도 안 걸린다.
SET @stmt := IF(@has_check = 1,
    'SELECT ''[C-1] ck_media_status 이미 있음'' AS message',
    'ALTER TABLE `media_objects` ADD CONSTRAINT `ck_media_status` CHECK ((`status` in (''pending'',''ready'')))');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- information_schema.statistics 는 **컬럼마다 한 행**이라 두 컬럼 인덱스는 2 가 나온다. `> 0` 으로 본다.
SET @stmt := IF(@has_index > 0,
    'SELECT ''[C-2] idx_media_orphan 이미 있음'' AS message',
    'ALTER TABLE `media_objects` ADD INDEX `idx_media_orphan` (`ref_type`, `created_at`)');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;


-- ── D. 사후 검증 ─────────────────────────────────────────
SET @d_cols := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'media_objects'
      AND column_name IN ('status', 'poster_key', 'width', 'height', 'duration_ms'));

SET @d_category := (
    SELECT IFNULL(MAX(column_type), '') FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'media_objects' AND column_name = 'category');
SET @d_category_ok := IF(@d_category = 'enum(''JOURNEY_IMAGE'',''POST_IMAGE'',''POST_VIDEO'',''PROFILE_IMAGE'',''REVIEW_IMAGE'')', 1, 0);

SET @d_check := (
    SELECT COUNT(*) FROM information_schema.table_constraints
    WHERE table_schema = DATABASE() AND table_name = 'media_objects'
      AND constraint_type = 'CHECK' AND constraint_name = 'ck_media_status');

SET @d_index := (
    SELECT COUNT(DISTINCT column_name) FROM information_schema.statistics
    WHERE table_schema = DATABASE() AND table_name = 'media_objects' AND index_name = 'idx_media_orphan');

SET @d_no_default := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'media_objects'
      AND column_name = 'status' AND column_default IS NULL AND is_nullable = 'NO');

SET @d_blank := (SELECT COUNT(*) FROM `media_objects` WHERE `status` NOT IN ('pending', 'ready'));
SET @d_rows  := (SELECT COUNT(*) FROM `media_objects`);

SELECT '[D] 사후 검증' AS section,
       @d_cols        AS new_columns_expect_5,
       @d_category_ok AS category_matches_hibernate_order_expect_1,
       @d_check       AS check_expect_1,
       @d_index       AS orphan_index_columns_expect_2,
       @d_no_default  AS status_not_null_without_default_expect_1,
       @d_blank       AS rows_with_unknown_status_expect_0,
       @d_rows        AS media_rows_same_as_before;

SET @stmt := IF(@d_cols = 5 AND @d_category_ok = 1 AND @d_check = 1 AND @d_index = 2
                AND @d_no_default = 1 AND @d_blank = 0 AND @d_rows = @rows_before,
    'SELECT ''[D] 통과 — 컬럼 다섯 · enum 다섯 값 · CHECK · 고아 인덱스 · 행 수 그대로'' AS message',
    'CALL heattrip_migration_abort(''ABORT: 사후 검증 실패. 위 [D] 행의 숫자를 확인하라.'')');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

DROP PROCEDURE IF EXISTS heattrip_migration_abort;
