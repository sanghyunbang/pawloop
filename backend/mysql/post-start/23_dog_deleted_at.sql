-- ============================================================================
-- 23_dog_deleted_at.sql
-- dog 에 소프트 삭제 컬럼을 더한다 — 이슈 #156
-- 대상: MySQL 8.x (운영/개발 공통)
--
-- ─────────────────────────────────────────────────
-- 무엇을 하나
--
--   ALTER TABLE dog ADD COLUMN deleted_at datetime(6) NULL
--
-- DELETE /api/dogs/{dogId} 가 이 값을 찍는다. 행은 남는다. 모든 조회(DogRepository 의
-- 세 쿼리)가 deleted_at IS NULL 을 걸어 지운 아이는 어느 조회에도 나오지 않는다.
--
-- ─────────────────────────────────────────────────
-- 왜 물리 삭제가 아닌가
--
-- walk.fk_walk_dog 가 ON DELETE CASCADE 다(12_walk.sql). 행을 지우면 **그 아이의 산책 이력
-- 전부가 조용히 함께 사라진다** — 되돌릴 수 없고, 사용자는 "프로필만 지웠다" 고 생각한다.
-- FK 를 RESTRICT 로 바꾸는 것은 답이 아니다 — 탈퇴(DELETE /auth/me, users 하드 삭제 →
-- fk_dog_user CASCADE)가 막힌다. #145 에서 실측: RESTRICT 로 바꿔 두면 11 의 사후검증이
-- fk_cascade_1=0 으로 멈춘다. 안전은 FK 가 아니라 이 컬럼으로 산다.
--
-- 산책 목록·통계는 이 컬럼을 보지 않는다 — 그 아이와 걸은 거리는 걸은 것이다(#156 4번,
-- "계속 센다"). 무지개다리를 건넌 아이의 기록을 통계에서 빼면 총 거리가 줄어 상실을 한 번
-- 더 겪게 한다. 통계에 ?dogId= 가 있으므로 "지금 우리 아이" 만 보고 싶으면 그것으로 고른다.
--
-- ─────────────────────────────────────────────────
-- 실행 순서
--
--   1. 11_dog.sql 이 먼저 돌아 있어야 한다 (dog 표). 없으면 시작하지 않는다.
--   2. 이 스크립트를 실행한다 — 새 애플리케이션을 배포하기 **전**.
--
-- 2 가 앞인 이유: prod 는 ddl-auto=validate 라 엔티티가 요구하는 컬럼이 없으면 부팅이
-- 실패한다. 옛 코드는 컬럼이 있어도 상관하지 않는다(모르는 컬럼은 안 읽는다).
--
-- 트랜잭션으로 감쌀 수 없다 — MySQL 의 DDL 은 암묵적 커밋을 일으킨다. 그래서 앞뒤로
-- 관문을 둔다: §0 사전 점검 · §D 사후 검증.
--
-- 멱등: 컬럼이 이미 있으면 "이미 있음" 을 찍고 지나간다. 있는데 모양이 다르면(datetime(6)
-- NULL 허용이 아니면) 고치지 않고 멈춘다 — 누가 손으로 만든 것이라 사람이 봐야 한다.
--
-- ─────────────────────────────────────────────────
-- 되돌리기(DOWN)
--
--   ALTER TABLE dog DROP COLUMN deleted_at;
--
-- 값을 잃는다 — 지운 아이들이 전부 되살아난다. 되돌리기 전에 앱을 먼저 내린다(validate).
-- ============================================================================


-- ── 0. 사전 점검 ─────────────────────────────────────────
SET NAMES utf8mb4;

DROP PROCEDURE IF EXISTS heattrip_migration_abort;
CREATE PROCEDURE heattrip_migration_abort(IN msg VARCHAR(128))
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = msg;

-- 0-1. dog 표가 있어야 한다.
SET @has_dog := (
    SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name = 'dog');

SET @stmt := IF(@has_dog = 1,
    'SELECT ''[0-1] dog 확인'' AS message',
    'CALL heattrip_migration_abort(''ABORT: dog 표가 없다. 11_dog.sql 을 먼저 돌려라.'')');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- 0-2. 컬럼이 이미 있나. 있으면 모양(datetime(6), NULL 허용)까지 본다.
SET @col_exists := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'dog'
      AND column_name = 'deleted_at');
SET @col_right_shape := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'dog'
      AND column_name = 'deleted_at'
      AND data_type = 'datetime' AND datetime_precision = 6 AND is_nullable = 'YES');

SET @stmt := IF(@col_exists = 0 OR @col_right_shape = 1,
    'SELECT ''[0-2] deleted_at 점검'' AS message',
    'CALL heattrip_migration_abort(''ABORT: dog.deleted_at 이 이미 있는데 datetime(6) NULL 허용이 아니다. 사람이 확인하라.'')');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @rows_before := (SELECT COUNT(*) FROM dog);

SELECT '[0] 사전 점검' AS section,
       @col_exists  AS column_already,
       @rows_before AS dog_rows;


-- ── A. 컬럼 ──────────────────────────────────────────────
SET @stmt := IF(@col_exists = 0,
    'ALTER TABLE dog ADD COLUMN deleted_at datetime(6) NULL',
    'SELECT ''[A] deleted_at 이미 있음'' AS message');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;


-- ── D. 사후 검증 ─────────────────────────────────────────
SET @d_col := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'dog'
      AND column_name = 'deleted_at'
      AND data_type = 'datetime' AND datetime_precision = 6 AND is_nullable = 'YES');

-- 행은 건드리지 않는다. 새 컬럼은 전부 NULL 이어야 한다 — 이 스크립트가 누구를 지운 것이 아니다.
SET @d_rows := (SELECT COUNT(*) FROM dog);
SET @d_marked := (SELECT COUNT(*) FROM dog WHERE deleted_at IS NOT NULL);

SELECT '[D] 사후 검증' AS section,
       @d_col    AS deleted_at_datetime6_nullable_expect_1,
       @d_rows   AS dog_rows_same,
       @d_marked AS marked_rows_info;

SET @stmt := IF(@d_col = 1 AND @d_rows = @rows_before,
    'SELECT ''[D] 통과 — dog.deleted_at datetime(6) NULL · 행 수 그대로'' AS message',
    'CALL heattrip_migration_abort(''ABORT: 사후 검증 실패. 위 [D] 행의 숫자를 확인하라.'')');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

DROP PROCEDURE IF EXISTS heattrip_migration_abort;
