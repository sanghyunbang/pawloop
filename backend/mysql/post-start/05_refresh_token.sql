-- ============================================================================
-- 05_refresh_token.sql
-- refresh 토큰 원장 테이블 — 이슈 #9
-- 대상: MySQL 8.x (운영/개발 공통)
--
-- ─────────────────────────────────────────────────────────────────────────────
-- 실행 순서
--
--   1. 이 스크립트를 실행한다 (앱 배포 **전**)
--   2. 그 다음 새 애플리케이션을 배포한다
--
-- 이 순서는 사실상 강제된다 — 테이블이 없으면 로그인이 실패한다.
-- 되돌릴 때는 반대로, 앱을 먼저 내린다.
--
-- 04 와 달리 백필이 없다. 새 테이블이라 옮겨 심을 기존 데이터가 없기 때문이다.
-- 그래도 04 의 관문 구조를 그대로 따른다 — 이유는 아래 §0 머리말에 있다.
--
-- ─────────────────────────────────────────────────────────────────────────────
-- ⚠️ 트랜잭션으로 감쌀 수 없다 — 실패해도 되돌아가지 않는다
--
-- MySQL 의 DDL(CREATE TABLE·ALTER TABLE …)은 **암묵적 커밋**을 일으킨다.
-- START TRANSACTION 으로 감싸도 소용이 없다. 그래서 앞뒤로 관문을 하나씩 둔다.
--   · §0 사전 점검 : 이미 있는 refresh_token 이 UNIQUE 를 못 걸 상태면 **아무것도 바꾸기 전에** 중단한다.
--   · §D 사후 검증 : 컬럼·UNIQUE·인덱스가 전부 걸렸는지 확인하고, 하나라도 빠지면 실패로 끝낸다.
-- 두 관문 모두 SIGNAL SQLSTATE '45000' 으로 mysql 클라이언트를 0 이 아닌 코드로 종료시킨다.
--
-- 사후 검증이 특히 필요한 이유는 04 와 똑같다: **Hibernate ddl-auto=validate 는 UNIQUE 제약을
-- 검사하지 않는다.** uk_refresh_token_token_hash 가 빠진 채 배포해도 앱은 멀쩡히 뜨고,
-- 재사용 감지의 전제("해시 1개 = 행 1개")가 아무도 모르게 무너진다.
--
-- 멱등: CREATE TABLE IF NOT EXISTS + 컬럼·인덱스별 information_schema 가드 + PREPARE/EXECUTE.
--       (01~04 가 쓰는 것과 같은 패턴이다.) 재실행해도 안전하다.
--
-- ─────────────────────────────────────────────────────────────────────────────
-- 되돌리기(DOWN) — 실행하지 말 것. 되돌려야 할 때만 손으로 골라 쓴다.
--
--   DROP TABLE refresh_token;
--
-- 되돌리면 모든 사용자의 refresh 토큰이 사라진다. 액세스 토큰은 만료(≤1시간)까지 살아 있고
-- 그 뒤로는 재로그인이다 — 이 기능을 도입하기 전과 같은 동작이다.
-- DOWN 전에 새 애플리케이션을 먼저 내려야 한다(엔티티가 테이블을 요구한다).
-- ============================================================================


-- ── 0. 사전 점검 ────────────────────────────────────────────────────────────
-- 여기서 걸리면 스키마는 한 글자도 바뀌지 않는다.
--
-- 새 테이블인데 왜 점검이 필요한가: dev 는 ddl-auto=update 라 **앱이 먼저 뜨면 Hibernate 가
-- 테이블을 이미 만들어 둔다.** 엔티티 초안이 다른 상태로 만든 테이블(UNIQUE 없음 등)이 남아
-- 있을 수 있고, 그 안에 중복 token_hash 가 들어 있으면 UNIQUE 를 걸 수 없다.
-- 그 경우에도 안전하게 실패해야 한다.

