-- ============================================================================
-- 36_schedule_repeat.sql
-- 반복 일정 — 규칙 한 줄과 하루짜리 예외 — 이슈 #421 (부모 #416)
-- 대상: MySQL 8.x (운영/개발 공통)
--
-- ─────────────────────────────────────────────────
-- 무엇을 하나
--
--   ALTER TABLE schedule ADD repeat_kind · repeat_until · origin_id
--   CREATE TABLE schedule_exception (schedule_id, on_date, kind)
--
-- ─────────────────────────────────────────────────
-- 행을 미리 만들지 않는다
--
-- 1년치 심장사상충 약을 365행으로 만들어 두면, 규칙을 고칠 때 그 전부를 손봐야 한다. 그
-- 손보기를 한 번 빠뜨리면 옛 값이 남은 행이 조용히 생긴다. 그래서 **규칙 한 줄**만 두고
-- 조회할 때 서버가 펼친다(`ScheduleExpansion`).
--
-- 요일·날짜 컬럼도 없다 — `weekly` 는 `on_date` 의 요일이고 `monthly` 는 그 날짜다. 따로
-- 두면 "매주 화요일인데 시작일은 수요일" 같은 모순을 저장할 수 있게 된다.
--
-- ─────────────────────────────────────────────────
-- 예외가 있어야 반복을 쓸 수 있다
--
-- `schedule_exception(schedule_id, on_date, kind)` 이 없으면 "이번 주 목욕만 하루 미루기" 가
-- 불가능하고, 사용자는 반복을 지우고 다시 만든다 — 그러면 지난 기록도 함께 사라진다.
--
-- `kind` 는 `skip`(그날 안 함) 또는 `override`(그날짜용 행이 대신함)다. **펼치기에서는 둘이
-- 같다** — 그날은 규칙에서 빠진다. 구분을 남기는 것은 사람이 DB 를 들여다볼 때를 위해서다.
--
-- 복합 PK — 한 규칙의 한 날짜에 예외는 하나뿐이다. 대리 키를 두면 같은 날짜에 두 줄이
-- 생길 수 있고, 그러면 펼치기가 그중 무엇을 볼지 정해야 한다.
--
-- **컬럼 순서가 `(on_date, schedule_id)` 인 것은 Hibernate 가 정한 것**이다
-- (`mysql/init/01_schema.sql` 이 엔티티에서 재생성된다). 바라던 순서는 아니지만 —
-- 이 표에 오는 질문은 "이 규칙의 예외" 라 `schedule_id` 가 앞이면 좋다 — **정본을 따른다**.
-- 반대로 적으면 새로 세운 DB 와 마이그레이션한 DB 의 인덱스가 갈리고 오류는 안 난다.
-- `fk_schedexc_schedule` 에 딸린 인덱스가 그 방향을 받는다(walk_dog 이 #343 에서 같은 자리).
--
-- ─────────────────────────────────────────────────
-- origin_id — 옮겨 둔 하루가 어느 규칙의 것인가
--
-- `schedule` 이 자기 자신을 가리키는 FK 다. `ON DELETE CASCADE` 라 규칙을 지우면 옮겨 둔
-- 하루도 함께 사라진다 — 남으면 그것이 무엇의 하루였는지 아무도 모른다.
--
-- ─────────────────────────────────────────────────
-- 실행 순서
--
--   1. 34_schedule.sql · 35_schedule_care_log.sql 이 먼저다. 없으면 시작하지 않는다.
--   2. 이 스크립트를 실행한다 — 새 애플리케이션을 배포하기 **전**.
--
-- **dev(`ddl-auto=update`)에서도 앱을 띄우기 전에 돌린다.** 안 돌리면 Hibernate 가 컬럼을
-- 자기 방식으로 얹고, 그 뒤에는 이 스크립트가 못 지나간다(#420 에서 겪었다).
--
-- 멱등: 컬럼·표가 이미 있으면 지나간다.
--
-- ─────────────────────────────────────────────────
-- 되돌리기(DOWN)
--
--   DROP TABLE schedule_exception;
--   ALTER TABLE schedule DROP FOREIGN KEY fk_schedule_origin,
--                        DROP COLUMN origin_id,
--                        DROP COLUMN repeat_until,
--                        DROP COLUMN repeat_kind;
--
-- 되풀이하던 일정은 **시작일 하루짜리**가 된다. 옮겨 둔 하루는 규칙과의 이음매만 잃고 행은
-- 남는다. 예외(건너뛴 날)는 사라진다.
-- ============================================================================


-- ── 0. 사전 점검 ─────────────────────────────────────────
SET NAMES utf8mb4;

DROP PROCEDURE IF EXISTS heattrip_migration_abort;
CREATE PROCEDURE heattrip_migration_abort(IN msg VARCHAR(128))
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = msg;

-- 34·35 가 만든 그 표여야 한다. 감정 여행 시절의 옛 표에 컬럼을 더하면 안 된다.
SET @ready := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'schedule'
      AND column_name IN ('owner_kind', 'care_log_id'));

SET @stmt := IF(@ready = 2,
    'SELECT ''[0-1] schedule 확인 (34·35 통과)'' AS message',
    'CALL heattrip_migration_abort(''ABORT: 34_schedule.sql · 35_schedule_care_log.sql 을 먼저 돌려라.'')');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @has_repeat := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'schedule'
      AND column_name = 'repeat_kind');
SET @has_exception := (
    SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name = 'schedule_exception');

