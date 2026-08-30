-- ============================================================================
-- 06_chat_rooms.sql
-- 방·멤버십·초대 3테이블 — 이슈 #74 (근거: ADR-0011)
-- 대상: MySQL 8.x (운영/개발 공통)
--
-- ─────────────────────────────────────────────────────────────────────────────
-- 실행 순서
--
--   1. 이 스크립트를 실행한다 (앱 배포 **전**)
--   2. 그 다음 새 애플리케이션을 배포한다
--
-- 이 순서는 사실상 강제된다 — prod 는 ddl-auto=validate 라 엔티티가 요구하는 테이블이
-- 없으면 **부팅 자체가 실패한다.** 되돌릴 때는 반대로, 앱을 먼저 내린다.
--
-- 빈 DB 를 새로 세우는 경우에는 이 파일이 필요 없다. mysql/init/01_schema.sql 이
-- 세 표를 이미 담고 있다(#58).
--
-- ─────────────────────────────────────────────────────────────────────────────
-- ⚠️ 트랜잭션으로 감쌀 수 없다 — 실패해도 되돌아가지 않는다
--
-- MySQL 의 DDL(CREATE TABLE·ALTER TABLE …)은 **암묵적 커밋**을 일으킨다.
-- START TRANSACTION 으로 감싸도 소용이 없다. 그래서 04·05 와 같이 앞뒤로 관문을 둔다.
--   · §0 사전 점검 : 만들 이름이 이미 **다른 것**으로 쓰이고 있으면 아무것도 바꾸기 전에 멈춘다.
--   · §D 사후 검증 : 표·UNIQUE·인덱스·FK 가 전부 걸렸는지 확인하고, 하나라도 빠지면 실패로 끝낸다.
-- 두 관문 모두 SIGNAL SQLSTATE '45000' 으로 mysql 클라이언트를 0 이 아닌 코드로 종료시킨다.
--
-- 사후 검증이 필요한 이유는 04·05 와 똑같다: **ddl-auto=validate 는 UNIQUE 도 인덱스도 FK 도
-- 검사하지 않는다.** uq_chat_room_origin 이 빠진 채 배포해도 앱은 멀쩡히 뜨고, 같은 가족
-- 그룹에 방이 둘 생기는 것을 아무도 못 막는다.
--
-- §D 는 하나를 더 본다 — **chat_* 표에서 chat 경계 밖으로 나가는 FK 가 0개인지.**
-- 그건 ADR-0011 결정 4 이고, 운영 DB 에서도 지켜져야 하는 성질이다. 저장소 쪽은
-- ChatBoundaryArchitectureTest 와 ChatRoomRepositoryTest 가 같은 것을 잠근다.
--
-- 멱등: CREATE TABLE IF NOT EXISTS + 인덱스·FK 별 information_schema 가드 + PREPARE/EXECUTE.
--       (01~05 가 쓰는 것과 같은 패턴이다.) 재실행해도 안전하다.
--
-- ─────────────────────────────────────────────────────────────────────────────
-- 되돌리기(DOWN) — 실행하지 말 것. 되돌려야 할 때만 손으로 골라 쓴다.
--
--   DROP TABLE chat_room_invite;
--   DROP TABLE chat_room_member;
--   DROP TABLE chat_room;
--
-- 순서가 중요하다. chat_room 을 먼저 지우려 하면 자식 표의 FK 때문에 ERROR 3730 이 난다.
-- 되돌리면 모든 방·멤버십·초대코드가 사라진다. 대화 내용도 함께 사라진다(chat_message 는
-- chat_room 에 ON DELETE CASCADE 로 매달린다 — #77).
-- DOWN 전에 새 애플리케이션을 먼저 내려야 한다(엔티티가 이 표들을 요구한다).
-- ============================================================================


-- ── 0. 사전 점검 ────────────────────────────────────────────────────────────
-- 여기서 걸리면 스키마는 한 글자도 바뀌지 않는다.
--
-- 새 표인데 왜 점검이 필요한가: dev 는 ddl-auto=update 라 **앱이 먼저 뜨면 Hibernate 가
-- 표를 이미 만들어 둔다.** 엔티티 초안이 다른 상태로 만든 표(UNIQUE 없음 등)가 남아
-- 있을 수 있고, 그 안에 중복 (origin_kind, origin_ref) 나 중복 code 가 들어 있으면
-- UNIQUE 를 걸 수 없다. 그 경우에도 안전하게 실패해야 한다.

-- 중단 장치. SIGNAL 은 prepared statement 프로토콜이 지원하지 않아서(ERROR 1295)
-- 조건부로 던지려면 프로시저 한 겹이 필요하다. CALL 은 PREPARE 가능하다.
-- MESSAGE_TEXT 는 128자가 상한이다(넘기면 ERROR 1648).
DROP PROCEDURE IF EXISTS heattrip_migration_abort;
CREATE PROCEDURE heattrip_migration_abort(IN msg VARCHAR(128))
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = msg;

-- 0-1. chat_room 이 이미 있는지 본다(= 재실행이거나 Hibernate 가 먼저 만들었는지).
SET @room_exists := (
    SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name = 'chat_room');
SET @col_origin_kind := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'chat_room' AND column_name = 'origin_kind');
SET @col_origin_ref := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'chat_room' AND column_name = 'origin_ref');

