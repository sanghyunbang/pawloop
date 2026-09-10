-- ============================================================================
-- 38_crew_favor.sql
-- 품앗이 — 서로 맡아 주기 — 이슈 #417
-- 대상: MySQL 8.x (운영/개발 공통)
--
-- ─────────────────────────────────────────────────
-- 무엇을 하나
--
--   CREATE TABLE crew_favor (crew_id, asked_by, taken_by, dog_id,
--                            on_date, slot, note, status, schedule_id)
--
-- ─────────────────────────────────────────────────
-- 돈이 안 붙는다 — 그것이 이 표의 크기를 정한다
--
-- 이슈가 스스로 그은 선이다: **결제·평점·보증·중개는 안 한다.** 돈이 오가는 순간 우리가
-- 중개자가 되고, 사고가 나면 배상 책임과 신고 의무가 따라온다. 그래서 이 표에는 **금액도,
-- 평점도, 후기도 없다.** 여기서 하는 일은 약속을 적는 것까지다.
--
-- ─────────────────────────────────────────────────
-- 끝났는지는 이 표가 모른다
--
-- 맡으면 크루 소유 일정 한 줄이 생기고(`schedule_id`), **그 줄의 완료 표시가 "했다" 를
-- 말한다.** 여기에 상태를 하나 더 두면 같은 사실이 두 곳에 살고 한쪽만 고쳐진다.
-- 그래서 `status` 는 `open`·`taken` 둘뿐이다 — "취소됨" 도 없다(거둬들이면 행이 사라진다).
--
-- ─────────────────────────────────────────────────
-- schedule_id 에 FK 가 없다
--
-- 걸려면 엔티티가 `schedule.entity.Schedule` 을 들어야 하고 그건 모듈 경계를 넘는다.
-- SQL 에만 적어 두면 `01_schema.sql` 재생성에서 조용히 사라진다 — `schedule.care_log_id`
-- 가 #420 에서 같은 자리였다. 크루를 지울 때 그 줄까지 거두는 것은 **서비스**가 한다
-- (`CrewFavorService.removeAllOf`).
--
-- ─────────────────────────────────────────────────
-- FK 넷의 삭제 규칙이 서로 다르다
--
--   crew_id  CASCADE   크루가 사라지면 그 부탁도 사라진다
--   asked_by SET NULL  탈퇴해도 부탁은 남는다 — 이미 맡은 사람이 있는 약속이
--                      조용히 사라지면 안 된다
--   taken_by SET NULL  같은 이유
--   dog_id   SET NULL  아이를 보내도 약속은 남는다 (`schedule.dog_id` 와 같은 판단)
--
-- ─────────────────────────────────────────────────
-- 실행 순서
--
--   1. `37_crew.sql` 이 먼저다. 없으면 시작하지 않는다.
--   2. 이 스크립트를 실행한다 — 새 애플리케이션을 배포하기 **전**.
--
-- **dev(`ddl-auto=update`)에서도 앱을 띄우기 전에 돌린다.** 안 돌리면 Hibernate 가 표를
-- 자기 방식으로 만들고(예: CHECK 없이), 그 뒤에는 이 스크립트가 `IF NOT EXISTS` 로 조용히
-- 지나가 **CHECK 가 없는 표가 남는다**(#420 에서 겪었다).
--
-- 멱등: 표가 이미 있으면 지나간다.
--
-- ─────────────────────────────────────────────────
-- 되돌리기(DOWN)
--
--   DROP TABLE crew_favor;
--
-- **맡아서 생긴 크루 일정은 안 지워진다** — `schedule` 의 행으로 남는다. 그 줄들은
-- `owner_kind='room'` 이라 크루 사람들의 달력에 계속 뜬다. 지우려면 따로 지운다:
--   DELETE FROM schedule WHERE owner_kind = 'room';
-- ============================================================================


-- ── 0. 사전 점검 ─────────────────────────────────────────
SET NAMES utf8mb4;

DROP PROCEDURE IF EXISTS heattrip_migration_abort;
CREATE PROCEDURE heattrip_migration_abort(IN msg VARCHAR(128))
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = msg;

-- 37 이 만든 그 표여야 한다.
SET @has_crew := (
    SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name = 'crew');

SET @stmt := IF(@has_crew = 1,
    'SELECT ''[0-1] crew 확인 (37 통과)'' AS message',
    'CALL heattrip_migration_abort(''ABORT: 37_crew.sql 을 먼저 돌려라.'')');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- 아이를 거는 FK 가 있으므로 dog 표도 있어야 한다.
SET @has_dog := (
    SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name = 'dog');

SET @stmt := IF(@has_dog = 1,
    'SELECT ''[0-2] dog 확인'' AS message',
    'CALL heattrip_migration_abort(''ABORT: dog 표가 없다.'')');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @has_favor := (
    SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name = 'crew_favor');

SELECT '[0] 사전 점검' AS section,
       @has_favor AS crew_favor_table_already;


-- ── A. 표 ────────────────────────────────────────────────
--
-- 컬럼 순서·타입은 `mysql/init/01_schema.sql` 과 **같아야 한다**. 그 파일은 엔티티에서 뽑은
-- 것이고 prod 는 `ddl-auto=validate` 다.
CREATE TABLE IF NOT EXISTS `crew_favor` (
  `on_date` date NOT NULL,
  `asked_by` bigint DEFAULT NULL,
  `created_at` datetime(6) NOT NULL,
  `crew_id` bigint NOT NULL,
  `dog_id` bigint DEFAULT NULL,
  `id` bigint NOT NULL AUTO_INCREMENT,
  `schedule_id` bigint DEFAULT NULL,
  `taken_by` bigint DEFAULT NULL,
  `updated_at` datetime(6) DEFAULT NULL,
  `slot` varchar(10) NOT NULL,
  `status` varchar(10) NOT NULL,
  `note` varchar(200) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_crew_favor_crew` (`crew_id`,`on_date`),
  KEY `fk_crew_favor_asker` (`asked_by`),
  KEY `fk_crew_favor_dog` (`dog_id`),
  KEY `fk_crew_favor_taker` (`taken_by`),
  CONSTRAINT `fk_crew_favor_asker` FOREIGN KEY (`asked_by`) REFERENCES `users` (`id`) ON DELETE SET NULL,
  CONSTRAINT `fk_crew_favor_crew` FOREIGN KEY (`crew_id`) REFERENCES `crew` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_crew_favor_dog` FOREIGN KEY (`dog_id`) REFERENCES `dog` (`id`) ON DELETE SET NULL,
  CONSTRAINT `fk_crew_favor_taker` FOREIGN KEY (`taken_by`) REFERENCES `users` (`id`) ON DELETE SET NULL,
  CONSTRAINT `ck_crew_favor_slot` CHECK ((`slot` in ('morning','afternoon','evening'))),
  CONSTRAINT `ck_crew_favor_status` CHECK ((`status` in ('open','taken')))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;


-- ── D. 사후 검증 ─────────────────────────────────────────
--
-- **전체 컬럼 수를 안 센다** — 컬럼이 늘면 재실행이 깨진다. 이름으로 묻는다.
SET @d_cols := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'crew_favor'
      AND column_name IN ('id','crew_id','asked_by','taken_by','dog_id',
                          'on_date','slot','note','status','schedule_id',
                          'created_at','updated_at'));

-- 크루가 사라지면 부탁도 사라져야 한다. 남으면 어느 크루의 약속인지 아무도 모른다.
SET @d_crew_cascade := (
    SELECT COUNT(*) FROM information_schema.referential_constraints
    WHERE constraint_schema = DATABASE() AND constraint_name = 'fk_crew_favor_crew'
      AND delete_rule = 'CASCADE');

-- 사람과 아이는 SET NULL 이다 — 탈퇴·이별이 남의 약속을 지우면 안 된다.
SET @d_set_null := (
    SELECT COUNT(*) FROM information_schema.referential_constraints
    WHERE constraint_schema = DATABASE()
      AND constraint_name IN ('fk_crew_favor_asker','fk_crew_favor_taker','fk_crew_favor_dog')
      AND delete_rule = 'SET NULL');

-- CHECK 둘. **Hibernate 의 update 도 prod 의 validate 도 CHECK 는 안 본다.**
SET @d_checks := (
    SELECT COUNT(*) FROM information_schema.table_constraints
    WHERE table_schema = DATABASE() AND table_name = 'crew_favor'
      AND constraint_type = 'CHECK'
      AND constraint_name IN ('ck_crew_favor_slot','ck_crew_favor_status'));

-- 크루 홈의 목록이 타는 인덱스다.
SET @d_index := (
    SELECT COUNT(DISTINCT column_name) FROM information_schema.statistics
    WHERE table_schema = DATABASE() AND table_name = 'crew_favor'
      AND index_name = 'idx_crew_favor_crew');

SELECT '[D] 사후 검증' AS section,
       @d_cols          AS named_columns_expect_12,
       @d_crew_cascade  AS crew_cascade_expect_1,
       @d_set_null      AS set_null_fks_expect_3,
       @d_checks        AS checks_expect_2,
       @d_index         AS list_index_columns_expect_2;

SET @stmt := IF(@d_cols = 12 AND @d_crew_cascade = 1 AND @d_set_null = 3
                AND @d_checks = 2 AND @d_index = 2,
    'SELECT ''[D] 통과 — crew_favor 표 · CASCADE 하나 · SET NULL 셋 · CHECK 둘'' AS message',
    'CALL heattrip_migration_abort(''ABORT: 사후 검증 실패. 위 [D] 행의 숫자를 확인하라.'')');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

DROP PROCEDURE IF EXISTS heattrip_migration_abort;
