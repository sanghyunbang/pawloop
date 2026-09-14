-- ============================================================================
-- 40_post_bookmark.sql
-- 글 저장 — "내 사진첩" 에 넣어 둔 글 — 이슈 #451 (4번)
-- 대상: MySQL 8.x (운영/개발 공통)
--
-- ─────────────────────────────────────────────────
-- 무엇을 하나
--
--   CREATE TABLE post_bookmark (post_id, user_id, created_at)
--
-- ─────────────────────────────────────────────────
-- reaction 과 닮았지만 다른 점 둘
--
-- **탈퇴하면 행이 사라진다** (`user_id` CASCADE). 반응은 집계가 남아야 해서 SET NULL 인데,
-- 저장은 그 사람만 보는 목록이라 사람이 없으면 목록도 없다. 그래서 `user_id` 가 NOT NULL 이고
-- 유니크는 `(post_id, user_id)` 둘이다 — 종류가 없으니 세 번째 축이 없다.
--
-- **정렬 축이 이 표의 시각이다.** 저장한 글 목록은 "언제 저장했나" 순이지 글이 쓰인 순이
-- 아니다(Instagram 의 저장됨). `idx_post_bookmark_user (user_id, created_at, id)` 가 커서의
-- 두 축을 그대로 든다 — 앞자리가 `user_id` 라 "내 것만" 이 인덱스 범위다.
--
-- ─────────────────────────────────────────────────
-- 표 이름이 post_bookmark 인 이유
--
-- `bookmark` 는 장소 저장(계획, docs/03-database/schema.md §10)이 예약한 이름이다. 글 저장과
-- 장소 저장은 대상이 다른 두 표다. 감정 여행 시절의 `bookmarks`(복수, #94 로 코드 삭제)와도
-- 다르다.
--
-- ─────────────────────────────────────────────────
-- 세지 않는다
--
-- "몇 명이 저장했나" 는 화면에 없다. 있으면 글쓴이에게 남의 사진첩을 들여다보는 숫자가 된다.
-- 그래서 집계 쿼리도, 그것을 위한 인덱스도 없다.
--
-- ─────────────────────────────────────────────────
-- 실행 순서
--
--   1. `14_community.sql` 이 먼저다(`post` 가 있어야 한다). 없으면 시작하지 않는다.
--   2. 이 스크립트를 실행한다 — 새 애플리케이션을 배포하기 **전**.
--
-- **dev(`ddl-auto=update`)에서도 앱을 띄우기 전에 돌린다.** 안 돌리면 Hibernate 가 표를
-- 자기 방식으로 만들고, 그 뒤에는 이 스크립트가 `IF NOT EXISTS` 로 조용히 지나간다 —
-- 이 표는 CHECK 가 없어 그래도 같은 모양이지만, 순서를 지키는 습관이 38 의 사고를 막는다.
--
-- 멱등: 표가 이미 있으면 지나간다.
--
-- ─────────────────────────────────────────────────
-- 되돌리기(DOWN)
--
--   DROP TABLE post_bookmark;
--
-- 글도 사람도 그대로다 — 이 표는 둘 사이의 선일 뿐이다.
-- ============================================================================

-- ── 0. 사전 점검 ────────────────────────────────────────
SET NAMES utf8mb4;

-- SIGNAL 은 PREPARE 할 수 없어서 프로시저로 감싼다 — 38 과 같은 모양.
DROP PROCEDURE IF EXISTS heattrip_migration_abort;
CREATE PROCEDURE heattrip_migration_abort(IN msg VARCHAR(128))
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = msg;

SET @has_post := (
    SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name = 'post');
SET @has_users := (
    SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name = 'users');
SET @has_bookmark := (
    SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name = 'post_bookmark');

SELECT '[0] 사전 점검' AS section,
       @has_post     AS post_table_expect_1,
       @has_users    AS users_table_expect_1,
       @has_bookmark AS post_bookmark_table_already;

-- post 가 없으면 FK 를 걸 곳이 없다 — 14 를 먼저 돌려야 한다.
SET @stmt := IF(@has_post = 1 AND @has_users = 1,
    'SELECT ''[0-1] post·users 확인 (14 통과)'' AS message',
    'CALL heattrip_migration_abort(''ABORT: 14_community.sql 을 먼저 돌려라.'')');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;


-- ── A. 표 ────────────────────────────────────────────────
--
-- 컬럼 순서·타입은 `mysql/init/01_schema.sql` 과 **같아야 한다**. 그 파일은 엔티티에서 뽑은
-- 것이고 prod 는 `ddl-auto=validate` 다.
CREATE TABLE IF NOT EXISTS `post_bookmark` (
  `created_at` datetime(6) NOT NULL,
  `id` bigint NOT NULL AUTO_INCREMENT,
  `post_id` bigint NOT NULL,
  `user_id` bigint NOT NULL,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uq_post_bookmark` (`post_id`,`user_id`),
  KEY `idx_post_bookmark_user` (`user_id`,`created_at`,`id`),
  CONSTRAINT `fk_post_bookmark_post` FOREIGN KEY (`post_id`) REFERENCES `post` (`id`) ON DELETE CASCADE,
  CONSTRAINT `fk_post_bookmark_user` FOREIGN KEY (`user_id`) REFERENCES `users` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;


-- ── D. 사후 검증 ─────────────────────────────────────────
--
-- **전체 컬럼 수를 안 센다** — 컬럼이 늘면 재실행이 깨진다. 이름으로 묻는다.
SET @d_cols := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'post_bookmark'
      AND column_name IN ('id','post_id','user_id','created_at'));

-- 글이 사라지면 저장도, 사람이 사라지면 목록째 사라진다 — 둘 다 CASCADE.
SET @d_cascade := (
    SELECT COUNT(*) FROM information_schema.referential_constraints
    WHERE constraint_schema = DATABASE()
      AND constraint_name IN ('fk_post_bookmark_post','fk_post_bookmark_user')
      AND delete_rule = 'CASCADE');

-- 한 사람이 한 글을 두 번 저장할 수 없다 — 멱등 삽입이 이 유니크를 딛는다.
SET @d_unique := (
    SELECT COUNT(DISTINCT column_name) FROM information_schema.statistics
    WHERE table_schema = DATABASE() AND table_name = 'post_bookmark'
      AND index_name = 'uq_post_bookmark' AND non_unique = 0);

-- 내가 저장한 글 목록이 타는 인덱스 — 커서의 두 축(created_at, id)을 user_id 뒤에 든다.
SET @d_index := (
    SELECT COUNT(DISTINCT column_name) FROM information_schema.statistics
    WHERE table_schema = DATABASE() AND table_name = 'post_bookmark'
      AND index_name = 'idx_post_bookmark_user');

SELECT '[D] 사후 검증' AS section,
       @d_cols    AS named_columns_expect_4,
       @d_cascade AS cascade_fks_expect_2,
       @d_unique  AS unique_columns_expect_2,
       @d_index   AS list_index_columns_expect_3;

-- Hibernate 가 먼저 만든 표(FK·인덱스 이름이 다르다)를 IF NOT EXISTS 가 조용히 지나쳤다면
-- 여기서 멈춘다 — 표를 지우고 다시 돌리든가, 이름을 맞추든가는 사람이 정한다.
SET @stmt := IF(@d_cols = 4 AND @d_cascade = 2 AND @d_unique = 2 AND @d_index = 3,
    'SELECT ''[D] 통과 — post_bookmark 표 · CASCADE 둘 · 유니크 · 목록 인덱스'' AS message',
    'CALL heattrip_migration_abort(''ABORT: 사후 검증 실패. 위 [D] 행의 숫자를 확인하라.'')');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

DROP PROCEDURE IF EXISTS heattrip_migration_abort;
