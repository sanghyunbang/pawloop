-- ============================================================================
-- 10_place_cache.sql
-- 관광공사(KTO) 프록시의 캐시와 호출 예산 — 이슈 #40
-- 대상: MySQL 8.x (운영/개발 공통)
--
-- ─────────────────────────────────────────────────────────────────────────────
-- 실행 순서
--
--   1. 이 스크립트를 실행한다 (앱 배포 **전**)
--   2. 그 다음 새 애플리케이션을 배포한다
--
-- 이 순서는 사실상 강제된다 — prod 는 ddl-auto=validate 라 엔티티가 요구하는 테이블이
-- 없으면 **부팅 자체가 실패한다.** 되돌릴 때는 반대로, 앱을 먼저 내린다.
--
-- 앞선 스크립트에 의존하지 않는다. 이 셋은 FK 가 하나도 없다(아래 참조).
--
-- 빈 DB 를 새로 세우는 경우에는 이 파일이 필요 없다. mysql/init/01_schema.sql 이
-- 세 표를 이미 담고 있다(#58).
--
-- ─────────────────────────────────────────────────────────────────────────────
-- 이 표들에서 되돌리기 비싼 결정 넷
--
-- 1. **kto_call_budget 이 DB 행이다.** 프로세스 안의 카운터가 아니다. 재기동하면 0 이 되고
--    인스턴스가 둘이면 각자 세기 때문이다 — 하루 세 번 배포하면 상한이 구조적으로 3배가
--    된다. KTO 일 한도는 1,000콜이고 그것을 넘기면 지도 탭이 죽는다. 상한을 지키는 장치는
--    **이 표 하나**이고, 예약은 조건을 SET 이 아니라 WHERE 에 넣은 조건부 UPDATE 다:
--
--        UPDATE kto_call_budget SET used = used + :units
--         WHERE day = :day AND pool = :pool AND used + :units <= :cap
--
--    조건이 WHERE 에 있어야 Connector/J 의 useAffectedRows 설정과 무관하게 판정이 뒤집히지
--    않는다. SET used = IF(used < cap, used+1, used) 로 쓰면 소진 상태에서도 '값이 안 바뀐
--    행 1건' 이 잡혀 통과한다(CLIENT_FOUND_ROWS 가 기본이다).
--
-- 2. **place_cell 에 만료(hard TTL)가 없다.** fetched_at 은 "갱신을 시도해도 되는가" 만
--    정하고, 예산이 없으면 오래된 스냅샷을 **그대로 계속 준다.** 만료를 두면 좌표를 훑는
--    요청이 며칠 이어졌을 때 셀이 전부 비고 지도가 영구히 빈 화면이 된다 — 만료가 없으면
--    그 경로 자체가 없다. 오래된 좌표를 보여 주는 것이 빈 지도보다 낫다.
--
-- 3. **pet_place_detail 의 시각이 소스별로 둘이다**(common_fetched_at · pet_fetched_at).
--    하나로 합치면 "개요는 받았는데 반려동반 정보만 타임아웃" 인 부분 성공이 완전 성공과
--    구분되지 않아 30일 동안 눌어붙는다. 둘로 나누면 다음 요청이 빠진 쪽만 다시 부른다.
--
-- 4. **FK 가 하나도 없다.** place_cell 은 좌표 격자이고 pet_place_detail 의 content_id 는
--    KTO 가 준 불투명 문자열이라 우리 표의 키가 아니다. places 표에 FK 를 걸면 KTO 가 새로
--    만든 장소를 우리가 적재하기 전까지 캐시할 수 없다.
--
-- ⚠️ 트랜잭션으로 감쌀 수 없다 — MySQL 의 DDL 은 암묵적 커밋을 일으킨다.
--    그래서 앞뒤로 관문을 둔다: §0 사전 점검 · §D 사후 검증.
--    두 관문 모두 SIGNAL SQLSTATE '45000' 으로 mysql 클라이언트를 0 이 아닌 코드로 끝낸다.
--
-- 멱등: CREATE TABLE IF NOT EXISTS + 인덱스별 information_schema 가드 + PREPARE/EXECUTE.
--       (01~09 가 쓰는 것과 같은 패턴이다.) 재실행해도 안전하다.
--
-- ─────────────────────────────────────────────────────────────────────────────
-- 되돌리기(DOWN) — 실행하지 말 것. 되돌려야 할 때만 손으로 골라 쓴다.
--
--   DROP TABLE pet_place_detail;
--   DROP TABLE place_cell;
--   DROP TABLE kto_call_budget;
--
-- 되돌리면 **그날의 호출 예산 사용량이 사라진다.** 그 순간부터 상한을 세는 장치가 없으므로
-- 앱을 먼저 내려야 한다. 캐시(place_cell · pet_place_detail)는 지워도 데이터 손실이
-- 아니지만, 다시 채우는 데 예산이 든다 — 서울 전역을 데우는 데 154콜이다.
-- ============================================================================


-- ── 0. 사전 점검 ────────────────────────────────────────────────────────────
-- 여기서 걸리면 스키마는 한 글자도 바뀌지 않는다.

-- 중단 장치. SIGNAL 은 prepared statement 프로토콜이 지원하지 않아서(ERROR 1295)
-- 조건부로 던지려면 프로시저 한 겹이 필요하다. MESSAGE_TEXT 는 128자가 상한이다.
-- 이 파일은 UTF-8 이고 중단 메시지가 한글이다. 세션 문자셋을 먼저 고정한다 —
-- 안 하면 클라이언트 기본값(윈도우 mysql 은 euckr)을 물려받아, 중단이 걸리는 순간
-- 이유는 안 보이고 ERROR 1366 (Incorrect string value) 만 남는다. 실측 2026-09-02, #169.
SET NAMES utf8mb4;

DROP PROCEDURE IF EXISTS heattrip_migration_abort;
CREATE PROCEDURE heattrip_migration_abort(IN msg VARCHAR(128))
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = msg;

-- 0-1. 세 표가 이미 있는지 본다(= 재실행이거나 Hibernate 가 먼저 만들었는지).
--      dev 는 ddl-auto=update 라 **앱이 먼저 뜨면 Hibernate 가 표를 이미 만들어 둔다.**
SET @has_budget := (
    SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name = 'kto_call_budget');
SET @has_cell := (
    SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name = 'place_cell');
SET @has_detail := (
    SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name = 'pet_place_detail');

SELECT '[0-1] 기존 표 확인' AS section,
       @has_budget AS kto_call_budget, @has_cell AS place_cell, @has_detail AS pet_place_detail;

-- 0-2. kto_call_budget 이 이미 있다면 기본키가 (day, pool) 인지 확인한다.
--      day 하나에만 걸려 있으면 풀 두 개가 한 행을 다투고, 상한이 합산으로 무너진다.
--      **이 표는 상한을 지키는 유일한 장치**라 잘못된 모양으로 통과시키면 안 된다.
SET @budget_pk_cols := (
    SELECT COUNT(*) FROM information_schema.statistics
    WHERE table_schema = DATABASE() AND table_name = 'kto_call_budget'
      AND index_name = 'PRIMARY');
SET @stmt := IF(@has_budget = 1 AND @budget_pk_cols <> 2,
    'CALL heattrip_migration_abort(''ABORT: kto_call_budget 의 PK 가 (day, pool) 두 컬럼이 아니다. 손으로 확인하라.'')',
    'SELECT ''[0-2] kto_call_budget 사전 점검 통과'' AS message');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- 0-3. place_cell 이 이미 있다면 기본키가 (lat_idx, lng_idx) 두 컬럼인지 확인한다.
--      하나만 걸려 있으면 위도가 같은 셀들이 서로를 덮어써서 지도가 엉뚱한 곳을 보여 준다.
SET @cell_pk_cols := (
    SELECT COUNT(*) FROM information_schema.statistics
    WHERE table_schema = DATABASE() AND table_name = 'place_cell'
      AND index_name = 'PRIMARY');
SET @stmt := IF(@has_cell = 1 AND @cell_pk_cols <> 2,
    'CALL heattrip_migration_abort(''ABORT: place_cell 의 PK 가 (lat_idx, lng_idx) 두 컬럼이 아니다. 손으로 확인하라.'')',
    'SELECT ''[0-3] place_cell 사전 점검 통과'' AS message');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;


-- ── A. 표 생성 (멱등) ───────────────────────────────────────────────────────

-- A-1. 하루치 호출 예산.
--      day 는 **KST 기준 날짜**이고 애플리케이션이 Java 에서 만들어 넘긴다 —
--      DB 세션 타임존을 믿지 않는다(운영과 로컬이 다를 수 있다).
--      pool 은 'nearby' | 'detail'. 상한(cap)은 여기 없다 — 프로퍼티다.
--      상한을 표에 두면 값을 바꿀 때 마이그레이션이 필요해지고, 배포 후 일주일 관측해서
--      조정하기로 한 값이라 그건 너무 비싸다.
CREATE TABLE IF NOT EXISTS kto_call_budget (
    `day`  DATE        NOT NULL,
    pool   VARCHAR(16) NOT NULL,
    used   INT         NOT NULL DEFAULT 0,
    PRIMARY KEY (`day`, pool)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- A-2. 격자 셀 하나의 스냅샷.
--      lat_idx/lng_idx 는 좌표를 0.02°로 양자화한 정수다(GridCell 참조).
--      payload 는 **우리 계약(Place)의 모양**으로 정규화한 JSON 배열이다 — KTO 응답 원문이
--      아니다. 원문을 두면 서빙할 때마다 KTO 의 모양을 다시 해석해야 하고, 그 해석이
--      두 곳에 살게 된다.
--      total_count 는 KTO 가 말한 전체 수다. item_count 보다 크면 잘렸다는 뜻이라,
--      numOfRows 를 올려야 하는지 **관측으로** 알 수 있다.
CREATE TABLE IF NOT EXISTS place_cell (
    lat_idx     INT      NOT NULL,
    lng_idx     INT      NOT NULL,
    payload     LONGTEXT NOT NULL,
    item_count  INT      NOT NULL,
    total_count INT      NOT NULL DEFAULT 0,
    fetched_at  DATETIME(6) NOT NULL,
    failed_at   DATETIME(6) NULL,
    fail_streak INT      NOT NULL DEFAULT 0,
    PRIMARY KEY (lat_idx, lng_idx)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- A-3. 장소 상세 캐시.
--      content_id 는 KTO 가 준 불투명 문자열이다. 우리 places 표의 키가 아니므로 FK 가 없다.
--      기본 필드(title·addr·lat·lng…)를 함께 든다. 상세 응답이 계약상
--      allOf: [Place, ...] 라 그 필드들이 함께 나가야 하는데, 셀 스냅샷 JSON 을 뒤져
--      찾으면 표 전체를 훑게 된다. 목록에 실어 보낼 때 여기 같이 적어 두는 편이 싸다.
--
--      not_found_at 이 **음수 캐시**다 — 없는 id 를 반복해 물어도 아웃바운드 호출이 0 이다.
--      이게 없으면 무작위 id 를 던지는 것만으로 상세 예산을 태울 수 있다.
CREATE TABLE IF NOT EXISTS pet_place_detail (
    content_id        VARCHAR(64)  NOT NULL,
    title             VARCHAR(255) NULL,
    addr              VARCHAR(255) NULL,
    tel               VARCHAR(64)  NULL,
    image             VARCHAR(512) NULL,
    lat               DOUBLE       NULL,
    lng               DOUBLE       NULL,
    content_type_id   VARCHAR(16)  NULL,
    overview          LONGTEXT    NULL,
    acmpy_psbl_cpam   TEXT        NULL,
    acmpy_need_mtr    TEXT        NULL,
    etc_acmpy_info    TEXT        NULL,
    common_fetched_at DATETIME(6) NULL,
    pet_fetched_at    DATETIME(6) NULL,
    not_found_at      DATETIME(6) NULL,
    PRIMARY KEY (content_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;


-- ── B. 인덱스 보정 (멱등) ───────────────────────────────────────────────────
-- 운영자가 "얼마나 오래된 셀이 남아 있나" 를 물을 때 쓴다. 서빙 경로는 PK 로만 찾으므로
-- 이 인덱스가 없어도 느려지지 않는다 — 없으면 관측이 표 전체 스캔이 될 뿐이다.

SET @idx_cell_fetched := (
    SELECT COUNT(*) FROM information_schema.statistics
    WHERE table_schema = DATABASE() AND table_name = 'place_cell'
      AND index_name = 'idx_place_cell_fetched');
SET @stmt := IF(@idx_cell_fetched = 0,
    'CREATE INDEX idx_place_cell_fetched ON place_cell (fetched_at)',
    'SELECT ''[B-1] idx_place_cell_fetched 이미 있음'' AS message');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;


-- ── D. 사후 검증 ────────────────────────────────────────────────────────────
-- '반쯤 적용된 채 성공처럼 끝나는' 상태를 막는 마지막 관문이다.
-- ddl-auto=validate 는 PK 도 인덱스도 검사하지 않으므로, 여기서 확인하지 않으면
-- 빠진 사실을 앱도 CI 도 끝까지 알려주지 않는다.

SET @d_tables := (
    SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema = DATABASE()
      AND table_name IN ('kto_call_budget', 'place_cell', 'pet_place_detail'));

SET @d_budget_cols := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'kto_call_budget'
      AND column_name IN ('day', 'pool', 'used'));

SET @d_cell_cols := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'place_cell'
      AND column_name IN ('lat_idx', 'lng_idx', 'payload', 'item_count', 'total_count',
                          'fetched_at', 'failed_at', 'fail_streak'));

SET @d_detail_cols := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'pet_place_detail'
      AND column_name IN ('content_id', 'title', 'addr', 'tel', 'image', 'lat', 'lng',
                          'content_type_id', 'overview', 'acmpy_psbl_cpam', 'acmpy_need_mtr',
                          'etc_acmpy_info', 'common_fetched_at', 'pet_fetched_at',
                          'not_found_at'));

-- PK 는 **컬럼 수로** 센다 — 이름만 보면 '한 컬럼만 걸린 PK' 를 통과시킨다.
-- kto_call_budget 의 PK 가 (day) 하나면 풀 둘이 한 행을 다투고 상한이 합산으로 무너진다.
SET @d_budget_pk := (
    SELECT COUNT(*) FROM information_schema.statistics
    WHERE table_schema = DATABASE() AND table_name = 'kto_call_budget' AND index_name = 'PRIMARY');
SET @d_cell_pk := (
    SELECT COUNT(*) FROM information_schema.statistics
    WHERE table_schema = DATABASE() AND table_name = 'place_cell' AND index_name = 'PRIMARY');
SET @d_detail_pk := (
    SELECT COUNT(*) FROM information_schema.statistics
    WHERE table_schema = DATABASE() AND table_name = 'pet_place_detail' AND index_name = 'PRIMARY');

-- FK 는 **0이어야 한다** (위 결정 4).
SET @d_fks := (
    SELECT COUNT(*) FROM information_schema.referential_constraints
    WHERE constraint_schema = DATABASE()
      AND table_name IN ('kto_call_budget', 'place_cell', 'pet_place_detail'));

SELECT '[D] 사후 검증' AS section,
       @d_tables AS tables_3, @d_budget_cols AS budget_cols_3, @d_cell_cols AS cell_cols_8,
       @d_detail_cols AS detail_cols_15, @d_budget_pk AS budget_pk_2, @d_cell_pk AS cell_pk_2,
       @d_detail_pk AS detail_pk_1, @d_fks AS fks_0;

SET @stmt := IF(@d_tables = 3 AND @d_budget_cols = 3 AND @d_cell_cols = 8
                AND @d_detail_cols = 15 AND @d_budget_pk = 2 AND @d_cell_pk = 2
                AND @d_detail_pk = 1 AND @d_fks = 0,
    'SELECT ''[D] 통과 — 표 3 · PK (day,pool)/(lat_idx,lng_idx)/(content_id) · FK 0'' AS message',
    'CALL heattrip_migration_abort(''ABORT: 사후 검증 실패. 위 [D] 행의 숫자를 확인하라.'')');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

DROP PROCEDURE IF EXISTS heattrip_migration_abort;


-- ── E. 여기서 하지 않는 것 (판단 근거) ──────────────────────────────────────
--
-- 1. **상한(cap)을 표에 두지 않는다.** 프로퍼티다(app.kto.budget.*). 배포 후 일주일
--    관측해서 조정하기로 한 값이라 마이그레이션을 요구하면 너무 비싸다.
--
-- 2. **좌표에 SPATIAL INDEX 를 걸지 않는다.** 서빙 경로가 (lat_idx, lng_idx) PK 조회
--    하나뿐이라 공간 인덱스가 할 일이 없다. 걸면 hibernate-spatial 의존성이 따라오고
--    SchemaDdlDriftTest 가 geometry 컬럼을 못 맞춘다.
--
-- 3. **오래된 셀을 지우는 이벤트/배치를 만들지 않는다.** 만료가 없다는 것이 위 결정 2 이고,
--    지우는 장치를 두면 그 결정이 무의미해진다. 격자가 유한하므로(전국이 약 25만 셀,
--    실제로 방문되는 것은 그 일부) 무한히 자라지 않는다.
--
-- 4. **places 표를 건드리지 않는다.** 그건 tour 도메인의 것이고, 이 캐시는 KTO 응답을
--    그대로 접어 두는 자리다. 둘을 합치면 적재 배치와 온디맨드 캐시가 같은 행을 다툰다.
