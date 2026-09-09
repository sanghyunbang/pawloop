-- ============================================================================
-- 35_schedule_care_log.sql
-- 완료한 일정이 남긴 케어 기록을 기억한다 — 이슈 #420 (부모 #416)
-- 대상: MySQL 8.x (운영/개발 공통)
--
-- ─────────────────────────────────────────────────
-- 무엇을 하나
--
--   ALTER TABLE schedule ADD COLUMN care_log_id bigint NULL
--
-- 일정을 **완료**로 바꾸면 오늘의 케어 칸에도 한 줄이 생긴다. 없으면 사람이 같은 일을 두 곳에
-- 두 번 적는다 — 일정에서 체크하고, 케어 칸에서 병원 버튼을 또 누른다. 그러면 "오늘 병원
-- 두 번" 이 기록에 남는다.
--
-- 되돌리면 그 줄을 **거둔다**. 거두려면 어느 줄이었는지 알아야 하고, 이 컬럼이 그것이다.
--
-- ─────────────────────────────────────────────────
-- FK 를 안 건다
--
-- `care_log` 를 가리키는 FK 를 걸려면 `Schedule` 엔티티가 `care.entity.CareLog` 를 들어야
-- 하고, 그건 모듈 경계를 넘는다(`owner_ref` 가 같은 이유로 FK 가 아니다). `01_schema.sql` 은
-- 엔티티에서 재생성되므로, 여기에만 FK 를 적어 두면 **다음 재생성에서 조용히 사라진다.**
--
-- 대신 사람이 케어 칸에서 그 줄을 먼저 지웠을 수 있다는 전제로 다룬다 — 거두기는 없는 id 를
-- 조용히 지나간다(`CareLogging.withdraw`).
--
-- ─────────────────────────────────────────────────
-- 인덱스를 안 만든다
--
-- 이 컬럼으로 **찾지 않는다**. 늘 `schedule` 한 줄을 이미 들고 있고 거기서 id 를 꺼내 쓸
-- 뿐이라, 인덱스는 쓰이지 않으면서 쓰기만 느리게 한다.
--
-- ─────────────────────────────────────────────────
-- 실행 순서
--
--   1. 34_schedule.sql 이 먼저다. 없으면 시작하지 않는다.
--   2. 이 스크립트를 실행한다 — 새 애플리케이션을 배포하기 **전**(prod 는 validate).
--
-- 멱등: 컬럼이 이미 있으면 지나간다.
--
-- ─────────────────────────────────────────────────
-- 되돌리기(DOWN)
--
--   ALTER TABLE schedule DROP COLUMN care_log_id;
--
-- 이미 남긴 케어 기록은 안 사라진다 — 그 줄과 일정 사이의 **이음매만** 잃는다. 되돌린 뒤에
-- 완료를 취소하면 케어 칸의 줄이 그대로 남는다(사람이 손으로 지워야 한다).
-- ============================================================================


-- ── 0. 사전 점검 ─────────────────────────────────────────
SET NAMES utf8mb4;

DROP PROCEDURE IF EXISTS heattrip_migration_abort;
CREATE PROCEDURE heattrip_migration_abort(IN msg VARCHAR(128))
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = msg;

-- schedule 이 있어야 하고, **34 가 만든 그 표**여야 한다. 감정 여행 시절의 옛 표
-- (`schedule_id` PK)에 컬럼을 더하면 엉뚱한 표가 늘어난다.
SET @has_schedule := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'schedule'
      AND column_name = 'owner_kind');

SET @stmt := IF(@has_schedule = 1,
    'SELECT ''[0-1] schedule 확인'' AS message',
    'CALL heattrip_migration_abort(''ABORT: 34_schedule.sql 이 만든 schedule 표가 없다. 먼저 돌려라.'')');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @has_column := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'schedule'
      AND column_name = 'care_log_id');

SELECT '[0] 사전 점검' AS section, @has_column AS column_already;


-- ── A. 컬럼 ──────────────────────────────────────────────
--
-- 타입은 `mysql/init/01_schema.sql` 과 **같아야 한다**. 그 파일은 엔티티에서 뽑은 것이고
-- (`SchemaDdlDriftTest`), prod 는 `ddl-auto=validate` 다.
SET @stmt := IF(@has_column = 1,
    'SELECT ''[A] 이미 있음 — 지나간다'' AS message',
    'ALTER TABLE `schedule` ADD COLUMN `care_log_id` bigint DEFAULT NULL');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;


-- ── D. 사후 검증 ─────────────────────────────────────────
SET @d_column := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'schedule'
      AND column_name = 'care_log_id' AND is_nullable = 'YES');

-- FK 가 **없어야** 한다. 있으면 다음 재생성에서 01_schema.sql 과 갈린다(헤더 주석 참조).
SET @d_no_fk := (
    SELECT COUNT(*) FROM information_schema.key_column_usage
    WHERE table_schema = DATABASE() AND table_name = 'schedule'
      AND column_name = 'care_log_id' AND referenced_table_name IS NOT NULL);

SELECT '[D] 사후 검증' AS section,
       @d_column AS care_log_id_nullable_expect_1,
       @d_no_fk  AS foreign_keys_expect_0;

SET @stmt := IF(@d_column = 1 AND @d_no_fk = 0,
    'SELECT ''[D] 통과 — schedule.care_log_id (NULL 허용 · FK 없음)'' AS message',
    'CALL heattrip_migration_abort(''ABORT: 사후 검증 실패. 위 [D] 행의 숫자를 확인하라.'')');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

DROP PROCEDURE IF EXISTS heattrip_migration_abort;
