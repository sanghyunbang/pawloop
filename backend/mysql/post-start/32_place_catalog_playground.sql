-- 32_place_catalog_playground.sql — 이슈 #346
--
-- ## 무엇을
--
--   chk_place_catalog_source 를 다섯으로 넓힌다:
--     'kto','localdata','durunubi','localtrail'  →  + 'playground'
--
-- ## 왜
--
-- 반려견 놀이터는 목줄을 풀 수 있는 유일한 곳인데 지도에 없었다. #346 의 결정 2번이다.
--
-- **전국 표준데이터가 없다.** 공공데이터포털에서 "반려견 놀이터" 로 찾으면 시·군·구가
-- 각자 올린 파일이 나온다(고양·성남·파주·동대문구·서초구·미추홀구·계양구 …). 전국을 한
-- API 로 주는 곳이 없어서, 파일을 사람이 받아 합친 자산을 읽는다.
--
-- ## 왜 CHECK 만 고치나
--
-- 31 과 같다 — 이 출처도 **외부를 안 부른다**. 자산(data/playgrounds.json)을 읽어
-- place_catalog 에 담을 뿐이라 새 표도 새 컬럼도 없다. 막고 있는 것은 CHECK 하나다.
--
-- ## 이 스크립트를 안 돌리면
--
-- **부팅은 그대로 뜨고, 놀이터만 조용히 안 담긴다.** ddl-auto 는 CHECK 를 안 건드리므로
-- update 도 validate 도 못 잡는다 — 로그의 "Check constraint … is violated" 한 줄이
-- 유일한 신호다. `bash scripts/check-migrations.sh` 가 이제 그것을 묻는다.
--
-- ## 되돌리기
--
--   ALTER TABLE place_catalog DROP CHECK chk_place_catalog_source;
--   ALTER TABLE place_catalog ADD CONSTRAINT chk_place_catalog_source
--     CHECK (source in ('kto','localdata','durunubi','localtrail'));
--   DELETE FROM place_catalog WHERE source = 'playground';
--
-- 멱등이다 — 이미 넓혀져 있으면 "이미 있음" 을 찍고 지나간다.

SET NAMES utf8mb4;

DROP PROCEDURE IF EXISTS heattrip_migration_abort;
CREATE PROCEDURE heattrip_migration_abort(IN msg VARCHAR(128))
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = msg;


-- ── 0. 사전 점검 ─────────────────────────────────────────
SET @has_table := (
    SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name = 'place_catalog');

SET @stmt := IF(@has_table = 1,
    'SELECT ''[0-1] place_catalog 확인'' AS message',
    'CALL heattrip_migration_abort(''ABORT: place_catalog 표가 없다. 18_place_catalog.sql 을 먼저 돌려라.'')');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- 31 이 안 돌았으면 여기서 멈춘다. 넷을 건너뛰고 다섯으로 가면 동네 길이 조용히 사라진다.
SET @has_localtrail := (
    SELECT COUNT(*) FROM information_schema.check_constraints
    WHERE constraint_schema = DATABASE() AND constraint_name = 'chk_place_catalog_source'
      AND check_clause LIKE '%localtrail%');

SET @stmt := IF(@has_localtrail = 1,
    'SELECT ''[0-2] localtrail 확인'' AS message',
    'CALL heattrip_migration_abort(''ABORT: CHECK 에 localtrail 이 없다. 31_place_catalog_localtrail.sql 을 먼저 돌려라.'')');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @already := (
    SELECT COUNT(*) FROM information_schema.check_constraints
    WHERE constraint_schema = DATABASE() AND constraint_name = 'chk_place_catalog_source'
      AND check_clause LIKE '%playground%');

SELECT '[0] 사전 점검' AS section, @already AS already_widened,
       (SELECT COUNT(*) FROM place_catalog) AS catalog_rows;


-- ── A. CHECK 을 다섯으로 ──────────────────────────────────
SET @stmt := IF(@already = 0,
    'ALTER TABLE place_catalog DROP CHECK chk_place_catalog_source',
    'SELECT ''[A-1] 이미 넓혀져 있음'' AS message');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @stmt := IF(@already = 0,
    'ALTER TABLE place_catalog ADD CONSTRAINT chk_place_catalog_source CHECK (source in (''kto'',''localdata'',''durunubi'',''localtrail'',''playground''))',
    'SELECT ''[A-2] 건너뜀'' AS message');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;


-- ── D. 사후 검증 ──────────────────────────────────────────
-- 다섯 값을 **하나씩** 센다. LIKE 하나로 뭉치면 옛 값이 빠져도 통과한다.
SET @d_kto := (
    SELECT COUNT(*) FROM information_schema.check_constraints
    WHERE constraint_schema = DATABASE() AND constraint_name = 'chk_place_catalog_source'
      AND check_clause LIKE '%kto%');
SET @d_localdata := (
    SELECT COUNT(*) FROM information_schema.check_constraints
    WHERE constraint_schema = DATABASE() AND constraint_name = 'chk_place_catalog_source'
      AND check_clause LIKE '%localdata%');
SET @d_durunubi := (
    SELECT COUNT(*) FROM information_schema.check_constraints
    WHERE constraint_schema = DATABASE() AND constraint_name = 'chk_place_catalog_source'
      AND check_clause LIKE '%durunubi%');
SET @d_localtrail := (
    SELECT COUNT(*) FROM information_schema.check_constraints
    WHERE constraint_schema = DATABASE() AND constraint_name = 'chk_place_catalog_source'
      AND check_clause LIKE '%localtrail%');
SET @d_playground := (
    SELECT COUNT(*) FROM information_schema.check_constraints
    WHERE constraint_schema = DATABASE() AND constraint_name = 'chk_place_catalog_source'
      AND check_clause LIKE '%playground%');

SELECT '[D] 사후 검증' AS section,
       @d_kto AS kto_expect_1, @d_localdata AS localdata_expect_1,
       @d_durunubi AS durunubi_expect_1, @d_localtrail AS localtrail_expect_1,
       @d_playground AS playground_expect_1;

SET @stmt := IF(@d_kto = 1 AND @d_localdata = 1 AND @d_durunubi = 1
                AND @d_localtrail = 1 AND @d_playground = 1,
    'SELECT ''[D] 통과 — chk_place_catalog_source 가 다섯 값을 받는다'' AS message',
    'CALL heattrip_migration_abort(''ABORT: 사후 검증 실패. 위 [D] 행의 숫자를 보라.'')');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

DROP PROCEDURE IF EXISTS heattrip_migration_abort;
