-- ============================================================================
-- 33_walk_dog.sql
-- 한 번의 산책에 여러 마리 — 이슈 #343
-- 대상: MySQL 8.x (운영/개발 공통)
--
-- ─────────────────────────────────────────────────
-- 무엇을 하나
--
--   CREATE TABLE walk_dog (walk_id, dog_id)
--   INSERT IGNORE INTO walk_dog SELECT id, dog_id FROM walk   -- 기존 기록 채우기
--
-- 지금 `walk` 는 아이 하나에 묶여 있다. 두 마리를 함께 데리고 나가면 한 마리 것으로
-- 저장되거나 같은 산책을 두 번 적어야 한다. 프로필은 "우리 아이들" 을 여러 마리 받는데
-- 산책만 한 마리다.
--
-- ─────────────────────────────────────────────────
-- walk.dog_id 를 남긴다
--
-- 지우지 않는다. 셋 때문이다.
--
--   1. `uq_walk_client (dog_id, client_walk_id)` 가 재전송을 막는 열쇠다. 이것을 빼면
--      전송이 타임아웃 났을 때 같은 산책이 두 줄이 된다(#145 가 만든 장치다).
--   2. 소유권이 이 연관을 타고 `dog.user_id` 로 간다. 여기를 끊으면 "누구 산책인가" 를
--      물을 자리가 없어진다.
--   3. 이미 쌓인 기록이 전부 이 컬럼으로 이어져 있다.
--
-- 그래서 `walk.dog_id` 는 **대표 아이**(앱이 고른 목록의 첫 마리)로 남고, `walk_dog` 가
-- 함께 나간 아이 전부를 든다. 대표 아이도 `walk_dog` 에 **한 줄 들어간다** — 안 넣으면
-- "아이별 통계" 가 두 곳을 합쳐 봐야 하고, 그 합치기를 잊는 화면이 언젠가 생긴다.
--
-- ─────────────────────────────────────────────────
-- 기존 기록을 채운다
--
-- 표만 만들고 비워 두면 아이별 통계가 **지금까지 걸은 것을 전부 0 으로** 말한다. 사용자가
-- 보기에 그것은 기록이 사라진 것이다. 그래서 이 스크립트가 `walk` 한 줄마다 `walk_dog`
-- 한 줄을 넣는다. `INSERT IGNORE` 라 두 번 돌려도 늘지 않는다.
--
-- ─────────────────────────────────────────────────
-- 지우기 규칙 — 둘 다 CASCADE
--
-- 이 표에는 사실이 없다. "이 산책에 이 아이가 있었다" 라는 **이음매**뿐이라, 산책이나
-- 아이가 사라지면 남을 이유가 없다. `care_log` 가 `SET NULL` 인 것과 다른 이유가 여기 있다 —
-- 거기는 "누가 밥을 줬다" 라는 사실이 사람이 사라져도 남아야 하는 행이다.
--
-- 다만 아이는 소프트 삭제다(#156, `dog.deleted_at`). 실제로 행이 지워지는 것은 계정 탈퇴
-- 같은 경로뿐이라, CASCADE 가 도는 일은 드물다.
--
-- ─────────────────────────────────────────────────
-- 실행 순서
--
--   1. 12_walk.sql · dog 표가 먼저 있어야 한다. 없으면 시작하지 않는다.
--   2. 이 스크립트를 실행한다 — 새 애플리케이션을 배포하기 **전**(prod 는 validate).
--
-- 멱등: 표가 이미 있으면 만들지 않고, 채우기는 `INSERT IGNORE` 라 두 번 돌아도 같다.
--
-- ─────────────────────────────────────────────────
-- 되돌리기(DOWN)
--
--   DROP TABLE walk_dog;
--
-- `walk.dog_id` 가 그대로라 **한 마리짜리 기록은 하나도 안 잃는다.** 잃는 것은 "두 번째
-- 이후 아이" 뿐이다. 되돌리기 전에 앱을 먼저 내린다.
-- ============================================================================


-- ── 0. 사전 점검 ─────────────────────────────────────────
SET NAMES utf8mb4;

DROP PROCEDURE IF EXISTS heattrip_migration_abort;
CREATE PROCEDURE heattrip_migration_abort(IN msg VARCHAR(128))
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = msg;

SET @has_walk := (
    SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name = 'walk');
SET @has_dog := (
    SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name = 'dog');

SET @stmt := IF(@has_walk = 1 AND @has_dog = 1,
    'SELECT ''[0-1] walk · dog 확인'' AS message',
    'CALL heattrip_migration_abort(''ABORT: walk 또는 dog 표가 없다. 12_walk.sql 을 먼저 돌려라.'')');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @has_join := (
    SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name = 'walk_dog');

-- 이미 있으면 컬럼이 둘 다 있는지만 본다. 모자라면 멈춘다 — 반쪽짜리 표에 앱을 붙이면
-- validate 가 부팅에서 죽거나, 더 나쁘게는 죽지 않고 아이별 통계를 조용히 틀리게 센다.
SET @cols := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'walk_dog'
      AND column_name IN ('walk_id','dog_id'));

SET @stmt := IF(@has_join = 0 OR @cols = 2,
    'SELECT ''[0-2] walk_dog 점검'' AS message',
    'CALL heattrip_migration_abort(''ABORT: walk_dog 표가 이미 있는데 컬럼이 모자라다. 사람이 확인하라.'')');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @walks_before := (SELECT COUNT(*) FROM `walk`);

SELECT '[0] 사전 점검' AS section,
       @has_join      AS walk_dog_already,
       @walks_before  AS walk_rows;


-- ── A. 표 ────────────────────────────────────────────────
--
-- PK 가 (dog_id, walk_id) 라 같은 산책에 같은 아이를 두 번 넣을 수 없다. 앱이 목록을
-- 중복해서 보내도 표가 막는다 — 서비스의 검사에만 맡기면 그 검사를 안 지나는 경로가
-- 언젠가 생긴다.
--
-- 순서가 (dog_id, walk_id) 인 것은 **엔티티가 만드는 것과 같게 하려는 것**이다.
-- `mysql/init/01_schema.sql` 은 엔티티에서 재생성하므로, 여기서 순서를 뒤집으면 새로
-- 세운 DB 와 마이그레이션한 DB 의 인덱스가 달라진다. 마침 바라던 순서이기도 하다 —
-- 이 표에 가장 자주 오는 질문이 "이 아이의 산책" 이라 dog_id 가 앞이어야 한다.
--
-- 반대 방향("이 산책의 아이들")은 MySQL 이 fk_walkdog_walk 에 자동으로 만드는 인덱스가
-- 받는다. 그래서 보조 인덱스를 따로 두지 않는다.
CREATE TABLE IF NOT EXISTS `walk_dog` (
  `dog_id` bigint NOT NULL,
  `walk_id` bigint NOT NULL,
  PRIMARY KEY (`dog_id`,`walk_id`),
  KEY `fk_walkdog_walk` (`walk_id`),
  CONSTRAINT `fk_walkdog_dog` FOREIGN KEY (`dog_id`) REFERENCES `dog` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_walkdog_walk` FOREIGN KEY (`walk_id`) REFERENCES `walk` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;


-- ── B. 이미 있는 기록 채우기 ─────────────────────────────
INSERT IGNORE INTO `walk_dog` (`walk_id`, `dog_id`)
SELECT `id`, `dog_id` FROM `walk`;


-- ── D. 사후 검증 ─────────────────────────────────────────
SET @d_table := (
    SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name = 'walk_dog');
SET @d_cols := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'walk_dog'
      AND column_name IN ('walk_id','dog_id'));
SET @d_fk_walk := (
    SELECT COUNT(*) FROM information_schema.referential_constraints
    WHERE constraint_schema = DATABASE() AND constraint_name = 'fk_walkdog_walk'
      AND delete_rule = 'CASCADE');
SET @d_fk_dog := (
    SELECT COUNT(*) FROM information_schema.referential_constraints
    WHERE constraint_schema = DATABASE() AND constraint_name = 'fk_walkdog_dog'
      AND delete_rule = 'CASCADE');
SET @d_pk := (
    SELECT COUNT(*) FROM information_schema.statistics
    WHERE table_schema = DATABASE() AND table_name = 'walk_dog' AND index_name = 'PRIMARY');

-- 채우기가 빠진 산책이 있으면 아이별 통계가 그만큼 적게 센다. 0 이어야 한다.
SET @d_orphans := (
    SELECT COUNT(*) FROM `walk` w
    WHERE NOT EXISTS (
        SELECT 1 FROM `walk_dog` wd WHERE wd.walk_id = w.id AND wd.dog_id = w.dog_id));

SELECT '[D] 사후 검증' AS section,
       @d_table    AS walk_dog_table_expect_1,
       @d_cols     AS columns_expect_2,
       @d_fk_walk  AS fk_walk_cascade_expect_1,
       @d_fk_dog   AS fk_dog_cascade_expect_1,
       @d_pk       AS pk_columns_expect_2,
       @d_orphans  AS walks_without_row_expect_0;

SET @stmt := IF(@d_table = 1 AND @d_cols = 2 AND @d_fk_walk = 1 AND @d_fk_dog = 1
                AND @d_pk = 2 AND @d_orphans = 0,
    'SELECT ''[D] 통과 — walk_dog 표 · FK 둘 CASCADE · 복합 PK · 기존 산책 전부 채움'' AS message',
    'CALL heattrip_migration_abort(''ABORT: 사후 검증 실패. 위 [D] 행의 숫자를 확인하라.'')');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

DROP PROCEDURE IF EXISTS heattrip_migration_abort;
