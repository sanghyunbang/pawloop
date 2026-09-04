-- ============================================================================
-- 18_place_catalog.sql
-- 전국 반려동반 장소 한 벌 — 이슈 #273 (#235 A4)
-- 대상: MySQL 8.x (운영/개발 공통)
--
-- ─────────────────────────────────────────────────────────────────────────────
-- 실행 순서
--
--   1. 이 스크립트를 실행한다 (앱 배포 **전**)
--   2. 그 다음 새 애플리케이션을 배포한다
--
-- 이 순서는 사실상 강제된다 — prod 는 ddl-auto=validate 라 엔티티가 요구하는 표가
-- 없으면 **부팅 자체가 실패한다.** 되돌릴 때는 반대로, 앱을 먼저 내린다.
--
-- 앞선 스크립트에 의존하지 않는다. FK 가 하나도 없다.
-- 다만 **10 이 먼저인 편이 낫다** — 이 표를 채우는 코드가 pet_place_detail 에 허용목록을
-- 함께 적기 때문이다. 없어도 이 스크립트는 성공하지만, 앱이 카탈로그를 받는 순간 실패한다.
--
-- 빈 DB 를 새로 세우는 경우에는 이 파일이 필요 없다. mysql/init/01_schema.sql 이
-- 이 표를 이미 담고 있다(#58).
--
-- ─────────────────────────────────────────────────────────────────────────────
-- 이 표에서 되돌리기 비싼 결정 넷
--
-- 1. **행이 하나다.** place_cell 은 좌표를 격자로 접은 키를 갖고, 이 표에는 키가 없다.
--    전국이 한 벌이고 그래서 **요청에 좌표도 지역도 실려 오지 않는다** — A안 빌드(완전
--    온디바이스)가 쓰는 길이다. 그 사실을 DB 가 지키도록 CHECK (id = 1) 를 건다.
--    관례로만 두면 인스턴스 둘이 동시에 갱신할 때 행이 둘이 되고, 그때 어느 것이 답인지
--    코드에 안 적혀 있다.
--
-- 2. **payload 가 응답 본문 그대로다.** 꺼내서 객체로 만들었다가 다시 직렬화하지 않는다.
--    한 벌이 2.83MB 라(실측 2026-09-04, 9,684곳) 요청마다 두 번 훑게 되기 때문이다.
--    저장할 때 한 번 만들고, 그 뒤로는 바이트를 옮기기만 한다.
--
-- 3. **etag 가 payload 의 해시다.** fetched_at 을 ETag 로 쓰면 내용이 같아도 갱신할 때마다
--    값이 바뀌어, 앱이 2.83MB 를 다시 받는다. 해시면 KTO 데이터가 안 바뀐 날은 304 로
--    끝난다. 행에 두는 이유는 재기동해도 같고 인스턴스가 여럿이어도 같아야 해서다.
--
-- 4. **만료(hard TTL)가 없다.** place_cell 과 같다. fetched_at 은 "갱신을 시도해도
--    되는가" 만 정하고, 예산이 없으면 오래된 한 벌을 그대로 계속 준다. 만료를 두면
--    KTO 가 며칠 아플 때 지도가 영구히 빈 화면이 된다.
--
-- 트랜잭션으로 감쌀 수 없다 — MySQL 의 DDL 은 암묵적 커밋을 일으킨다.
--    그래서 앞뒤로 관문을 둔다: §0 사전 점검 · §D 사후 검증.
--    두 관문 모두 SIGNAL SQLSTATE '45000' 으로 mysql 클라이언트를 0 이 아닌 코드로 끝낸다.
--
-- 멱등: CREATE TABLE IF NOT EXISTS + information_schema 가드 + PREPARE/EXECUTE.
--       재실행해도 안전하다.
--
-- ─────────────────────────────────────────────────────────────────────────────
-- 되돌리기(DOWN) — 실행하지 말 것. 되돌려야 할 때만 손으로 골라 쓴다.
--
--   DROP TABLE place_catalog;
--
-- 되돌려도 데이터 손실이 아니다 — KTO 에서 다시 받을 수 있다. 다만 다시 채우는 데
-- 10콜이 들고, 그동안 A안 빌드의 지도가 빈다. 앱을 먼저 내린다.
-- ============================================================================


-- ── 0. 사전 점검 ────────────────────────────────────────────────────────────
-- 여기서 걸리면 스키마는 한 글자도 바뀌지 않는다.

-- 세션 문자셋을 먼저 고정한다 — 안 하면 클라이언트 기본값(윈도우 mysql 은 euckr)을
-- 물려받아, 중단이 걸리는 순간 이유는 안 보이고 ERROR 1366 만 남는다(실측 2026-09-02, #169).
SET NAMES utf8mb4;

DROP PROCEDURE IF EXISTS heattrip_migration_abort;
CREATE PROCEDURE heattrip_migration_abort(IN msg VARCHAR(128))
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = msg;

-- 0-1. 표가 이미 있는지 본다(= 재실행이거나 Hibernate 가 먼저 만들었는지).
--      dev 는 ddl-auto=update 라 **앱이 먼저 뜨면 Hibernate 가 표를 이미 만들어 둔다.**
SET @has_catalog := (
    SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name = 'place_catalog');

SELECT '[0-1] 기존 표 확인' AS section, @has_catalog AS place_catalog;

-- 0-2. 표가 이미 있는데 행이 둘 이상이면 멈춘다.
--      CHECK (id = 1) 가 CREATE 에 함께 있으므로 새로 만든 표에는 문제가 없지만, 이미
--      있는 표에는 그 제약이 없을 수 있다. 행이 여럿인 상태로 통과시키면 어느 것이
--      답인지 아무 데도 안 적혀 있고, 앱은 id = 1 만 읽으므로 나머지가 조용히 유령이 된다.
SET @row_count := 0;
SET @stmt := IF(@has_catalog = 1,
    'SELECT COUNT(*) INTO @row_count FROM place_catalog',
    'SELECT ''[0-2] 표가 없어 행 수를 세지 않는다'' AS message');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @stmt := IF(@row_count > 1,
    'CALL heattrip_migration_abort(''ABORT: place_catalog 에 행이 둘 이상이다. 어느 것이 정본인지 사람이 정하라.'')',
    'SELECT ''[0-2] 행 수 사전 점검 통과'' AS message');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- 0-3. 표가 이미 있는데 PK 가 한 컬럼이 아니면 멈춘다.
--      엔티티 초안이 다른 상태로 만든 표라는 뜻이고, 그 위에 CHECK 를 걸어도 뜻이 맞지 않는다.
SET @pk_cols := (
    SELECT COUNT(*) FROM information_schema.statistics
    WHERE table_schema = DATABASE() AND table_name = 'place_catalog'
      AND index_name = 'PRIMARY');
SET @stmt := IF(@has_catalog = 1 AND @pk_cols <> 1,
    'CALL heattrip_migration_abort(''ABORT: place_catalog 의 PK 가 한 컬럼(id)이 아니다. 손으로 확인하라.'')',
    'SELECT ''[0-3] PK 사전 점검 통과'' AS message');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;


-- ── A. 표 생성 (멱등) ───────────────────────────────────────────────────────
--
-- id 는 항상 1 이다. CHECK 가 그것을 지킨다 — MySQL 8.0.16 부터 CHECK 가 실제로 강제된다.
-- 그 아래 버전에서는 파싱만 되고 무시되므로, 사후 검증(§D)이 제약의 **존재**를 확인한다.
--
-- payload 는 우리 계약(Place)의 모양으로 정규화한 JSON 배열이다 — KTO 응답 원문이 아니다.
-- LONGTEXT 인 이유: TEXT 는 64KB 라 한 벌(2.83MB)이 안 들어가고, MEDIUMTEXT(16MB)로는
-- 지금 들어가지만 데이터가 여섯 배로 늘면 조용히 잘린다. 잘린 JSON 은 파싱 오류가 아니라
-- **읽히는 순간까지 정상으로 보인다.**
--
-- etag 는 SHA-256 앞 32자(hex)다. 64 로 잡아 둔 것은 전체 해시로 바꿀 여지를 남긴 것이다.
CREATE TABLE IF NOT EXISTS place_catalog (
    id          INT          NOT NULL,
    payload     LONGTEXT     NOT NULL,
    etag        VARCHAR(64)  NOT NULL,
    item_count  INT          NOT NULL,
    total_count INT          NOT NULL DEFAULT 0,
    fetched_at  DATETIME(6)  NOT NULL,
    failed_at   DATETIME(6)  NULL,
    fail_streak INT          NOT NULL DEFAULT 0,
    PRIMARY KEY (id),
    CONSTRAINT chk_place_catalog_singleton CHECK (id = 1)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;


-- ── B. 이미 있던 표 보정 (멱등) ─────────────────────────────────────────────
-- Hibernate 가 먼저 만든 표에는 CHECK 가 없을 수 있다. ddl-auto=update 는 이미 있는
-- 표에 제약을 나중에 붙여 주지 않는다. 여기서 붙인다.

SET @has_check := (
    SELECT COUNT(*) FROM information_schema.table_constraints
    WHERE constraint_schema = DATABASE() AND table_name = 'place_catalog'
      AND constraint_name = 'chk_place_catalog_singleton');
SET @stmt := IF(@has_check = 0,
    'ALTER TABLE place_catalog ADD CONSTRAINT chk_place_catalog_singleton CHECK (id = 1)',
    'SELECT ''[B-1] chk_place_catalog_singleton 이미 있음'' AS message');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;


-- ── D. 사후 검증 ────────────────────────────────────────────────────────────
-- '반쯤 적용된 채 성공처럼 끝나는' 상태를 막는 마지막 관문이다.
-- ddl-auto=validate 는 PK 도 CHECK 도 검사하지 않으므로, 여기서 확인하지 않으면
-- 빠진 사실을 앱도 CI 도 끝까지 알려주지 않는다.

SET @d_table := (
    SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name = 'place_catalog');

-- 컬럼은 **이름으로** 센다. COUNT(*) 만 세면 남는 옛 컬럼이 수를 맞춰 통과시킨다.
SET @d_cols := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'place_catalog'
      AND column_name IN ('id', 'payload', 'etag', 'item_count', 'total_count',
                          'fetched_at', 'failed_at', 'fail_streak'));

-- PK 는 **컬럼 수로** 센다 — 이름만 보면 잘못된 모양을 통과시킨다.
SET @d_pk := (
    SELECT COUNT(*) FROM information_schema.statistics
    WHERE table_schema = DATABASE() AND table_name = 'place_catalog' AND index_name = 'PRIMARY');

SET @d_check := (
    SELECT COUNT(*) FROM information_schema.table_constraints
    WHERE constraint_schema = DATABASE() AND table_name = 'place_catalog'
      AND constraint_name = 'chk_place_catalog_singleton');

-- FK 는 **0이어야 한다**. 담긴 content_id 는 KTO 가 준 불투명 문자열이고 우리 표의 키가 아니다.
SET @d_fks := (
    SELECT COUNT(*) FROM information_schema.referential_constraints
    WHERE constraint_schema = DATABASE() AND table_name = 'place_catalog');

-- payload 가 LONGTEXT 인지 본다. MEDIUMTEXT 로 만들어져 있으면 데이터가 커지는 날
-- **조용히 잘린다** — 그 순간 지도에서 장소가 사라지고, 오류는 아무 데도 안 남는다.
SET @d_payload_type := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'place_catalog'
      AND column_name = 'payload' AND data_type = 'longtext');

SELECT '[D] 사후 검증' AS section,
       @d_table AS table_1, @d_cols AS cols_8, @d_pk AS pk_1,
       @d_check AS check_1, @d_fks AS fks_0, @d_payload_type AS payload_longtext_1;

SET @stmt := IF(@d_table = 1 AND @d_cols = 8 AND @d_pk = 1
                AND @d_check = 1 AND @d_fks = 0 AND @d_payload_type = 1,
    'SELECT ''[D] 통과 — 표 1 · PK (id) · CHECK (id = 1) · FK 0 · payload LONGTEXT'' AS message',
    'CALL heattrip_migration_abort(''ABORT: 사후 검증 실패. 위 [D] 행의 숫자를 확인하라.'')');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

DROP PROCEDURE IF EXISTS heattrip_migration_abort;


-- ── E. 여기서 하지 않는 것 (판단 근거) ──────────────────────────────────────
--
-- 1. **place_cell 을 지우지 않는다.** 좌표를 보내는 빌드가 여전히 그 길을 쓴다.
--    두 길은 같은 KTO 데이터를 다르게 캐시할 뿐이고, 어느 쪽을 쓸지는 앱의 빌드 플래그
--    (LocationUploadPolicy)가 정한다.
--
-- 2. **payload 에 JSON 타입을 안 쓴다.** MySQL 의 JSON 은 저장할 때 파싱·정규화하고
--    꺼낼 때 다시 직렬화한다. 이 값은 **응답 본문 그대로** 나갈 문자열이라 그 왕복이
--    순수한 낭비다. DB 안에서 이 JSON 을 질의할 계획도 없다.
--
-- 3. **오래된 한 벌을 지우는 이벤트/배치를 만들지 않는다.** 행이 하나라 자라지 않는다.
--
-- 4. **item_count 에 최소값 CHECK 를 안 건다.** "전국이 0곳" 을 막는 것은
--    CatalogSnapshotStore.store 이고, 그것이 유일한 쓰기 경로다. DB 에도 걸면 실패
--    자리표시(payload = '[]')를 못 쓰게 되는데, 그 자리표시가 백오프의 근거다.
