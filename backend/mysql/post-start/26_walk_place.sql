-- ============================================================================
-- 26_walk_place.sql
-- walk 에 장소 축을 더한다 — 이슈 #338
-- 대상: MySQL 8.x (운영/개발 공통)
--
-- ─────────────────────────────────────────────────
-- 무엇을 하나
--
--   ALTER TABLE walk
--     ADD COLUMN place_source     varchar(16)  NULL,
--     ADD COLUMN place_content_id varchar(64)  NULL,
--     ADD COLUMN place_name       varchar(120) NULL
--   ALTER TABLE walk ADD KEY idx_walk_place (place_source, place_content_id)
--
-- "서울숲에서 산책" 을 기록할 수 있게 하는 컬럼 셋이다. 통계의 "자주 가는 곳"
-- (GET /api/walks/stats/weekly 의 topPlaces)이 이 값을 센다 — 그 전까지는 셀 근거가
-- 없어서 늘 빈 배열이었다.
--
-- ─────────────────────────────────────────────────
-- 왜 셋인가 — 이름 하나가 아니라
--
-- 계약의 PlaceRef 가 source·contentId·title 셋을 요구한다(openapi.yaml). 이름만 저장하면
-- 화면이 그 장소로 갈 수 없다 — "서울숲" 을 눌러도 어느 서울숲인지 모른다. 그래서
-- 카탈로그에서 고른 장소는 셋 다 채우고, 손으로 적은 이름은 place_name 만 채운다.
--
-- 손으로 적은 이름은 **topPlaces 에 들어가지 않는다.** PlaceRef 를 만들 수 없기 때문이고,
-- 그 사실은 openapi 와 walks.md 에 적혀 있다. 기록 카드에는 그대로 보인다.
--
-- FK 를 걸지 않는다. place_catalog 는 공공데이터를 통째로 갈아 끼우는 표라(월 1회 적재)
-- FK 를 걸면 적재가 남의 산책 기록에 막히거나, 적재 뒤 참조가 깨진다. 장소가 카탈로그에서
-- 사라져도 "그날 거기를 걸었다" 는 사실은 남아야 한다 — 그래서 값만 베껴 둔다(스냅숏).
--
-- ─────────────────────────────────────────────────
-- 폭
--
--   place_source     16  — 'kto' | 'vet' | 'shop' | 'trail' (place_catalog.source 와 같은 폭)
--   place_content_id 64  — PetPlace.contentId ('2733967' · 'vet:12' · 'trail:41')
--   place_name       120 — 화면에 그대로 나가는 이름. place_catalog 의 title 과 같은 폭
--
-- ─────────────────────────────────────────────────
-- 실행 순서
--
--   1. 12_walk.sql 이 먼저 돌아 있어야 한다 (walk 표). 없으면 시작하지 않는다.
--   2. 이 스크립트를 실행한다 — 새 애플리케이션을 배포하기 **전**.
--
-- 2 가 앞인 이유: prod 는 ddl-auto=validate 라 엔티티가 요구하는 컬럼이 없으면 부팅이
-- 실패한다. 옛 코드는 컬럼이 있어도 상관하지 않는다(모르는 컬럼은 안 읽는다).
--
-- 트랜잭션으로 감쌀 수 없다 — MySQL 의 DDL 은 암묵적 커밋을 일으킨다. 그래서 앞뒤로
-- 관문을 둔다: §0 사전 점검 · §D 사후 검증.
--
-- 멱등: 컬럼이 이미 있으면 "이미 있음" 을 찍고 지나간다. 있는데 모양이 다르면 고치지 않고
-- 멈춘다 — 누가 손으로 만든 것이라 사람이 봐야 한다.
--
-- ─────────────────────────────────────────────────
-- 되돌리기(DOWN)
--
--   ALTER TABLE walk DROP KEY idx_walk_place;
--   ALTER TABLE walk DROP COLUMN place_name, DROP COLUMN place_content_id, DROP COLUMN place_source;
--
-- 값을 잃는다 — 어느 산책이 어디였는지가 사라지고 "자주 가는 곳" 이 다시 빈다.
-- 되돌리기 전에 앱을 먼저 내린다(validate).
-- ============================================================================


-- ── 0. 사전 점검 ─────────────────────────────────────────
SET NAMES utf8mb4;

DROP PROCEDURE IF EXISTS heattrip_migration_abort;
CREATE PROCEDURE heattrip_migration_abort(IN msg VARCHAR(128))
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = msg;

-- 0-1. walk 표가 있어야 한다.
SET @has_walk := (
    SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name = 'walk');

SET @stmt := IF(@has_walk = 1,
    'SELECT ''[0-1] walk 확인'' AS message',
    'CALL heattrip_migration_abort(''ABORT: walk 표가 없다. 12_walk.sql 을 먼저 돌려라.'')');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- 0-2. 컬럼 셋이 이미 있나. 있으면 모양(varchar 폭, NULL 허용)까지 본다.
