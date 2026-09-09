-- ============================================================================
-- 37_crew.sql
-- 동네 반려인 모임 — 이슈 #417
-- 대상: MySQL 8.x (운영/개발 공통)
--
-- ─────────────────────────────────────────────────
-- 무엇을 하나
--
--   CREATE TABLE crew (name, intro, neighborhood_code, visibility, capacity)
--
-- 그게 전부다. **표 하나뿐이다.**
--
-- ─────────────────────────────────────────────────
-- crew_member 표를 안 만든다
--
-- 크루의 멤버는 **그 크루 방의 멤버**이고, 그것은 `chat_room_member` 다. ADR-0011 이 "채팅은
-- 가족 그룹 종속이 아니라 범용 다중 방" 이라고 정하면서 `chat_room.origin_kind`/`origin_ref`
-- 를 열어 뒀고, 그 컬럼 주석이 이미 **"가족방도 산책 크루 방도 같은 표에 산다"** 고 적고 있다.
--
-- 표를 따로 만들면 멤버십이 **두 곳**에 생긴다. 그러면 "크루는 나갔는데 방에는 남아 있는"
-- 계정이 언젠가 만들어지고, 그 사람은 크루 화면에서 안 보이는 채로 대화를 읽는다.
-- `family_group` 이 같은 이유로 사용자 컬럼을 안 갖는다.
--
-- 방장도 여기 없다. 방장은 그 방의 `OWNER` 멤버다(`chat_room_member.role`). 컬럼을 따로 두면
-- 둘이 갈리는 날이 오고, 그날 "크루 화면에서는 방장인데 대화방에서는 못 내보내는" 사람이 생긴다.
--
-- ─────────────────────────────────────────────────
-- chat_room 으로 나가는 FK 가 없다
--
-- 크루 하나에 방 하나지만 `room_id` 컬럼을 안 둔다. 방의 출처는 이미 `chat_room` 쪽이
-- `(origin_kind='CREW', origin_ref=crew.id)` 로 들고 있고, 여기에도 두면 **같은 사실이 두
-- 곳**에 산다. 그리고 그 FK 를 엔티티가 들려면 `crew` 가 `chat.entity.ChatRoom` 을 import
-- 해야 하는데 그건 모듈 경계를 넘는다(`ChatBoundaryArchitectureTest`). SQL 에만 적어 두면
-- `01_schema.sql` 재생성에서 조용히 사라진다 — 35 가 같은 판단을 했다.
--
-- ─────────────────────────────────────────────────
-- 동네는 행정동 코드다 — 좌표가 아니다
--
-- A안(#235)에서 좌표는 기기를 안 떠난다. `neighborhood_code` 는 **사용자가 스스로 고른 값**
-- (#342)이라 위치정보가 아니고, 찾기는 앞 다섯 자리(시군구)로 한다.
-- `idx_crew_public (visibility, neighborhood_code)` 가 그 `LIKE '11200%'` 를 받는다.
--
-- NULL 을 허용한다 — 동네를 안 고른 사람이 만든 크루다. 그 크루는 어느 동네 목록에도 안 뜨고
-- 코드로만 들어온다(그래서 **공개로는 만들 수 없다** — 서비스가 앞에서 막는다).
--
-- ─────────────────────────────────────────────────
-- 정원은 방이 아니라 여기 있다
--
-- `chat_room` 의 정원은 `ChatLimits` 가 정하는 **서비스 전체의 상한**이고, 크루 정원은
-- **방장이 정하는 값**이다. 둘은 뜻이 다르다 — 20명짜리 모임을 만든 사람이 21번째를 받고
-- 싶지 않은 것은 서비스 정책이 아니라 그 모임의 규칙이다.
--
-- `ck_crew_capacity` 가 2..100 을 잡는다. 1명짜리 모임은 모임이 아니고, 100을 넘으면 동네
-- 모임이 아니다.
--
-- ─────────────────────────────────────────────────
-- 실행 순서
--
--   1. 이 스크립트를 실행한다 — 새 애플리케이션을 배포하기 **전**.
--   2. 앞선 스크립트에 의존하지 않는다. 새 표 하나라 아무 때나 돌려도 된다.
--
-- **dev(`ddl-auto=update`)에서도 앱을 띄우기 전에 돌린다.** 안 돌리면 Hibernate 가 표를
-- 자기 방식으로 만들고(예: CHECK 없이), 그 뒤에는 이 스크립트가 `IF NOT EXISTS` 로 조용히
-- 지나가 **CHECK 가 없는 표가 남는다**(#420 에서 겪었다).
--
-- 멱등: 표가 이미 있으면 지나간다.
--
-- ─────────────────────────────────────────────────
-- 되돌리기(DOWN)
--
--   DROP TABLE crew;
--
-- **방은 안 지워진다.** `chat_room` 의 `origin_kind='CREW'` 행과 그 메시지는 그대로 남고,
-- 채팅 목록에도 계속 보인다 — 크루 화면에서만 사라진다. 대화를 지우는 것은 다른 동작이고,
-- 되돌리기가 사람들의 대화를 지우면 안 된다.
-- ============================================================================


-- ── 0. 사전 점검 ─────────────────────────────────────────
SET NAMES utf8mb4;

DROP PROCEDURE IF EXISTS heattrip_migration_abort;
CREATE PROCEDURE heattrip_migration_abort(IN msg VARCHAR(128))
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = msg;

-- 크루는 방 위에 얹는 것이라 `chat_room` 이 먼저 있어야 한다. 없는 DB 에 이 표만 만들면
-- 크루를 만드는 첫 요청이 500 이다.
SET @has_room := (
    SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name = 'chat_room');

SET @stmt := IF(@has_room = 1,
    'SELECT ''[0-1] chat_room 확인'' AS message',
    'CALL heattrip_migration_abort(''ABORT: chat_room 이 없다. 크루는 방 위에 얹는다.'')');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @has_crew := (
    SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name = 'crew');

SELECT '[0] 사전 점검' AS section,
       @has_crew AS crew_table_already;


-- ── A. 표 ────────────────────────────────────────────────
--
-- 컬럼 순서·타입은 `mysql/init/01_schema.sql` 과 **같아야 한다**. 그 파일은 엔티티에서 뽑은
-- 것이고 prod 는 `ddl-auto=validate` 다.
CREATE TABLE IF NOT EXISTS `crew` (
  `capacity` int NOT NULL,
  `created_at` datetime(6) NOT NULL,
  `id` bigint NOT NULL AUTO_INCREMENT,
  `updated_at` datetime(6) DEFAULT NULL,
  `neighborhood_code` varchar(10) DEFAULT NULL,
  `visibility` varchar(10) NOT NULL,
  `name` varchar(30) NOT NULL,
  `intro` varchar(200) DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_crew_public` (`visibility`,`neighborhood_code`),
  CONSTRAINT `ck_crew_capacity` CHECK ((`capacity` between 2 and 100)),
  CONSTRAINT `ck_crew_visibility` CHECK ((`visibility` in ('invite','public')))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;


-- ── D. 사후 검증 ─────────────────────────────────────────
--
-- **전체 컬럼 수를 안 센다** — 컬럼이 늘면 재실행이 깨진다. 이름으로 묻는다.
SET @d_cols := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'crew'
      AND column_name IN ('id','name','intro','neighborhood_code','visibility',
                          'capacity','created_at','updated_at'));

-- 우리 동네 목록이 타는 인덱스다. 없으면 동네가 커질수록 전 테이블 훑기가 된다.
SET @d_index := (
    SELECT COUNT(DISTINCT column_name) FROM information_schema.statistics
    WHERE table_schema = DATABASE() AND table_name = 'crew'
      AND index_name = 'idx_crew_public');

-- CHECK 둘. **Hibernate 의 update 도 prod 의 validate 도 CHECK 는 안 본다** — 여기서 안
-- 재면 아무 데서도 안 잡힌다(2026-09-08 에 24·29 가 실제로 그랬다).
SET @d_checks := (
    SELECT COUNT(*) FROM information_schema.table_constraints
    WHERE table_schema = DATABASE() AND table_name = 'crew'
      AND constraint_type = 'CHECK'
      AND constraint_name IN ('ck_crew_visibility','ck_crew_capacity'));

SELECT '[D] 사후 검증' AS section,
       @d_cols   AS named_columns_expect_8,
       @d_index  AS public_index_columns_expect_2,
       @d_checks AS checks_expect_2;

SET @stmt := IF(@d_cols = 8 AND @d_index = 2 AND @d_checks = 2,
    'SELECT ''[D] 통과 — crew 표 · 동네 인덱스 · CHECK 둘'' AS message',
    'CALL heattrip_migration_abort(''ABORT: 사후 검증 실패. 위 [D] 행의 숫자를 확인하라.'')');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

DROP PROCEDURE IF EXISTS heattrip_migration_abort;
