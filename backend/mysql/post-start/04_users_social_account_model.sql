-- ============================================================================
-- 04_users_social_account_model.sql
-- users 소셜 계정 모델 마이그레이션 — 이슈 #7
-- 대상: MySQL 8.x (운영/개발 공통)
--
-- ─────────────────────────────────────────────────────────────────────────────
-- 실행 위치를 왜 여기로 두었나
--
-- 이 저장소에는 Flyway·Liquibase 가 없고 스키마는 Hibernate ddl-auto 로만 움직인다.
--   dev  : ddl-auto=update   → 새 컬럼·제약을 Hibernate 가 알아서 만든다. 단 **데이터 백필은 안 한다.**
--   prod : ddl-auto=validate → Hibernate 는 스키마를 만들지 않고 '엔티티와 다르면 부팅 실패' 만 한다.
--
-- 그래서 '앱이 뜬 뒤 사람이 실행하는 SQL' 은 전부 mysql/post-start 에 번호 순으로 모여 있고,
-- 실행 커맨드는 backend/mysql/README.md 에 있다. 이 파일도 같은 자리·같은 방식이다.
-- (문서 디렉터리 backend/docs/database 에는 실행 대상이 아닌 설명만 둔다.)
--
--   1. 백엔드 앱을 띄워 users 테이블이 만들어지게 한다 (dev) / 기존 운영 DB 를 그대로 쓴다 (prod)
--   2. 이 스크립트를 실행한다
--   3. 그 다음 새 애플리케이션을 배포한다
--
-- ─────────────────────────────────────────────────────────────────────────────
-- ⚠️ 트랜잭션으로 감쌀 수 없다 — 실패해도 되돌아가지 않는다
--
-- MySQL 의 DDL(ALTER TABLE …)은 **암묵적 커밋(implicit commit)** 을 일으킨다.
-- START TRANSACTION 으로 감싸도 ALTER 를 만나는 순간 앞의 작업이 커밋되고 새 트랜잭션이 열린다.
-- 즉 A 의 ADD COLUMN 이 끝난 뒤 C 의 ADD CONSTRAINT 가 실패하면 **A·B 는 그대로 남는다.**
-- 그리고 그 반쯤 적용된 상태를 Hibernate ddl-auto=validate 는 통과시킨다
-- (validate 는 테이블·컬럼만 보고 UNIQUE 제약은 검사하지 않는다).
-- → 제약 없이 운영이 도는데 아무도 모르는 상태가 만들어진다.
--
-- 그래서 이 스크립트는 트랜잭션 대신 두 개의 관문을 둔다.
--   · §0 사전 점검 : 제약을 못 걸 데이터(중복 소셜 계정 등)가 있으면 **아무것도 바꾸기 전에** 중단한다.
--   · §D 사후 검증 : 컬럼·제약·백필이 전부 끝났는지 확인하고, 하나라도 빠졌으면 실패로 끝낸다.
-- 두 관문 모두 SIGNAL SQLSTATE '45000' 으로 mysql 클라이언트를 0 이 아닌 코드로 종료시킨다.
--
-- 멱등: A·C 는 information_schema 가드로 감쌌고 B 는 WHERE 로 걸러진다. 재실행해도 안전하다.
--       (01·02·03 이 쓰는 것과 같은 PREPARE/EXECUTE 패턴이다.)
--
-- ─────────────────────────────────────────────────────────────────────────────
-- 되돌리기(DOWN) — 실행하지 말 것. 되돌려야 할 때만 손으로 골라 쓴다.
--
--   ALTER TABLE users DROP INDEX uk_users_provider_social_id;
--   ALTER TABLE users DROP COLUMN provider, DROP COLUMN social_id, DROP COLUMN role;
--   -- email 을 NOT NULL 로 되돌리는 문장은 일부러 적지 않는다. 이 마이그레이션 이후에
--   -- email = NULL 인 행(카카오 이메일 미동의자)이 생기므로 그대로는 실패한다.
--
-- DOWN 을 돌리기 전에 새 애플리케이션을 먼저 내려야 한다(엔티티가 컬럼을 요구한다).
-- 백필로 채운 provider/social_id 값은 DROP COLUMN 과 함께 사라진다. username 은 남아 있으므로
-- 다시 UP 을 돌리면 §B 가 같은 값을 복원한다 — 그것이 username 을 지우지 않는 이유 중 하나다(§E).
-- ============================================================================


