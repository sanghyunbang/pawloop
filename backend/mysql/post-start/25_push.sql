-- ============================================================================
-- 25_push.sql
-- 푸시 알림의 표 둘과 방별 음소거 컬럼 하나 — 이슈 #83
-- 대상: MySQL 8.x (운영/개발 공통)
--
-- ─────────────────────────────────────────────────
-- 무엇을 하나
--
--   ALTER TABLE chat_room_member ADD COLUMN muted_at datetime(6) NULL
--   CREATE TABLE device_token   (기기 토큰 원장 — UNIQUE(token), user_id 는 값만)
--   CREATE TABLE push_preference (사용자별 전체 끄기 — 행이 없으면 켜진 것)
--
-- 방별 음소거는 멤버십의 속성이라 chat_room_member 에 두고, 토큰과 전체 끄기는 push 모듈의
-- 표다. 셋 다 FK 를 걸지 않는다 — device_token.user_id · push_preference.user_id 는 users.id
-- 값만 든다(push 가 users 를 모른다). 탈퇴 때 행은 애플리케이션이 지운다(UserSessionsRevoked).
--
-- ─────────────────────────────────────────────────
-- 왜 지우지 않고 revoked_at 인가
--
-- FCM 이 "없는 기기" 라고 답한 토큰과 로그아웃한 기기의 토큰은 지우지 않고 시각을 찍는다.
-- 지우면 "한 번도 없던 토큰" 과 "죽은 토큰" 을 구별할 수 없다 — refresh_token 과 같은 이유다.
-- 탈퇴만 행을 지운다(개인정보).
--
-- ─────────────────────────────────────────────────
-- 실행 순서
--
--   1. 06_chat_rooms.sql 이 먼저 돌아 있어야 한다 (chat_room_member 표). 없으면 시작하지 않는다.
--   2. 이 스크립트를 실행한다 — 새 애플리케이션을 배포하기 **전**.
--
-- 2 가 앞인 이유: prod 는 ddl-auto=validate 라 엔티티가 요구하는 표·컬럼이 없으면 부팅이
-- 실패한다. 옛 코드는 새 표와 컬럼이 있어도 상관하지 않는다.
--
-- 트랜잭션으로 감쌀 수 없다 — MySQL 의 DDL 은 암묵적 커밋을 일으킨다. 그래서 앞뒤로
-- 관문을 둔다: §0 사전 점검 · §D 사후 검증.
--
-- 멱등: 이미 있으면 "이미 있음" 을 찍고 지나간다. 있는데 모양이 다르면 고치지 않고 멈춘다 —
-- 누가 손으로 만든 것이라 사람이 봐야 한다.
--
-- ─────────────────────────────────────────────────
-- 되돌리기(DOWN)
--
--   ALTER TABLE chat_room_member DROP COLUMN muted_at;
--   DROP TABLE push_preference;
--   DROP TABLE device_token;
--
-- 값을 잃는다 — 음소거·끄기 설정과 등록된 기기가 전부 사라진다. 되돌리기 전에 앱을 먼저
-- 내린다(validate).
-- ============================================================================


-- ── 0. 사전 점검 ─────────────────────────────────────────
SET NAMES utf8mb4;

DROP PROCEDURE IF EXISTS heattrip_migration_abort;
CREATE PROCEDURE heattrip_migration_abort(IN msg VARCHAR(128))
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = msg;

-- 0-1. chat_room_member 표가 있어야 한다.
SET @has_member := (
    SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name = 'chat_room_member');

SET @stmt := IF(@has_member = 1,
    'SELECT ''[0-1] chat_room_member 확인'' AS message',
    'CALL heattrip_migration_abort(''ABORT: chat_room_member 표가 없다. 06_chat_rooms.sql 을 먼저 돌려라.'')');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- 0-2. muted_at 이 이미 있나. 있으면 모양(datetime(6), NULL 허용)까지 본다.
SET @muted_exists := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'chat_room_member'
      AND column_name = 'muted_at');
SET @muted_right_shape := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'chat_room_member'
      AND column_name = 'muted_at'
      AND data_type = 'datetime' AND datetime_precision = 6 AND is_nullable = 'YES');

SET @stmt := IF(@muted_exists = 0 OR @muted_right_shape = 1,
    'SELECT ''[0-2] muted_at 점검'' AS message',
    'CALL heattrip_migration_abort(''ABORT: chat_room_member.muted_at 이 다른 모양으로 있다(datetime(6) NULL 이어야 한다). 사람이 확인하라.'')');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- 0-3. device_token 이 이미 있나. 있으면 token 컬럼의 모양(varchar(512) NOT NULL)까지 본다.
SET @dt_exists := (
    SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name = 'device_token');
SET @dt_right_shape := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'device_token'
      AND column_name = 'token'
      AND data_type = 'varchar' AND character_maximum_length = 512 AND is_nullable = 'NO');

