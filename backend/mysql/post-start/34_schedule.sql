-- ============================================================================
-- 34_schedule.sql
-- 앞으로 할 일을 적는 자리 — 이슈 #418 (부모 #416)
-- 대상: MySQL 8.x (운영/개발 공통)
--
-- ─────────────────────────────────────────────────
-- 무엇을 하나
--
--   CREATE TABLE schedule (...)
--
-- 지금 앱은 **지나간 일만** 안다. `care_log` 는 "누가 언제 했다" 이고(`occurred_at` 이 서버
-- 시계라 미래를 못 넣는다), `walk` 은 끝난 산책이다. 앞으로 할 일을 적을 자리가 한 곳도 없다.
--
-- 그래서 가족은 병원 일정을 **채팅으로** 조율하고, 그 결정은 스크롤 위로 사라진다
-- (`docs/00-product/feature-family-care.md` S3 가 그 장면을 그대로 적고 있다).
--
-- ─────────────────────────────────────────────────
-- owner_kind + owner_ref — chat_room 과 같은 방식이다
--
-- 일정의 주인이 셋이다: **아이**("보리 심장사상충 약") · **가족 그룹**("토요일 병원, 아빠
-- 담당") · **크루**("토요일 합동 산책", #417). 셋을 표 셋으로 나누면 "합쳐 보기" 가 매번
-- UNION 이 되고, 화면 하나가 그중 하나를 빠뜨리는 날이 온다.
--
-- `chat_room` 이 이미 이 문제를 이렇게 풀었다(ADR-0011) — `origin_kind`(어느 도메인) +
-- `origin_ref`(그 도메인의 id)를 **불투명하게** 든다. 같은 방식을 쓴다.
--
-- **FK 를 안 건다.** 세 도메인을 가리키는 컬럼 하나에 FK 를 걸 수 없다. `chat_room` 이
-- 같은 이유로 안 걸고, 그 대신 서비스가 소유권을 확인한다.
--
-- ─────────────────────────────────────────────────
-- dog_id 는 owner 와 별개다
--
-- "가족 소유인데 보리 것" 이 흔하다. owner 로만 두면 그 일정이 어느 아이 것인지 적을 자리가
-- 없고, dog_id 로만 두면 "사료 주문" 처럼 아이 하나에 안 묶이는 일을 못 적는다.
--
-- `ON DELETE SET NULL` — 아이를 지워도 그날 병원에 갔다는 계획은 남는다. `care_log.dog_id`
-- 가 같은 답을 골랐다(#154).
--
-- ─────────────────────────────────────────────────
-- at_time 이 NULL 일 수 있다
--
-- 시각 없는 일정이 많다 — "이번 주말 목욕". 0시로 채워 넣으면 화면이 "00:00 목욕" 이라고
-- 적게 되고, 그건 사용자가 안 정한 것을 정한 것처럼 보이게 한다.
--
-- ─────────────────────────────────────────────────
-- version — 낙관적 잠금
--
-- 가족 여럿이 같은 일정을 고친다. 실시간 공동 편집은 안 한다(소켓이 아직 없고, 일정은 초당
-- 여러 번 고치는 것이 아니다). 대신 뒤에 온 쪽이 409 를 받고 최신 값을 본다 — 조용히
-- 덮어쓰면 아빠가 옮긴 병원 시각이 엄마의 옛 화면으로 되돌아간다.
--
-- ─────────────────────────────────────────────────
-- 인덱스
--
--   idx_schedule_owner_date (owner_kind, owner_ref, on_date)
--     달력이 묻는 유일한 질문 — "이 주인의 이 기간". 세 컬럼이 그 순서다.
--
--   idx_schedule_dog_date (dog_id, on_date)
--     "보리 것만" 필터. dog_id 로 시작하지 않으면 위 인덱스를 못 쓴다.
--
-- ─────────────────────────────────────────────────
-- 같은 이름의 옛 표가 운영 DB 에 있다 — 지우지 않고 옆으로 옮긴다
--
-- 감정 여행 시절에 `schedule` 이라는 표가 있었다 — 여행 일정
-- (`schedule_id, user_id, title, content, date_from, date_to, created_at, updated_at`)이고
-- `journey.schedule_id` 가 그것을 가리킨다. 코드는 #94 가 지웠지만 **표는 남겨 뒀다**
-- (`docs/03-database/schema.md` 부록 A 가 그 목록을 들고 있다).
--
-- 실측으로 확인했다 — dev DB(localhost:3306 heat_trip_db)에 그 표가 그대로 있고 컬럼 여덟에
-- 들어오는 FK 가 `journey.schedule_id` 하나다.
--
-- **지우지 않는다.** 사람이 적어 둔 행이고 이 마이그레이션이 결정할 일이 아니다. 대신
-- `schedule_legacy_journey` 로 **이름만 옮긴다**:
--
--   * `RENAME TABLE` 은 그 표를 가리키는 FK 를 MySQL 이 함께 고쳐 준다 — `journey` 는
--     그대로 붙어 있다. 사후 검증이 그것을 잰다.
--   * 되돌리기는 이름을 되돌리는 것이다. 값은 한 줄도 안 잃는다.
--   * 이미 `schedule_legacy_journey` 가 있으면 **멈춘다** — 두 번 옮길 자리가 아니고,
--     그 상황은 사람이 봐야 한다.
--
-- ─────────────────────────────────────────────────
-- 실행 순서
--
--   1. 01_users.sql · dog 표가 먼저 있어야 한다. 없으면 시작하지 않는다.
--   2. 이 스크립트를 실행한다 — 새 애플리케이션을 배포하기 **전**(prod 는 validate).
--
-- 멱등: 표가 이미 있으면 지나간다. 있는데 컬럼이 모자라면 고치지 않고 멈춘다.
--
-- ─────────────────────────────────────────────────
-- 되돌리기(DOWN)
--
--   DROP TABLE schedule;
--   RENAME TABLE schedule_legacy_journey TO schedule;   -- 옛 표가 있었다면
--
-- 사람들이 적어 둔 일정이 전부 사라진다. 되돌리기 전에 앱을 먼저 내린다.
-- ============================================================================


-- ── 0. 사전 점검 ─────────────────────────────────────────
SET NAMES utf8mb4;

DROP PROCEDURE IF EXISTS heattrip_migration_abort;
CREATE PROCEDURE heattrip_migration_abort(IN msg VARCHAR(128))
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = msg;

SET @has_users := (
    SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name = 'users');
SET @has_dog := (
    SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name = 'dog');

SET @stmt := IF(@has_users = 1 AND @has_dog = 1,
    'SELECT ''[0-1] users · dog 확인'' AS message',
    'CALL heattrip_migration_abort(''ABORT: users 또는 dog 표가 없다. 01_users.sql 을 먼저 돌려라.'')');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @has_schedule := (
    SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name = 'schedule');

-- 옛 표인가. 감정 여행 시절의 `schedule` 은 PK 가 `schedule_id` 였다 — 새 표에는 그 이름의
-- 컬럼이 없으므로 이 한 칸으로 둘을 가른다.
SET @is_legacy := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'schedule'
      AND column_name = 'schedule_id');

SET @legacy_parked := (
    SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name = 'schedule_legacy_journey');

SELECT '[0] 사전 점검' AS section,
       @has_schedule    AS schedule_already,
       @is_legacy       AS looks_like_the_old_travel_table,
       @legacy_parked   AS legacy_already_parked;


-- ── 0-3. 옛 표를 옆으로 옮긴다 ───────────────────────────
-- 지우지 않는다 — 헤더 주석 참조. 두 번 옮길 자리가 없으므로 이미 옮겨져 있는데 또 옛
-- 표가 있으면 멈춘다.
SET @stmt := IF(@is_legacy = 1 AND @legacy_parked = 1,
    'CALL heattrip_migration_abort(''ABORT: schedule 이 옛 표인데 schedule_legacy_journey 도 이미 있다. 사람이 확인하라.'')',
    'SELECT ''[0-3] 옛 표 점검'' AS message');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @stmt := IF(@is_legacy = 1,
    'RENAME TABLE `schedule` TO `schedule_legacy_journey`',
    'SELECT ''[0-3] 옮길 옛 표가 없다'' AS message');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- 옮겼으면 이제 이 이름은 비어 있다.
SET @has_schedule := IF(@is_legacy = 1, 0, @has_schedule);


-- ── 0-4. 새 표가 이미 있으면 컬럼이 다 있는지만 본다 ─────
-- 모자라면 멈춘다 — 반쪽짜리 표에 앱을 붙이면 validate 가 부팅에서 죽거나, 더 나쁘게는
-- 죽지 않고 일정을 조용히 잃는다.
SET @cols := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'schedule'
      AND column_name IN ('id','owner_kind','owner_ref','dog_id','kind','title','memo',
                          'on_date','at_time','assignee','status','done_at','version',
                          'created_by','updated_by','created_at','updated_at'));

