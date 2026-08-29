-- ============================================================================
-- users 소셜 계정 모델 마이그레이션 — 이슈 #7
-- 대상: MySQL 8.x (운영/개발 공통)
--
-- ─────────────────────────────────────────────────────────────────────────────
-- 왜 SQL 파일인가 (판단 근거)
--
-- 이 저장소에는 Flyway·Liquibase 가 없고 스키마는 Hibernate ddl-auto 로만 움직인다.
--   dev  : ddl-auto=update   → 새 컬럼·제약을 Hibernate 가 알아서 만든다. 단 **데이터 백필은 안 한다.**
--   prod : ddl-auto=validate → Hibernate 는 스키마를 만들지 않고 '엔티티와 다르면 부팅 실패' 만 한다.
--
-- 즉 운영에서는 이 스크립트를 **배포 전에 사람이 먼저 실행해야** 애플리케이션이 뜬다.
-- 배포 순서를 지키지 않으면 validate 단계에서 부팅이 실패한다(장애가 아니라 안전장치다).
--
--   1. 이 스크립트를 운영 DB 에 실행한다 (아래 A → B → C 순서 그대로)
--   2. 그 다음 새 애플리케이션을 배포한다
--
-- 백필 파싱을 자바가 아니라 SQL 로 둔 이유: 실행 시점이 '배포 전 1회'라서 애플리케이션
-- 수명주기에 붙일 자리가 없다. 시작 시 러너로 만들면 매 부팅마다 전체 users 를 훑게 되고,
-- 되돌리기도 어렵다. 운영자는 어차피 위 1번에서 SQL 을 실행하므로 같은 트랜잭션 안에서 끝낸다.
--
-- 이 스크립트가 아직 실행되지 않은 환경(주로 dev)에서도 로그인은 깨지지 않는다.
-- CustomOAuth2UserService.findExisting() 이 username = '{provider}_{social_id}' 인 레거시 행을
-- 찾아 그 자리에서 새 컬럼을 채운다(지연 백필). 이 스크립트는 그 일을 한 번에 끝내는 쪽이다.
--
-- 멱등성: A 의 ADD COLUMN 과 C 의 ADD CONSTRAINT 는 MySQL 에 IF NOT EXISTS 가 없어
-- 두 번 실행하면 에러가 난다. 재실행 전에는 상태를 확인할 것 (맨 아래 검증 쿼리).
-- ============================================================================

-- ── A. 컬럼 추가 ────────────────────────────────────────────────────────────
-- provider  : 계정 출처. 계약(docs/04-api/openapi.yaml)의 User.provider enum 과 같은 문자열.
-- social_id : 소셜 공급자가 발급한 고유 ID. 이메일 가입자는 NULL.
--             191 = utf8mb4 기준 InnoDB 단일 컬럼 인덱스 상한(767바이트)에 맞춘 관례값.
-- role      : 권한. 예전에는 토큰 발급 때마다 코드에서 'ROLE_USER' 를 하드코딩했다.
ALTER TABLE users
  ADD COLUMN provider  VARCHAR(20)  NULL,
  ADD COLUMN social_id VARCHAR(191) NULL,
  ADD COLUMN role      VARCHAR(20)  NOT NULL DEFAULT 'ROLE_USER';

-- email 을 NULL 허용으로 바꾼다.
-- 카카오 account_email 은 '선택 동의'라서 사용자가 거부하면 이메일이 오지 않는다.
-- UNIQUE 는 유지한다 — MySQL 은 UNIQUE 인덱스에서 NULL 을 서로 다른 값으로 보므로
-- 이메일 없는 사용자가 여럿이어도 충돌하지 않는다. (H2 도 같다 — UserRepositoryTest 가 확인)
--
-- ⚠️ 아래는 현재 운영 스키마가 VARCHAR(255) NOT NULL 인 경우를 가정한 문장이다.
--    실제 정의를 먼저 확인하고 길이·문자셋을 그대로 유지한 채 NULL 만 바꿀 것:
--        SHOW CREATE TABLE users\G
ALTER TABLE users
  MODIFY COLUMN email VARCHAR(255) NULL;

