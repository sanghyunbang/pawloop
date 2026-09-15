-- ============================================================================
-- 49_walk_walked_by.sql — 산책에 "누가 걸었나" (이슈 #563)
--
-- 왜 필요한가
--
-- 이 앱의 목적은 **업무 분담과 누락 방지**다(#76). 그런데 walk 표에 사람 컬럼이 없다.
-- 산책의 주인이 **아이의 주인**이다.
--
--   select w from Walk w join fetch w.dog d where d.user.id = :userId
--
-- 그래서 아빠가 엄마 아이 보리를 산책시키면
--   · 지금은 저장 자체가 거절되고(requireMineEntity),
--   · 소유 검사만 풀면 그 기록이 **엄마 목록에만** 간다. 아빠는 방금 걸은 경로를 못 본다.
--
-- 그리고 "누가 걸었나" 를 물어볼 자리가 표에 없다. 지금 케어 카드가 "아빠가 아침에
-- 걸었어요" 를 그릴 수 있는 것은 산책이 **케어 로그를 한 줄 따로 남기기** 때문이고
-- (그 줄에는 done_by 가 있다), 산책 기록 자체에는 없다.
--
-- 무엇을 하나
--
--   walk.walked_by BIGINT NULL — 걸은 사람(users.id). FK 는 ON DELETE SET NULL.
--   이미 쌓인 행은 dog.user_id 로 채운다.
--
-- 옛 행을 채우는 것이 지어내기가 아닌 이유
--
-- 이 마이그레이션 전에는 **남의 아이로 산책을 저장할 수 없었다**(requireMineEntity).
-- 그래서 그때의 "아이 주인" 은 곧 "걸은 사람" 이다. 추측이 아니라 그 시절 규칙의 결과다.
--
-- 왜 NULL 을 허용하나
--
-- 사람이 탈퇴하면 SET NULL 로 떨어진다. care_log.done_by 와 같은 판단이다(08_care_log.sql):
-- 걸은 사람이 계정을 지웠다고 **그 산책이 없던 일이 되면 안 된다.** 기록의 주인은
-- 아이이고 그 아이는 살아 있다. 이름은 응답에서 '알 수 없음' 으로 떨어진다.
--
-- 실행
--
--   mysql -u root -p heattrip < mysql/post-start/49_walk_walked_by.sql
--
-- **12_walk.sql 과 11_dog.sql 이 먼저다.** 멱등하다 — 두 번 돌려도 같은 상태로 끝난다.
--
-- 되돌리기
--
--   ALTER TABLE walk DROP FOREIGN KEY fk_walk_walkedby;
--   ALTER TABLE walk DROP COLUMN walked_by;
--
-- 되돌리면 "누가 걸었나" 가 사라진다. 옛 행은 dog.user_id 로 다시 만들 수 있지만,
-- 이 마이그레이션 **뒤에** 남이 걸어 준 산책은 다시 만들 수 없다.
--
-- ----------------------------------------------------------------------------
-- 안 하는 것
--
-- 1. **NOT NULL 로 안 만든다.** 위의 SET NULL 과 같은 이유다.
-- 2. **인덱스를 안 만든다.** 조회의 축은 여전히 아이다("우리 집 아이의 산책").
--    walked_by 로 거르는 화면이 생기면 그때 만든다.
-- 3. **walk 에 group_id 를 안 더한다.** "우리 집" 은 아이에서 파생한다(#563 조각 1) —
--    컬럼으로 두면 가족에 들어오고 나갈 때마다 옮기는 코드가 생긴다.
-- ============================================================================


-- ── 0. 사전 점검 ────────────────────────────────────────────────────────────
-- 여기서 걸리면 스키마는 한 글자도 바뀌지 않는다.

-- 이 파일은 UTF-8 이고 중단 메시지가 한글이다. 세션 문자셋을 먼저 고정한다 —
-- 안 하면 클라이언트 기본값(윈도우 mysql 은 euckr)을 물려받아, 중단이 걸리는 순간
-- 이유는 안 보이고 ERROR 1366 (Incorrect string value) 만 남는다.
SET NAMES utf8mb4;

DROP PROCEDURE IF EXISTS heattrip_migration_abort;
CREATE PROCEDURE heattrip_migration_abort(IN msg VARCHAR(128))
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = msg;

-- 0-1. 부모 표 셋. walk 는 고칠 대상이고, dog 는 옛 행을 채우는 근거이고,
--      users 는 FK 가 가리키는 곳이다.
SET @parents := (
    SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name IN ('walk', 'dog', 'users'));
SET @abort_msg := CONCAT(
    'ABORT: 부모 표가 ', @parents, '/3 이다. 11_dog.sql · 12_walk.sql 을 먼저 적용하라.');
SET @stmt := IF(@parents = 3,
    'SELECT ''[0-1] walk · dog · users 확인'' AS message',
    'CALL heattrip_migration_abort(@abort_msg)');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- 0-2. 이미 있는지 본다(= 재실행이거나 Hibernate 가 먼저 만들었는지).
--      dev 는 ddl-auto=update 라 앱이 먼저 뜨면 컬럼이 이미 있을 수 있다.
SET @pre_col := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'walk' AND column_name = 'walked_by');

-- 0-3. NOT NULL 로 먼저 만들어져 있으면 멈춘다. 그 상태로는 탈퇴가 산책을 지운다.
SET @pre_not_null := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'walk'
      AND column_name = 'walked_by' AND is_nullable = 'NO');
SET @stmt := IF(@pre_not_null = 0,
    'SELECT ''[0-3] walked_by 가 NOT NULL 로 있지 않다'' AS message',
    'CALL heattrip_migration_abort(''ABORT: walk.walked_by 가 NOT NULL 이다. 탈퇴가 산책을 지운다 — NULL 허용으로 바꿔라.'')');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SELECT '[0] 사전 점검' AS section, @parents AS parents_3, @pre_col AS walked_by_before;


-- ── A. 컬럼 추가 ────────────────────────────────────────────────────────────
-- ADD COLUMN IF NOT EXISTS 는 MySQL 에 없다. 있는지 보고 조립한다.

SET @stmt := IF(@pre_col = 0,
    'ALTER TABLE walk ADD COLUMN walked_by BIGINT NULL COMMENT ''걸은 사람(users.id). 탈퇴하면 NULL 이다 — 그 산책이 없던 일이 되면 안 된다'' AFTER dog_id',
    'SELECT ''[A] walked_by 이미 있음 — 건너뜀'' AS message');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;


-- ── B. 옛 행 채우기 ─────────────────────────────────────────────────────────
-- 이 마이그레이션 전에는 남의 아이로 산책을 저장할 수 없었다(requireMineEntity).
-- 그래서 그때의 "아이 주인" 이 곧 "걸은 사람" 이다 — 지어내는 것이 아니다.
--
-- 이미 값이 있는 행은 안 건드린다. 재실행해도 나중에 남이 걸어 준 산책을 덮지 않는다.

UPDATE walk w
  JOIN dog d ON d.id = w.dog_id
   SET w.walked_by = d.user_id
 WHERE w.walked_by IS NULL;

SELECT '[B] 옛 행 채움' AS section, ROW_COUNT() AS filled_rows;


-- ── C. FK ───────────────────────────────────────────────────────────────────
-- ON DELETE SET NULL 이다. care_log.done_by 와 같은 판단(08_care_log.sql §B) —
-- 걸은 사람이 탈퇴했다고 그 산책이 사라지면 안 된다. 기록의 주인은 아이다.

SET @has_fk := (
    SELECT COUNT(*) FROM information_schema.referential_constraints
    WHERE constraint_schema = DATABASE() AND table_name = 'walk'
      AND constraint_name = 'fk_walk_walkedby');
SET @stmt := IF(@has_fk = 0,
    'ALTER TABLE walk ADD CONSTRAINT fk_walk_walkedby FOREIGN KEY (walked_by) REFERENCES users (id) ON DELETE SET NULL',
    'SELECT ''[C] fk_walk_walkedby 이미 있음 — 건너뜀'' AS message');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;


-- ── D. 사후 검증 ────────────────────────────────────────────────────────────
-- 여기서 걸리면 위가 의도대로 안 된 것이다. validate 는 FK 도 삭제 규칙도 안 본다.

SET @d_col := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'walk' AND column_name = 'walked_by');

