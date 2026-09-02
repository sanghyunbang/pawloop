-- ============================================================================
-- 13_walk_path_t.sql — 산책 경로의 점별 시각 (이슈 #155, ADR-0017)
--
-- 왜 지금인가
--
-- walk.path 는 LINESTRING 이고 **x, y 만 담는다.** 점마다 몇 초에 찍혔는지는 어디에도
-- 없다. 시각은 그 순간에만 있는 정보라, 안 넣으면 지금부터 쌓이는 행 전체에 대해
-- 아래가 **영원히 불가능**해진다.
--
--   구간 페이스        "처음 1km 는 빨랐고 뒤가 느렸다"
--   일시정지 구간 복원  지금은 멈춘 동안의 좌표가 없어 나중에 보면 순간이동이다
--   거리 재계산        앱이 신고한 distance_m 을 서버가 검증할 근거
--
-- 12_walk.sql §E-2 가 "넣는 날은 마이그레이션이다" 라고 적어 둔 그 날이다.
--
-- 왜 지금이 가장 싼가
--
-- 2026-09-02 기준 walk 4행, 그중 path 가 있는 것 3행이다. 지금 미루면서 잃는 것이
-- **3행**이고, 내일은 더 많다. 이 결정만은 미룰수록 되돌릴 수 없는 손실이 커진다.
--
-- 무엇을 하나
--
--   walk.path_t JSON NULL 컬럼 하나. 시작 시각 기준 **델타 초** 배열이고
--   path 의 점 개수와 길이가 같다.
--
-- 실행
--
--   mysql -u root -p heattrip < mysql/post-start/13_walk_path_t.sql
--
-- **12_walk.sql 이 먼저다.** 멱등하다 — 두 번 돌려도 같은 상태로 끝난다.
--
-- 되돌리기
--
--   ALTER TABLE walk DROP COLUMN path_t;
--
-- 되돌리면 그때까지 쌓인 점별 시각이 사라지고 **다시 만들 수 없다.** 경로 자체는
-- 남으므로 거리·시간은 무사하다.
--
-- ----------------------------------------------------------------------------
-- 왜 JSON 이고 왜 별도 표가 아닌가
--
-- 점별 시각은 path 와 **개수가 같고 함께 태어나 함께 죽는다.** 별도 표로 빼면 조인이
-- 하나 늘고, path 는 있는데 시각이 없는 상태를 코드가 다뤄야 한다. 그 상태에 의미가
-- 없으므로 만들지 않는다.
--
-- 배열 하나가 480점(8분을 1초마다)이면 약 1.5KB 다. LINESTRING 자체가 이미 그 정도라
-- 행 크기가 두 배가 되지만, 산책 한 건이 3KB 인 것은 문제가 아니다.
--
-- NULL 을 허용하는 이유는 path 와 같다 — **손입력 기록과 위치 거부 기록에는 경로가
-- 없고**, 그러면 시각도 없다. 그리고 이 마이그레이션 이전에 쌓인 행은 영영 NULL 이다.
--
-- ----------------------------------------------------------------------------
-- 응답에는 싣지 않는다
--
-- 지금 이 값을 그리는 화면이 없다. 목록에서 path 를 뺀 것과 같은 이유로, 쓰지 않는
-- 것을 응답에 실으면 목록 한 번에 수백 KB 가 오간다. 필요해지는 날 상세 응답에 넣는다.
-- ============================================================================


-- ── 0. 사전 점검 ────────────────────────────────────────────────────────────
-- 여기서 걸리면 스키마는 한 글자도 바뀌지 않는다.

-- 이 파일은 UTF-8 이고 중단 메시지가 한글이다. 세션 문자셋을 먼저 고정한다 —
-- 안 하면 클라이언트 기본값(윈도우 mysql 은 euckr)을 물려받아, 중단이 걸리는 순간
-- 이유는 안 보이고 ERROR 1366 (Incorrect string value) 만 남는다. 실측 2026-09-02, #169.
SET NAMES utf8mb4;

DROP PROCEDURE IF EXISTS heattrip_migration_abort;
CREATE PROCEDURE heattrip_migration_abort(IN msg VARCHAR(128))
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = msg;

-- 0-1. walk 가 있어야 컬럼을 붙인다. 없으면 12_walk.sql 부터다.
SET @has_walk := (
    SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name = 'walk');
SET @stmt := IF(@has_walk = 1,
    'SELECT ''[0-1] walk 확인'' AS message',
    'CALL heattrip_migration_abort(''ABORT: walk 표가 없다. post-start/12_walk.sql 을 먼저 적용하라.'')');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- 0-2. path 컬럼이 있어야 한다. path_t 는 그것과 짝이라 혼자서는 뜻이 없다.
SET @has_path := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'walk' AND column_name = 'path');
SET @stmt := IF(@has_path = 1,
    'SELECT ''[0-2] path 확인'' AS message',
    'CALL heattrip_migration_abort(''ABORT: walk.path 가 없다. 12_walk.sql 이 온전히 적용됐는지 보라.'')');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- 0-3. 이미 있는지 본다(= 재실행이거나 Hibernate 가 먼저 만들었는지).
