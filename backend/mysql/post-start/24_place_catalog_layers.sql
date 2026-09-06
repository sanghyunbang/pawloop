-- ============================================================================
-- 24_place_catalog_layers.sql
-- place_catalog 를 출처별 한 벌로 넓히고 trail_route 를 만든다 — 이슈 #291
-- 대상: MySQL 8.x (운영/개발 공통)
--
-- ─────────────────────────────────────────────────
-- 무엇을 하나
--
--   A. ALTER TABLE place_catalog ADD COLUMN source varchar(16)            (NULL 로 먼저)
--   B. UPDATE place_catalog SET source = 'kto' WHERE id = 1               (옛 행은 KTO 다)
--   C. source NOT NULL · UNIQUE uk_place_catalog_source
--      · CHECK chk_place_catalog_singleton (id = 1) 을 지우고
--        CHECK chk_place_catalog_source (source in ('kto','localdata','durunubi')) 를 건다
--   D. CREATE TABLE trail_route                                            (산책로 코스의 선)
--
-- 18 에서 이 표는 **행이 하나**였다(전국 KTO 한 벌). 동물병원·펫샵(행정안전부 인허가)과
-- 산책로(두루누비)가 붙으면서 **출처마다 한 벌**이 된다 — 갱신 주기(KTO 매일 · 나머지 월 1회)와
-- 예산이 다르고, 한 벌에 섞으면 KTO 가 아픈 날 병원까지 사라진다. 앱이 받는 응답은 여전히
-- 하나다 — GET /api/places/catalog 이 세 벌을 이어 붙인다.
--
-- 번호는 고정이다: 1 = kto · 2 = localdata · 3 = durunubi (CatalogSource). 그래서 옛 행 1 은
-- 그대로 KTO 이고, 이 스크립트는 그 행에 source='kto' 만 적는다.
--
-- trail_route 는 코스 하나의 선([[경도, 위도], …] JSON)이다. 카탈로그에는 코스의 시작점만
-- 실리고, 선은 사용자가 그 산책로를 눌렀을 때 GET /api/places/trails/{courseId}/route 로 준다 —
-- 2,000 코스의 선을 카탈로그에 실으면 한 벌이 16MB 다. FK 는 없다(course_id 는 두루누비의 키).
--
-- ─────────────────────────────────────────────────
-- 실행 순서
--
--   1. 18_place_catalog.sql 이 먼저 돌아 있어야 한다 (place_catalog 표). 없으면 시작하지 않는다.
--   2. 이 스크립트를 실행한다 — 새 애플리케이션을 배포하기 **전**.
--
-- 2 가 앞인 이유: prod 는 ddl-auto=validate 라 엔티티가 요구하는 컬럼(source)과 표(trail_route)가
-- 없으면 부팅이 실패한다. 옛 코드는 새 컬럼이 있어도 상관하지 않는다 — 다만 옛 코드는
-- source 를 안 채우므로, 이 스크립트 뒤에 옛 코드가 카탈로그를 **새로** 저장하면 NOT NULL 에
-- 걸려 실패한다(옛 한 벌은 계속 서빙된다). 그래서 이 스크립트와 배포 사이를 길게 두지 않는다.
--
-- 트랜잭션으로 감쌀 수 없다 — MySQL 의 DDL 은 암묵적 커밋을 일으킨다. 그래서 앞뒤로
-- 관문을 둔다: §0 사전 점검 · §E 사후 검증.
--
-- 멱등: 컬럼·제약·표가 이미 있으면 "이미 있음" 을 찍고 지나간다. source 가 있는데 모양이
-- 다르면(varchar(16) 이 아니면) 고치지 않고 멈춘다. id 가 1·2·3 밖인 행이 있으면 멈춘다 —
-- 누가 손으로 넣은 행이라 사람이 봐야 한다.
--
-- ─────────────────────────────────────────────────
-- 되돌리기(DOWN)
--
--   DELETE FROM place_catalog WHERE id <> 1;
--   ALTER TABLE place_catalog DROP CHECK chk_place_catalog_source;
--   ALTER TABLE place_catalog DROP INDEX uk_place_catalog_source;
--   ALTER TABLE place_catalog DROP COLUMN source;
--   ALTER TABLE place_catalog ADD CONSTRAINT chk_place_catalog_singleton CHECK (id = 1);
--   DROP TABLE trail_route;
--
-- 레이어 한 벌 둘과 산책로 선을 잃는다 — 다음 적재가 다시 받는다(공공데이터라 복구 가능).
-- 되돌리기 전에 앱을 먼저 내린다(validate).
-- ============================================================================