SELECT '[0] 사전 점검' AS section,
       @has_repeat    AS repeat_columns_already,
       @has_exception AS exception_table_already;


-- ── A. 컬럼 셋 ───────────────────────────────────────────
--
-- 타입은 `mysql/init/01_schema.sql` 과 **같아야 한다**. 그 파일은 엔티티에서 뽑은 것이고
-- prod 는 `ddl-auto=validate` 다.
--
-- `repeat_kind` 에 DEFAULT 를 두는 것은 **이미 있는 행 때문**이다 — NOT NULL 컬럼을 더하려면
-- 그 행들이 채워질 값이 있어야 하고, 되풀이하지 않던 일정은 전부 `none` 이 맞다.
SET @stmt := IF(@has_repeat = 1,
    'SELECT ''[A] 이미 있음 — 지나간다'' AS message',
    'ALTER TABLE `schedule`
       ADD COLUMN `repeat_kind` varchar(10) NOT NULL DEFAULT ''none'',
       ADD COLUMN `repeat_until` date DEFAULT NULL,
       ADD COLUMN `origin_id` bigint DEFAULT NULL,
       ADD CONSTRAINT `ck_schedule_repeat`
           CHECK (`repeat_kind` in (''none'',''daily'',''weekly'',''monthly'')),
       ADD CONSTRAINT `fk_schedule_origin` FOREIGN KEY (`origin_id`)
           REFERENCES `schedule` (`id`) ON DELETE CASCADE');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- DEFAULT 를 **떼어 낸다**. 있는 행을 채우려고 잠깐 빌린 것이지, 엔티티가 만드는 컬럼에는
-- 없다(`01_schema.sql` 이 정본이다). 남겨 두면 새로 세운 DB 와 마이그레이션한 DB 가
-- 달라지고, 그 차이는 `validate` 도 안 잡는다.
SET @stmt := IF(@has_repeat = 1,
    'SELECT ''[A] 이미 있음 — DEFAULT 도 손대지 않는다'' AS message',
    'ALTER TABLE `schedule` ALTER COLUMN `repeat_kind` DROP DEFAULT');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;


-- ── B. 예외 표 ───────────────────────────────────────────
CREATE TABLE IF NOT EXISTS `schedule_exception` (
  `schedule_id` bigint NOT NULL,
  `on_date` date NOT NULL,
  `kind` varchar(10) NOT NULL,
  PRIMARY KEY (`on_date`,`schedule_id`),
  KEY `fk_schedexc_schedule` (`schedule_id`),
  CONSTRAINT `fk_schedexc_schedule` FOREIGN KEY (`schedule_id`)
    REFERENCES `schedule` (`id`) ON DELETE CASCADE,
  CONSTRAINT `ck_schedule_exception_kind` CHECK (`kind` in ('skip','override'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;


-- ── D. 사후 검증 ─────────────────────────────────────────
SET @d_cols := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'schedule'
      AND column_name IN ('repeat_kind', 'repeat_until', 'origin_id'));

-- 규칙을 지우면 옮겨 둔 하루도 함께 사라져야 한다. 안 그러면 그 행이 무엇의 하루였는지
-- 아무도 모르는 채로 남는다.
SET @d_origin_cascade := (
    SELECT COUNT(*) FROM information_schema.referential_constraints
    WHERE constraint_schema = DATABASE() AND constraint_name = 'fk_schedule_origin'
      AND delete_rule = 'CASCADE');
-- 예외도 마찬가지다 — 규칙이 없는 예외는 아무 일도 안 한다.
SET @d_exc_cascade := (
    SELECT COUNT(*) FROM information_schema.referential_constraints
    WHERE constraint_schema = DATABASE() AND constraint_name = 'fk_schedexc_schedule'
      AND delete_rule = 'CASCADE');
-- 한 규칙의 한 날짜에 예외는 하나뿐이다.
SET @d_exc_pk := (
    SELECT COUNT(*) FROM information_schema.statistics
    WHERE table_schema = DATABASE() AND table_name = 'schedule_exception'
      AND index_name = 'PRIMARY');
-- DEFAULT 가 남아 있으면 새로 세운 DB 와 갈린다(A 절 참조).
SET @d_no_default := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'schedule'
      AND column_name = 'repeat_kind' AND column_default IS NULL);
-- 되풀이하지 않던 행은 전부 none 이어야 한다.
SET @d_backfilled := (SELECT COUNT(*) FROM `schedule` WHERE `repeat_kind` IS NULL);

SELECT '[D] 사후 검증' AS section,
       @d_cols            AS repeat_columns_expect_3,
       @d_origin_cascade  AS origin_cascade_expect_1,
       @d_exc_cascade     AS exception_cascade_expect_1,
       @d_exc_pk          AS exception_pk_columns_expect_2,
       @d_backfilled      AS rows_with_null_repeat_expect_0,
       @d_no_default      AS repeat_kind_without_default_expect_1;

SET @stmt := IF(@d_cols = 3 AND @d_origin_cascade = 1 AND @d_exc_cascade = 1
                AND @d_exc_pk = 2 AND @d_backfilled = 0 AND @d_no_default = 1,
    'SELECT ''[D] 통과 — 반복 컬럼 셋 · 예외 표 · CASCADE 둘'' AS message',
    'CALL heattrip_migration_abort(''ABORT: 사후 검증 실패. 위 [D] 행의 숫자를 확인하라.'')');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

DROP PROCEDURE IF EXISTS heattrip_migration_abort;
