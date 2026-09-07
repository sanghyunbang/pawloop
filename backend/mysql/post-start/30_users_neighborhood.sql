-- ============================================================================
-- 30_users_neighborhood.sql
-- 사용자가 스스로 고른 동네 — 이슈 #342
-- 대상: MySQL 8.x (운영/개발 공통)
--
-- ─────────────────────────────────────────────────
-- 무엇을 하나
--
--   ALTER TABLE users ADD COLUMN neighborhood_code varchar(10) NULL
--   ALTER TABLE users ADD KEY idx_users_neighborhood (neighborhood_code)
--
-- 행정동 코드 열 자리다(통계청 `adm_cd2`). 앞 다섯 자리가 시군구라, 커뮤니티의
-- "우리 동네" 는 `LIKE '11200%'` 로 구(區) 단위를 훑는다 — 인덱스가 앞자리 범위를 탄다.
--
-- ─────────────────────────────────────────────────
-- 왜 좌표가 아니라 코드인가
--
-- 위치기반서비스사업 신고 전이라(#235, A안) 서버가 사용자 위치를 알 수 없다. 그런데
-- 이 앱의 이름값은 "동네" 다 — 커뮤니티가 전국 한 줄이면 옆 동네 산책로 후기를 볼 수 없다.
--
-- **사용자가 스스로 고른 행정동 이름은 위치정보가 아니다.** 단말이 측정한 값이 아니라
-- 사람이 입력한 텍스트이기 때문이다(당근이 쓰는 방식이다). 개인정보이긴 하므로
-- 개인정보처리방침의 수집 항목에 적고, 탈퇴하면 users 행과 함께 사라진다.
--
-- 그래서 이 컬럼에는 **코드만** 둔다. 위도·경도 컬럼을 나란히 두지 않는 것이 그 선이다 —
-- 중심 좌표는 앱이 내장 자산에서 읽고, 서버는 그 값을 받지도 저장하지도 않는다.
--
-- ─────────────────────────────────────────────────
-- 왜 varchar(10) 인가
--
-- 통계청 행정동 코드가 열 자리다(`1120052000`). 정수로 두면 앞의 0 이 사라지는 시도가
-- 생기고(제주 `50`, 세종 `36`), 그러면 자릿수 맞추기를 코드가 매번 해야 한다.
--
-- ─────────────────────────────────────────────────
-- 실행 순서
--
--   1. 01_schema.sql(users) 이 먼저 돌아 있어야 한다.
--   2. 이 스크립트를 실행한다 — 새 애플리케이션을 배포하기 **전**(prod 는 validate).
--
-- 멱등: 컬럼·인덱스가 이미 있으면 지나간다.
--
-- ─────────────────────────────────────────────────
-- 되돌리기(DOWN)
--
--   ALTER TABLE users DROP KEY idx_users_neighborhood;
--   ALTER TABLE users DROP COLUMN neighborhood_code;
--
-- 사람들이 고른 동네를 잃는다. 계정은 그대로다.
-- ============================================================================


-- ── 0. 사전 점검 ─────────────────────────────────────────
SET NAMES utf8mb4;

DROP PROCEDURE IF EXISTS heattrip_migration_abort;
CREATE PROCEDURE heattrip_migration_abort(IN msg VARCHAR(128))
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = msg;

SET @has_users := (
    SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name = 'users');

SET @stmt := IF(@has_users = 1,
    'SELECT ''[0-1] users 확인'' AS message',
    'CALL heattrip_migration_abort(''ABORT: users 표가 없다. 01_schema.sql 을 먼저 돌려라.'')');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @col_exists := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'users'
      AND column_name = 'neighborhood_code');
SET @col_right := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'users'
      AND column_name = 'neighborhood_code'
      AND data_type = 'varchar' AND character_maximum_length >= 10 AND is_nullable = 'YES');

SET @stmt := IF(@col_exists = 0 OR @col_right = 1,
    'SELECT ''[0-2] neighborhood_code 점검'' AS message',
    'CALL heattrip_migration_abort(''ABORT: users.neighborhood_code 가 이미 있는데 varchar(10) NULL 허용이 아니다. 사람이 확인하라.'')');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @rows_before := (SELECT COUNT(*) FROM users);

SELECT '[0] 사전 점검' AS section, @col_exists AS already, @rows_before AS user_rows;


-- ── A. 컬럼 ──────────────────────────────────────────────
SET @stmt := IF(@col_exists = 0,
    'ALTER TABLE users ADD COLUMN neighborhood_code varchar(10) NULL',
    'SELECT ''[A] 컬럼 이미 있음'' AS message');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;


-- ── B. 인덱스 ────────────────────────────────────────────
-- 커뮤니티의 "우리 동네" 가 LIKE '11200%' 로 훑는다. 앞자리 범위라 이 인덱스를 탄다.
SET @idx_exists := (
    SELECT COUNT(*) FROM information_schema.statistics
    WHERE table_schema = DATABASE() AND table_name = 'users'
      AND index_name = 'idx_users_neighborhood');

SET @stmt := IF(@idx_exists = 0,
    'ALTER TABLE users ADD KEY idx_users_neighborhood (neighborhood_code)',
    'SELECT ''[B] 인덱스 이미 있음'' AS message');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;


-- ── D. 사후 검증 ─────────────────────────────────────────
SET @d_col := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'users'
      AND column_name = 'neighborhood_code'
      AND data_type = 'varchar' AND character_maximum_length >= 10 AND is_nullable = 'YES');
SET @d_idx := (
    SELECT COUNT(*) FROM information_schema.statistics
    WHERE table_schema = DATABASE() AND table_name = 'users'
      AND index_name = 'idx_users_neighborhood');
-- 좌표 컬럼이 생기면 안 된다. 이 표에 위치를 두지 않는 것이 #235 A안의 선이다.
SET @d_no_coords := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'users'
      AND column_name IN ('lat', 'lng', 'latitude', 'longitude', 'neighborhood_lat', 'neighborhood_lng'));
SET @d_rows := (SELECT COUNT(*) FROM users);

SELECT '[D] 사후 검증' AS section,
       @d_col       AS code_varchar10_nullable_expect_1,
       @d_idx       AS index_expect_1_or_more,
       @d_no_coords AS coordinate_columns_expect_0,
       @d_rows      AS user_rows_same;

SET @stmt := IF(@d_col = 1 AND @d_idx >= 1 AND @d_no_coords = 0 AND @d_rows = @rows_before,
    'SELECT ''[D] 통과 — neighborhood_code varchar(10) NULL · 인덱스 · 좌표 컬럼 없음 · 행 수 그대로'' AS message',
    'CALL heattrip_migration_abort(''ABORT: 사후 검증 실패. 위 [D] 행의 숫자를 확인하라.'')');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

DROP PROCEDURE IF EXISTS heattrip_migration_abort;