-- ── 0. 사전 점검 ─────────────────────────────────────────
SET NAMES utf8mb4;

DROP PROCEDURE IF EXISTS heattrip_migration_abort;
CREATE PROCEDURE heattrip_migration_abort(IN msg VARCHAR(128))
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = msg;

-- 0-1. place_catalog 표가 있어야 한다.
SET @has_catalog := (
    SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name = 'place_catalog');

SET @stmt := IF(@has_catalog = 1,
    'SELECT ''[0-1] place_catalog 확인'' AS message',
    'CALL heattrip_migration_abort(''ABORT: place_catalog 표가 없다. 18_place_catalog.sql 을 먼저 돌려라.'')');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- 0-2. 행의 번호가 1·2·3 밖이면 누가 손으로 넣은 것이다 — 멈춘다.
SET @odd_rows := (SELECT COUNT(*) FROM place_catalog WHERE id NOT IN (1, 2, 3));

SET @stmt := IF(@odd_rows = 0,
    'SELECT ''[0-2] 행 번호 점검'' AS message',
    'CALL heattrip_migration_abort(''ABORT: place_catalog 에 id 가 1·2·3 이 아닌 행이 있다. 사람이 확인하라.'')');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- 0-3. source 컬럼이 이미 있나. 있으면 모양(varchar(16))까지 본다.
SET @col_exists := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'place_catalog'
      AND column_name = 'source');
SET @col_right_shape := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'place_catalog'
      AND column_name = 'source'
      AND data_type = 'varchar' AND character_maximum_length = 16);

SET @stmt := IF(@col_exists = 0 OR @col_right_shape = 1,
    'SELECT ''[0-3] source 점검'' AS message',
    'CALL heattrip_migration_abort(''ABORT: place_catalog.source 가 이미 있는데 varchar(16) 이 아니다. 사람이 확인하라.'')');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @rows_before := (SELECT COUNT(*) FROM place_catalog);
SET @has_trail := (
    SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name = 'trail_route');

SELECT '[0] 사전 점검' AS section,
       @col_exists  AS source_column_already,
       @has_trail   AS trail_route_already,
       @rows_before AS catalog_rows;


-- ── A. source 컬럼 (NULL 허용으로 먼저) ──────────────────
SET @stmt := IF(@col_exists = 0,
    'ALTER TABLE place_catalog ADD COLUMN source varchar(16) NULL',
    'SELECT ''[A] source 이미 있음'' AS message');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;


-- ── B. 값 — 옛 행 1 은 KTO 다 ────────────────────────────
UPDATE place_catalog
   SET source = CASE id WHEN 1 THEN 'kto' WHEN 2 THEN 'localdata' WHEN 3 THEN 'durunubi' END
 WHERE source IS NULL;

SELECT '[B] source 채움' AS section, ROW_COUNT() AS rows_filled;


-- ── C. NOT NULL · UNIQUE · CHECK 교체 ────────────────────
-- 같은 모양으로 MODIFY 는 멱등이다. 값이 다 찼으므로 NOT NULL 이 걸린다.
ALTER TABLE place_catalog MODIFY source varchar(16) NOT NULL;

SET @has_uk := (
    SELECT COUNT(*) FROM information_schema.statistics
    WHERE table_schema = DATABASE() AND table_name = 'place_catalog'
      AND index_name = 'uk_place_catalog_source');
SET @stmt := IF(@has_uk = 0,
    'ALTER TABLE place_catalog ADD CONSTRAINT uk_place_catalog_source UNIQUE (source)',
    'SELECT ''[C-1] uk_place_catalog_source 이미 있음'' AS message');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @has_old_chk := (
    SELECT COUNT(*) FROM information_schema.table_constraints
    WHERE table_schema = DATABASE() AND table_name = 'place_catalog'
      AND constraint_type = 'CHECK' AND constraint_name = 'chk_place_catalog_singleton');
