-- ============================================================================
-- 07_family_group.sql
-- 가족 케어 그룹 표 — 이슈 #75 (근거: ADR-0011)
-- 대상: MySQL 8.x (운영/개발 공통)
--
-- ─────────────────────────────────────────────────────────────────────────────
-- 실행 순서
--
--   1. 06_chat_rooms.sql 을 먼저 실행한다 (방·멤버십·초대 3표)
--   2. 이 스크립트를 실행한다 (앱 배포 **전**)
--   3. 그 다음 새 애플리케이션을 배포한다
--
-- 1 이 앞인 것은 FK 때문이 아니다 — 이 표에는 FK 가 하나도 없다. 그룹을 만드는 코드가
-- 같은 트랜잭션에서 chat_room · chat_room_member 를 함께 INSERT 하기 때문이고, 그 표가
-- 없으면 그룹 생성이 통째로 실패한다.
--
-- 3 은 사실상 강제된다 — prod 는 ddl-auto=validate 라 엔티티가 요구하는 표가 없으면
-- **부팅 자체가 실패한다.** 되돌릴 때는 반대로, 앱을 먼저 내린다.
--
-- 빈 DB 를 새로 세우는 경우에는 이 파일이 필요 없다. mysql/init/01_schema.sql 이
-- family_group 을 이미 담고 있다(#58).
--
-- ─────────────────────────────────────────────────────────────────────────────
-- ⚠️ 트랜잭션으로 감쌀 수 없다 — 실패해도 되돌아가지 않는다
--
-- MySQL 의 DDL 은 **암묵적 커밋**을 일으킨다. 그래서 04·05·06 과 같이 앞뒤로 관문을 둔다.
--   · §0 사전 점검 : 같은 이름의 표가 **다른 모양**으로 이미 있으면 아무것도 바꾸기 전에 멈춘다.
--   · §D 사후 검증 : 표·컬럼과 **경계**가 전부 맞는지 확인하고, 하나라도 어긋나면 실패로 끝낸다.
--
-- ─────────────────────────────────────────────────────────────────────────────
-- 이 표에 없는 것 — 그게 이 표의 요점이다
--
-- · **invite_code 컬럼이 없다.** 옛 정의에는 invite_code VARCHAR(12) + UNIQUE 가 있었다.
--   그건 그룹당 코드 하나가 영구히 사는 모양이라 만료·사용횟수·폐기를 걸 자리가 없고,
--   코드를 바꾸려면 그룹 행을 UPDATE 해야 해서 누가 언제 발급했는지가 안 남는다.
--   초대코드는 chat_room_invite 다(06). §0 이 그 컬럼이 남아 있으면 중단한다.
-- · **group_member 표를 만들지 않는다.** 멤버십은 chat_room_member 하나다
--   (ADR-0011 결정 1). 둘을 두면 '가족인데 방에 없는 사람' 이라는 상태가 생기고,
--   그걸 막는 코드를 영원히 쓴다.
-- · **chat_room 으로 가는 FK 가 없다.** 화살표는 반대 방향 하나다 —
--   chat_room(origin_kind='FAMILY', origin_ref=<이 표의 id>). §D 가 양쪽을 다 본다.
--
-- ─────────────────────────────────────────────────────────────────────────────
-- 되돌리기(DOWN) — 실행하지 말 것. 되돌려야 할 때만 손으로 골라 쓴다.
--
--   DROP TABLE family_group;
--
-- 되돌리면 가족 그룹이 사라진다. **방과 대화는 남는다** — chat_room 은 이 표로 FK 를
-- 걸지 않기 때문이다. 남은 방은 origin_ref 가 가리키는 그룹이 없는 상태가 되고,
-- GET /api/groups/me 의 목록에서 조용히 빠진다(FamilyGroupService.groupOf 참조).
-- DOWN 전에 새 애플리케이션을 먼저 내려야 한다(엔티티가 이 표를 요구한다).
-- ============================================================================


-- ── 0. 사전 점검 ────────────────────────────────────────────────────────────
-- 여기서 걸리면 스키마는 한 글자도 바뀌지 않는다.
--
-- CREATE TABLE IF NOT EXISTS 는 **이미 있는 표를 고치지 않는다.** 그래서 이름만 같고
-- 모양이 다른 표가 있으면 이 스크립트는 조용히 성공하고, 그 차이는 prod 부팅
-- (ddl-auto=validate)에서야 드러난다. 그 전에 여기서 멈춘다.

-- 중단 장치. SIGNAL 은 prepared statement 프로토콜이 지원하지 않아서(ERROR 1295)
-- 조건부로 던지려면 프로시저 한 겹이 필요하다. MESSAGE_TEXT 는 128자가 상한이다.
-- 이 파일은 UTF-8 이고 중단 메시지가 한글이다. 세션 문자셋을 먼저 고정한다 —
-- 안 하면 클라이언트 기본값(윈도우 mysql 은 euckr)을 물려받아, 중단이 걸리는 순간
-- 이유는 안 보이고 ERROR 1366 (Incorrect string value) 만 남는다. 실측 2026-09-02, #169.
SET NAMES utf8mb4;

DROP PROCEDURE IF EXISTS heattrip_migration_abort;
CREATE PROCEDURE heattrip_migration_abort(IN msg VARCHAR(128))
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = msg;

SET @group_exists := (
    SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name = 'family_group');

-- 0-1. 옛 모양의 잔재. ADR-0011 이 초대코드를 chat_room_invite 로 옮겼다.
SET @legacy_invite_code := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'family_group'
      AND column_name = 'invite_code');