-- ── B. 기존 데이터 백필 ─────────────────────────────────────────────────────
-- 소셜 가입자: username 이 '{provider}_{socialId}' 한 문자열에 뭉쳐 있다.
-- 첫 '_' 앞이 provider, 뒤가 social_id 다. social_id 쪽에 '_' 가 더 있어도(구글 sub 등)
-- SUBSTRING(... LOCATE + 1) 이 나머지를 통째로 가져가므로 안전하다.
--   'kakao_1234'        → ('kakao',  '1234')
--   'google_1_2_3'      → ('google', '1_2_3')
UPDATE users
SET provider  = SUBSTRING_INDEX(username, '_', 1),
    social_id = SUBSTRING(username, LOCATE('_', username) + 1)
WHERE provider IS NULL
  AND username IS NOT NULL
  AND SUBSTRING_INDEX(username, '_', 1) IN ('kakao', 'google', 'naver')
  AND LOCATE('_', username) > 0
  AND LOCATE('_', username) < CHAR_LENGTH(username);

-- 이메일 가입자: username 이 없거나 위 규칙에 맞지 않는 나머지는 전부 local 이다.
UPDATE users
SET provider = 'local'
WHERE provider IS NULL;

-- role 이 비어 있는 행 보정 (DEFAULT 로 이미 채워지지만 명시적으로 한 번 더).
UPDATE users
SET role = 'ROLE_USER'
WHERE role IS NULL OR role = '';

-- ── C. 제약 추가 ────────────────────────────────────────────────────────────
-- '한 소셜 계정 = 한 행'을 DB 수준에서 보증한다. 지금까지는 username 문자열 조합 규칙에만
-- 의존했다. NULL 은 서로 다른 값이라 이메일 가입자(social_id NULL)가 여럿이어도 걸리지 않는다.
--
-- ⚠️ 아래가 실패하면 이미 중복된 소셜 계정 행이 있다는 뜻이다. 먼저 D 의 진단 쿼리로
--    중복을 찾아 병합/삭제한 뒤 다시 실행할 것.
ALTER TABLE users
  ADD CONSTRAINT uk_users_provider_social_id UNIQUE (provider, social_id);

-- ── D. 검증 · 진단 ──────────────────────────────────────────────────────────
-- 1) 백필 결과 분포. provider 가 NULL 인 행이 남아 있으면 안 된다.
--    SELECT provider, COUNT(*) FROM users GROUP BY provider;
--
-- 2) C 가 실패했을 때 중복 소셜 계정 찾기.
--    SELECT provider, social_id, COUNT(*) c
--    FROM users
--    WHERE social_id IS NOT NULL
--    GROUP BY provider, social_id
--    HAVING c > 1;
--
-- 3) 이메일이 NULL 인 사용자 수 (카카오 이메일 미동의자 — 정상이다).
--    SELECT COUNT(*) FROM users WHERE email IS NULL;
--
-- 4) 제약이 실제로 붙었는지.
--    SHOW INDEX FROM users WHERE Key_name = 'uk_users_provider_social_id';

-- ── E. username 컬럼은 지우지 않는다 (판단 근거) ────────────────────────────
-- 이제 식별 키가 아니지만 이번 마이그레이션에서 DROP 하지 않는다.
--   1) 컬럼 삭제는 되돌릴 수 없다. 백필이 모든 행에서 옳았는지 운영 데이터로 확인한 뒤가 맞다.
--   2) 지연 백필(CustomOAuth2UserService.findExisting)이 이 컬럼으로 레거시 행을 찾는다.
--      이 스크립트를 아직 돌리지 않은 환경이 하나라도 있으면 그 사용자들의 계정이 중복 생성된다.
--   3) prod 는 ddl-auto=validate 라 엔티티에서 필드를 지워도 컬럼은 남는다. 즉 '지웠다고
--      믿는데 안 지워진' 상태가 만들어지기 쉽다.
-- 삭제는 별도 이슈에서, 아래를 모두 확인한 뒤 진행한다.
--   - 모든 환경에서 이 스크립트 실행 완료
--   - SELECT COUNT(*) FROM users WHERE provider IS NULL  → 0
--   - 코드에서 findByUsername 호출 지점이 남아 있지 않음
