-- ============================================================================
-- 29_care_type_poop.sql
-- 케어 종류에 배변·마킹을 더한다 — 이슈 #340
-- 대상: MySQL 8.x (운영/개발 공통)
--
-- ─────────────────────────────────────────────────
-- 무엇을 하나
--
--   ALTER TABLE care_log DROP CHECK ck_carelog_type;
--   ALTER TABLE care_log ADD  CONSTRAINT ck_carelog_type
--     CHECK (type IN ('water','meal','walk','med','vet','poop','pee'));
--
-- 컬럼은 그대로다. type 은 VARCHAR(10) 이라 'poop'(4)·'pee'(3)가 그냥 들어간다 —
-- 이 스크립트가 넓히는 것은 **CHECK 제약 하나**뿐이다.
--
-- ─────────────────────────────────────────────────
-- 왜 필요한가
--
-- 산책 중에 일어나는 일을 그 자리에서 한 탭으로 남기는 화면이 생긴다(#340). 지금 케어는
-- 물·밥·산책·투약·병원 다섯이고, 배변과 마킹이 없다. 배변은 재미가 아니라 **건강 신호**다 —
-- 횟수와 시각이 쌓여야 "요즘 뜸하다" 를 말할 수 있다.
--
-- 물은 이미 있는 water 를 그대로 쓴다. 새 값은 둘이다.
--
--   poop  배변
--   pee   마킹(소변)
--
-- **위치는 여기 없다.** 어디서 눴는지는 기기에만 남는다(A안 #235) — 이 표에 좌표 컬럼을
-- 더하지 않는 것이 그 결정이다.
--
-- ─────────────────────────────────────────────────
-- 왜 CHECK 를 굳이 고치나 — 앱 검증이 있는데
--
-- DB 가 마지막 방어선이다(📌 #86 원칙 5). 지금 CHECK 가 다섯만 받으므로 애플리케이션이
-- 'poop' 을 보내면 **INSERT 자체가 실패한다** — 코드만 고치고 이 스크립트를 안 돌리면
-- 새 버튼이 서버에서 500 을 받는다.
--
-- 반대로 제약을 아예 없애는 선택은 하지 않았다. 그러면 오타 하나가 조용히 저장되고,
-- 그 값을 읽는 화면은 칸 하나가 비어 보이는 것으로만 알려 준다.
--
-- ─────────────────────────────────────────────────
-- 실행 순서
--
--   1. 08_care_log.sql(care_log) 이 먼저 돌아 있어야 한다.
--   2. 이 스크립트를 실행한다 — 새 애플리케이션을 배포하기 **전**.
--      prod 는 ddl-auto=validate 인데, validate 는 CHECK 를 보지 않으므로 부팅은 뜬다.
--      부팅이 아니라 **첫 배변 기록**이 실패한다. 그래서 배포 전이다.
--
-- 멱등: 이미 일곱 값이면 지나간다. 제약이 없으면 만든다.
--
-- ─────────────────────────────────────────────────
-- 되돌리기(DOWN)
--
--   DELETE FROM care_log WHERE type IN ('poop','pee');   -- 남아 있으면 아래가 실패한다
--   ALTER TABLE care_log DROP CHECK ck_carelog_type;
--   ALTER TABLE care_log ADD  CONSTRAINT ck_carelog_type
--     CHECK (type IN ('water','meal','walk','med','vet'));
--
-- **되돌리면 배변·마킹 기록을 잃는다.** 값을 지우지 않고 제약만 좁히면 그 ALTER 가
-- 거절당한다(MySQL 이 기존 행을 검사한다) — 그게 안전한 쪽이라 순서를 이렇게 적는다.
-- ============================================================================


-- ── 0. 사전 점검 ─────────────────────────────────────────
SET NAMES utf8mb4;

DROP PROCEDURE IF EXISTS heattrip_migration_abort;
CREATE PROCEDURE heattrip_migration_abort(IN msg VARCHAR(128))
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = msg;

SET @has_table := (
    SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name = 'care_log');

SET @stmt := IF(@has_table = 1,
    'SELECT ''[0-1] care_log 확인'' AS message',
    'CALL heattrip_migration_abort(''ABORT: care_log 표가 없다. 08_care_log.sql 을 먼저 돌려라.'')');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- 컬럼 폭이 모자라면 CHECK 를 넓혀도 값이 안 들어간다. 'poop' 은 네 글자다.
SET @type_len := (
    SELECT IFNULL(MAX(character_maximum_length), 0) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'care_log' AND column_name = 'type');

SET @stmt := IF(@type_len >= 5,
    'SELECT ''[0-2] type 폭 확인'' AS message',
    'CALL heattrip_migration_abort(''ABORT: care_log.type 이 다섯 글자보다 짧다. 사람이 확인하라.'')');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @clause_before := (
    SELECT IFNULL(MAX(check_clause), '') FROM information_schema.check_constraints
    WHERE constraint_schema = DATABASE() AND constraint_name = 'ck_carelog_type');

SET @already := IF(@clause_before LIKE '%poop%' AND @clause_before LIKE '%pee%', 1, 0);
SET @rows_before := (SELECT COUNT(*) FROM care_log);

SELECT '[0] 사전 점검' AS section,
       @already     AS already_widened,
       @rows_before AS care_log_rows;


-- ── A. 옛 제약을 떼어 낸다 ───────────────────────────────
-- 이미 넓혀져 있으면 건드리지 않는다. 제약이 아예 없는 DB(Hibernate 가 만든 표)도 있다.
SET @stmt := IF(@already = 0 AND @clause_before <> '',
    'ALTER TABLE care_log DROP CHECK ck_carelog_type',
    'SELECT ''[A] 뗄 제약 없음'' AS message');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;


-- ── B. 일곱 값으로 다시 건다 ─────────────────────────────
SET @stmt := IF(@already = 0,
    'ALTER TABLE care_log ADD CONSTRAINT ck_carelog_type CHECK (type IN (''water'',''meal'',''walk'',''med'',''vet'',''poop'',''pee''))',
    'SELECT ''[B] 이미 일곱 값'' AS message');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;


-- ── D. 사후 검증 ─────────────────────────────────────────
SET @clause_after := (
    SELECT IFNULL(MAX(check_clause), '') FROM information_schema.check_constraints
    WHERE constraint_schema = DATABASE() AND constraint_name = 'ck_carelog_type');

SET @d_poop  := IF(@clause_after LIKE '%poop%', 1, 0);
SET @d_pee   := IF(@clause_after LIKE '%pee%', 1, 0);
-- 넓히면서 옛 다섯 중 하나를 흘리면 오늘 쓰는 기록이 내일 안 들어간다.
SET @d_water := IF(@clause_after LIKE '%water%', 1, 0);
SET @d_meal  := IF(@clause_after LIKE '%meal%', 1, 0);
SET @d_walk  := IF(@clause_after LIKE '%walk%', 1, 0);
SET @d_med   := IF(@clause_after LIKE '%med%', 1, 0);
SET @d_vet   := IF(@clause_after LIKE '%vet%', 1, 0);
SET @d_rows  := (SELECT COUNT(*) FROM care_log);

SELECT '[D] 사후 검증' AS section,
       @d_poop  AS has_poop_expect_1,
       @d_pee   AS has_pee_expect_1,
       @d_water AS has_water_expect_1,
       @d_vet   AS has_vet_expect_1,
       @d_rows  AS care_log_rows_same;

SET @stmt := IF(@d_poop = 1 AND @d_pee = 1 AND @d_water = 1 AND @d_meal = 1
                AND @d_walk = 1 AND @d_med = 1 AND @d_vet = 1 AND @d_rows = @rows_before,
    'SELECT ''[D] 통과 — ck_carelog_type 이 일곱 값을 받는다 · 행 수 그대로'' AS message',
    'CALL heattrip_migration_abort(''ABORT: 사후 검증 실패. 위 [D] 행의 숫자를 확인하라.'')');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

DROP PROCEDURE IF EXISTS heattrip_migration_abort;
