-- ============================================================================
-- 52_dog_character.sql
-- 사진이 없어도 아이 얼굴이 갈리게 — dog.character_key 한 칸 (이슈 #585)
-- 대상: MySQL 8.x (운영/개발 공통)
--
-- ─────────────────────────────────────────────────
-- 무엇을 하나
--
--   ALTER TABLE dog ADD COLUMN character_key VARCHAR(20) NULL;
--
-- 그것뿐이다. 기존 행은 전부 NULL 이고, NULL 은 "안 골랐다" 라 화면이 지금과 똑같다.
--
-- ─────────────────────────────────────────────────
-- 왜 필요한가
--
-- 아이 얼굴이 **종류당 하나**였다 — 강아지면 모두 같은 그림. 사진을 안 올린 집은 아이가
-- 둘이어도 홈의 고르기 칩이 같은 얼굴 둘로 서고, 이름을 읽기 전에는 못 가른다. 사진을
-- 강요할 수는 없다(사장님, 2026-09-16).
--
-- ─────────────────────────────────────────────────
-- 왜 avatar 컬럼을 같이 안 쓰나
--
-- 거기는 S3 키 자리다. 한 칸에 두 가지 뜻을 담으면 읽는 곳마다 "이 값이 사진인가 캐릭터
-- 인가" 를 물어야 하고, 그 판정이 코드 여러 곳에 흩어진다.
--
-- 그리고 **둘은 동시에 있어야 한다.** 사진을 올린 뒤에도 고른 캐릭터가 남아 있어야, 사진을
-- 지웠을 때 "고르기 전" 이 아니라 "고른 캐릭터" 로 돌아간다 — 그게 사용자가 기대하는 바다.
-- 한 칸에 담으면 그 둘 중 하나가 반드시 지워진다.
--
-- ─────────────────────────────────────────────────
-- 왜 CHECK 를 안 거나
--
-- 목록이 **화면의 그림 목록**이라 코드 쪽에서 늘어난다. CHECK 를 걸면 캐릭터 하나를 더할
-- 때마다 마이그레이션이 따라오고, 반대로 하나를 뺄 때는 이미 그 값을 고른 행 때문에
-- ALTER 가 거절당한다. 값 검증은 서버가 한다(PetCharacter.of → 400).
--
-- 그래서 **모르는 값이 행에 남을 수 있다**. 앱이 그것을 종류 기본 그림으로 떨어뜨린다 —
-- 그림 하나가 밋밋한 것과 화면이 안 뜨는 것은 무게가 다르다(care_item.icon 과 같은 판단).
--
-- ─────────────────────────────────────────────────
-- 왜 character 가 아니라 character_key 인가
--
-- CHARACTER 는 MySQL 예약어다(CHARACTER SET). 백틱으로 감싸면 되지만, 감싸는 것을 한 번
-- 빠뜨리면 그 자리만 조용히 문법 오류가 난다 — 이름을 비켜 두는 쪽이 싸다.
--
-- ─────────────────────────────────────────────────
-- 실행 순서
--
--   1. 07_dog.sql(dog 표)이 먼저 돌아 있어야 한다.
--   2. 이 스크립트를 실행한다 — 새 애플리케이션을 배포하기 **전**.
--      prod 는 ddl-auto=validate 라 엔티티에 있는 컬럼이 표에 없으면 **부팅이 막힌다**.
--
-- 멱등: 이미 있으면 지나간다.
--
-- ─────────────────────────────────────────────────
-- 되돌리기(DOWN)
--
--   ALTER TABLE dog DROP COLUMN character_key;
--
-- 되돌리면 고른 캐릭터를 잃는다. 사진과 종류는 그대로라 화면은 #585 이전으로 돌아간다.
-- ============================================================================


-- ── 0. 사전 점검 ─────────────────────────────────────────
SET NAMES utf8mb4;

DROP PROCEDURE IF EXISTS heattrip_migration_abort;
CREATE PROCEDURE heattrip_migration_abort(IN msg VARCHAR(160))
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = msg;

SET @has_table := (
    SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name = 'dog');

SET @stmt := IF(@has_table = 1,
    'SELECT ''[0-1] dog 확인'' AS message',
    'CALL heattrip_migration_abort(''ABORT: dog 표가 없다. 07_dog.sql 을 먼저 돌려라.'')');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @pre_col := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'dog' AND column_name = 'character_key');

SET @rows_before := (SELECT COUNT(*) FROM dog);

SELECT '[0] 사전 점검' AS section,
       @pre_col     AS character_key_before,
       @rows_before AS dog_rows;


-- ── A. 칸 하나 ───────────────────────────────────────────
-- ADD COLUMN IF NOT EXISTS 는 MySQL 에 없다. 있는지 보고 조립한다.
SET @stmt := IF(@pre_col = 0,
    'ALTER TABLE dog ADD COLUMN character_key VARCHAR(20) NULL COMMENT ''사진이 없을 때의 얼굴. NULL 이면 종류 기본 그림 (#585)''',
    'SELECT ''[A] character_key 이미 있음 — 건너뜀'' AS message');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;


-- ── D. 사후 검증 ─────────────────────────────────────────
SET @d_col := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'dog' AND column_name = 'character_key');

SET @d_nullable := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'dog'
      AND column_name = 'character_key' AND is_nullable = 'YES');

-- 행 수가 그대로여야 한다. 칸만 더하는 변경이라 한 행도 지워지면 안 된다.
SET @d_rows := (SELECT COUNT(*) FROM dog);

-- 사진 칸을 안 건드렸는지도 본다 — 둘은 함께 살아야 한다(머리말).
SET @d_avatar := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'dog' AND column_name = 'avatar');

SELECT '[D] 사후 검증' AS section,
       @d_col      AS character_key_1,
       @d_nullable AS nullable_1,
       @d_avatar   AS avatar_kept_1,
       @d_rows     AS rows_same;

SET @abort_msg := CONCAT(
    'ABORT: 사후 검증 실패 — character_key ', @d_col, '/1, NULL허용 ', @d_nullable, '/1, ',
    'avatar ', @d_avatar, '/1, 행 ', @d_rows, '(', @rows_before, ' 이어야 한다).');
SET @stmt := IF(@d_col = 1 AND @d_nullable = 1 AND @d_avatar = 1 AND @d_rows = @rows_before,
    'SELECT ''[D] 통과'' AS message',
    'CALL heattrip_migration_abort(@abort_msg)');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

DROP PROCEDURE IF EXISTS heattrip_migration_abort;

SELECT '52_dog_character.sql 완료' AS message;
