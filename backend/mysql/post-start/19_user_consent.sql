-- ============================================================================
-- 19_user_consent.sql
-- 약관 동의의 이력 — 이슈 #190 · ADR-0020
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
--
-- 빈 DB 를 새로 세우는 경우에는 이 파일이 필요 없다. mysql/init/01_schema.sql 이
-- 이 표를 이미 담고 있다(#58).
--
-- ─────────────────────────────────────────────────────────────────────────────
-- 이 표에서 되돌리기 비싼 결정 셋
--
-- 1. **덧붙이기만 한다.** 동의도 철회도 새 행이다. "지금 상태" 는 계정·문서별 마지막
--    행이다. users 의 agree_* 아홉 컬럼처럼 덮어쓰는 칸이면 철회한 순간 "언제까지
--    동의 상태였는지" 가 사라진다 — 위치정보법 제24조는 철회 **전**에 제공된 것은 그대로라
--    하므로 그 경계 시각이 남아야 한다.
--
-- 2. **users 로 FK 를 안 건다.** report 와 같은 판단이다. 탈퇴가 users 행을 물리 삭제하는데
--    CASCADE 면 "동의했었다" 는 기록이 탈퇴와 함께 사라지고, RESTRICT 면 동의한 사람은
--    영구히 탈퇴 불가가 된다. 값(user_id)으로만 가리킨다.
--
-- 3. **서버는 문서 버전을 모른다.** version 은 앱이 보낸 문자열을 그대로 적는다. 문서는
--    앱이 들고 있고(app/assets/terms/), 재동의가 필요한지도 앱이 정한다. 서버가 "최신
--    버전" 을 알게 하면 앱의 문서와 조용히 갈린다.
--
-- 트랜잭션으로 감쌀 수 없다 — MySQL 의 DDL 은 암묵적 커밋을 일으킨다.
--    그래서 앞뒤로 관문을 둔다: §0 사전 점검 · §D 사후 검증.
--
-- 멱등: CREATE TABLE IF NOT EXISTS + information_schema 가드 + PREPARE/EXECUTE.
--
-- ─────────────────────────────────────────────────────────────────────────────
-- 되돌리기(DOWN) — 실행하지 말 것.
--
--   DROP TABLE user_consent;
--
-- 되돌리면 **동의 기록이 사라진다.** 이 표는 캐시가 아니라 증빙이다. 되돌려야 한다면
-- 먼저 덤프를 뜬다.
-- ============================================================================


-- ── 0. 사전 점검 ────────────────────────────────────────────────────────────
SET NAMES utf8mb4;

DROP PROCEDURE IF EXISTS heattrip_migration_abort;
CREATE PROCEDURE heattrip_migration_abort(IN msg VARCHAR(128))
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = msg;

SET @has_table := (
    SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name = 'user_consent');

SELECT '[0-1] 기존 표 확인' AS section, @has_table AS user_consent;

-- 0-2. 표가 이미 있는데 users 로 FK 가 걸려 있으면 멈춘다 — 위 결정 2 와 반대 모양이다.
--      dev 는 ddl-auto=update 라 엔티티 초안이 다른 상태로 만든 표가 있을 수 있다.
SET @fk_count := (
    SELECT COUNT(*) FROM information_schema.referential_constraints
    WHERE constraint_schema = DATABASE() AND table_name = 'user_consent');
SET @stmt := IF(@has_table = 1 AND @fk_count > 0,
    'CALL heattrip_migration_abort(''ABORT: user_consent 에 FK 가 있다. 탈퇴가 동의 기록을 지우는 모양이다. 손으로 확인하라.'')',
    'SELECT ''[0-2] FK 사전 점검 통과'' AS message');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;


-- ── A. 표 생성 (멱등) ───────────────────────────────────────────────────────
-- created_at 은 **UTC 벽시계**다(#248 규약). 서버가 찍는 순간이라 사람의 존이 없다.
-- kind 의 CHECK 는 서비스 상수(ConsentKind)와 같은 넷이다 — DB 가 비어 있으면 그 상수를
-- 안 거치는 경로가 무방비다.
CREATE TABLE IF NOT EXISTS user_consent (
    id         BIGINT       NOT NULL AUTO_INCREMENT,
    user_id    BIGINT       NOT NULL,
    kind       VARCHAR(16)  NOT NULL,
    version    VARCHAR(16)  NOT NULL,
    agreed     BIT(1)       NOT NULL,
    created_at DATETIME(6)  NOT NULL,
    PRIMARY KEY (id),
    CONSTRAINT chk_user_consent_kind CHECK (kind IN ('TERMS','PRIVACY','LOCATION','MARKETING'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;


-- ── B. 인덱스·제약 보정 (멱등) ──────────────────────────────────────────────
-- 서빙 경로가 "이 계정의 행 전부, 최신이 앞" 이라 (user_id, id) 다.
SET @has_idx := (
    SELECT COUNT(DISTINCT index_name) FROM information_schema.statistics
    WHERE table_schema = DATABASE() AND table_name = 'user_consent'
      AND index_name = 'idx_user_consent_user');
SET @stmt := IF(@has_idx = 0,
    'CREATE INDEX idx_user_consent_user ON user_consent (user_id, id)',
    'SELECT ''[B-1] idx_user_consent_user 이미 있음'' AS message');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- Hibernate 가 먼저 만든 표에는 CHECK 가 없을 수 있다.
SET @has_check := (
    SELECT COUNT(*) FROM information_schema.table_constraints
    WHERE constraint_schema = DATABASE() AND table_name = 'user_consent'
      AND constraint_name = 'chk_user_consent_kind');
SET @stmt := IF(@has_check = 0,
    'ALTER TABLE user_consent ADD CONSTRAINT chk_user_consent_kind CHECK (kind IN (''TERMS'',''PRIVACY'',''LOCATION'',''MARKETING''))',
    'SELECT ''[B-2] chk_user_consent_kind 이미 있음'' AS message');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;


-- ── D. 사후 검증 ────────────────────────────────────────────────────────────
SET @d_table := (
    SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name = 'user_consent');

-- 컬럼은 **이름으로** 센다 (#267).
SET @d_cols := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'user_consent'
      AND column_name IN ('id', 'user_id', 'kind', 'version', 'agreed', 'created_at'));

SET @d_idx := (
    SELECT COUNT(DISTINCT index_name) FROM information_schema.statistics
    WHERE table_schema = DATABASE() AND table_name = 'user_consent'
      AND index_name = 'idx_user_consent_user');

SET @d_check := (
    SELECT COUNT(*) FROM information_schema.table_constraints
    WHERE constraint_schema = DATABASE() AND table_name = 'user_consent'
      AND constraint_name = 'chk_user_consent_kind');

-- FK 는 **0이어야 한다** (위 결정 2).
SET @d_fks := (
    SELECT COUNT(*) FROM information_schema.referential_constraints
    WHERE constraint_schema = DATABASE() AND table_name = 'user_consent');

SELECT '[D] 사후 검증' AS section,
       @d_table AS table_1, @d_cols AS cols_6, @d_idx AS idx_1, @d_check AS check_1, @d_fks AS fks_0;

SET @stmt := IF(@d_table = 1 AND @d_cols = 6 AND @d_idx = 1 AND @d_check = 1 AND @d_fks = 0,
    'SELECT ''[D] 통과 — 표 1 · 컬럼 6 · 인덱스 1 · CHECK 1 · FK 0'' AS message',
    'CALL heattrip_migration_abort(''ABORT: 사후 검증 실패. 위 [D] 행의 숫자를 확인하라.'')');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

DROP PROCEDURE IF EXISTS heattrip_migration_abort;


-- ── E. 여기서 하지 않는 것 ──────────────────────────────────────────────────
--
-- 1. **users 의 agree_* 아홉 컬럼을 안 지운다.** 이메일 가입 경로가 아직 채운다.
--    지울지는 사람이 정한다(ADR-0020).
--
-- 2. **기존 사용자의 동의를 백필하지 않는다.** 기기에만 있던 동의는 서버가 모르고,
--    모르는 것을 "동의했다" 로 적으면 그게 바로 이 표가 막으려는 거짓이다. 그 사람들은
--    다음 로그인에 한 번 더 동의 화면을 본다 — 배포된 클라이언트가 아직 없어 실질 대상은 0이다.
--
-- 3. **UNIQUE 가 없다.** 같은 문서에 같은 버전으로 두 번 동의해도 두 행이다 — 이력이다.
