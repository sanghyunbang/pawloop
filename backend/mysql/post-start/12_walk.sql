-- ============================================================================
-- 12_walk.sql — 산책 기록 표 (이슈 #145)
--
-- 왜 지금인가
--
-- 산책을 끝내면 아무것도 남지 않고 있었다. 앱은 경로·거리·시간을 제대로 쌓는데 저장할
-- 곳이 없었다. M1 의 잔여가 이것이다.
--
-- 무엇을 하나
--
--   walk 표 하나. dog 1:N walk.
--
-- 실행
--
--   mysql -u root -p heattrip < mysql/post-start/12_walk.sql
--
-- **11_dog.sql 이 먼저다.** walk 가 dog 을 FK 로 참조한다.
-- 멱등하다. 두 번 돌려도 같은 상태로 끝난다.
--
-- 되돌리기
--
--   DROP TABLE walk;
--
-- **되돌리면 사용자가 기록한 산책이 전부 사라진다.** 경로도 거리도 복구할 수 없다.
-- 앱을 먼저 내려라.
--
-- ----------------------------------------------------------------------------
-- path 가 LINESTRING 인 근거 — ADR-0015
--
-- ADR-0013 이 hibernate-spatial 을 기각했던 근거 둘 중 "SchemaDdlDriftTest 의 geometry
-- 대조 문제" 는 성립하지 않는 것으로 실측됐다. 다른 하나("공간 인덱스가 할 일이 없다")는
-- walk 에도 유효해서 **SPATIAL INDEX 는 만들지 않는다.**
--
-- 그래서 path 는 NULL 을 허용한다. MySQL 은 SPATIAL INDEX 에 NOT NULL 을 요구하는데,
-- **경로 없는 산책이 실제로 있다** — 손으로 입력한 기록과 위치 권한을 거부한 기록이다.
-- 없는 경로를 만들어 넣으면 화면이 거짓말을 한다.
-- ============================================================================


-- ── 0. 사전 점검 ────────────────────────────────────────────────────────────
-- 여기서 걸리면 스키마는 한 글자도 바뀌지 않는다.

DROP PROCEDURE IF EXISTS heattrip_migration_abort;
CREATE PROCEDURE heattrip_migration_abort(IN msg VARCHAR(128))
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = msg;

-- 0-1. dog 이 있어야 FK 를 걸 수 있다. 없으면 11_dog.sql 부터다.
SET @has_dog := (
    SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name = 'dog');
SET @stmt := IF(@has_dog = 1,
    'SELECT ''[0-1] dog 확인'' AS message',
    'CALL heattrip_migration_abort(''ABORT: dog 표가 없다. post-start/11_dog.sql 을 먼저 적용하라.'')');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- 0-2. MySQL 8 이어야 한다. SRID 를 컬럼에 못 박는 문법(`linestring srid 4326`)이
--      8.0 부터다. 5.7 에서는 이 CREATE 가 구문 오류로 죽는데, 그 오류만 보고는
--      "버전이 문제" 라는 것을 알기 어렵다.
SET @major := CAST(SUBSTRING_INDEX(VERSION(), '.', 1) AS UNSIGNED);
SET @stmt := IF(@major >= 8,
    'SELECT ''[0-2] MySQL 8 확인'' AS message',
    'CALL heattrip_migration_abort(''ABORT: MySQL 8 이상이 필요하다 (컬럼 SRID 문법).'')');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- 0-3. walk 가 이미 있는지 본다(= 재실행이거나 Hibernate 가 먼저 만들었는지).
--      dev 는 ddl-auto=update 라 **앱이 먼저 뜨면 Hibernate 가 표를 이미 만들어 둔다.**
SET @has_walk := (
    SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name = 'walk');

SELECT '[0-3] 기존 표 확인' AS section, @has_walk AS walk;

-- 0-4. walk 가 이미 있다면 client_walk_id 가 있는지 본다.
--      #145 이전 설계(schema.md §4 초안)에는 이 컬럼이 없었다. 없는 채로 통과시키면
--      **재전송이 같은 산책을 두 줄로 만든다** — 사용자가 지우기 전까지 통계가 두 배다.
SET @has_client_key := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'walk'
      AND column_name = 'client_walk_id');