-- ── 0. 사전 점검 ────────────────────────────────────────────────────────────
-- 여기서 걸리면 users 는 한 글자도 바뀌지 않는다.

-- 중단 장치. SIGNAL 은 prepared statement 프로토콜이 지원하지 않아서(ERROR 1295)
-- 조건부로 던지려면 프로시저 한 겹이 필요하다. CALL 은 PREPARE 가능하다.
-- MESSAGE_TEXT 는 128자가 상한이다(넘기면 ERROR 1648). 자세한 내용은 메시지가 아니라
-- 바로 앞의 진단 SELECT 로 보여 준다.
--
-- ⓘ 중단하면 스크립트 끝의 DROP PROCEDURE 에 도달하지 못해 이 프로시저가 스키마에 남는다.
--   무해하고(아무도 호출하지 않는다) 다음 실행의 DROP PROCEDURE IF EXISTS 가 지우지만,
--   재실행하지 않을 거라면 손으로 지워도 된다: DROP PROCEDURE IF EXISTS heattrip_migration_abort;
--   실행 계정에 CREATE ROUTINE 권한이 필요하다 — 없으면 users 를 건드리기 전에 실패한다(안전 실패).
DROP PROCEDURE IF EXISTS heattrip_migration_abort;
CREATE PROCEDURE heattrip_migration_abort(IN msg VARCHAR(128))
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = msg;

-- 0-1. users 테이블이 있어야 한다.
SET @table_exists := (
    SELECT COUNT(*)
    FROM information_schema.tables
    WHERE table_schema = DATABASE()
      AND table_name = 'users'
);
SET @abort_msg := 'ABORT: users 테이블이 없다. 백엔드 앱을 먼저 띄운 뒤 다시 실행하라.';
SET @stmt := IF(@table_exists = 0,
    'CALL heattrip_migration_abort(@abort_msg)',
    'SELECT ''[0-1] users 테이블 확인 OK'' AS message');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- 0-2. 새 컬럼이 이미 있는지(= 재실행인지) 본다.
--      아직 없는 컬럼을 정적 SQL 로 참조하면 파싱 단계에서 죽으므로,
--      사전 점검 쿼리는 전부 PREPARE 로 조립한다.
SET @col_provider := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'users' AND column_name = 'provider');
SET @col_social_id := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'users' AND column_name = 'social_id');
SET @col_username := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'users' AND column_name = 'username');

-- 0-3. 마이그레이션이 끝났을 때 각 행이 갖게 될 (provider, social_id) 를 미리 계산해 모은다.
--      · 이미 컬럼이 있는 행 → 그 값
--      · 레거시 행           → username = '{provider}_{socialId}' 를 파싱한 값
--      social_id 를 넉넉한 길이로 받는 이유: 191 을 넘는 값도 잘라내지 말고 그대로 신고해야 한다.
DROP TEMPORARY TABLE IF EXISTS heattrip_social_key_precheck;
CREATE TEMPORARY TABLE heattrip_social_key_precheck (
    user_id   BIGINT        NOT NULL,
    provider  VARCHAR(64)   NOT NULL,
    social_id VARCHAR(1024) NOT NULL
);

SET @legacy_match := IF(@col_username = 1,
    '(u.username IS NOT NULL'
    ' AND LOCATE(''_'', u.username) > 0'
    ' AND LOCATE(''_'', u.username) < CHAR_LENGTH(u.username)'
    ' AND SUBSTRING_INDEX(u.username, ''_'', 1) IN (''kakao'', ''google'', ''naver''))',
    '(1 = 0)');

--      username 은 §E 의 후속 이슈에서 언젠가 사라진다. 그 뒤에 이 스크립트를 다시 돌려도
--      죽지 않도록, username 을 참조하는 조각은 전부 @col_username 가드 안에 둔다.
--      (가드 없이 COALESCE(u.provider, … u.username …) 을 조립하면 username 이 없는 DB 에서
--       ERROR 1054 'Unknown column u.username' 로 사전 점검 자체가 죽는다.)
SET @prov_expr := IF(@col_provider = 1,
    IF(@col_username = 1, 'COALESCE(u.provider, SUBSTRING_INDEX(u.username, ''_'', 1))', 'u.provider'),
    IF(@col_username = 1, 'SUBSTRING_INDEX(u.username, ''_'', 1)', '''unknown'''));
