-- ============================================================================
-- 51_care_log_custom_type.sql
-- 직접 만든 항목의 기록을 담을 수 있게 care_log.type 을 NULL 허용으로 — 이슈 #560
-- 대상: MySQL 8.x (운영/개발 공통)
--
-- ─────────────────────────────────────────────────
-- 무엇을 하나
--
--   care_log.type 을 NOT NULL → NULL 허용으로 넓힌다. 그것뿐이다.
--
-- 컬럼의 폭도 타입도 그대로다. 옛 행은 한 줄도 안 바뀐다.
--
-- ─────────────────────────────────────────────────
-- 왜 필요한가
--
-- #560 이 목록을 표로 내리면서 사용자가 "양치" 를 만들 수 있게 됐다(50_care_item.sql).
-- 그런데 그 항목을 누르면 **넣을 값이 없다** — type 은 NOT NULL 이고 CHECK 가 일곱 값만
-- 받는다. 일곱 중 아무거나 넣으면 그 칸이 양치 기록을 함께 세고('meal' 을 넣으면 밥 칸이
-- 하루에 두 번으로 보인다), 'custom' 같은 값을 더하면 종류가 아닌 것이 종류 목록에 들어앉아
-- 앱·계약·DB 세 곳의 enum 이 다 넓어진다.
--
-- 그래서 "종류" 를 **기본 일곱일 때만 있는 것**으로 정했다.
--
--   기본 일곱의 기록  →  type 이 있다 (care_item_id 도 함께 든다)
--   직접 만든 항목     →  type 이 없고 care_item_id 만 있다
--
-- 세는 쪽도 이 갈래를 그대로 쓴다: system_type 이 있는 항목은 care_log.type 으로,
-- 없는 항목은 care_log.care_item_id 로 센다. **이미 쌓인 기록을 한 행도 안 건드린다.**
--
-- ─────────────────────────────────────────────────
-- 왜 CHECK 를 못 거나 — 실측
--
-- "종류도 항목도 없는 행" 은 어느 칸의 기록도 아니라 화면에 안 뜨고, 안 뜨니 지울 수도 없다.
-- 그래서 CHECK (type IS NOT NULL OR care_item_id IS NOT NULL) 을 걸려고 했는데 MySQL 8 이
-- 거절한다:
--
--   Column 'care_item_id' cannot be used in a check constraint 'ck_carelog_source':
--   needed in a foreign key constraint 'fk_carelog_item' referential action.
--
-- SET NULL 로 값을 쓰는 FK 가 걸린 컬럼은 CHECK 에서 못 읽는다. fk_carelog_item 의 SET NULL 은
-- "항목을 지워도 기록은 남는다" 라서 포기할 수 없는 쪽이다. 그래서 이 불변식은 서버가 지킨다
-- (CareService.record — type 과 careItemId 는 정확히 하나). DB 가 마지막 방어선이라는 원칙
-- (📌 #86 원칙 5)을 여기서는 못 지킨다는 뜻이고, 그게 사실이라 그대로 적는다.
--
-- ck_carelog_type 은 **그대로 둔다.** MySQL 의 CHECK 는 값이 NULL 이면 UNKNOWN 이라
-- 통과하므로, 일곱 값 제약과 NULL 허용이 서로 부딪히지 않는다.
--
-- ─────────────────────────────────────────────────
-- 실행 순서
--
--   1. 08_care_log.sql · 29_care_type_poop.sql · 50_care_item.sql 이 먼저 돌아 있어야 한다.
--      50 이 care_item_id 컬럼을 만든다 — 없으면 아래 CHECK 를 걸 수 없다.
--   2. 이 스크립트를 실행한다 — 새 애플리케이션을 배포하기 **전**.
--      prod 는 ddl-auto=validate 인데 validate 는 **NULL 허용 여부를 본다.** 엔티티가
--      nullable 인데 컬럼이 NOT NULL 이면 **부팅이 막힌다**(CHECK 만 고쳤던 29 와 다른 점이다).
--
-- 멱등: 이미 NULL 허용이면 지나간다.
--
-- ─────────────────────────────────────────────────
-- 되돌리기(DOWN)
--
--   DELETE FROM care_log WHERE type IS NULL;   -- 남아 있으면 아래가 실패한다
--   ALTER TABLE care_log MODIFY type VARCHAR(10) NOT NULL COMMENT 'water|meal|walk|med|vet|poop|pee';
--
-- **되돌리면 직접 만든 항목의 기록을 잃는다.** 행을 지우지 않고 컬럼만 좁히면 그 ALTER 가
-- 거절당한다 — 그게 안전한 쪽이라 순서를 이렇게 적는다.
-- ============================================================================


-- ── 0. 사전 점검 ─────────────────────────────────────────
SET NAMES utf8mb4;

DROP PROCEDURE IF EXISTS heattrip_migration_abort;
CREATE PROCEDURE heattrip_migration_abort(IN msg VARCHAR(160))
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = msg;

SET @has_table := (
    SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name = 'care_log');

SET @stmt := IF(@has_table = 1,
    'SELECT ''[0-1] care_log 확인'' AS message',
    'CALL heattrip_migration_abort(''ABORT: care_log 표가 없다. 08_care_log.sql 을 먼저 돌려라.'')');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- 50 이 먼저다. care_item_id 가 없으면 '종류도 항목도 없는 행' 자체가 성립하지 않고,
-- §D 가 그것을 못 센다.
SET @has_item_col := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'care_log' AND column_name = 'care_item_id');