SET @stmt := IF(@has_schedule = 0 OR @cols = 17,
    'SELECT ''[0-4] schedule 점검'' AS message',
    'CALL heattrip_migration_abort(''ABORT: schedule 표가 이미 있는데 컬럼이 모자라다. 사람이 확인하라.'')');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;


-- ── A. 표 ────────────────────────────────────────────────
--
-- 컬럼 타입은 `mysql/init/01_schema.sql` 과 **같아야 한다**. 그 파일은 엔티티에서 뽑은 것이고
-- (`SchemaDdlDriftTest`), prod 는 `ddl-auto=validate` 다 — `time` 과 `time(6)` 처럼 사소해
-- 보이는 차이가 부팅을 막는다. DEFAULT 를 안 붙인 것도 같은 이유다(엔티티가 늘 채워 넣는다).
CREATE TABLE IF NOT EXISTS `schedule` (
  `id` bigint NOT NULL AUTO_INCREMENT,
  `owner_kind` varchar(10) NOT NULL,
  `owner_ref` bigint NOT NULL,
  `dog_id` bigint DEFAULT NULL,
  `kind` varchar(10) NOT NULL,
  `title` varchar(100) NOT NULL,
  `memo` varchar(500) DEFAULT NULL,
  `on_date` date NOT NULL,
  `at_time` time(6) DEFAULT NULL,
  `assignee` bigint DEFAULT NULL,
  `status` varchar(10) NOT NULL,
  `done_at` datetime(6) DEFAULT NULL,
  `version` int NOT NULL,
  `created_by` bigint NOT NULL,
  `updated_by` bigint DEFAULT NULL,
  `created_at` datetime(6) NOT NULL,
  `updated_at` datetime(6) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_schedule_owner_date` (`owner_kind`,`owner_ref`,`on_date`),
  KEY `idx_schedule_dog_date` (`dog_id`,`on_date`),
  KEY `fk_schedule_assignee` (`assignee`),
  KEY `fk_schedule_created_by` (`created_by`),
  KEY `fk_schedule_updated_by` (`updated_by`),
  CONSTRAINT `fk_schedule_dog` FOREIGN KEY (`dog_id`) REFERENCES `dog` (`id`) ON DELETE SET NULL,
  CONSTRAINT `fk_schedule_assignee` FOREIGN KEY (`assignee`) REFERENCES `users` (`id`) ON DELETE SET NULL,
  CONSTRAINT `fk_schedule_created_by` FOREIGN KEY (`created_by`) REFERENCES `users` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_schedule_updated_by` FOREIGN KEY (`updated_by`) REFERENCES `users` (`id`) ON DELETE SET NULL,
  CONSTRAINT `ck_schedule_owner_kind` CHECK (`owner_kind` in ('dog','group','room')),
  CONSTRAINT `ck_schedule_kind` CHECK (`kind` in ('walk','vet','med','groom','bath','food','etc')),
  CONSTRAINT `ck_schedule_status` CHECK (`status` in ('planned','done','skipped'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;


-- ── D. 사후 검증 ─────────────────────────────────────────
SET @d_table := (
    SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name = 'schedule');
SET @d_cols := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'schedule'
      AND column_name IN ('id','owner_kind','owner_ref','dog_id','kind','title','memo',
                          'on_date','at_time','assignee','status','done_at','version',
                          'created_by','updated_by','created_at','updated_at'));

-- 아이를 지워도 계획은 남아야 한다. CASCADE 로 들어가면 아이를 보낸 사람이 그 아이와
-- 함께 적어 둔 것을 통째로 잃는다.
SET @d_fk_dog := (
    SELECT COUNT(*) FROM information_schema.referential_constraints
    WHERE constraint_schema = DATABASE() AND constraint_name = 'fk_schedule_dog'
      AND delete_rule = 'SET NULL');
-- 담당자가 탈퇴해도 일정은 남는다 — care_log.done_by 와 같은 답이다.
SET @d_fk_assignee := (
    SELECT COUNT(*) FROM information_schema.referential_constraints
    WHERE constraint_schema = DATABASE() AND constraint_name = 'fk_schedule_assignee'
      AND delete_rule = 'SET NULL');
SET @d_idx := (
    SELECT COUNT(DISTINCT index_name) FROM information_schema.statistics
    WHERE table_schema = DATABASE() AND table_name = 'schedule'
      AND index_name IN ('idx_schedule_owner_date','idx_schedule_dog_date'));
-- at_time 은 NULL 을 받아야 한다. NOT NULL 이면 "이번 주말 목욕" 이 00:00 이 된다.
SET @d_time_nullable := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'schedule'
      AND column_name = 'at_time' AND is_nullable = 'YES');

-- 옛 표를 옮겼다면 그것이 그대로 있어야 한다. 값을 잃지 않았다는 증거다.
SET @d_legacy_kept := IF(@is_legacy = 0, 1, (
    SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name = 'schedule_legacy_journey'));
-- 그리고 그 표를 가리키던 FK 도 함께 따라가야 한다 — MySQL 의 RENAME TABLE 이 하는 일이다.
-- 안 따라가면 journey 가 새 schedule 을 가리키게 되고, 그건 남의 표에 남의 id 다.
SET @d_legacy_fk_moved := (
    SELECT COUNT(*) FROM information_schema.key_column_usage
    WHERE table_schema = DATABASE() AND referenced_table_name = 'schedule');

SELECT '[D] 사후 검증' AS section,
       @d_table            AS schedule_table_expect_1,
       @d_cols             AS columns_expect_17,
       @d_fk_dog           AS fk_dog_set_null_expect_1,
       @d_fk_assignee      AS fk_assignee_set_null_expect_1,
       @d_idx              AS indexes_expect_2,
       @d_time_nullable    AS at_time_nullable_expect_1,
       @d_legacy_kept      AS legacy_table_kept_expect_1,
       @d_legacy_fk_moved  AS inbound_fks_to_new_schedule_expect_0;

SET @stmt := IF(@d_table = 1 AND @d_cols = 17 AND @d_fk_dog = 1 AND @d_fk_assignee = 1
                AND @d_idx = 2 AND @d_time_nullable = 1 AND @d_legacy_kept = 1
                AND @d_legacy_fk_moved = 0,
    'SELECT ''[D] 통과 — schedule 표 · dog/담당자 SET NULL · 인덱스 둘 · at_time NULL 허용 · 옛 표 보존'' AS message',
    'CALL heattrip_migration_abort(''ABORT: 사후 검증 실패. 위 [D] 행의 숫자를 확인하라.'')');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

DROP PROCEDURE IF EXISTS heattrip_migration_abort;