SET @sid_expr := IF(@col_social_id = 1,
    IF(@col_username = 1, 'COALESCE(u.social_id, SUBSTRING(u.username, LOCATE(''_'', u.username) + 1))', 'u.social_id'),
    IF(@col_username = 1, 'SUBSTRING(u.username, LOCATE(''_'', u.username) + 1)', '''unknown'''));
SET @row_filter := IF(@col_social_id = 1,
    CONCAT('(u.social_id IS NOT NULL OR ', @legacy_match, ')'),
    @legacy_match);

-- social_id 도 username 도 없는 DB 에는 모을 후보 자체가 없다. 그런 DB 에서는 문장을
-- 아예 만들지 않는다(위 식이 'unknown' 리터럴로 떨어지므로 조립은 되지만 의미가 없다).
SET @stmt := IF(@col_social_id = 0 AND @col_username = 0,
    'SELECT ''[0-3] provider/social_id 후보 없음 — 사전 점검 대상 0행'' AS message',
    CONCAT(
        'INSERT INTO heattrip_social_key_precheck (user_id, provider, social_id) ',
        'SELECT u.id, ', @prov_expr, ', ', @sid_expr, ' FROM users u WHERE ', @row_filter));
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- 0-4. 중복이 있으면 어떤 행인지 그대로 보여 준다. (없으면 빈 결과)
SELECT '[0-4] 중복 소셜 계정 (있으면 아래 목록의 행을 병합/삭제한 뒤 재실행)' AS section;
SELECT provider,
       social_id,
       COUNT(*)                              AS row_count,
       GROUP_CONCAT(user_id ORDER BY user_id) AS user_ids
FROM heattrip_social_key_precheck
GROUP BY provider, social_id
HAVING COUNT(*) > 1
ORDER BY row_count DESC, provider, social_id;

-- 0-5. social_id 컬럼(VARCHAR(191))에 들어가지 못할 만큼 긴 값도 미리 잡는다.
--      그냥 두면 strict 모드에서 §B 가 ERROR 1406 으로 죽고, --force 로 밀면
--      다음 문장이 그 행을 provider='local' 로 잘못 표시한다.
SELECT '[0-5] social_id 길이 초과(> 191)' AS section;
SELECT user_id, provider, CHAR_LENGTH(social_id) AS social_id_length
FROM heattrip_social_key_precheck
WHERE CHAR_LENGTH(social_id) > 191
ORDER BY user_id;

-- 0-6. 하나라도 걸리면 여기서 끝낸다. users 는 아직 그대로다.
SET @dup_groups := (
    SELECT COUNT(*) FROM (
        SELECT 1 FROM heattrip_social_key_precheck
        GROUP BY provider, social_id HAVING COUNT(*) > 1
    ) d);
SET @too_long := (
    SELECT COUNT(*) FROM heattrip_social_key_precheck WHERE CHAR_LENGTH(social_id) > 191);
SET @abort_msg := CONCAT(
    'ABORT: 중복 소셜 계정 ', @dup_groups, '건 / social_id 길이초과 ', @too_long,
    '건 — 위 [0-4],[0-5] 참고. users 는 그대로다.');
SET @stmt := IF(@dup_groups > 0 OR @too_long > 0,
    'CALL heattrip_migration_abort(@abort_msg)',
    'SELECT ''[0-6] 사전 점검 통과 — 중복 없음, 길이 초과 없음'' AS message');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;


-- ── A. 컬럼 추가 (멱등) ─────────────────────────────────────────────────────
-- provider  : 계정 출처. 계약(docs/04-api/openapi.yaml)의 User.provider enum 과 같은 문자열.
-- social_id : 소셜 공급자가 발급한 고유 ID. 이메일 가입자는 NULL.
--             191 = utf8mb4 기준 InnoDB 단일 컬럼 인덱스 상한(767바이트)에 맞춘 관례값.
-- role      : 권한. 예전에는 토큰 발급 때마다 코드에서 'ROLE_USER' 를 하드코딩했다.
--             엔티티(User.java)도 @Column(nullable = false) 라 dev 의 ddl-auto=update 와 정의가 같다.

SET @col_exists := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'users' AND column_name = 'provider');
SET @stmt := IF(@col_exists = 0,
    'ALTER TABLE users ADD COLUMN provider VARCHAR(20) NULL',
    'SELECT ''[A] provider 컬럼은 이미 있다.'' AS message');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @col_exists := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'users' AND column_name = 'social_id');
SET @stmt := IF(@col_exists = 0,
    'ALTER TABLE users ADD COLUMN social_id VARCHAR(191) NULL',
    'SELECT ''[A] social_id 컬럼은 이미 있다.'' AS message');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @col_exists := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'users' AND column_name = 'role');