--      dev 는 ddl-auto=update 라 앱이 먼저 뜨면 Hibernate 가 컬럼을 이미 만들어 둔다.
SET @pre_path_t := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'walk' AND column_name = 'path_t');

SELECT '[0] 사전 점검' AS section, @has_walk AS walk_1, @has_path AS path_1,
       @pre_path_t AS path_t_before;


-- ── A. 컬럼 추가 ────────────────────────────────────────────────────────────
-- ADD COLUMN IF NOT EXISTS 는 MySQL 에 없다. 있는지 보고 조립한다.

SET @stmt := IF(@pre_path_t = 0,
    'ALTER TABLE walk ADD COLUMN path_t JSON NULL COMMENT ''시작 시각 기준 델타 초 배열. path 의 점 개수와 길이가 같다'' AFTER path',
    'SELECT ''[A] path_t 이미 있음 — 건너뜀'' AS message');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;


-- ── B. 안 하는 것 ───────────────────────────────────────────────────────────
-- 1. **길이 일치를 DB 제약으로 걸지 않는다.** path 의 점 개수와 path_t 의 배열 길이가
--    같아야 하는데, MySQL 의 CHECK 로 그것을 쓰려면 ST_NumPoints 와 JSON_LENGTH 를
--    함께 부르는 식이 되고, 생성 컬럼 없이는 인덱스도 못 건다. 실익 대비 복잡하다.
--    **서버가 저장 전에 검사한다**(WalkService). 그 검사가 유일한 방어선이므로
--    테스트로 잠근다.
--
-- 2. **인덱스를 만들지 않는다.** 이 값으로 조회하는 질의가 없다. 필요해지면 그때
--    생성 컬럼 + 인덱스를 만든다.
--
-- 3. **이미 쌓인 행을 채우지 않는다.** 채울 값이 없다 — 그 시각은 존재한 적이 없다.
--    NULL 이 정확한 표현이다.


-- ── D. 사후 검증 ────────────────────────────────────────────────────────────
-- 여기서 걸리면 위가 의도대로 안 된 것이다.

SET @d_col := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'walk' AND column_name = 'path_t');

-- JSON 이어야 한다. Hibernate 가 먼저 만들었으면 LONGTEXT 일 수 있고, 그러면
-- JSON_LENGTH 가 못 돈다.
SET @d_json := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'walk' AND column_name = 'path_t'
      AND data_type = 'json');

-- NULL 을 허용해야 한다. NOT NULL 이면 손입력 기록을 저장할 수 없다.
SET @d_nullable := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'walk' AND column_name = 'path_t'
      AND is_nullable = 'YES');

-- path 가 그대로인지도 함께 본다. 이 마이그레이션이 그것을 건드릴 이유가 없는데,
-- 건드렸다면 훨씬 큰 문제다.
SET @d_srid := (
    SELECT COUNT(*) FROM information_schema.st_geometry_columns
    WHERE table_schema = DATABASE() AND table_name = 'walk'
      AND column_name = 'path' AND srs_id = 4326);

SELECT '[D] 사후 검증' AS section,
       @d_col AS path_t_1, @d_json AS json_1, @d_nullable AS nullable_1,
       @d_srid AS path_srid_1;

SET @stmt := IF(@d_col = 1 AND @d_json = 1 AND @d_nullable = 1 AND @d_srid = 1,
    'SELECT ''[D] 통과'' AS message',
    'CALL heattrip_migration_abort(''ABORT: 사후 검증 실패. 위 [D] 행의 숫자를 확인하라.'')');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

DROP PROCEDURE IF EXISTS heattrip_migration_abort;


-- ── E. 이번에도 안 하는 것 ──────────────────────────────────────────────────
-- 1. **응답에 싣지 않는다.** 지금 이 값을 그리는 화면이 없다. 목록에서 path 를 뺀 것과
--    같은 이유다 — 쓰지 않는 것을 실으면 목록 한 번에 수백 KB 가 오간다.
--
-- 2. **서버가 거리를 다시 재지 않는다.** path_t 가 생겼으니 "3초에 500m" 같은 구간을
--    걸러낼 수 있게 됐지만, 앱이 신고한 distance_m 과 다를 때 **무엇을 믿을지는 여전히
--    안 정했다.** 순위표나 보상이 생기는 날 그 판단이 필요해진다. (12_walk.sql §E-3)
--
-- 3. **일시정지 구간을 따로 표시하지 않는다.** 델타 초가 건너뛰면 그 사이가 멈춘
--    구간이라는 것을 화면이 추론할 수 있다. 별도 플래그를 두면 두 값이 어긋날 자리가
--    생긴다.
