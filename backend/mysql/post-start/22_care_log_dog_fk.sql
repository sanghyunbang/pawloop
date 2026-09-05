-- ============================================================================
-- 22_care_log_dog_fk.sql
-- care_log.dog_id 를 dog 에 잇는다 — 이슈 #154
-- 대상: MySQL 8.x (운영/개발 공통)
--
-- ─────────────────────────────────────────────────
-- 무엇을 하나
--
--   care_log.dog_id  →  dog(id)   FK fk_carelog_dog, ON DELETE SET NULL
--   idx_carelog_dog (dog_id, occurred_at)
--
-- 08_care_log.sql 은 dog_id 컬럼을 NULL 허용으로만 만들고 FK 를 걸지 않았다. 그때는
-- CareLog 가 dog_id 를 스칼라 Long 으로 들고 있어서 Hibernate 가 FK 를 만들지 않았고,
-- 여기서 ALTER 로 더하면 운영 DB 에는 있고 커밋된 스키마(01_schema.sql — 엔티티로 만든
-- DB 에서 뽑은 파일)에는 없는 제약이 되어 다음 재생성 때 조용히 사라졌기 때문이다.
-- #154 에서 CareLog 가 @ManyToOne Dog 를 들게 됐다. 이제 FK 가 엔티티에서 나오므로
-- 새로 세우는 DB 는 01_schema.sql 이 걸고, 이미 있는 DB 는 이 스크립트가 같은 모양으로 건다.
--
-- ─────────────────────────────────────────────────
-- ON DELETE SET NULL 인 이유 (#154 완료 조건 4)
--
-- 케어는 "누가 언제 무엇을 했는가" 의 기록이라 반려동물이 지워져도 그 사실은 남아야 한다.
-- 같은 표의 group_id(가족 해산)·done_by(탈퇴)가 같은 질문에 같은 답을 했다. walk.dog_id 가
-- CASCADE 인 것과 다른 이유는 산책은 그 개의 기록이고 케어는 가족의 기록이기 때문이다.
--
-- 사용자 탈퇴(DELETE /auth/me, users 하드 삭제)는 fk_dog_user 로 dog 을 CASCADE 로 지우고,
-- 그 삭제가 여기를 SET NULL 로 훑는다. idx_carelog_dog 가 그 자리다 — 없으면 dog 한 마리
-- 삭제가 care_log 전체 스캔이다. RESTRICT 로 걸면 케어 기록이 있는 사람은 탈퇴를 못 한다.
--
-- ─────────────────────────────────────────────────
-- 값은 아직 항상 NULL 이다
--
-- POST /api/groups/{groupId}/care-logs 가 아직 dogId 를 받지 않는다. 받으려면 "가족
-- 구성원이 남의 반려동물 id 를 알 수 있는가" 가 먼저 정해져야 하고(#209 Dogs-high-3),
-- 그 전까지 FK 는 "잘못된 id 는 못 들어간다" 만 지킨다. 그래서 §0 의 고아 점검은 지금은
-- 항상 0 이다 — 누가 손으로 넣은 값이 있으면 멈춘다.
--
-- ─────────────────────────────────────────────────
-- 실행 순서
--
--   1. 08_care_log.sql(care_log) 과 11_dog.sql(dog) 이 먼저 돌아 있어야 한다. 없으면 시작하지 않는다.
--   2. 이 스크립트를 실행한다 — 앱 배포 전·후 어느 쪽이든 된다.
--
-- 순서 제약이 없는 이유: prod 의 ddl-auto=validate 는 표·컬럼만 보고 FK·인덱스는 안 본다.
-- 새 코드는 FK 가 있든 없든 돌고, 옛 코드도 마찬가지다. 그래도 배포 전에 돌리는 것을 권한다 —
-- 새 코드가 걸었다고 믿는 제약이 실제로 있는 상태로 시작하는 쪽이 낫다.
--
-- 트랜잭션으로 감쌀 수 없다 — MySQL 의 DDL 은 암묵적 커밋을 일으킨다. 그래서 앞뒤로
-- 관문을 둔다: §0 사전 점검 · §D 사후 검증.
--
-- 멱등: FK·인덱스가 이미 있으면 "이미 있음" 을 찍고 지나간다. 두 번 돌려도 같은 상태.
--
-- ─────────────────────────────────────────────────
-- 되돌리기(DOWN)
--
--   ALTER TABLE care_log DROP FOREIGN KEY fk_carelog_dog;
--   ALTER TABLE care_log DROP INDEX idx_carelog_dog;
--
-- 값은 건드리지 않으므로 되돌려도 잃는 것이 없다. 단, 되돌린 채 새 코드를 돌리면 엔티티가
-- 약속하는 제약이 DB 에 없는 상태다 — validate 는 그것을 못 잡는다.
-- ============================================================================


-- ── 0. 사전 점검 ─────────────────────────────────────────
SET NAMES utf8mb4;

DROP PROCEDURE IF EXISTS heattrip_migration_abort;
CREATE PROCEDURE heattrip_migration_abort(IN msg VARCHAR(128))
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = msg;

-- 0-1. 두 표가 있어야 한다.
SET @has_care_log := (
    SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name = 'care_log');
SET @has_dog := (
    SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name = 'dog');

SET @stmt := IF(@has_care_log = 1 AND @has_dog = 1,
    'SELECT ''[0-1] care_log · dog 확인'' AS message',
    'CALL heattrip_migration_abort(''ABORT: care_log 또는 dog 표가 없다. 08_care_log.sql 과 11_dog.sql 을 먼저 돌려라.'')');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- 0-2. dog_id 컬럼이 있고 NULL 허용이어야 한다. SET NULL 은 NULL 허용 컬럼에만 걸 수 있다.
SET @dog_id_nullable := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'care_log'
      AND column_name = 'dog_id' AND is_nullable = 'YES');