SET @stmt := IF(@col_exists = 0,
    'ALTER TABLE users ADD COLUMN role VARCHAR(20) NOT NULL DEFAULT ''ROLE_USER''',
    'SELECT ''[A] role 컬럼은 이미 있다.'' AS message');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- email 을 NULL 허용으로 바꾼다.
-- 카카오 account_email 은 '선택 동의'라서 사용자가 거부하면 이메일이 오지 않는다.
-- UNIQUE 는 유지한다 — MySQL 은 UNIQUE 인덱스에서 NULL 을 서로 다른 값으로 보므로
-- 이메일 없는 사용자가 여럿이어도 충돌하지 않는다. (H2 도 같다 — UserRepositoryTest 가 확인)
--
-- 길이·문자셋·콜레이션·COMMENT 를 하드코딩하지 않고 현재 정의에서 그대로 읽어 재사용한다.
-- (예전 초안은 VARCHAR(255) 로 못박아 두어서, 컬럼이 더 길게 만들어진 DB 에서는
--  ERROR 1406 으로 죽거나 값을 조용히 잘라 먹었다.)
SET @email_nullable := (
    SELECT IS_NULLABLE FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'users' AND column_name = 'email');
SET @email_type := (
    SELECT COLUMN_TYPE FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'users' AND column_name = 'email');
SET @email_charset := (
    SELECT CHARACTER_SET_NAME FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'users' AND column_name = 'email');
SET @email_collation := (
    SELECT COLLATION_NAME FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'users' AND column_name = 'email');
SET @email_comment := (
    SELECT COLUMN_COMMENT FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'users' AND column_name = 'email');
SET @stmt := IF(@email_nullable = 'NO',
    CONCAT('ALTER TABLE users MODIFY COLUMN email ', @email_type,
           IF(@email_charset IS NULL, '',
              CONCAT(' CHARACTER SET ', @email_charset, ' COLLATE ', @email_collation)),
           ' NULL',
           IF(@email_comment IS NULL OR @email_comment = '', '',
              CONCAT(' COMMENT ', QUOTE(@email_comment)))),
    'SELECT ''[A] email 은 이미 NULL 을 허용한다.'' AS message');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;


-- ── B. 기존 데이터 백필 ─────────────────────────────────────────────────────
-- 여기부터는 A 가 컬럼을 만든 뒤라 정적 SQL 로 provider/social_id 를 참조해도 된다.
--
-- 소셜 가입자: username 이 '{provider}_{socialId}' 한 문자열에 뭉쳐 있다.
-- 첫 '_' 앞이 provider, 뒤가 social_id 다. social_id 쪽에 '_' 가 더 있어도(구글 sub 등)
-- SUBSTRING(... LOCATE + 1) 이 나머지를 통째로 가져가므로 안전하다.
--   'kakao_1234'        → ('kakao',  '1234')
--   'google_1_2_3'      → ('google', '1_2_3')
-- CHAR_LENGTH 조건은 §0-5 가 이미 걸러 준 것을 한 번 더 잠근다(191 초과는 여기까지 오지 않는다).
UPDATE users
SET provider  = SUBSTRING_INDEX(username, '_', 1),
    social_id = SUBSTRING(username, LOCATE('_', username) + 1)
WHERE provider IS NULL
  AND username IS NOT NULL
  AND SUBSTRING_INDEX(username, '_', 1) IN ('kakao', 'google', 'naver')
  AND LOCATE('_', username) > 0
  AND LOCATE('_', username) < CHAR_LENGTH(username)
  AND CHAR_LENGTH(SUBSTRING(username, LOCATE('_', username) + 1)) <= 191;

-- 이메일 가입자: username 이 없거나 위 규칙에 맞지 않는 나머지는 전부 local 이다.
UPDATE users
SET provider = 'local'
WHERE provider IS NULL;

-- role 이 비어 있는 행 보정 (DEFAULT 로 이미 채워지지만 명시적으로 한 번 더).
UPDATE users
SET role = 'ROLE_USER'
WHERE role IS NULL OR role = '';