-- 중단 장치. SIGNAL 은 prepared statement 프로토콜이 지원하지 않아서(ERROR 1295)
-- 조건부로 던지려면 프로시저 한 겹이 필요하다. CALL 은 PREPARE 가능하다.
-- MESSAGE_TEXT 는 128자가 상한이다(넘기면 ERROR 1648).
-- 이 파일은 UTF-8 이고 중단 메시지가 한글이다. 세션 문자셋을 먼저 고정한다 —
-- 안 하면 클라이언트 기본값(윈도우 mysql 은 euckr)을 물려받아, 중단이 걸리는 순간
-- 이유는 안 보이고 ERROR 1366 (Incorrect string value) 만 남는다. 실측 2026-09-02, #169.
SET NAMES utf8mb4;

DROP PROCEDURE IF EXISTS heattrip_migration_abort;
CREATE PROCEDURE heattrip_migration_abort(IN msg VARCHAR(128))
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = msg;

-- 0-1. users 테이블이 있어야 한다.
--      FK 를 걸지는 않지만(엔티티가 Long userId 라 dev 의 update 가 FK 를 만들지 않는다 —
--      SQL 로만 걸면 dev/prod 스키마가 갈라지고 validate 는 FK 를 검사하지 않는다),
--      users 가 없는 DB 는 아직 앱이 뜬 적이 없다는 뜻이라 순서가 틀린 것이다.
SET @users_exists := (
    SELECT COUNT(*)
    FROM information_schema.tables
    WHERE table_schema = DATABASE()
      AND table_name = 'users'
);
SET @abort_msg := 'ABORT: users 테이블이 없다. 백엔드 앱을 먼저 띄운 뒤 다시 실행하라.';
SET @stmt := IF(@users_exists = 0,
    'CALL heattrip_migration_abort(@abort_msg)',
    'SELECT ''[0-1] users 테이블 확인 OK'' AS message');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- 0-2. refresh_token 이 이미 있는지(= 재실행이거나 Hibernate 가 먼저 만들었는지) 본다.
SET @rt_exists := (
    SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name = 'refresh_token');
SET @col_token_hash := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'refresh_token' AND column_name = 'token_hash');

-- 0-3. 이미 있는 테이블에 UNIQUE 를 못 걸 데이터가 있는지 모은다.
--      아직 없는 테이블·컬럼을 정적 SQL 로 참조하면 파싱 단계에서 죽으므로 PREPARE 로 조립한다.
DROP TEMPORARY TABLE IF EXISTS heattrip_refresh_token_precheck;
CREATE TEMPORARY TABLE heattrip_refresh_token_precheck (
    token_hash VARCHAR(255) NULL,
    row_count  BIGINT       NOT NULL
);

SET @stmt := IF(@rt_exists = 1 AND @col_token_hash = 1,
    CONCAT(
        'INSERT INTO heattrip_refresh_token_precheck (token_hash, row_count) ',
        'SELECT r.token_hash, COUNT(*) FROM refresh_token r ',
        'GROUP BY r.token_hash HAVING COUNT(*) > 1 OR r.token_hash IS NULL'),
    'SELECT ''[0-3] refresh_token 이 아직 없다 — 사전 점검 대상 0행'' AS message');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- 0-4. 걸린 것이 있으면 그대로 보여 준다. (없으면 빈 결과)
--      해시 원문을 그대로 찍어도 되는 이유: 이건 토큰이 아니라 토큰의 SHA-256 이다.
SELECT '[0-4] UNIQUE 를 막는 token_hash (있으면 아래 행을 지운 뒤 재실행)' AS section;
SELECT token_hash, row_count FROM heattrip_refresh_token_precheck ORDER BY row_count DESC;

-- 0-5. 하나라도 걸리면 여기서 끝낸다. 스키마는 아직 그대로다.
SET @bad_hashes := (SELECT COUNT(*) FROM heattrip_refresh_token_precheck);
SET @abort_msg := CONCAT(
    'ABORT: token_hash 중복/NULL ', @bad_hashes,
    '건 — 위 [0-4] 참고. 해당 행을 지우면 사용자는 재로그인만 하면 된다.');
SET @stmt := IF(@bad_hashes > 0,
    'CALL heattrip_migration_abort(@abort_msg)',
    'SELECT ''[0-5] 사전 점검 통과 — token_hash 중복 없음, NULL 없음'' AS message');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;