SET @src_exists := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'walk' AND column_name = 'place_source');
SET @src_right := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'walk' AND column_name = 'place_source'
      AND data_type = 'varchar' AND character_maximum_length = 16 AND is_nullable = 'YES');

SET @cid_exists := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'walk' AND column_name = 'place_content_id');
SET @cid_right := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'walk' AND column_name = 'place_content_id'
      AND data_type = 'varchar' AND character_maximum_length = 64 AND is_nullable = 'YES');

SET @name_exists := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'walk' AND column_name = 'place_name');
SET @name_right := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'walk' AND column_name = 'place_name'
      AND data_type = 'varchar' AND character_maximum_length = 120 AND is_nullable = 'YES');

SET @stmt := IF((@src_exists = 0 OR @src_right = 1)
                AND (@cid_exists = 0 OR @cid_right = 1)
                AND (@name_exists = 0 OR @name_right = 1),
    'SELECT ''[0-2] 장소 컬럼 점검'' AS message',
    'CALL heattrip_migration_abort(''ABORT: walk 의 place_* 컬럼이 이미 있는데 모양이 다르다. 사람이 확인하라.'')');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @rows_before := (SELECT COUNT(*) FROM walk);

SELECT '[0] 사전 점검' AS section,
       @src_exists  AS place_source_already,
       @cid_exists  AS place_content_id_already,
       @name_exists AS place_name_already,
       @rows_before AS walk_rows;


-- ── A. 컬럼 셋 ───────────────────────────────────────────
SET @stmt := IF(@src_exists = 0,
    'ALTER TABLE walk ADD COLUMN place_source varchar(16) NULL',
    'SELECT ''[A] place_source 이미 있음'' AS message');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @stmt := IF(@cid_exists = 0,
    'ALTER TABLE walk ADD COLUMN place_content_id varchar(64) NULL',
    'SELECT ''[A] place_content_id 이미 있음'' AS message');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @stmt := IF(@name_exists = 0,
    'ALTER TABLE walk ADD COLUMN place_name varchar(120) NULL',
    'SELECT ''[A] place_name 이미 있음'' AS message');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;


-- ── B. 인덱스 ────────────────────────────────────────────
-- "자주 가는 곳" 은 (place_source, place_content_id) 로 묶어 센다. 한 사람의 산책 수는
-- 많지 않지만, 이 인덱스가 없으면 그 묶음이 매번 전체 스캔이 된다.
SET @idx_exists := (
    SELECT COUNT(*) FROM information_schema.statistics
    WHERE table_schema = DATABASE() AND table_name = 'walk' AND index_name = 'idx_walk_place');

SET @stmt := IF(@idx_exists = 0,
    'ALTER TABLE walk ADD KEY idx_walk_place (place_source, place_content_id)',
    'SELECT ''[B] idx_walk_place 이미 있음'' AS message');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;


-- ── D. 사후 검증 ─────────────────────────────────────────
SET @d_src := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'walk' AND column_name = 'place_source'
      AND data_type = 'varchar' AND character_maximum_length = 16 AND is_nullable = 'YES');
SET @d_cid := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'walk' AND column_name = 'place_content_id'
      AND data_type = 'varchar' AND character_maximum_length = 64 AND is_nullable = 'YES');
SET @d_name := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'walk' AND column_name = 'place_name'
      AND data_type = 'varchar' AND character_maximum_length = 120 AND is_nullable = 'YES');
SET @d_idx := (
    SELECT COUNT(DISTINCT index_name) FROM information_schema.statistics
    WHERE table_schema = DATABASE() AND table_name = 'walk' AND index_name = 'idx_walk_place');

-- 행은 건드리지 않는다. 새 컬럼은 전부 NULL 이어야 한다 — 이 스크립트가 장소를 지어낸 것이 아니다.
SET @d_rows := (SELECT COUNT(*) FROM walk);
SET @d_filled := (SELECT COUNT(*) FROM walk WHERE place_name IS NOT NULL);

SELECT '[D] 사후 검증' AS section,
       @d_src    AS place_source_varchar16_nullable_expect_1,
       @d_cid    AS place_content_id_varchar64_nullable_expect_1,
       @d_name   AS place_name_varchar120_nullable_expect_1,
       @d_idx    AS idx_walk_place_expect_1,
       @d_rows   AS walk_rows_same,
       @d_filled AS rows_with_place_info;

SET @stmt := IF(@d_src = 1 AND @d_cid = 1 AND @d_name = 1 AND @d_idx = 1 AND @d_rows = @rows_before,
    'SELECT ''[D] 통과 — walk.place_source/place_content_id/place_name · idx_walk_place · 행 수 그대로'' AS message',
    'CALL heattrip_migration_abort(''ABORT: 사후 검증 실패. 위 [D] 행의 숫자를 확인하라.'')');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

DROP PROCEDURE IF EXISTS heattrip_migration_abort;