SET @stmt := IF(@dt_exists = 0 OR @dt_right_shape = 1,
    'SELECT ''[0-3] device_token 점검'' AS message',
    'CALL heattrip_migration_abort(''ABORT: device_token 이 다른 모양으로 있다(token varchar(512) NOT NULL 이어야 한다). 사람이 확인하라.'')');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- 0-4. push_preference 가 이미 있나. 있으면 enabled 컬럼의 모양(bit(1) NOT NULL)까지 본다.
SET @pp_exists := (
    SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name = 'push_preference');
SET @pp_right_shape := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'push_preference'
      AND column_name = 'enabled'
      AND data_type = 'bit' AND is_nullable = 'NO');

SET @stmt := IF(@pp_exists = 0 OR @pp_right_shape = 1,
    'SELECT ''[0-4] push_preference 점검'' AS message',
    'CALL heattrip_migration_abort(''ABORT: push_preference 가 다른 모양으로 있다(enabled bit(1) NOT NULL 이어야 한다). 사람이 확인하라.'')');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;


-- ── A. chat_room_member.muted_at ─────────────────────────
SET @stmt := IF(@muted_exists = 0,
    'ALTER TABLE chat_room_member ADD COLUMN muted_at datetime(6) NULL',
    'SELECT ''[A] muted_at 이미 있음'' AS message');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;


-- ── B. device_token ──────────────────────────────────────
-- 컬럼·제약 이름은 엔티티(push.entity.DeviceToken)가 만드는 것과 같다 — 01_schema.sql 재생성에도
-- 같은 모양이 나온다. token 은 varchar(512) — FCM 토큰은 보통 160자 안팎이지만 상한이 문서화돼
-- 있지 않아 여유를 둔다(utf8mb4 로도 UNIQUE 인덱스 한도 3072 바이트 안이다).
CREATE TABLE IF NOT EXISTS device_token (
  id            bigint       NOT NULL AUTO_INCREMENT,
  user_id       bigint       NOT NULL COMMENT 'users.id 값만 — FK 없음',
  token         varchar(512) NOT NULL,
  platform      varchar(8)   NOT NULL COMMENT 'android|ios',
  created_at    datetime(6)  NOT NULL,
  last_seen_at  datetime(6)  NOT NULL COMMENT '마지막 등록 시각 — 상한을 넘칠 때 오래된 것부터 폐기',
  revoked_at    datetime(6)  NULL     COMMENT '폐기 시각 — NULL 이면 살아 있다',
  PRIMARY KEY (id),
  UNIQUE KEY uk_device_token_token (token),
  KEY idx_device_token_user (user_id, revoked_at),
  CONSTRAINT chk_device_token_platform CHECK (platform IN ('android','ios'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;


-- ── C. push_preference ───────────────────────────────────
CREATE TABLE IF NOT EXISTS push_preference (
  user_id     bigint      NOT NULL COMMENT 'users.id 값 — FK 없음',
  enabled     bit(1)      NOT NULL,
  updated_at  datetime(6) NOT NULL,
  PRIMARY KEY (user_id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;


-- ── D. 사후 검증 ─────────────────────────────────────────
-- 이 스크립트가 만든 컬럼을 이름으로 센다 — 표의 전체 컬럼 수를 세면 다른 스크립트가 컬럼을
-- 더한 뒤에 헛빨간불이 난다(MigrationPostChecksNameColumnsTest).
SET @muted_after := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'chat_room_member'
      AND column_name IN ('muted_at')
      AND data_type = 'datetime' AND datetime_precision = 6 AND is_nullable = 'YES');

SET @dt_after := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'device_token'
      AND column_name IN ('id', 'user_id', 'token', 'platform', 'created_at', 'last_seen_at', 'revoked_at'));

SET @dt_unique := (
    SELECT COUNT(*) FROM information_schema.table_constraints
    WHERE table_schema = DATABASE() AND table_name = 'device_token'
      AND constraint_name = 'uk_device_token_token' AND constraint_type = 'UNIQUE');

SET @pp_after := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'push_preference'
      AND column_name IN ('user_id', 'enabled', 'updated_at'));

SET @stmt := IF(@muted_after = 1 AND @dt_after = 7 AND @dt_unique = 1 AND @pp_after = 3,
    'SELECT ''[D] 사후 검증 통과 — muted_at 1 · device_token 컬럼 7 + UNIQUE · push_preference 컬럼 3'' AS message',
    'CALL heattrip_migration_abort(''ABORT: 사후 검증 실패 — 표나 컬럼이 기대와 다르다. 사람이 확인하라.'')');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

DROP PROCEDURE IF EXISTS heattrip_migration_abort;

SELECT '25_push.sql 완료 — chat_room_member.muted_at · device_token · push_preference' AS message;