-- 0-2. 이미 있는 표에 필요한 컬럼이 빠져 있는지.
SET @present_columns := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'family_group'
      AND column_name IN ('id', 'name', 'created_at'));

SELECT '[0-1] 사전 점검' AS section,
       @group_exists       AS family_group_exists,
       @legacy_invite_code AS legacy_invite_code_expect_0,
       @present_columns    AS present_columns_expect_0_or_3;

SET @abort_msg := CONCAT(
    'ABORT: family_group 에 invite_code 컬럼이 남아 있다. 초대코드는 chat_room_invite 로 ',
    '옮겼다(ADR-0011). 값을 옮긴 뒤 그 컬럼을 지우고 다시 실행하라.');
SET @stmt := IF(@legacy_invite_code > 0,
    'CALL heattrip_migration_abort(@abort_msg)',
    'SELECT ''[0-1] 옛 invite_code 컬럼 없음'' AS message');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @abort_msg := CONCAT(
    'ABORT: family_group 이 이미 있는데 컬럼이 ', @present_columns,
    '/3 이다. IF NOT EXISTS 는 이 표를 고치지 않는다 — 손으로 맞춘 뒤 다시 실행하라.');
SET @stmt := IF(@group_exists = 1 AND @present_columns <> 3,
    'CALL heattrip_migration_abort(@abort_msg)',
    'SELECT ''[0-2] 사전 점검 통과'' AS message');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;


-- ── A. 표 생성 (멱등) ───────────────────────────────────────────────────────
-- 컬럼 타입은 엔티티(group/entity/FamilyGroup.java)가 만들 모양과 같아야 한다.
-- prod 의 ddl-auto=validate 가 타입 불일치로 부팅을 막기 때문이다. 정본은
-- mysql/init/01_schema.sql 이고 그 파일은 엔티티에서 뽑은 것이다.
--   · name 은 VARCHAR(50) — chat_room.name 과 **같은 길이여야 한다.** 여기만 길면
--     그룹은 만들어지고 같은 이름으로 방을 만드는 두 번째 INSERT 가 실패한다.
--   · created_at 은 DATETIME(6) — Hibernate 는 LocalDateTime 을 그렇게 만든다.

