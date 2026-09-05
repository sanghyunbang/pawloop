-- ============================================================================
-- 21_users_drop_consent_columns.sql
-- users 의 옛 동의 컬럼 아홉을 지운다 — 이슈 #190 후속 (ADR-0020 결정)
-- 대상: MySQL 8.x (운영/개발 공통)
--
-- ─────────────────────────────────────────────────────────────────────────────
-- 무엇을 지우나
--
--   agree_tos · agree_privacy · agree_marketing          (동의했나)
--   tos_version · privacy_version · marketing_version    (어느 버전에)
--   tos_agreed_at · privacy_agreed_at · marketing_agreed_at (언제)
--
-- 이메일 가입이 적던 칸이다. #190 부터 같은 내용이 user_consent 에 이력으로 남고(위치
-- 동의까지 포함), 재동의도 그 표를 보고 정한다. 두 군데에 적으면 어느 쪽이 참인지가
-- 사람마다 달라진다 — 한 곳만 남긴다.
--
-- ─────────────────────────────────────────────────────────────────────────────
-- 지우기 전에 옮긴다
--
-- 이 아홉 칸의 값은 서버가 실제로 받은 동의다(이메일 가입 화면의 체크). 그냥 지우면 그
-- 사람들의 동의 증빙이 사라진다. 그래서 먼저 user_consent 로 옮긴다:
--
--   agree_tos = 1       → TERMS     행 (version = tos_version,       created_at = tos_agreed_at)
--   agree_privacy = 1   → PRIVACY   행 (version = privacy_version,   created_at = privacy_agreed_at)
--   agree_marketing = 1 → MARKETING 행 (version = marketing_version, created_at = marketing_agreed_at)
--
-- 0 이나 NULL 은 안 옮긴다 — "동의 안 함" 은 user_consent 에서 "행 없음" 과 같다.
-- 버전이 비어 있으면 'v1.0'(옛 코드의 기본값), 시각이 비어 있으면 가입 시각(created_at),
-- 그것도 없으면 지금(UTC). 이미 같은 사람·같은 문서의 행이 있으면 안 옮긴다 — 두 번
-- 돌려도 두 행이 되지 않는다.
--
-- ─────────────────────────────────────────────────────────────────────────────
-- 실행 순서
--
--   1. 새 애플리케이션을 먼저 배포한다 (User 엔티티에서 아홉 필드가 사라진 것)
--   2. 그 다음 이 스크립트를 실행한다
--
-- 20 과 같은 "반대 순서" 다 — 지우는 스크립트는 코드가 먼저다. 옛 코드가 도는데 컬럼을
-- 지우면 그 코드가 validate 에서 죽는다. 새 코드는 컬럼이 있든 없든 상관하지 않는다.
--
-- 19(user_consent) 가 먼저 돌아 있어야 한다. 없으면 옮길 곳이 없으므로 시작하지 않는다.
--
-- 트랜잭션으로 감쌀 수 없다 — MySQL 의 DDL 은 암묵적 커밋을 일으킨다.
--    그래서 앞뒤로 관문을 둔다: §0 사전 점검 · §D 사후 검증. 옮기기(§A)는 DML 이라
--    중간에 죽어도 다시 돌리면 이어서 한다(같은 행은 안 옮기므로).
--
-- 멱등: 컬럼이 이미 없으면 "이미 없음" 을 찍고 지나간다. 두 번 돌려도 같은 상태.
--
-- ─────────────────────────────────────────────────────────────────────────────
-- 되돌리기(DOWN) — 컬럼은 되살릴 수 있어도 값은 못 되살린다.
--
--   ALTER TABLE users
--     ADD COLUMN agree_tos bit(1) NULL, ADD COLUMN agree_privacy bit(1) NULL,
--     ADD COLUMN agree_marketing bit(1) NULL,
--     ADD COLUMN tos_version varchar(255) NULL, ADD COLUMN privacy_version varchar(255) NULL,
--     ADD COLUMN marketing_version varchar(255) NULL,
--     ADD COLUMN tos_agreed_at datetime(6) NULL, ADD COLUMN privacy_agreed_at datetime(6) NULL,
--     ADD COLUMN marketing_agreed_at datetime(6) NULL;
--
-- 값은 user_consent 에 있다(위 §A 로 옮겼다). 되돌려야 한다면 거기서 다시 채운다.
-- ============================================================================


-- ── 0. 사전 점검 ────────────────────────────────────────────────────────────
SET NAMES utf8mb4;

DROP PROCEDURE IF EXISTS heattrip_migration_abort;
CREATE PROCEDURE heattrip_migration_abort(IN msg VARCHAR(128))
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = msg;

SET @has_users := (
    SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name = 'users');
SET @has_consent := (
    SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name = 'user_consent');

-- 아홉 컬럼 중 몇 개가 남아 있나. 9 면 처음, 0 이면 이미 끝난 것.
SET @cols_left := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'users'
      AND column_name IN ('agree_tos', 'agree_privacy', 'agree_marketing',
                          'tos_version', 'privacy_version', 'marketing_version',
                          'tos_agreed_at', 'privacy_agreed_at', 'marketing_agreed_at'));

