-- ============================================================================
-- 50_care_item.sql — 그 집이 챙기는 일의 목록 (이슈 #560)
--
-- 왜 필요한가
--
-- 사장님 말씀은 "투두리스트처럼 커스터마이징" 이었다. 정해진 일곱 중에 켜고 끄는 것이
-- 아니라 **직접 만들고 이름 붙이고 지우고 순서를 바꾸는 것**이다.
--
-- 그런데 care_log.type 은 일곱 개짜리 닫힌 목록이다.
--
--   CONSTRAINT ck_carelog_type CHECK (type IN ('water','meal','walk','med','vet','poop','pee'))
--
-- "양치" 를 만들면 **넣을 값이 없다.** 종류를 늘리는 방식(CHECK 에 값을 더하는 것)으로는
-- 사용자가 만든 항목을 담을 수 없다 — 배포 없이는 한 글자도 못 늘린다.
--
-- 무엇을 하나
--
--   1. care_item 표를 만든다 — 그 집의 할 일 목록.
--   2. care_log.care_item_id 를 더한다(NULL 허용) + fk_carelog_item(SET NULL).
--   3. **이미 있는 모든 가족 그룹**에 기본 일곱을 넣는다.
--
-- 기존 기록을 한 행도 안 건드린다
--
-- care_item.system_type 이 그 이유다. 기본 일곱은 이 값을 들고, 직접 만든 것은 NULL 이다.
-- 읽을 때 항목마다 오늘 몇 번인지를 이렇게 센다.
--
--   · system_type 이 있으면 → care_log.type = system_type 으로
--   · 없으면              → care_log.care_item_id 로
--
-- 그래서 산책 트래킹이 type='walk' 로 남기는 줄도, 배변·마킹도 그대로 살아 있다.
-- **옛 care_log 에 care_item_id 를 채우는 UPDATE 가 없다** — 채울 이유가 없다.
--
-- 왜 유니크가 (group_id, system_type) 인가
--
-- "물이 두 칸" 을 막는다. MySQL 의 유니크는 NULL 을 서로 다른 값으로 보므로 **직접 만든
-- 항목은 몇 개든 된다** — 막는 것은 기본 항목의 중복뿐이고, 그게 이 스크립트를 두 번
-- 돌려도 안전한 이유이기도 하다.
--
-- 왜 fk_careitem_group 은 CASCADE 이고 fk_carelog_item 은 SET NULL 인가
--
-- care_item 은 **앞으로 할 일의 목록**이라 그 집이 없어지면 남길 것이 없다. care_log 는
-- **일어난 사실**이라 이름표를 잃어도 "누가 언제 했다" 는 남아야 한다 — care_log 의
-- dog_id·group_id·done_by 가 같은 질문에 같은 답을 했다(08_care_log.sql).
--
-- 아이를 보내면(dog 삭제) care_item.dog_id 는 SET NULL 이다. 같은 이름의 일을 다른 아이에게
-- 계속 할 수 있고, CASCADE 로 두면 **아이 한 마리를 보낸 것이 집의 할 일 목록을 지우는 일**
-- 이 된다.
--
-- 실행
--
--   mysql -u root -p heattrip < mysql/post-start/50_care_item.sql
--
-- **08_care_log.sql · 11_dog.sql · family_group 이 먼저다.** 멱등하다 — 두 번 돌려도 같은
-- 상태로 끝난다.
--
-- 되돌리기
--
--   ALTER TABLE care_log DROP FOREIGN KEY fk_carelog_item;
--   ALTER TABLE care_log DROP COLUMN care_item_id;
--   DROP TABLE care_item;
--
-- 되돌리면 **사용자가 만든 항목과 그 기록의 이름표가 사라진다.** 기본 일곱으로 남긴 기록은
-- type 으로 세므로 그대로다.
--
-- ----------------------------------------------------------------------------
-- 안 하는 것
--
-- 1. **care_log 의 CHECK 를 안 건드린다.** 직접 만든 항목은 type 을 안 쓰고 care_item_id 로
--    센다. CHECK 를 늘리면 배포마다 값을 늘려야 하는 그 문제로 돌아간다.
-- 2. **care_item_id 를 NOT NULL 로 안 만든다.** 옛 행에 채울 값이 없고, 기본 일곱은 앞으로도
--    type 으로 센다.
-- 3. **name 에 유니크를 안 건다.** "밥" 을 아이마다 따로 두고 싶은 집이 있다 — 그건 dog_id 로
--    가른다.
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

-- 0-1. 부모 표 셋. care_log 는 컬럼을 더할 대상이고, family_group·dog 는 FK 가 가리키는 곳이다.
SET @parents := (
    SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name IN ('care_log', 'family_group', 'dog'));
SET @abort_msg := CONCAT(
    'ABORT: 부모 표가 ', @parents, '/3 이다. 08_care_log.sql · 11_dog.sql 을 먼저 적용하라.');
SET @stmt := IF(@parents = 3,
    'SELECT ''[0-1] care_log · family_group · dog 확인'' AS message',
    'CALL heattrip_migration_abort(@abort_msg)');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- 0-2. 이미 있는지 본다(= 재실행이거나 Hibernate 가 먼저 만들었는지).
--      dev 는 ddl-auto=update 라 앱이 먼저 뜨면 표와 컬럼이 이미 있을 수 있다.
SET @pre_table := (
    SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name = 'care_item');
SET @pre_col := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'care_log' AND column_name = 'care_item_id');

