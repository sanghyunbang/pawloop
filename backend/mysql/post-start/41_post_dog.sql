-- ============================================================================
-- 41_post_dog.sql
-- 글에 "어떤 아이가 찍혔나" 를 붙인다 — 이슈 #451 (5번, 아이 사진첩)
-- 대상: MySQL 8.x (운영/개발 공통)
--
-- ─────────────────────────────────────────────────
-- 무엇을 하나
--
--   ALTER TABLE post
--     ADD COLUMN dog_id bigint NULL
--     ADD KEY idx_post_dog (dog_id, created_at, id)
--     ADD CONSTRAINT fk_post_dog FOREIGN KEY (dog_id) REFERENCES dog (id) ON DELETE SET NULL
--
-- ─────────────────────────────────────────────────
-- 왜 컬럼 하나인가
--
-- "아이 사진첩" 은 그 아이가 찍힌 글의 사진 격자다. 글 하나에 아이 하나면 컬럼 하나로 족하다 —
-- 여러 아이가 찍힌 글은 대표 아이 하나를 고른다(산책의 walk_dog 처럼 다대다로 가면 사진첩마다
-- 같은 글이 겹쳐 뜨고, 글쓰기 화면이 복잡해진다). 늘릴 날이 오면 그때 표를 세운다.
--
-- ─────────────────────────────────────────────────
-- FK 가 SET NULL 인 이유
--
-- 아이는 소프트 삭제라(`dog.deleted_at`) 행이 안 사라지지만, 물리 삭제가 오는 날에도 글은
-- 남아야 한다 — 글은 사람이 쓴 것이고 아이 연결은 꼬리표다.
--
-- ─────────────────────────────────────────────────
-- 인덱스가 (dog_id, created_at, id) 인 이유
--
-- 사진첩의 목록이 `?dogId=` 로 좁혀 커서(created_at, id)로 내려간다. 앞자리가 dog_id 라
-- "이 아이의 글" 이 인덱스 범위이고 정렬도 인덱스 순서 그대로다.
--
-- ─────────────────────────────────────────────────
-- 실행 순서
--
--   1. `14_community.sql`(post)과 `11_dog.sql`(dog)이 먼저다. 없으면 시작하지 않는다.
--   2. 이 스크립트를 실행한다 — 새 애플리케이션을 배포하기 **전**.
--
-- **dev(`ddl-auto=update`)에서도 앱을 띄우기 전에 돌린다.** 안 돌리면 Hibernate 가 컬럼·FK 를
-- 자기 이름으로 더해 두고, 이 스크립트는 "이미 있음" 으로 지나가 이름이 다른 FK 가 남는다.
--
-- 멱등: 조각마다 있으면 지나간다.
--
-- ─────────────────────────────────────────────────
-- 되돌리기(DOWN)
--
--   ALTER TABLE post DROP FOREIGN KEY fk_post_dog;
--   ALTER TABLE post DROP KEY idx_post_dog;
--   ALTER TABLE post DROP COLUMN dog_id;
--
-- 글도 아이도 그대로다 — 꼬리표만 사라진다.
-- ============================================================================

-- ── 0. 사전 점검 ────────────────────────────────────────
SET NAMES utf8mb4;

DROP PROCEDURE IF EXISTS heattrip_migration_abort;
CREATE PROCEDURE heattrip_migration_abort(IN msg VARCHAR(128))
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = msg;

SET @has_post := (
    SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name = 'post');
SET @has_dog := (
    SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name = 'dog');

SET @stmt := IF(@has_post = 1 AND @has_dog = 1,
    'SELECT ''[0-1] post·dog 확인 (14·11 통과)'' AS message',
    'CALL heattrip_migration_abort(''ABORT: post 또는 dog 표가 없다. 14_community.sql 과 11_dog.sql 을 먼저 돌려라.'')');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @col_exists := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'post' AND column_name = 'dog_id');
SET @col_right := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'post' AND column_name = 'dog_id'
      AND data_type = 'bigint' AND is_nullable = 'YES');

-- 있는데 모양이 다르면(NOT NULL 등) 사람이 확인한다 — 조용히 덮지 않는다.
SET @stmt := IF(@col_exists = 0 OR @col_right = 1,
    'SELECT ''[0-2] dog_id 점검'' AS message',
    'CALL heattrip_migration_abort(''ABORT: post.dog_id 가 이미 있는데 bigint NULL 허용이 아니다. 사람이 확인하라.'')');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @rows_before := (SELECT COUNT(*) FROM post);

SELECT '[0] 사전 점검' AS section, @col_exists AS already, @rows_before AS post_rows;


-- ── A. 컬럼 ──────────────────────────────────────────────
SET @stmt := IF(@col_exists = 0,
    'ALTER TABLE post ADD COLUMN dog_id bigint NULL',
    'SELECT ''[A] 컬럼 이미 있음'' AS message');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;


-- ── B. 인덱스 ────────────────────────────────────────────
SET @idx_exists := (
    SELECT COUNT(*) FROM information_schema.statistics
    WHERE table_schema = DATABASE() AND table_name = 'post' AND index_name = 'idx_post_dog');

SET @stmt := IF(@idx_exists = 0,
    'ALTER TABLE post ADD KEY idx_post_dog (dog_id, created_at, id)',
    'SELECT ''[B] 인덱스 이미 있음'' AS message');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;


-- ── C. FK ────────────────────────────────────────────────
SET @fk_exists := (
    SELECT COUNT(*) FROM information_schema.table_constraints
    WHERE table_schema = DATABASE() AND table_name = 'post'
      AND constraint_name = 'fk_post_dog' AND constraint_type = 'FOREIGN KEY');

SET @stmt := IF(@fk_exists = 0,
    'ALTER TABLE post ADD CONSTRAINT fk_post_dog FOREIGN KEY (dog_id) REFERENCES dog (id) ON DELETE SET NULL',
    'SELECT ''[C] FK 이미 있음'' AS message');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;


-- ── D. 사후 검증 ─────────────────────────────────────────
SET @d_col := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'post' AND column_name = 'dog_id'
      AND data_type = 'bigint' AND is_nullable = 'YES');
-- 사진첩 목록의 커서 축(created_at, id)이 dog_id 뒤에 온다 — 열 셋.
SET @d_idx := (
    SELECT COUNT(DISTINCT column_name) FROM information_schema.statistics
    WHERE table_schema = DATABASE() AND table_name = 'post' AND index_name = 'idx_post_dog');
SET @d_fk := (
    SELECT COUNT(*) FROM information_schema.referential_constraints
    WHERE constraint_schema = DATABASE() AND constraint_name = 'fk_post_dog'
      AND delete_rule = 'SET NULL');
SET @d_rows := (SELECT COUNT(*) FROM post);

SELECT '[D] 사후 검증' AS section,
       @d_col  AS dog_id_bigint_nullable_expect_1,
       @d_idx  AS index_columns_expect_3,
       @d_fk   AS fk_set_null_expect_1,
       @d_rows AS post_rows_same;

SET @stmt := IF(@d_col = 1 AND @d_idx = 3 AND @d_fk = 1 AND @d_rows = @rows_before,
    'SELECT ''[D] 통과 — post.dog_id bigint NULL · idx_post_dog 세 열 · fk_post_dog SET NULL · 행 수 그대로'' AS message',
    'CALL heattrip_migration_abort(''ABORT: 사후 검증 실패. 위 [D] 행의 숫자를 확인하라.'')');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

DROP PROCEDURE IF EXISTS heattrip_migration_abort;