SET @users_before := 0;
SET @stmt := IF(@has_users = 1, 'SELECT COUNT(*) INTO @users_before FROM users', 'DO 0');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @consent_before := 0;
SET @stmt := IF(@has_consent = 1, 'SELECT COUNT(*) INTO @consent_before FROM user_consent', 'DO 0');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SELECT '[0] 사전 점검' AS section,
       @has_users AS users_1, @has_consent AS user_consent_1,
       @cols_left AS old_columns_left, @users_before AS users_rows, @consent_before AS consent_rows;

SET @stmt := IF(@has_users = 1 AND @has_consent = 1,
    'SELECT ''[0] 표 확인'' AS message',
    'CALL heattrip_migration_abort(''ABORT: users 또는 user_consent 가 없다. 19_user_consent.sql 을 먼저 돌려라.'')');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- 아홉이거나 0 이어야 한다. 그 사이면 누가 손으로 일부만 지운 것이다 — 옮길 값이 어디까지
-- 남았는지 알 수 없으니 사람이 봐야 한다.
SET @stmt := IF(@cols_left = 9 OR @cols_left = 0,
    'SELECT ''[0] 컬럼 상태 확인'' AS message',
    'CALL heattrip_migration_abort(''ABORT: 옛 동의 컬럼이 일부만 남아 있다. 어느 값이 남았는지 사람이 확인하라.'')');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;


-- ── A. user_consent 로 옮긴다 (컬럼이 아직 있을 때만) ───────────────────────
SET @stmt := IF(@cols_left = 9,
    'INSERT INTO user_consent (user_id, kind, version, agreed, created_at)
     SELECT u.id, ''TERMS'', COALESCE(NULLIF(u.tos_version, ''''), ''v1.0''), 1,
            COALESCE(u.tos_agreed_at, u.created_at, UTC_TIMESTAMP(6))
     FROM users u
     WHERE u.agree_tos = 1
       AND NOT EXISTS (SELECT 1 FROM user_consent c WHERE c.user_id = u.id AND c.kind = ''TERMS'')',
    'SELECT ''[A-1] TERMS 옮길 컬럼 없음 — 이미 지워졌다'' AS message');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @stmt := IF(@cols_left = 9,
    'INSERT INTO user_consent (user_id, kind, version, agreed, created_at)
     SELECT u.id, ''PRIVACY'', COALESCE(NULLIF(u.privacy_version, ''''), ''v1.0''), 1,
            COALESCE(u.privacy_agreed_at, u.created_at, UTC_TIMESTAMP(6))
     FROM users u
     WHERE u.agree_privacy = 1
       AND NOT EXISTS (SELECT 1 FROM user_consent c WHERE c.user_id = u.id AND c.kind = ''PRIVACY'')',
    'SELECT ''[A-2] PRIVACY 옮길 컬럼 없음'' AS message');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @stmt := IF(@cols_left = 9,
    'INSERT INTO user_consent (user_id, kind, version, agreed, created_at)
     SELECT u.id, ''MARKETING'', COALESCE(NULLIF(u.marketing_version, ''''), ''v1.0''), 1,
            COALESCE(u.marketing_agreed_at, u.created_at, UTC_TIMESTAMP(6))
     FROM users u
     WHERE u.agree_marketing = 1
       AND NOT EXISTS (SELECT 1 FROM user_consent c WHERE c.user_id = u.id AND c.kind = ''MARKETING'')',
    'SELECT ''[A-3] MARKETING 옮길 컬럼 없음'' AS message');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SELECT '[A] 옮긴 뒤' AS section,
       (SELECT COUNT(*) FROM user_consent) AS consent_rows,
       (SELECT COUNT(*) FROM user_consent) - @consent_before AS moved_rows;


-- ── B. 아홉 컬럼을 지운다 ───────────────────────────────────────────────────
SET @stmt := IF(@cols_left = 9,
    'ALTER TABLE users
       DROP COLUMN agree_tos, DROP COLUMN agree_privacy, DROP COLUMN agree_marketing,
       DROP COLUMN tos_version, DROP COLUMN privacy_version, DROP COLUMN marketing_version,
       DROP COLUMN tos_agreed_at, DROP COLUMN privacy_agreed_at, DROP COLUMN marketing_agreed_at',
    'SELECT ''[B] 컬럼 이미 없음'' AS message');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;


-- ── D. 사후 검증 ────────────────────────────────────────────────────────────
SET @d_cols := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'users'
      AND column_name IN ('agree_tos', 'agree_privacy', 'agree_marketing',
                          'tos_version', 'privacy_version', 'marketing_version',
                          'tos_agreed_at', 'privacy_agreed_at', 'marketing_agreed_at'));

-- users 행 수는 그대로여야 한다 — 컬럼을 지우는 스크립트가 행을 건드릴 이유가 없다.
SET @d_users := (SELECT COUNT(*) FROM users);

-- 옮긴 뒤의 user_consent 는 줄어들면 안 된다.
SET @d_consent := (SELECT COUNT(*) FROM user_consent);

SELECT '[D] 사후 검증' AS section,
       @d_cols AS old_columns_0, @d_users AS users_rows_same, @d_consent AS consent_rows_not_less;

SET @stmt := IF(@d_cols = 0 AND @d_users = @users_before AND @d_consent >= @consent_before,
    'SELECT ''[D] 통과 — 옛 컬럼 0 · users 행 수 그대로 · user_consent 안 줄어듦'' AS message',
    'CALL heattrip_migration_abort(''ABORT: 사후 검증 실패. 위 [D] 행의 숫자를 확인하라.'')');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

DROP PROCEDURE IF EXISTS heattrip_migration_abort;