SET @stmt := IF(@has_walk = 1 AND @has_client_key = 0,
    'CALL heattrip_migration_abort(''ABORT: walk 는 있는데 client_walk_id 가 없다. 기존 행에 값을 채운 뒤 UNIQUE 를 걸어야 한다 — 손으로 확인하라.'')',
    'SELECT ''[0-4] 멱등키 사전 점검 통과'' AS message');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;


-- ── A. 표 생성 (멱등) ───────────────────────────────────────────────────────

-- A-1. 산책 한 건. schema.md §4 (ADR-0015 반영본) 그대로다.
--
--      시각은 전부 **UTC** 로 들어온다. 애플리케이션이 Instant 를 UTC 벽시계로 눕혀
--      넣는다 — LocalDateTime 은 드라이버가 시간대 변환을 하지 않는 유일한 타입이라,
--      JDBC URL 의 serverTimezone 이나 컨테이너 시계가 무엇이든 넣은 값이 그대로 나온다.
--      (이 저장소의 JDBC URL 은 Asia/Seoul 인데 컨테이너 시계는 UTC 다 — 실측.)
--
--      주 경계 계산도 Java 가 한다. WEEKDAY()·CURDATE() 는 세션 시간대를 읽으므로
--      쓰지 않는다. #40 에서 그 함정이 00:00–09:00 KST 에만 터졌다.
--
--      created_at 이 목록 커서의 기준이다. started_at 은 앱이 보낸 값이라, 오프라인에
--      쌓아 둔 산책이 며칠 뒤 과거 시각으로 들어오면 이미 발급된 커서 아래 행이
--      **영원히 건너뛰어진다.**
CREATE TABLE IF NOT EXISTS walk (
    id             BIGINT       NOT NULL AUTO_INCREMENT,
    dog_id         BIGINT       NOT NULL,
    client_walk_id VARCHAR(64)  NOT NULL COMMENT '앱이 만드는 멱등키(UUID v4)',
    started_at     DATETIME(6)  NOT NULL COMMENT 'UTC. 앱이 보낸 값 — 커서로 쓰지 않는다',
    ended_at       DATETIME(6)  NULL COMMENT 'UTC',
    distance_m     INT          NOT NULL COMMENT '총 거리(m). 앱의 자기 신고값',
    duration_s     INT          NOT NULL COMMENT '총 소요(초). 앱의 자기 신고값',
    path           LINESTRING SRID 4326 NULL COMMENT 'GPS 경로. 손입력·권한거부 기록은 NULL',
    memo           VARCHAR(500) NULL,
    weather        VARCHAR(30)  NULL,
    created_at     DATETIME(6)  NOT NULL COMMENT 'UTC, 서버 시각 — 목록 커서의 기준',
    PRIMARY KEY (id),
    UNIQUE KEY uq_walk_client (dog_id, client_walk_id),
    KEY idx_walk_dog (dog_id, started_at),
    KEY idx_walk_dog_created (dog_id, created_at, id),
    CONSTRAINT fk_walk_dog FOREIGN KEY (dog_id)
      REFERENCES dog (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;


-- ── B. 인덱스·FK 가드 ───────────────────────────────────────────────────────
-- CREATE TABLE IF NOT EXISTS 는 **표가 이미 있으면 아무것도 하지 않는다.**
-- Hibernate 가 먼저 만든 표에는 빠진 것이 있을 수 있다.
--
-- 이 가드들은 **있는지만 보고 모양은 안 본다.** 이미 잘못된 모드로 서 있으면 여기서
-- 고치지 않고 아래 [D] 가 잡아 중단시킨다 — 운영 표의 제약을 조용히 DROP 하고 다시
-- 만드는 것이 중단시키고 사람에게 알리는 것보다 위험하다.

SET @has_uq := (
    SELECT COUNT(*) FROM information_schema.statistics
    WHERE table_schema = DATABASE() AND table_name = 'walk' AND index_name = 'uq_walk_client');
SET @stmt := IF(@has_uq = 0,
    'ALTER TABLE walk ADD UNIQUE KEY uq_walk_client (dog_id, client_walk_id)',
    'SELECT ''[B] uq_walk_client 이미 있음'' AS message');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @has_idx_started := (
    SELECT COUNT(*) FROM information_schema.statistics
    WHERE table_schema = DATABASE() AND table_name = 'walk' AND index_name = 'idx_walk_dog');
SET @stmt := IF(@has_idx_started = 0,
    'ALTER TABLE walk ADD KEY idx_walk_dog (dog_id, started_at)',
    'SELECT ''[B] idx_walk_dog 이미 있음'' AS message');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @has_idx_created := (
    SELECT COUNT(*) FROM information_schema.statistics
    WHERE table_schema = DATABASE() AND table_name = 'walk'
      AND index_name = 'idx_walk_dog_created');
SET @stmt := IF(@has_idx_created = 0,
    'ALTER TABLE walk ADD KEY idx_walk_dog_created (dog_id, created_at, id)',
    'SELECT ''[B] idx_walk_dog_created 이미 있음'' AS message');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @has_fk := (
    SELECT COUNT(*) FROM information_schema.referential_constraints
    WHERE constraint_schema = DATABASE() AND table_name = 'walk'
      AND constraint_name = 'fk_walk_dog');
SET @stmt := IF(@has_fk = 0,
    'ALTER TABLE walk ADD CONSTRAINT fk_walk_dog FOREIGN KEY (dog_id) REFERENCES dog (id) ON DELETE CASCADE',
    'SELECT ''[B] fk_walk_dog 이미 있음'' AS message');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;


-- ── D. 사후 검증 ────────────────────────────────────────────────────────────
-- '반쯤 적용된 채 성공처럼 끝나는' 상태를 막는 마지막 관문이다.

SET @d_table := (
    SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name = 'walk');

SET @d_cols := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'walk'
      AND column_name IN ('id', 'dog_id', 'client_walk_id', 'started_at', 'ended_at',
                          'distance_m', 'duration_s', 'path', 'memo', 'weather',
                          'created_at'));

SET @d_pk := (
    SELECT COUNT(*) FROM information_schema.statistics
    WHERE table_schema = DATABASE() AND table_name = 'walk' AND index_name = 'PRIMARY');

-- 멱등키는 **두 컬럼**이어야 한다. dog_id 없이 client_walk_id 에만 UNIQUE 를 걸면
-- 서로 다른 사람의 앱이 같은 UUID 를 만들 확률이 0 은 아니고, 그때 남의 저장이 막힌다.
SET @d_uq_cols := (
    SELECT COUNT(*) FROM information_schema.statistics
    WHERE table_schema = DATABASE() AND table_name = 'walk' AND index_name = 'uq_walk_client');

SET @d_idx := (
    SELECT COUNT(DISTINCT index_name) FROM information_schema.statistics
    WHERE table_schema = DATABASE() AND table_name = 'walk'
      AND index_name IN ('idx_walk_dog', 'idx_walk_dog_created'));

-- FK 는 **CASCADE 여야 한다.** dog 이 사라지면 그 산책도 갈 곳이 없다.
SET @d_fk_cascade := (
    SELECT COUNT(*) FROM information_schema.referential_constraints
    WHERE constraint_schema = DATABASE() AND table_name = 'walk'
      AND constraint_name = 'fk_walk_dog' AND delete_rule = 'CASCADE');

-- **SRID 는 여기서만 확인된다.**
--
-- information_schema.columns.column_type 은 'linestring' 뿐이라 SRID 가 들어 있지 않다
-- (ADR-0015 에서 실측). 즉 SchemaDdlDriftTest 는 **SRID 가 빠진 스키마와 있는 스키마를
-- 같다고 본다.** SRID 가 없으면 ST_Distance_Sphere·ST_Length(path,'metre') 가 못 쓰고,
-- 그 사실은 그 함수를 처음 부르는 날까지 아무도 모른다.
SET @d_srid := (
    SELECT COUNT(*) FROM information_schema.st_geometry_columns
    WHERE table_schema = DATABASE() AND table_name = 'walk'
      AND column_name = 'path' AND srs_id = 4326);

-- SPATIAL INDEX 는 **0 이어야 한다**(ADR-0015). 있으면 path 가 NOT NULL 이라는 뜻이고,
-- 그러면 경로 없는 산책을 저장할 수 없다.
SET @d_spatial := (
    SELECT COUNT(*) FROM information_schema.statistics
    WHERE table_schema = DATABASE() AND table_name = 'walk' AND index_type = 'SPATIAL');

SELECT '[D] 사후 검증' AS section,
       @d_table AS table_1, @d_cols AS cols_11, @d_pk AS pk_1, @d_uq_cols AS uq_cols_2,
       @d_idx AS idx_2, @d_fk_cascade AS fk_cascade_1, @d_srid AS srid_1,
       @d_spatial AS spatial_0;

SET @stmt := IF(@d_table = 1 AND @d_cols = 11 AND @d_pk = 1 AND @d_uq_cols = 2
                AND @d_idx = 2 AND @d_fk_cascade = 1 AND @d_srid = 1 AND @d_spatial = 0,
    'SELECT ''[D] 통과'' AS message',
    'CALL heattrip_migration_abort(''ABORT: 사후 검증 실패. 위 [D] 행의 숫자를 확인하라.'')');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

DROP PROCEDURE IF EXISTS heattrip_migration_abort;


-- ── E. 여기서 하지 않는 것 (판단 근거) ──────────────────────────────────────
--
-- 1. **SPATIAL INDEX 를 만들지 않는다.** 저장소에 walk 를 공간으로 묻는 질의가 하나도
--    없다("이 산책로를 지난 산책" 같은 것). 쓰지 않는 인덱스를 위해 쓰기 비용과
--    NOT NULL 제약을 사는 셈이고, NOT NULL 은 경로 없는 산책을 막는다(ADR-0015).
--
-- 2. **점별 시각을 저장하지 않는다.** LINESTRING 은 x,y 만 담는다. 넣으려면 path_t JSON
--    같은 컬럼이 하나 더 필요하다. 480점이면 약 1.5KB 로 거의 공짜지만, **안 넣으면
--    구간 페이스·일시정지 구간 복원·거리 재계산이 쌓인 행 전체에 대해 영원히 불가능**
--    하다. 그 값이 필요해지는 화면이 아직 없어서 미뤘고, 넣는 날은 마이그레이션이다.
--
-- 3. **서버가 거리를 다시 재지 않는다.** ST_Length(path, 'metre') 는 동작한다(ADR-0015
--    에서 실측). 그런데 GPS 표본이 성기면 실제보다 짧게 나오고, 그 값과 앱이 신고한
--    distance_m 이 다를 때 **무엇을 믿을지 정하지 않았다.** 순위표나 보상이 생기는 날
--    그 판단이 필요해진다.
--
-- 4. **경로 가지치기·아카이빙을 하지 않는다.** DAU 를 모른다. 1,000 DAU × 1.5회/일이면
--    walk 가 1년 안에 이 DB 에서 가장 큰 표가 되지만, 그 가정은 관측이 아니다.
--
-- 5. **walk 에 사용자 컬럼을 두지 않는다.** 소유권은 walk → dog → users 를 탄다.
--    컬럼을 따로 두면 그 둘이 어긋나는 날이 온다.
--
-- ----------------------------------------------------------------------------
-- ⚠️ 이 컬럼을 네이티브 SQL 로 다룰 사람에게
--
-- **DB 안의 좌표 순서는 계약과 반대다.** MySQL 은 SRID 4326 의 축 순서를
-- (위도, 경도)로 본다(EPSG 정의 그대로다). 계약과 앱은 [경도, 위도]이고,
-- hibernate-spatial 이 쓸 때 뒤집고 읽을 때 되돌린다.
--
-- 실측:
--   앱이 보낸 것   [[126.978, 37.5665], ...]
--   DB 에 있는 것  LINESTRING(37.5665 126.978, ...)
--   API 가 준 것   [[126.978, 37.5665], ...]     ← 왕복은 정확하다
--
-- 그래서 "이 지점에서 가까운 산책" 같은 질의를 쓸 때는
--   ST_GeomFromText('POINT(위도 경도)', 4326)
-- 이지 POINT(경도 위도) 가 아니다. 뒤집으면 **오류가 나지 않고 조용히 엉뚱한 거리**가
-- 나온다.
--
-- 저장된 값이 의미상 맞다는 것도 확인했다 — 위 3점에 대해 ST_Length(path,'metre') 가
-- 393.9m 를 주고, 그것이 그 좌표들의 실제 거리다(구간 185m + 209m).
-- ============================================================================