-- 0-2. UNIQUE (origin_kind, origin_ref) 를 못 걸 데이터가 있는지 모은다.
--      아직 없는 표·컬럼을 정적 SQL 로 참조하면 파싱 단계에서 죽으므로 PREPARE 로 조립한다.
DROP TEMPORARY TABLE IF EXISTS heattrip_chat_room_precheck;
CREATE TEMPORARY TABLE heattrip_chat_room_precheck (
    origin_kind VARCHAR(64) NULL,
    origin_ref  VARCHAR(64) NULL,
    row_count   BIGINT      NOT NULL
);

SET @stmt := IF(@room_exists = 1 AND @col_origin_kind = 1 AND @col_origin_ref = 1,
    CONCAT(
        'INSERT INTO heattrip_chat_room_precheck (origin_kind, origin_ref, row_count) ',
        'SELECT r.origin_kind, r.origin_ref, COUNT(*) FROM chat_room r ',
        'GROUP BY r.origin_kind, r.origin_ref HAVING COUNT(*) > 1'),
    'SELECT ''[0-2] chat_room 이 아직 없다 — 사전 점검 대상 0행'' AS message');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- 0-3. 걸린 것이 있으면 그대로 보여 준다. (없으면 빈 결과)
--      origin_kind/origin_ref 는 개인정보가 아니라 도메인 이름과 그 도메인의 id 다.
SELECT '[0-3] UNIQUE 를 막는 (origin_kind, origin_ref) (있으면 방을 하나로 합친 뒤 재실행)' AS section;
SELECT origin_kind, origin_ref, row_count FROM heattrip_chat_room_precheck ORDER BY row_count DESC;

-- 0-4. 초대코드 쪽도 같은 점검을 한다.
SET @invite_exists := (
    SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name = 'chat_room_invite');
SET @col_code := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'chat_room_invite' AND column_name = 'code');

DROP TEMPORARY TABLE IF EXISTS heattrip_chat_invite_precheck;
CREATE TEMPORARY TABLE heattrip_chat_invite_precheck (
    code      VARCHAR(64) NULL,
    row_count BIGINT      NOT NULL
);

SET @stmt := IF(@invite_exists = 1 AND @col_code = 1,
    CONCAT(
        'INSERT INTO heattrip_chat_invite_precheck (code, row_count) ',
        'SELECT i.code, COUNT(*) FROM chat_room_invite i ',
        'GROUP BY i.code HAVING COUNT(*) > 1 OR i.code IS NULL'),
    'SELECT ''[0-4] chat_room_invite 가 아직 없다 — 사전 점검 대상 0행'' AS message');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SELECT '[0-5] UNIQUE 를 막는 초대코드 (있으면 해당 행을 지운 뒤 재실행)' AS section;