SET @stmt := IF(@has_item_col = 1,
    'SELECT ''[0-2] care_item_id 확인'' AS message',
    'CALL heattrip_migration_abort(''ABORT: care_log.care_item_id 가 없다. 50_care_item.sql 을 먼저 돌려라.'')');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @nullable_before := (
    SELECT IFNULL(MAX(is_nullable), 'NO') FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'care_log' AND column_name = 'type');

SET @rows_before := (SELECT COUNT(*) FROM care_log);

SELECT '[0] 사전 점검' AS section,
       @nullable_before AS type_nullable_before,
       @rows_before     AS care_log_rows;


-- ── A. type 을 NULL 허용으로 ─────────────────────────────
-- 코멘트를 함께 다시 적는다. MODIFY 는 컬럼 정의를 통째로 바꾸므로 빼면 코멘트가 사라진다.
SET @stmt := IF(@nullable_before = 'NO',
    'ALTER TABLE care_log MODIFY type VARCHAR(10) NULL COMMENT ''기본 일곱이면 그 종류, 직접 만든 항목이면 NULL (#560)''',
    'SELECT ''[A] 이미 NULL 허용 — 건너뜀'' AS message');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;


-- ── D. 사후 검증 ─────────────────────────────────────────
SET @d_nullable := (
    SELECT IFNULL(MAX(is_nullable), 'NO') FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'care_log' AND column_name = 'type');

-- 일곱 값 제약을 흘리면 오타가 조용히 저장된다. 넓히면서 잃지 않았는지 본다.
SET @d_type_check := (
    SELECT COUNT(*) FROM information_schema.check_constraints
    WHERE constraint_schema = DATABASE() AND constraint_name = 'ck_carelog_type'
      AND check_clause LIKE '%poop%');

-- 행 수가 그대로여야 한다. 넓히는 변경이라 한 행도 지워지면 안 된다.
SET @d_rows := (SELECT COUNT(*) FROM care_log);

-- 유령(종류도 항목도 없는 행)이 이미 있으면 안 된다. DB 가 못 막는 자리라 여기서 센다 —
-- 0 이 아니면 서버의 검증을 지나온 경로가 아니라는 뜻이고, 사람이 봐야 한다.
SET @d_orphan := (
    SELECT COUNT(*) FROM care_log WHERE type IS NULL AND care_item_id IS NULL);

-- fk_carelog_item 이 그대로 있는지도 본다. CHECK 를 걸려던 시도가 이 FK 를 죽이는 것을
-- 실측으로 봤다(엔티티 javadoc) — 그 자리를 여기서도 한 번 더 지킨다.
SET @d_fk_item := (
    SELECT COUNT(*) FROM information_schema.referential_constraints
    WHERE constraint_schema = DATABASE() AND table_name = 'care_log'
      AND constraint_name = 'fk_carelog_item' AND delete_rule = 'SET NULL');

SELECT '[D] 사후 검증' AS section,
       @d_nullable   AS type_nullable_expect_YES,
       @d_type_check AS type_check_kept_expect_1,
       @d_fk_item    AS fk_item_setnull_expect_1,
       @d_rows       AS rows_same,
       @d_orphan     AS orphans_expect_0;

SET @abort_msg := CONCAT(
    'ABORT: 사후 검증 실패 — type NULL허용 ', @d_nullable, '(YES여야 한다), ',
    'ck_carelog_type(poop) ', @d_type_check, '/1, fk_carelog_item(SET NULL) ', @d_fk_item, '/1, ',
    '행 ', @d_rows, '(', @rows_before, ' 이어야 한다), 유령 ', @d_orphan, '(0이어야 한다).');
SET @stmt := IF(@d_nullable = 'YES' AND @d_type_check = 1 AND @d_fk_item = 1
                AND @d_rows = @rows_before AND @d_orphan = 0,
    'SELECT ''[D] 통과'' AS message',
    'CALL heattrip_migration_abort(@abort_msg)');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

DROP PROCEDURE IF EXISTS heattrip_migration_abort;

SELECT '51_care_log_custom_type.sql 완료' AS message;