-- ── C. 제약 추가 (멱등) ─────────────────────────────────────────────────────
-- '한 소셜 계정 = 한 행'을 DB 수준에서 보증한다. 지금까지는 username 문자열 조합 규칙에만
-- 의존했다. NULL 은 서로 다른 값이라 이메일 가입자(social_id NULL)가 여럿이어도 걸리지 않는다.
-- 여기까지 왔다면 §0 이 중복 없음을 이미 확인했다.
SET @idx_exists := (
    SELECT COUNT(*) FROM information_schema.statistics
    WHERE table_schema = DATABASE()
      AND table_name = 'users'
      AND index_name = 'uk_users_provider_social_id');
SET @stmt := IF(@idx_exists = 0,
    'ALTER TABLE users ADD CONSTRAINT uk_users_provider_social_id UNIQUE (provider, social_id)',
    'SELECT ''[C] uk_users_provider_social_id 는 이미 있다.'' AS message');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;


-- ── D. 사후 검증 ────────────────────────────────────────────────────────────
-- '반쯤 적용된 채 성공처럼 끝나는' 상태를 막는 마지막 관문이다.
-- Hibernate ddl-auto=validate 는 컬럼만 보고 UNIQUE 제약은 검사하지 않으므로,
-- 여기서 확인하지 않으면 제약이 빠진 사실을 앱도 CI 도 끝까지 알려주지 않는다.
SET @new_columns := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'users'
      AND column_name IN ('provider', 'social_id', 'role'));
SET @unique_cols := (
    SELECT COUNT(*) FROM information_schema.statistics
    WHERE table_schema = DATABASE()
      AND table_name = 'users'
      AND index_name = 'uk_users_provider_social_id'
      AND non_unique = 0);
SET @provider_nulls := (SELECT COUNT(*) FROM users WHERE provider IS NULL);
SET @role_blanks := (SELECT COUNT(*) FROM users WHERE role IS NULL OR role = '');

SELECT '[D] 사후 검증' AS section,
       @new_columns    AS new_columns_expect_3,
       @unique_cols    AS unique_index_columns_expect_2,
       @provider_nulls AS provider_null_rows_expect_0,
       @role_blanks    AS role_blank_rows_expect_0;

SET @abort_msg := CONCAT(
    'ABORT: 반쯤 적용됨 — 컬럼 ', @new_columns, '/3, UNIQUE ', @unique_cols, '/2, ',
    'provider NULL ', @provider_nulls, '행, role 공백 ', @role_blanks, '행. 위 [D] 참고.');
SET @stmt := IF(@new_columns <> 3 OR @unique_cols <> 2 OR @provider_nulls > 0 OR @role_blanks > 0,
    'CALL heattrip_migration_abort(@abort_msg)',
    'SELECT ''[D] 사후 검증 통과 — 컬럼·제약·백필 모두 적용됨'' AS message');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- 참고용 분포. 실패시키지 않는다.
SELECT '[D] provider 분포' AS section;
SELECT provider, COUNT(*) AS rows_count FROM users GROUP BY provider ORDER BY provider;

SELECT '[D] email 이 NULL 인 사용자 수 (카카오 이메일 미동의자 — 정상이다)' AS section;
SELECT COUNT(*) AS email_null_rows FROM users WHERE email IS NULL;

DROP TEMPORARY TABLE IF EXISTS heattrip_social_key_precheck;
DROP PROCEDURE IF EXISTS heattrip_migration_abort;

SELECT '04_users_social_account_model.sql 완료' AS message;


-- ── E. username 컬럼은 지우지 않는다 (판단 근거) ────────────────────────────
-- 이제 식별 키가 아니지만 이번 마이그레이션에서 DROP 하지 않는다.
--   1) 컬럼 삭제는 되돌릴 수 없다. 백필이 모든 행에서 옳았는지 운영 데이터로 확인한 뒤가 맞다.
--   2) 지연 백필(CustomOAuth2UserService.findExisting)이 이 컬럼으로 레거시 행을 찾는다.
--      이 스크립트를 아직 돌리지 않은 환경이 하나라도 있으면 그 사용자들의 계정이 중복 생성된다.
--   3) prod 는 ddl-auto=validate 라 엔티티에서 필드를 지워도 컬럼은 남는다. 즉 '지웠다고
--      믿는데 안 지워진' 상태가 만들어지기 쉽다.
--   4) 위 DOWN 절이 provider/social_id 를 되살릴 수 있는 유일한 원본이다.
-- 삭제는 별도 이슈에서, 아래를 모두 확인한 뒤 진행한다.
--   - 모든 환경에서 이 스크립트 실행 완료
--   - SELECT COUNT(*) FROM users WHERE provider IS NULL  → 0
--   - 코드에서 findByUsername 호출 지점이 남아 있지 않음