SELECT code, row_count FROM heattrip_chat_invite_precheck ORDER BY row_count DESC;

-- 0-6. 하나라도 걸리면 여기서 끝낸다. 스키마는 아직 그대로다.
SET @bad_rooms := (SELECT COUNT(*) FROM heattrip_chat_room_precheck);
SET @bad_codes := (SELECT COUNT(*) FROM heattrip_chat_invite_precheck);
SET @abort_msg := CONCAT(
    'ABORT: 중복 origin 쌍 ', @bad_rooms, '건, 중복/NULL 초대코드 ', @bad_codes,
    '건 — 위 [0-3][0-5] 참고. 정리한 뒤 다시 실행하라.');
SET @stmt := IF(@bad_rooms > 0 OR @bad_codes > 0,
    'CALL heattrip_migration_abort(@abort_msg)',
    'SELECT ''[0-6] 사전 점검 통과 — 중복 origin 쌍 없음, 중복 초대코드 없음'' AS message');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;


-- ── A. 표 생성 (멱등) ───────────────────────────────────────────────────────
-- 컬럼 타입은 엔티티(chat/entity/*.java)가 만들 모양과 같아야 한다. prod 의
-- ddl-auto=validate 가 타입 불일치로 부팅을 막기 때문이다. 정본은 mysql/init/01_schema.sql
-- 이고 그 파일은 엔티티에서 뽑은 것이다 — 값이 다르면 그쪽을 따른다.
--   · 문자열은 VARCHAR — Hibernate 는 String 을 그렇게 매핑한다.
--   · 시각은 DATETIME(6) — Hibernate 는 LocalDateTime 을 그렇게 만든다.
--   · role 은 VARCHAR(10) + CHECK — 네이티브 ENUM 을 쓰면 값이 늘 때 ALTER TABLE 이 필요하다.
--   · rejoin_blocked 는 BIT(1) — Hibernate 는 boolean 을 그렇게 만든다.
--
-- **users·family_group·dog 로 나가는 FK 는 걸지 않는다.** chat 경계 밖으로 FK 를 내지
-- 않는 것이 이 도메인의 규칙이고(ADR-0011 결정 4), refresh_token.user_id(#9)가 이미 같은
-- 방식이다. 특히 ON DELETE CASCADE 는 안 된다 — 탈퇴 한 번에 남의 방 멤버십과 미읽음
-- 기준이 사라진다. §D 가 이 성질을 다시 확인한다.

CREATE TABLE IF NOT EXISTS chat_room (
    id          BIGINT      NOT NULL AUTO_INCREMENT,
    origin_kind VARCHAR(20) NOT NULL,
    origin_ref  VARCHAR(64) NOT NULL,
    name        VARCHAR(50) NOT NULL,
    tag         VARCHAR(20) NOT NULL,
    last_seq    BIGINT      NOT NULL DEFAULT 0,
    created_at  DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    PRIMARY KEY (id),
    UNIQUE KEY uq_chat_room_origin (origin_kind, origin_ref)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS chat_room_member (
    id             BIGINT      NOT NULL AUTO_INCREMENT,
    room_id        BIGINT      NOT NULL,
    user_id        BIGINT      NOT NULL,
    role           VARCHAR(10) NOT NULL DEFAULT 'MEMBER',
    joined_at      DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    last_read_seq  BIGINT      NOT NULL DEFAULT 0,
    removed_at     DATETIME(6) NULL,
    removed_by     BIGINT      NULL,
    rejoin_blocked BIT(1)      NOT NULL DEFAULT b'0',
    PRIMARY KEY (id),
    UNIQUE KEY uq_chat_member (room_id, user_id),
    KEY idx_chat_member_user (user_id),
    CONSTRAINT fk_chat_member_room FOREIGN KEY (room_id)
        REFERENCES chat_room (id) ON DELETE CASCADE,
    -- 이름을 붙이지 않는다. Hibernate 가 @Enumerated(STRING) 매핑에서 만드는 CHECK 도
    -- 무명이라 MySQL 이 chat_room_member_chk_1 로 붙인다. 여기만 이름을 주면
    -- init 으로 세운 DB 와 post-start 로 세운 DB 의 제약 이름이 갈린다.
    CHECK (role IN ('OWNER','MEMBER'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS chat_room_invite (
    id         BIGINT      NOT NULL AUTO_INCREMENT,
    room_id    BIGINT      NOT NULL,
    code       VARCHAR(32) NOT NULL,
    created_by BIGINT      NOT NULL,
    expires_at DATETIME(6) NULL,
    max_uses   INT         NULL,
    used_count INT         NOT NULL DEFAULT 0,
    revoked_at DATETIME(6) NULL,
    created_at DATETIME(6) NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    PRIMARY KEY (id),
    UNIQUE KEY uq_chat_invite_code (code),
    KEY idx_chat_invite_room (room_id, created_at),
    CONSTRAINT fk_chat_invite_room FOREIGN KEY (room_id)
        REFERENCES chat_room (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;


-- ── B. 제약·인덱스 보정 (멱등) ──────────────────────────────────────────────
-- Hibernate 가 다른 초안으로 먼저 만들어 둔 표에는 UNIQUE 나 FK 가 없을 수 있다.
-- MySQL 에는 ADD CONSTRAINT 용 IF NOT EXISTS 가 없어서 information_schema 가드를 쓴다.
-- 이름은 엔티티의 @Table(uniqueConstraints/indexes)·@JoinColumn(foreignKey) 와 같아야 한다.

SET @idx_exists := (
    SELECT COUNT(*) FROM information_schema.statistics
    WHERE table_schema = DATABASE()
      AND table_name = 'chat_room'
      AND index_name = 'uq_chat_room_origin');
SET @stmt := IF(@idx_exists = 0,
    'ALTER TABLE chat_room ADD CONSTRAINT uq_chat_room_origin UNIQUE (origin_kind, origin_ref)',
    'SELECT ''[B] uq_chat_room_origin 은 이미 있다.'' AS message');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @idx_exists := (
    SELECT COUNT(*) FROM information_schema.statistics
    WHERE table_schema = DATABASE()
      AND table_name = 'chat_room_member'
      AND index_name = 'uq_chat_member');
SET @stmt := IF(@idx_exists = 0,
    'ALTER TABLE chat_room_member ADD CONSTRAINT uq_chat_member UNIQUE (room_id, user_id)',
    'SELECT ''[B] uq_chat_member 는 이미 있다.'' AS message');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @idx_exists := (
    SELECT COUNT(*) FROM information_schema.statistics
    WHERE table_schema = DATABASE()
      AND table_name = 'chat_room_member'
      AND index_name = 'idx_chat_member_user');
SET @stmt := IF(@idx_exists = 0,
    'CREATE INDEX idx_chat_member_user ON chat_room_member (user_id)',
    'SELECT ''[B] idx_chat_member_user 는 이미 있다.'' AS message');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @idx_exists := (
    SELECT COUNT(*) FROM information_schema.statistics
    WHERE table_schema = DATABASE()
      AND table_name = 'chat_room_invite'
      AND index_name = 'uq_chat_invite_code');
SET @stmt := IF(@idx_exists = 0,
    'ALTER TABLE chat_room_invite ADD CONSTRAINT uq_chat_invite_code UNIQUE (code)',
    'SELECT ''[B] uq_chat_invite_code 는 이미 있다.'' AS message');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @idx_exists := (
    SELECT COUNT(*) FROM information_schema.statistics
    WHERE table_schema = DATABASE()
      AND table_name = 'chat_room_invite'
      AND index_name = 'idx_chat_invite_room');
SET @stmt := IF(@idx_exists = 0,
    'CREATE INDEX idx_chat_invite_room ON chat_room_invite (room_id, created_at)',
    'SELECT ''[B] idx_chat_invite_room 은 이미 있다.'' AS message');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- 경계 **안쪽** FK 둘. 방이 지워지면 멤버십·초대도 함께 지워져야 한다.
SET @fk_exists := (
    SELECT COUNT(*) FROM information_schema.table_constraints
    WHERE table_schema = DATABASE()
      AND table_name = 'chat_room_member'
      AND constraint_name = 'fk_chat_member_room');
SET @stmt := IF(@fk_exists = 0,
    'ALTER TABLE chat_room_member ADD CONSTRAINT fk_chat_member_room FOREIGN KEY (room_id) REFERENCES chat_room (id) ON DELETE CASCADE',
    'SELECT ''[B] fk_chat_member_room 은 이미 있다.'' AS message');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @fk_exists := (
    SELECT COUNT(*) FROM information_schema.table_constraints
    WHERE table_schema = DATABASE()
      AND table_name = 'chat_room_invite'
      AND constraint_name = 'fk_chat_invite_room');
SET @stmt := IF(@fk_exists = 0,
    'ALTER TABLE chat_room_invite ADD CONSTRAINT fk_chat_invite_room FOREIGN KEY (room_id) REFERENCES chat_room (id) ON DELETE CASCADE',
    'SELECT ''[B] fk_chat_invite_room 은 이미 있다.'' AS message');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;


-- ── D. 사후 검증 ────────────────────────────────────────────────────────────
-- '반쯤 적용된 채 성공처럼 끝나는' 상태를 막는 마지막 관문이다.
-- validate 는 UNIQUE 도 인덱스도 FK 도 검사하지 않으므로, 여기서 확인하지 않으면 빠진
-- 사실을 앱도 CI 도 끝까지 알려주지 않는다.

SET @chat_tables := (
    SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema = DATABASE()
      AND table_name IN ('chat_room', 'chat_room_member', 'chat_room_invite'));

SET @room_columns := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'chat_room'
      AND column_name IN ('id', 'origin_kind', 'origin_ref', 'name', 'tag', 'last_seq', 'created_at'));

SET @member_columns := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'chat_room_member'
      AND column_name IN ('id', 'room_id', 'user_id', 'role', 'joined_at',
                          'last_read_seq', 'removed_at', 'removed_by', 'rejoin_blocked'));

SET @invite_columns := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'chat_room_invite'
      AND column_name IN ('id', 'room_id', 'code', 'created_by', 'expires_at',
                          'max_uses', 'used_count', 'revoked_at', 'created_at'));

-- UNIQUE 는 컬럼 수로 센다 — (origin_kind, origin_ref) 는 2행, (room_id, user_id) 는 2행,
-- (code) 는 1행이다. 인덱스 이름만 보면 '한 컬럼만 걸린 UNIQUE' 를 통과시킨다.
SET @uq_room := (
    SELECT COUNT(*) FROM information_schema.statistics
    WHERE table_schema = DATABASE() AND table_name = 'chat_room'
      AND index_name = 'uq_chat_room_origin' AND non_unique = 0);
SET @uq_member := (
    SELECT COUNT(*) FROM information_schema.statistics
    WHERE table_schema = DATABASE() AND table_name = 'chat_room_member'
      AND index_name = 'uq_chat_member' AND non_unique = 0);
SET @uq_invite := (
    SELECT COUNT(*) FROM information_schema.statistics
    WHERE table_schema = DATABASE() AND table_name = 'chat_room_invite'
      AND index_name = 'uq_chat_invite_code' AND non_unique = 0);

SET @inside_fks := (
    SELECT COUNT(*) FROM information_schema.referential_constraints
    WHERE constraint_schema = DATABASE()
      AND table_name IN ('chat_room_member', 'chat_room_invite')
      AND referenced_table_name = 'chat_room');

-- 경계 밖으로 나가는 FK. **0이어야 한다** (ADR-0011 결정 4).
SET @outside_fks := (
    SELECT COUNT(*) FROM information_schema.referential_constraints
    WHERE constraint_schema = DATABASE()
      AND table_name LIKE 'chat\_%'
      AND referenced_table_name NOT LIKE 'chat\_%');

SELECT '[D] 사후 검증' AS section,
       @chat_tables    AS tables_expect_3,
       @room_columns   AS room_columns_expect_7,
       @member_columns AS member_columns_expect_9,
       @invite_columns AS invite_columns_expect_9,
       @uq_room        AS uq_room_columns_expect_2,
       @uq_member      AS uq_member_columns_expect_2,
       @uq_invite      AS uq_invite_columns_expect_1,
       @inside_fks     AS inside_fks_expect_2,
       @outside_fks    AS outside_fks_expect_0;

SET @abort_msg := CONCAT(
    'ABORT: 반쯤 적용됨 — 표 ', @chat_tables, '/3, UNIQUE ', @uq_room, '/2 ', @uq_member,
    '/2 ', @uq_invite, '/1, 경계안 FK ', @inside_fks, '/2. 위 [D] 참고.');
SET @stmt := IF(@chat_tables <> 3 OR @room_columns <> 7 OR @member_columns <> 9
                OR @invite_columns <> 9 OR @uq_room <> 2 OR @uq_member <> 2
                OR @uq_invite <> 1 OR @inside_fks <> 2,
    'CALL heattrip_migration_abort(@abort_msg)',
    'SELECT ''[D] 사후 검증 통과 — 표·컬럼·UNIQUE·경계안 FK 모두 적용됨'' AS message');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @abort_msg := CONCAT(
    'ABORT: chat 경계 밖으로 나가는 FK 가 ', @outside_fks,
    '개다. users/family_group/dog 로의 FK 는 0이어야 한다 (ADR-0011).');
SET @stmt := IF(@outside_fks > 0,
    'CALL heattrip_migration_abort(@abort_msg)',
    'SELECT ''[D] 경계 검증 통과 — chat 밖으로 나가는 FK 0개'' AS message');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- 참고용. 실패시키지 않는다.
SELECT '[D] 현재 chat_room 행 수 (첫 실행이면 0이다)' AS section;
SELECT COUNT(*) AS rows_count FROM chat_room;

DROP TEMPORARY TABLE IF EXISTS heattrip_chat_room_precheck;
DROP TEMPORARY TABLE IF EXISTS heattrip_chat_invite_precheck;
DROP PROCEDURE IF EXISTS heattrip_migration_abort;

SELECT '06_chat_rooms.sql 완료' AS message;


-- ── E. 여기서 하지 않는 것 (판단 근거) ──────────────────────────────────────
-- · **last_seq 발급 로직은 없다.** UPDATE chat_room SET last_seq = LAST_INSERT_ID(last_seq + 1)
--   는 이슈 #78 이 넣는다. 이 스크립트는 컬럼과 기본값 0 까지다.
-- · **chat_message 는 없다.** 이슈 #77 이 만든다. 그 표가 chat_room 에 매다는 FK 는
--   경계 **안**이라 이 규칙에 걸리지 않는다.
-- · **family_group 은 만들지 않는다.** 방은 그 표를 몰라도 된다 — origin_kind/origin_ref
--   불투명 쌍이 유일한 통로이고, 그래서 순서 의존이 없다.
-- · **group_member 는 영영 만들지 않는다.** 멤버십은 chat_room_member 하나다
--   (ADR-0011 결정 1). 둘을 두면 '가족인데 방에 없는 사람' 이라는 상태가 생기고,
--   그걸 막는 코드를 영원히 쓴다.