SET @stmt := IF(@has_old_chk = 1,
    'ALTER TABLE place_catalog DROP CHECK chk_place_catalog_singleton',
    'SELECT ''[C-2] chk_place_catalog_singleton 이미 없음'' AS message');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @has_new_chk := (
    SELECT COUNT(*) FROM information_schema.table_constraints
    WHERE table_schema = DATABASE() AND table_name = 'place_catalog'
      AND constraint_type = 'CHECK' AND constraint_name = 'chk_place_catalog_source');
SET @stmt := IF(@has_new_chk = 0,
    'ALTER TABLE place_catalog ADD CONSTRAINT chk_place_catalog_source CHECK (source in (''kto'',''localdata'',''durunubi''))',
    'SELECT ''[C-3] chk_place_catalog_source 이미 있음'' AS message');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;


-- ── D. trail_route ───────────────────────────────────────
-- 엔티티(place/entity/TrailRoute)가 만드는 모양 그대로다. FK 없음 — course_id 는 두루누비의 키다.
CREATE TABLE IF NOT EXISTS trail_route (
  course_id   varchar(32)  NOT NULL,
  name        varchar(150) NOT NULL,
  point_count int          NOT NULL,
  length_m    int          NOT NULL,
  start_lat   double       NOT NULL,
  start_lng   double       NOT NULL,
  payload     longtext     NOT NULL,
  fetched_at  datetime(6)  NOT NULL,
  PRIMARY KEY (course_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;


-- ── E. 사후 검증 ─────────────────────────────────────────
SET @e_source := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'place_catalog'
      AND column_name = 'source'
      AND data_type = 'varchar' AND character_maximum_length = 16 AND is_nullable = 'NO');
SET @e_uk := (
    SELECT COUNT(*) FROM information_schema.statistics
    WHERE table_schema = DATABASE() AND table_name = 'place_catalog'
      AND index_name = 'uk_place_catalog_source' AND non_unique = 0);
SET @e_chk := (
    SELECT COUNT(*) FROM information_schema.table_constraints
    WHERE table_schema = DATABASE() AND table_name = 'place_catalog'
      AND constraint_type = 'CHECK' AND constraint_name = 'chk_place_catalog_source');
SET @e_old_chk := (
    SELECT COUNT(*) FROM information_schema.table_constraints
    WHERE table_schema = DATABASE() AND table_name = 'place_catalog'
      AND constraint_type = 'CHECK' AND constraint_name = 'chk_place_catalog_singleton');
-- 개수가 아니라 이름을 센다 — 나중에 컬럼이 늘어도 이 스크립트가 다시 돈다.
SET @e_trail_cols := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'trail_route'
      AND column_name IN ('course_id', 'name', 'point_count', 'length_m',
                          'start_lat', 'start_lng', 'payload', 'fetched_at'));
SET @e_rows := (SELECT COUNT(*) FROM place_catalog);
SET @e_bad_source := (
    SELECT COUNT(*) FROM place_catalog
    WHERE source IS NULL OR source NOT IN ('kto', 'localdata', 'durunubi'));

SELECT '[E] 사후 검증' AS section,
       @e_source     AS source_varchar16_not_null_expect_1,
       @e_uk         AS unique_source_expect_1,
       @e_chk        AS check_source_expect_1,
       @e_old_chk    AS check_singleton_expect_0,
       @e_trail_cols AS trail_route_named_columns_expect_8,
       @e_rows       AS catalog_rows_same,
       @e_bad_source AS bad_source_rows_expect_0;

SET @stmt := IF(@e_source = 1 AND @e_uk = 1 AND @e_chk = 1 AND @e_old_chk = 0
                AND @e_trail_cols = 8 AND @e_rows = @rows_before AND @e_bad_source = 0,
    'SELECT ''[E] 통과 — place_catalog.source(UNIQUE·CHECK) · trail_route · 행 수 그대로'' AS message',
    'CALL heattrip_migration_abort(''ABORT: 사후 검증 실패. 위 [E] 행의 숫자를 확인하라.'')');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

DROP PROCEDURE IF EXISTS heattrip_migration_abort;