-- ── A. 테이블 생성 (멱등) ───────────────────────────────────────────────────
-- 컬럼 타입은 엔티티(user/entity/RefreshToken.java)가 만들 모양과 같아야 한다.
-- prod 의 ddl-auto=validate 가 타입 불일치로 부팅을 막기 때문이다.
--   · token_hash 는 CHAR(64) 가 아니라 VARCHAR(64) — Hibernate 는 String 을 VARCHAR 로 매핑한다.
--   · 시각은 DATETIME(6) — Hibernate 는 LocalDateTime 을 그렇게 만든다.
--   · users 로의 FK 는 걸지 않는다(§0-1 주석 참조). 탈퇴 정리는 UserService.deleteMe 가
--     사용자보다 먼저 refresh 토큰을 지우는 것으로 보장하고 테스트가 그 순서를 잠근다.
CREATE TABLE IF NOT EXISTS refresh_token (
    id         BIGINT      NOT NULL AUTO_INCREMENT,
    user_id    BIGINT      NOT NULL,
    token_hash VARCHAR(64) NOT NULL,
    expires_at DATETIME(6) NOT NULL,
    revoked_at DATETIME(6) NULL,
    created_at DATETIME(6) NOT NULL,
    PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;


-- ── B. 컬럼 보정 (멱등) ─────────────────────────────────────────────────────
-- Hibernate 가 다른 초안으로 먼저 만들어 둔 테이블에 빠진 컬럼이 있을 수 있다.
-- MySQL 에는 ADD COLUMN 용 IF NOT EXISTS 가 없어서 information_schema 가드를 쓴다.

SET @col_exists := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'refresh_token' AND column_name = 'user_id');
SET @stmt := IF(@col_exists = 0,
    'ALTER TABLE refresh_token ADD COLUMN user_id BIGINT NOT NULL',
    'SELECT ''[B] user_id 컬럼은 이미 있다.'' AS message');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @col_exists := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'refresh_token' AND column_name = 'token_hash');
SET @stmt := IF(@col_exists = 0,
    'ALTER TABLE refresh_token ADD COLUMN token_hash VARCHAR(64) NOT NULL',
    'SELECT ''[B] token_hash 컬럼은 이미 있다.'' AS message');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @col_exists := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'refresh_token' AND column_name = 'expires_at');
SET @stmt := IF(@col_exists = 0,
    'ALTER TABLE refresh_token ADD COLUMN expires_at DATETIME(6) NOT NULL',
    'SELECT ''[B] expires_at 컬럼은 이미 있다.'' AS message');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @col_exists := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'refresh_token' AND column_name = 'revoked_at');
SET @stmt := IF(@col_exists = 0,
    'ALTER TABLE refresh_token ADD COLUMN revoked_at DATETIME(6) NULL',
    'SELECT ''[B] revoked_at 컬럼은 이미 있다.'' AS message');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @col_exists := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'refresh_token' AND column_name = 'created_at');
SET @stmt := IF(@col_exists = 0,
    'ALTER TABLE refresh_token ADD COLUMN created_at DATETIME(6) NOT NULL',
    'SELECT ''[B] created_at 컬럼은 이미 있다.'' AS message');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;


-- ── C. 제약·인덱스 추가 (멱등) ──────────────────────────────────────────────
-- 이름은 엔티티의 @Table(uniqueConstraints/indexes) 와 같아야 한다.
-- 인덱스 3개는 접근 경로 3개와 1:1 이다 — 회전 조회 / 전 기기 폐기·탈퇴 삭제 / 만료 정리 범위 스캔.

SET @idx_exists := (
    SELECT COUNT(*) FROM information_schema.statistics
    WHERE table_schema = DATABASE()
      AND table_name = 'refresh_token'
      AND index_name = 'uk_refresh_token_token_hash');
SET @stmt := IF(@idx_exists = 0,
    'ALTER TABLE refresh_token ADD CONSTRAINT uk_refresh_token_token_hash UNIQUE (token_hash)',
    'SELECT ''[C] uk_refresh_token_token_hash 는 이미 있다.'' AS message');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @idx_exists := (
    SELECT COUNT(*) FROM information_schema.statistics
    WHERE table_schema = DATABASE()
      AND table_name = 'refresh_token'
      AND index_name = 'idx_refresh_token_user_id');