SET @stmt := IF(@dog_id_nullable = 1,
    'SELECT ''[0-2] care_log.dog_id NULL 허용 확인'' AS message',
    'CALL heattrip_migration_abort(''ABORT: care_log.dog_id 가 없거나 NOT NULL 이다. 08_care_log.sql 의 모양이 아니다 — 사람이 확인하라.'')');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- 0-3. 고아 — dog 에 없는 id 를 든 행. 있으면 FK 를 걸 수 없다. 앱은 이 컬럼에 값을 쓴 적이
--      없으므로 0 이어야 하고, 아니면 누가 손으로 넣은 것이다. 지우지 않고 멈춘다.
SET @orphans := (
    SELECT COUNT(*) FROM care_log c
    WHERE c.dog_id IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM dog d WHERE d.id = c.dog_id));

SET @stmt := IF(@orphans = 0,
    'SELECT ''[0-3] 고아 dog_id 0건 확인'' AS message',
    'CALL heattrip_migration_abort(''ABORT: dog 에 없는 dog_id 를 든 care_log 행이 있다(고아). 어느 값인지 사람이 확인하라.'')');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- 0-4. 이미 걸려 있나. 있는데 규칙이 SET NULL 이 아니면 옛 계획(fk_carelog_dog, 규칙 미정)을
--      손으로 걸어 둔 것이다 — 고치지 않고 멈춘다.
SET @fk_exists := (
    SELECT COUNT(*) FROM information_schema.referential_constraints
    WHERE constraint_schema = DATABASE() AND table_name = 'care_log'
      AND constraint_name = 'fk_carelog_dog');
SET @fk_wrong_rule := (
    SELECT COUNT(*) FROM information_schema.referential_constraints
    WHERE constraint_schema = DATABASE() AND table_name = 'care_log'
      AND constraint_name = 'fk_carelog_dog' AND delete_rule <> 'SET NULL');
SET @idx_exists := (
    SELECT COUNT(DISTINCT index_name) FROM information_schema.statistics
    WHERE table_schema = DATABASE() AND table_name = 'care_log'
      AND index_name = 'idx_carelog_dog');

SET @stmt := IF(@fk_wrong_rule = 0,
    'SELECT ''[0-4] 기존 FK 점검'' AS message',
    'CALL heattrip_migration_abort(''ABORT: fk_carelog_dog 가 이미 있는데 ON DELETE SET NULL 이 아니다. 사람이 확인하라.'')');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @rows_before := (SELECT COUNT(*) FROM care_log);

SELECT '[0] 사전 점검' AS section,
       @fk_exists   AS fk_already,
       @idx_exists  AS index_already,
       @orphans     AS orphans_expect_0,
       @rows_before AS care_log_rows;


-- ── A. 인덱스 ────────────────────────────────────────────
-- FK 보다 먼저 만든다 — 그래야 InnoDB 가 FK 용 인덱스를 따로(fk_carelog_dog 이름으로) 만들지
-- 않고 이 인덱스를 쓴다. (dog_id, occurred_at) 은 왼쪽 열이 dog_id 라 FK 가 그대로 탄다.
SET @stmt := IF(@idx_exists = 0,
    'ALTER TABLE care_log ADD INDEX idx_carelog_dog (dog_id, occurred_at)',
    'SELECT ''[A] idx_carelog_dog 이미 있음'' AS message');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;


-- ── B. FK ────────────────────────────────────────────────
SET @stmt := IF(@fk_exists = 0,
    'ALTER TABLE care_log
       ADD CONSTRAINT fk_carelog_dog FOREIGN KEY (dog_id)
       REFERENCES dog (id) ON DELETE SET NULL',
    'SELECT ''[B] fk_carelog_dog 이미 있음'' AS message');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;


-- ── D. 사후 검증 ─────────────────────────────────────────
SET @d_fk := (
    SELECT COUNT(*) FROM information_schema.referential_constraints
    WHERE constraint_schema = DATABASE() AND table_name = 'care_log'
      AND constraint_name = 'fk_carelog_dog'
      AND referenced_table_name = 'dog' AND delete_rule = 'SET NULL');

-- 인덱스는 이름만이 아니라 열 순서까지 본다 — (dog_id, occurred_at) 이어야 한다.
SET @d_idx := (
    SELECT COUNT(*) FROM information_schema.statistics
    WHERE table_schema = DATABASE() AND table_name = 'care_log'
      AND index_name = 'idx_carelog_dog'
      AND ((seq_in_index = 1 AND column_name = 'dog_id')
        OR (seq_in_index = 2 AND column_name = 'occurred_at')));

-- 컬럼은 그대로 NULL 허용이어야 한다.
SET @d_nullable := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'care_log'
      AND column_name = 'dog_id' AND is_nullable = 'YES');

-- 행은 건드리지 않는다.
SET @d_rows := (SELECT COUNT(*) FROM care_log);

SELECT '[D] 사후 검증' AS section,
       @d_fk       AS fk_set_null_expect_1,
       @d_idx      AS index_columns_expect_2,
       @d_nullable AS dog_id_nullable_expect_1,
       @d_rows     AS care_log_rows_same;

SET @stmt := IF(@d_fk = 1 AND @d_idx = 2 AND @d_nullable = 1 AND @d_rows = @rows_before,
    'SELECT ''[D] 통과 — fk_carelog_dog(SET NULL) · idx_carelog_dog(dog_id, occurred_at) · 행 수 그대로'' AS message',
    'CALL heattrip_migration_abort(''ABORT: 사후 검증 실패. 위 [D] 행의 숫자를 확인하라.'')');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

DROP PROCEDURE IF EXISTS heattrip_migration_abort;