SET @d_nullable := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'walk'
      AND column_name = 'walked_by' AND is_nullable = 'YES');

SET @d_fk := (
    SELECT COUNT(*) FROM information_schema.referential_constraints
    WHERE constraint_schema = DATABASE() AND table_name = 'walk'
      AND constraint_name = 'fk_walk_walkedby' AND delete_rule = 'SET NULL');

-- 옛 행이 남아 있으면 안 된다. dog 가 없는 walk 는 있을 수 없다(dog_id NOT NULL).
SET @d_unfilled := (SELECT COUNT(*) FROM walk WHERE walked_by IS NULL);

SELECT '[D] 사후 검증' AS section,
       @d_col AS walked_by_1, @d_nullable AS nullable_1, @d_fk AS fk_setnull_1,
       @d_unfilled AS unfilled_expect_0;

SET @abort_msg := CONCAT(
    'ABORT: 사후 검증 실패 — 컬럼 ', @d_col, '/1, NULL허용 ', @d_nullable,
    '/1, FK(SET NULL) ', @d_fk, '/1, 안 채운 행 ', @d_unfilled, '(0이어야 한다).');
SET @stmt := IF(@d_col = 1 AND @d_nullable = 1 AND @d_fk = 1 AND @d_unfilled = 0,
    'SELECT ''[D] 통과'' AS message',
    'CALL heattrip_migration_abort(@abort_msg)');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

DROP PROCEDURE IF EXISTS heattrip_migration_abort;

SELECT '49_walk_walked_by.sql 완료' AS message;