CREATE TABLE IF NOT EXISTS family_group (
    id         BIGINT      NOT NULL AUTO_INCREMENT,
    name       VARCHAR(50) NOT NULL,
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    PRIMARY KEY (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;


-- ── D. 사후 검증 ────────────────────────────────────────────────────────────
-- '반쯤 적용된 채 성공처럼 끝나는' 상태를 막는 마지막 관문이다.
-- validate 는 FK 도 UNIQUE 도 검사하지 않으므로, 여기서 안 보면 아무도 안 알려준다.

SET @group_table := (
    SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name = 'family_group');

SET @group_columns := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'family_group'
      AND column_name IN ('id', 'name', 'created_at'));

-- 경계 ①: family_group 에서 나가는 FK. **0이어야 한다.**
-- 특히 chat_room 으로 가는 FK 를 두면 화살표가 양방향이 되어 어느 쪽도 혼자 못 움직인다.
SET @group_out_fks := (
    SELECT COUNT(*) FROM information_schema.referential_constraints
    WHERE constraint_schema = DATABASE() AND table_name = 'family_group');

-- 경계 ②: chat_* 표에서 family_group 으로 들어오는 FK. **0이어야 한다** (ADR-0011 결정 4).
-- 06 이 'chat 밖으로 나가는 FK 0개' 로 같은 것을 보지만, 이 표를 만드는 순간이
-- 그 FK 를 걸고 싶어지는 순간이라 여기서 한 번 더 본다.
SET @chat_in_fks := (
    SELECT COUNT(*) FROM information_schema.referential_constraints
    WHERE constraint_schema = DATABASE()
      AND table_name LIKE 'chat\_%'
      AND referenced_table_name = 'family_group');

-- 경계 ③: group_member 표. **영영 만들지 않는다** (ADR-0011 결정 1).
SET @group_member_table := (
    SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name = 'group_member');

SELECT '[D] 사후 검증' AS section,
       @group_table        AS family_group_expect_1,
       @group_columns      AS columns_expect_3,
       @group_out_fks      AS out_fks_expect_0,
       @chat_in_fks        AS chat_to_group_fks_expect_0,
       @group_member_table AS group_member_expect_0;

SET @abort_msg := CONCAT(
    'ABORT: 반쯤 적용됨 — 표 ', @group_table, '/1, 컬럼 ', @group_columns, '/3. 위 [D] 참고.');
SET @stmt := IF(@group_table <> 1 OR @group_columns <> 3,
    'CALL heattrip_migration_abort(@abort_msg)',
    'SELECT ''[D] 사후 검증 통과 — 표·컬럼 적용됨'' AS message');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @abort_msg := CONCAT(
    'ABORT: 경계 위반 — family_group 이 내보내는 FK ', @group_out_fks, '개, chat_* 가 ',
    'family_group 으로 거는 FK ', @chat_in_fks, '개. 둘 다 0이어야 한다 (ADR-0011).');
SET @stmt := IF(@group_out_fks > 0 OR @chat_in_fks > 0,
    'CALL heattrip_migration_abort(@abort_msg)',
    'SELECT ''[D] 경계 검증 통과 — 양방향 FK 0개'' AS message');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @abort_msg := CONCAT(
    'ABORT: group_member 표가 있다. 멤버십 표는 chat_room_member 하나다 (ADR-0011 결정 1). ',
    '행을 chat_room_member 로 옮긴 뒤 그 표를 지우고 다시 실행하라.');
SET @stmt := IF(@group_member_table > 0,
    'CALL heattrip_migration_abort(@abort_msg)',
    'SELECT ''[D] group_member 없음 — 멤버십 표는 하나다'' AS message');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- 참고용. 실패시키지 않는다.
SELECT '[D] 현재 family_group 행 수 (첫 실행이면 0이다)' AS section;
SELECT COUNT(*) AS rows_count FROM family_group;

DROP PROCEDURE IF EXISTS heattrip_migration_abort;

SELECT '07_family_group.sql 완료' AS message;