-- 0-3. care_item_id 가 NOT NULL 로 먼저 만들어져 있으면 멈춘다. 그 상태로는 옛 행이 못 산다.
SET @pre_not_null := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'care_log'
      AND column_name = 'care_item_id' AND is_nullable = 'NO');
SET @stmt := IF(@pre_not_null = 0,
    'SELECT ''[0-3] care_item_id 가 NOT NULL 로 있지 않다'' AS message',
    'CALL heattrip_migration_abort(''ABORT: care_log.care_item_id 가 NOT NULL 이다. 옛 기록에는 채울 값이 없다 — NULL 허용으로 바꿔라.'')');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @pre_groups := (SELECT COUNT(*) FROM family_group);

SELECT '[0] 사전 점검' AS section,
       @parents AS parents_3, @pre_table AS care_item_before,
       @pre_col AS care_item_id_before, @pre_groups AS groups_total;


-- ── A. care_item 표 ─────────────────────────────────────────────────────────
-- 정의는 mysql/init/01_schema.sql 과 **글자까지 같다** — 그 파일은 엔티티에서 뽑은 정본이라,
-- 여기서 다르게 만들면 빈 DB 로 세운 곳과 이미 있는 DB 가 서로 다른 표를 갖게 된다.

CREATE TABLE IF NOT EXISTS `care_item` (
  `daily_target` int DEFAULT NULL,
  `sort_order` int NOT NULL,
  `archived_at` datetime(6) DEFAULT NULL,
  `created_at` datetime(6) NOT NULL,
  `dog_id` bigint DEFAULT NULL,
  `group_id` bigint NOT NULL,
  `id` bigint NOT NULL AUTO_INCREMENT,
  `system_type` varchar(10) DEFAULT NULL,
  `icon` varchar(20) NOT NULL,
  `name` varchar(20) NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_careitem_system` (`group_id`,`system_type`),
  KEY `idx_careitem_group` (`group_id`,`sort_order`),
  KEY `idx_careitem_dog` (`dog_id`),
  CONSTRAINT `fk_careitem_dog` FOREIGN KEY (`dog_id`) REFERENCES `dog` (`id`) ON DELETE SET NULL,
  CONSTRAINT `fk_careitem_group` FOREIGN KEY (`group_id`) REFERENCES `family_group` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

SELECT '[A] care_item 표' AS section, @pre_table AS existed_before;


-- ── B. care_log.care_item_id ────────────────────────────────────────────────
-- ADD COLUMN IF NOT EXISTS 는 MySQL 에 없다. 있는지 보고 조립한다.

SET @stmt := IF(@pre_col = 0,
    'ALTER TABLE care_log ADD COLUMN care_item_id BIGINT NULL COMMENT ''직접 만든 항목의 기록일 때만 채워진다. 기본 일곱은 type 으로 센다'' FIRST',
    'SELECT ''[B] care_item_id 이미 있음 — 건너뜀'' AS message');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @has_fk := (
    SELECT COUNT(*) FROM information_schema.referential_constraints
    WHERE constraint_schema = DATABASE() AND table_name = 'care_log'
      AND constraint_name = 'fk_carelog_item');
SET @stmt := IF(@has_fk = 0,
    'ALTER TABLE care_log ADD CONSTRAINT fk_carelog_item FOREIGN KEY (care_item_id) REFERENCES care_item (id) ON DELETE SET NULL',
    'SELECT ''[B] fk_carelog_item 이미 있음 — 건너뜀'' AS message');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;


-- ── C. 이미 있는 그룹에 기본 일곱 ───────────────────────────────────────────
-- 새로 만드는 그룹은 FamilyGroupCreated 이벤트가 같은 일곱을 넣는다(CareItemService).
-- 여기는 **이 마이그레이션 전에 이미 있던 집**을 위한 것이다.
--
-- 이름·아이콘·순서는 CareItem.defaultsFor 와 **글자까지 같아야 한다.** 다르면 마이그레이션으로
-- 세운 집과 새로 만든 집이 서로 다른 목록을 갖는다 — CareItemDefaultsMatchMigrationTest 가
-- 그 둘을 대조한다.
--
-- uq_careitem_system 덕분에 재실행이 두 번 넣지 않는다. WHERE NOT EXISTS 는 그 제약에
-- 기대지 않고 **정상 경로로** 건너뛰기 위한 것이다.

INSERT INTO care_item (group_id, dog_id, name, icon, system_type, daily_target, sort_order, archived_at, created_at)
SELECT g.id, NULL, d.name, d.icon, d.system_type, NULL, d.sort_order, NULL, NOW(6)
  FROM family_group g
  JOIN (
        SELECT '물'   AS name, 'water' AS icon, 'water' AS system_type, 0 AS sort_order
  UNION SELECT '밥',          'meal',          'meal',                 1
  UNION SELECT '산책',        'walk',          'walk',                 2
  UNION SELECT '투약',        'med',           'med',                  3
  UNION SELECT '병원',        'vet',           'vet',                  4
  UNION SELECT '배변',        'poop',          'poop',                 5
  UNION SELECT '마킹',        'pee',           'pee',                  6
  ) d
 WHERE NOT EXISTS (
        SELECT 1 FROM care_item i
         WHERE i.group_id = g.id AND i.system_type = d.system_type);

SELECT '[C] 기본 일곱 넣음' AS section, ROW_COUNT() AS inserted_rows;


-- ── D. 사후 검증 ────────────────────────────────────────────────────────────
-- 여기서 걸리면 위가 의도대로 안 된 것이다. validate 는 FK 도 삭제 규칙도 안 본다.

SET @d_table := (
    SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name = 'care_item');

SET @d_col := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'care_log' AND column_name = 'care_item_id');

SET @d_nullable := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'care_log'
      AND column_name = 'care_item_id' AND is_nullable = 'YES');

SET @d_fk_log := (
    SELECT COUNT(*) FROM information_schema.referential_constraints
    WHERE constraint_schema = DATABASE() AND table_name = 'care_log'
      AND constraint_name = 'fk_carelog_item' AND delete_rule = 'SET NULL');

SET @d_fk_group := (
    SELECT COUNT(*) FROM information_schema.referential_constraints
    WHERE constraint_schema = DATABASE() AND table_name = 'care_item'
      AND constraint_name = 'fk_careitem_group' AND delete_rule = 'CASCADE');

SET @d_fk_dog := (
    SELECT COUNT(*) FROM information_schema.referential_constraints
    WHERE constraint_schema = DATABASE() AND table_name = 'care_item'
      AND constraint_name = 'fk_careitem_dog' AND delete_rule = 'SET NULL');

-- **일곱이 안 들어간 그룹이 하나도 없어야 한다.** 이게 이 스크립트의 약속이다.
SET @d_short := (
    SELECT COUNT(*) FROM (
        SELECT g.id FROM family_group g
          LEFT JOIN care_item i ON i.group_id = g.id AND i.system_type IS NOT NULL
         GROUP BY g.id HAVING COUNT(i.id) < 7) short_groups);

SELECT '[D] 사후 검증' AS section,
       @d_table AS care_item_1, @d_col AS care_item_id_1, @d_nullable AS nullable_1,
       @d_fk_log AS fk_log_setnull_1, @d_fk_group AS fk_group_cascade_1,
       @d_fk_dog AS fk_dog_setnull_1, @d_short AS groups_short_expect_0;

SET @abort_msg := CONCAT(
    'ABORT: 사후 검증 실패 — 표 ', @d_table, '/1, 컬럼 ', @d_col, '/1, NULL허용 ', @d_nullable,
    '/1, FK(log/SET NULL) ', @d_fk_log, '/1, FK(group/CASCADE) ', @d_fk_group,
    '/1, FK(dog/SET NULL) ', @d_fk_dog, '/1, 일곱이 안 찬 그룹 ', @d_short, '(0이어야 한다).');
SET @stmt := IF(@d_table = 1 AND @d_col = 1 AND @d_nullable = 1 AND @d_fk_log = 1
                AND @d_fk_group = 1 AND @d_fk_dog = 1 AND @d_short = 0,
    'SELECT ''[D] 통과'' AS message',
    'CALL heattrip_migration_abort(@abort_msg)');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

DROP PROCEDURE IF EXISTS heattrip_migration_abort;

SELECT '50_care_item.sql 완료' AS message;
