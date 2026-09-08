-- 31_place_catalog_localtrail.sql — 이슈 #346
--
-- ## 무엇을
--
--   chk_place_catalog_source 를 넷으로 넓힌다:
--     'kto', 'localdata', 'durunubi'  →  + 'localtrail'
--
-- ## 왜
--
-- 산책로 칩이 코리아둘레길만 보여 줬다. 서울숲에서 누르면 가장 가까운 코스가 19.7km 밖
-- DMZ 평화의 길 18km 였다(#328 · 실측 2026-09-08). 두루누비 142코스의 길이 중앙값이
-- 15.6km 이고 **5km 이하가 한 개도 없다** — 반려견과 30분 걷는 사람에게 줄 것이 없다.
--
-- 전국길관광정보표준데이터(공공데이터포털 15017321)를 넣는다. 1,302개 · 길이 중앙값
-- 7.9km · 5km 이하 447개다. 서울숲 8km 안에 89개가 들어오고 그중 중앙값이 2.2km 다.
--
-- ## 왜 CHECK 만 고치나
--
-- 이 출처는 **외부를 안 부른다.** 원본의 갱신주기가 "연간" 이라 저장소에 넣어 둔 자산을
-- 읽어 place_catalog 에 담는다(#342 의 행정동 목록과 같은 판단). 그래서 새 표도 새 컬럼도
-- 없고, 막고 있는 것은 24 가 건 CHECK 하나뿐이다.
--
-- ## 이 스크립트를 안 돌리면
--
-- **부팅은 그대로 뜨고, 동네 길만 조용히 안 담긴다.** ddl-auto 는 CHECK 를 안 건드리므로
-- update 도 validate 도 이것을 못 잡는다 — 로그의 "Check constraint … is violated" 한 줄이
-- 유일한 신호다. 2026-09-08 에 24 가 안 돌아 병원·펫샵 8,110행이 매일 버려지고 있었던 것이
-- 정확히 그 모양이었다. `bash scripts/check-migrations.sh` 가 이제 그것을 묻는다.
--
-- ## 되돌리기
--
--   ALTER TABLE place_catalog DROP CHECK chk_place_catalog_source;
--   ALTER TABLE place_catalog ADD CONSTRAINT chk_place_catalog_source
--     CHECK (source in ('kto','localdata','durunubi'));
--   DELETE FROM place_catalog WHERE source = 'localtrail';
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

-- 24 가 안 돌았으면 여기서 멈춘다. singleton CHECK 가 남은 채로 넓혀 봐야
-- 행 4 를 못 넣는다 — 사람이 24 를 먼저 돌려야 한다.
SET @has_singleton := (
    SELECT COUNT(*) FROM information_schema.table_constraints
    WHERE constraint_schema = DATABASE() AND table_name = 'place_catalog'
      AND constraint_name = 'chk_place_catalog_singleton');

SET @stmt := IF(@has_singleton = 0,
    'SELECT ''[0-2] singleton 없음 확인'' AS message',
    'CALL heattrip_migration_abort(''ABORT: chk_place_catalog_singleton 이 남아 있다. 24_place_catalog_layers.sql 을 먼저 돌려라.'')');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @already := (
    SELECT COUNT(*) FROM information_schema.check_constraints
    WHERE constraint_schema = DATABASE() AND constraint_name = 'chk_place_catalog_source'
      AND check_clause LIKE '%localtrail%');

SELECT '[0] 사전 점검' AS section, @already AS already_widened,
       (SELECT COUNT(*) FROM place_catalog) AS catalog_rows;


-- ── A. CHECK 을 넷으로 ────────────────────────────────────
SET @stmt := IF(@already = 0,
    'ALTER TABLE place_catalog DROP CHECK chk_place_catalog_source',
    'SELECT ''[A-1] 이미 넓혀져 있음'' AS message');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @stmt := IF(@already = 0,
    'ALTER TABLE place_catalog ADD CONSTRAINT chk_place_catalog_source CHECK (source in (''kto'',''localdata'',''durunubi'',''localtrail''))',
    'SELECT ''[A-2] 건너뜀'' AS message');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;


-- ── D. 사후 검증 ──────────────────────────────────────────
-- 네 값을 **하나씩** 센다. LIKE 하나로 뭉치면 옛 값이 빠져도 통과한다.
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
SET @d_singleton := (
    SELECT COUNT(*) FROM information_schema.table_constraints
    WHERE constraint_schema = DATABASE() AND table_name = 'place_catalog'
      AND constraint_name = 'chk_place_catalog_singleton');

SELECT '[D] 사후 검증' AS section,
       @d_kto AS kto_expect_1, @d_localdata AS localdata_expect_1,
       @d_durunubi AS durunubi_expect_1, @d_localtrail AS localtrail_expect_1,
       @d_singleton AS singleton_expect_0;

SET @stmt := IF(@d_kto = 1 AND @d_localdata = 1 AND @d_durunubi = 1
                AND @d_localtrail = 1 AND @d_singleton = 0,
    'SELECT ''[D] 통과 — chk_place_catalog_source 가 네 값을 받는다'' AS message',
    'CALL heattrip_migration_abort(''ABORT: 사후 검증 실패. 위 [D] 행의 숫자를 보라.'')');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

DROP PROCEDURE IF EXISTS heattrip_migration_abort;