SET @stmt := IF(@idx_exists = 0,
    'CREATE INDEX idx_refresh_token_user_id ON refresh_token (user_id)',
    'SELECT ''[C] idx_refresh_token_user_id 는 이미 있다.'' AS message');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @idx_exists := (
    SELECT COUNT(*) FROM information_schema.statistics
    WHERE table_schema = DATABASE()
      AND table_name = 'refresh_token'
      AND index_name = 'idx_refresh_token_expires_at');
SET @stmt := IF(@idx_exists = 0,
    'CREATE INDEX idx_refresh_token_expires_at ON refresh_token (expires_at)',
    'SELECT ''[C] idx_refresh_token_expires_at 는 이미 있다.'' AS message');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;


-- ── D. 사후 검증 ────────────────────────────────────────────────────────────
-- '반쯤 적용된 채 성공처럼 끝나는' 상태를 막는 마지막 관문이다.
-- validate 는 UNIQUE 도 인덱스도 검사하지 않으므로, 여기서 확인하지 않으면 빠진 사실을
-- 앱도 CI 도 끝까지 알려주지 않는다.
SET @rt_columns := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'refresh_token'
      AND column_name IN ('id', 'user_id', 'token_hash', 'expires_at', 'revoked_at', 'created_at'));
SET @unique_cols := (
    SELECT COUNT(*) FROM information_schema.statistics
    WHERE table_schema = DATABASE()
      AND table_name = 'refresh_token'
      AND index_name = 'uk_refresh_token_token_hash'
      AND non_unique = 0);
SET @user_idx := (
    SELECT COUNT(*) FROM information_schema.statistics
    WHERE table_schema = DATABASE()
      AND table_name = 'refresh_token'
      AND index_name = 'idx_refresh_token_user_id');
SET @expires_idx := (
    SELECT COUNT(*) FROM information_schema.statistics
    WHERE table_schema = DATABASE()
      AND table_name = 'refresh_token'
      AND index_name = 'idx_refresh_token_expires_at');

SELECT '[D] 사후 검증' AS section,
       @rt_columns   AS columns_expect_6,
       @unique_cols  AS unique_index_columns_expect_1,
       @user_idx     AS user_id_index_expect_1,
       @expires_idx  AS expires_at_index_expect_1;

SET @abort_msg := CONCAT(
    'ABORT: 반쯤 적용됨 — 컬럼 ', @rt_columns, '/6, UNIQUE ', @unique_cols, '/1, ',
    'user_id 인덱스 ', @user_idx, '/1, expires_at 인덱스 ', @expires_idx, '/1. 위 [D] 참고.');
SET @stmt := IF(@rt_columns <> 6 OR @unique_cols <> 1 OR @user_idx < 1 OR @expires_idx < 1,
    'CALL heattrip_migration_abort(@abort_msg)',
    'SELECT ''[D] 사후 검증 통과 — 컬럼·UNIQUE·인덱스 모두 적용됨'' AS message');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- 참고용. 실패시키지 않는다.
SELECT '[D] 현재 refresh_token 행 수 (첫 실행이면 0이다)' AS section;
SELECT COUNT(*) AS rows_count FROM refresh_token;

DROP TEMPORARY TABLE IF EXISTS heattrip_refresh_token_precheck;
DROP PROCEDURE IF EXISTS heattrip_migration_abort;

SELECT '05_refresh_token.sql 완료' AS message;


-- ── E. 만료 행은 누가 지우는가 (판단 근거) ──────────────────────────────────
-- 이 스크립트는 만들기만 한다. 만료된 행 정리는 애플리케이션의 야간 스케줄 잡이 한다
--   (user/service/RefreshTokenPurgeScheduler — 기본 04:30 Asia/Seoul,
--    auth.refresh-token.purge-cron 으로 옮기거나 끌 수 있다).
--
-- 조회 시 lazy 삭제를 고르지 않은 이유: 그 방식은 '다시 오지 않는 사용자의 행'을 영원히
-- 못 지운다 — 정확히 쌓이는 것이 그 행들이다.
--
-- 폐기된 행(revoked_at IS NOT NULL)을 즉시 지우지 않는 이유: 지우면 '이미 회전된 RT 가
-- 다시 왔다'를 '없는 토큰'과 구별할 수 없어 재사용 감지가 무력해진다. 만료 뒤에 지운다.
