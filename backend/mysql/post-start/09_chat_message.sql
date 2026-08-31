-- ============================================================================
-- 09_chat_message.sql
-- 채팅 메시지 표와 방별 room_seq — 이슈 #78 (근거: ADR-0011 결정 2·4)
-- 대상: MySQL 8.x (운영/개발 공통)
--
-- ─────────────────────────────────────────────────────────────────────────────
-- 실행 순서
--
--   1. 06_chat_rooms.sql 이 먼저다 (이 표가 chat_room 에 FK 를 건다)
--   2. 이 스크립트를 실행한다 (앱 배포 **전**)
--   3. 그 다음 새 애플리케이션을 배포한다
--
-- 이 순서는 사실상 강제된다 — prod 는 ddl-auto=validate 라 엔티티가 요구하는 테이블이
-- 없으면 **부팅 자체가 실패한다.** 되돌릴 때는 반대로, 앱을 먼저 내린다.
--
-- 빈 DB 를 새로 세우는 경우에는 이 파일이 필요 없다. mysql/init/01_schema.sql 이
-- chat_message 를 이미 담고 있다(#58).
--
-- ─────────────────────────────────────────────────────────────────────────────
-- 이 표에서 되돌리기 비싼 결정 셋
--
-- 1. **UNIQUE (room_id, room_seq).** 커서가 id 가 아니라 room_seq 인 것이 이 표의 요점이다.
--    id AUTO_INCREMENT 는 INSERT 시점에 배정되고 가시성은 커밋 시점에 생겨서, 늦게 커밋된
--    작은 id 를 afterId 폴링이 **영구히** 건너뛴다. 그 자리를 막는 것이 이 제약이다.
-- 2. **UNIQUE (room_id, sender_user_id, client_msg_id).** 재전송 멱등의 근거다. 없으면
--    타임아웃된 전송을 앱이 재시도할 때 같은 말이 두 줄 남고, 그 둘은 서로 다른 room_seq 를
--    가져 어느 쪽도 지울 근거가 없다. NULL 은 여러 번 허용되므로 멱등키 없는 전송은 막지
--    않는다. 범위에 sender_user_id 가 들어 있는 것은 #79 에서 좁힌 것이다 — #78 의
--    (room_id, client_msg_id) 는 같은 방의 다른 멤버가 같은 키를 쓰면 뒤에 보낸 사람의
--    메시지를 조용히 삼켰다(실측). 멱등이 막아야 하는 것은 '같은 사람의 같은 요청' 이다.
-- 3. **sender_user_id 에 FK 를 걸지 않는다.** ADR-0011 결정 4 이고, 여기서는 이유가 하나 더
--    있다 — ON DELETE CASCADE 면 탈퇴 한 번에 그 사람이 방에 쓴 말이 전부 사라지고, 남는
--    것은 대답만 있고 질문이 없는 대화다. §D 가 이 성질을 다시 확인한다.
--
-- ⚠️ 트랜잭션으로 감쌀 수 없다 — 06 과 같다. MySQL 의 DDL 은 암묵적 커밋을 일으킨다.
--    그래서 앞뒤로 관문을 둔다: §0 사전 점검 · §D 사후 검증.
--    두 관문 모두 SIGNAL SQLSTATE '45000' 으로 mysql 클라이언트를 0 이 아닌 코드로 끝낸다.
--
-- 멱등: CREATE TABLE IF NOT EXISTS + 인덱스·FK 별 information_schema 가드 + PREPARE/EXECUTE.
--       (01~08 이 쓰는 것과 같은 패턴이다.) 재실행해도 안전하다.
--
-- ─────────────────────────────────────────────────────────────────────────────
-- 되돌리기(DOWN) — 실행하지 말 것. 되돌려야 할 때만 손으로 골라 쓴다.
--
--   DROP TABLE chat_message;
--
-- 되돌리면 **모든 대화 내용이 사라진다.** 방·멤버십은 남지만 그 방의 말은 복구할 수 없고,
-- 미읽음의 좌변인 chat_room.last_seq 는 그대로 남아 실제 메시지보다 큰 값을 가리키게 된다.
-- DOWN 전에 새 애플리케이션을 먼저 내려야 한다(엔티티가 이 표를 요구한다).
-- ============================================================================


-- ── 0. 사전 점검 ────────────────────────────────────────────────────────────
-- 여기서 걸리면 스키마는 한 글자도 바뀌지 않는다.

-- 중단 장치. SIGNAL 은 prepared statement 프로토콜이 지원하지 않아서(ERROR 1295)
-- 조건부로 던지려면 프로시저 한 겹이 필요하다. MESSAGE_TEXT 는 128자가 상한이다.
DROP PROCEDURE IF EXISTS heattrip_migration_abort;
CREATE PROCEDURE heattrip_migration_abort(IN msg VARCHAR(128))
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = msg;

-- 0-1. 부모 표가 있어야 FK 를 건다. 없으면 06 을 먼저 돌리라고 말하고 멈춘다.
--      "FK 를 빼고 만들어 두는" 선택지는 없다 — 방이 지워졌는데 그 방의 메시지가 남으면
--      아무도 볼 수 없는 행이 영원히 쌓인다.
SET @room_table := (
    SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name = 'chat_room');
SET @stmt := IF(@room_table = 0,
    'CALL heattrip_migration_abort(''ABORT: chat_room 이 없다. post-start/06_chat_rooms.sql 을 먼저 실행하라.'')',
    'SELECT ''[0-1] chat_room 확인 — FK 를 걸 수 있다'' AS message');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- 0-2. chat_message 가 이미 있는지 본다(= 재실행이거나 Hibernate 가 먼저 만들었는지).
--      dev 는 ddl-auto=update 라 **앱이 먼저 뜨면 Hibernate 가 표를 이미 만들어 둔다.**
--      엔티티 초안이 다른 상태로 만든 표(UNIQUE 없음 등)에 중복 행이 들어 있으면
--      UNIQUE 를 걸 수 없다. 그 경우에도 안전하게 실패해야 한다.
SET @msg_exists := (
    SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name = 'chat_message');
SET @col_room_id := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'chat_message' AND column_name = 'room_id');
SET @col_room_seq := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'chat_message' AND column_name = 'room_seq');
SET @col_client := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'chat_message' AND column_name = 'client_msg_id');
SET @col_sender := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'chat_message'
      AND column_name = 'sender_user_id');

DROP TEMPORARY TABLE IF EXISTS heattrip_chat_seq_precheck;
CREATE TEMPORARY TABLE heattrip_chat_seq_precheck (
    room_id   BIGINT NULL,
    room_seq  BIGINT NULL,
    row_count BIGINT NOT NULL
);

SET @stmt := IF(@msg_exists = 1 AND @col_room_id = 1 AND @col_room_seq = 1,
    CONCAT(
        'INSERT INTO heattrip_chat_seq_precheck (room_id, room_seq, row_count) ',
        'SELECT m.room_id, m.room_seq, COUNT(*) FROM chat_message m ',
        'GROUP BY m.room_id, m.room_seq HAVING COUNT(*) > 1'),
    'SELECT ''[0-2] chat_message 가 아직 없다 — 사전 점검 대상 0행'' AS message');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- 0-3. 걸린 것이 있으면 그대로 보여 준다. (없으면 빈 결과)
--      방 id 와 번호만 낸다 — 본문도 발신자도 여기 싣지 않는다(#6).
SELECT '[0-3] UNIQUE 를 막는 (room_id, room_seq) (있으면 한쪽 번호를 다시 매긴 뒤 재실행)' AS section;
SELECT room_id, room_seq, row_count FROM heattrip_chat_seq_precheck ORDER BY row_count DESC;

-- 0-4. 멱등키 쪽도 같은 점검을 한다. NULL 은 중복이 아니다 — 세지 않는다.
--      범위는 (room_id, sender_user_id, client_msg_id) 다 — 보낸 사람까지 포함한다(#79).
--      #78 이 세운 (room_id, client_msg_id) 는 같은 방의 다른 멤버가 같은 키를 쓰면
--      뒤에 보낸 사람의 메시지를 조용히 삼켰다(실측). 좁히는 방향이라 옛 제약을 통과한
--      데이터는 새 제약도 반드시 통과한다 — 이 점검이 더 엄해지지 않는다.
DROP TEMPORARY TABLE IF EXISTS heattrip_chat_client_precheck;
CREATE TEMPORARY TABLE heattrip_chat_client_precheck (
    room_id        BIGINT      NULL,
    sender_user_id BIGINT      NULL,
    client_msg_id  VARCHAR(64) NULL,
    row_count      BIGINT      NOT NULL
);

SET @stmt := IF(@msg_exists = 1 AND @col_room_id = 1 AND @col_client = 1 AND @col_sender = 1,
    CONCAT(
        'INSERT INTO heattrip_chat_client_precheck ',
        '(room_id, sender_user_id, client_msg_id, row_count) ',
        'SELECT m.room_id, m.sender_user_id, m.client_msg_id, COUNT(*) FROM chat_message m ',
        'WHERE m.client_msg_id IS NOT NULL ',
        'GROUP BY m.room_id, m.sender_user_id, m.client_msg_id HAVING COUNT(*) > 1'),
    'SELECT ''[0-4] chat_message 가 아직 없다 — 사전 점검 대상 0행'' AS message');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SELECT '[0-5] UNIQUE 를 막는 (room_id, sender_user_id, client_msg_id) (있으면 늦게 들어온 중복 행을 지운 뒤 재실행)' AS section;
SELECT room_id, sender_user_id, client_msg_id, row_count
FROM heattrip_chat_client_precheck ORDER BY row_count DESC;

-- 0-6. 하나라도 걸리면 여기서 끝낸다. 스키마는 아직 그대로다.
SET @bad_seqs := (SELECT COUNT(*) FROM heattrip_chat_seq_precheck);
SET @bad_keys := (SELECT COUNT(*) FROM heattrip_chat_client_precheck);
SET @abort_msg := CONCAT(
    'ABORT: 중복 (room_id, room_seq) ', @bad_seqs, '건, 중복 멱등키 ', @bad_keys,
    '건 — 위 [0-3][0-5] 참고. 정리한 뒤 다시 실행하라.');
SET @stmt := IF(@bad_seqs > 0 OR @bad_keys > 0,
    'CALL heattrip_migration_abort(@abort_msg)',
    'SELECT ''[0-6] 사전 점검 통과 — 중복 번호 없음, 중복 멱등키 없음'' AS message');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;


-- ── A. 표 생성 (멱등) ───────────────────────────────────────────────────────
-- 컬럼 타입은 엔티티(chat/entity/ChatMessage.java)가 만들 모양과 같아야 한다. prod 의
-- ddl-auto=validate 가 타입 불일치로 부팅을 막기 때문이다. 정본은 mysql/init/01_schema.sql
-- 이고 그 파일은 엔티티에서 뽑은 것이다 — 값이 다르면 그쪽을 따른다.
--   · 시각은 DATETIME(6) — Hibernate 는 LocalDateTime 을 그렇게 만든다.
--   · body 는 TEXT(64KB) — LONGTEXT 가 아니다. 한 줄 채팅에 4GB 를 열어 둘 이유가 없다.
--   · sender_name 은 VARCHAR(255) — users.nickname 과 같은 폭이다.
--
-- **users 로 나가는 FK 는 걸지 않는다.** 위 헤더 3번 참조. §D 가 다시 확인한다.

CREATE TABLE IF NOT EXISTS chat_message (
    id             BIGINT       NOT NULL AUTO_INCREMENT,
    room_id        BIGINT       NOT NULL,
    room_seq       BIGINT       NOT NULL,
    sender_user_id BIGINT       NOT NULL,
    sender_name    VARCHAR(255) NOT NULL,
    content_type   VARCHAR(16)  NOT NULL DEFAULT 'text',
    body           TEXT         NOT NULL,
    client_msg_id  VARCHAR(64)  NULL,
    created_at     DATETIME(6)  NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    deleted_at     DATETIME(6)  NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uq_chat_room_seq (room_id, room_seq),
    UNIQUE KEY uq_chat_msg_client (room_id, sender_user_id, client_msg_id),
    KEY idx_chat_sender (sender_user_id),
    CONSTRAINT fk_chat_room FOREIGN KEY (room_id)
        REFERENCES chat_room (id) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;


-- ── B. 제약·인덱스 보정 (멱등) ──────────────────────────────────────────────
-- Hibernate 가 다른 초안으로 먼저 만들어 둔 표에는 UNIQUE 나 FK 가 없을 수 있다.
-- MySQL 에는 ADD CONSTRAINT 용 IF NOT EXISTS 가 없어서 information_schema 가드를 쓴다.
-- 이름은 엔티티의 @Table(uniqueConstraints/indexes)·@JoinColumn(foreignKey) 와 같아야 한다.

SET @idx_exists := (
    SELECT COUNT(*) FROM information_schema.statistics
    WHERE table_schema = DATABASE()
      AND table_name = 'chat_message'
      AND index_name = 'uq_chat_room_seq');
SET @stmt := IF(@idx_exists = 0,
    'ALTER TABLE chat_message ADD CONSTRAINT uq_chat_room_seq UNIQUE (room_id, room_seq)',
    'SELECT ''[B] uq_chat_room_seq 는 이미 있다.'' AS message');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- uq_chat_msg_client 는 **범위가 바뀌었다** (#79).
-- #78 이 (room_id, client_msg_id) 로 세웠는데, 그 범위에서는 같은 방의 다른 멤버가 같은
-- 키를 쓰면 뒤에 보낸 사람의 메시지가 조용히 사라진다(실측 — 서버가 200 과 함께 남의
-- 메시지를 돌려주므로 앱은 성공으로 읽고 재시도하지 않는다). 그래서 보낸 사람까지 범위에
-- 넣는다. **좁히는 방향이라 이미 쌓인 데이터가 새 제약을 어길 수 없다** — 옛 제약을
-- 통과한 행들은 새 제약도 통과한다.
--
-- 이미 2컬럼으로 걸려 있는 DB 는 이름이 같으므로 아래 "없으면 만든다" 가드만으로는
-- 안 고쳐진다. 컬럼 수를 세서 다르면 먼저 떨어뜨린다. 인덱스가 아예 없는 DB 에서는
-- 아무 일도 하지 않는다(@uq_client_columns = 0).
SET @uq_client_columns := (
    SELECT COUNT(*) FROM information_schema.statistics
    WHERE table_schema = DATABASE()
      AND table_name = 'chat_message'
      AND index_name = 'uq_chat_msg_client');
SET @stmt := IF(@uq_client_columns > 0 AND @uq_client_columns <> 3,
    'ALTER TABLE chat_message DROP INDEX uq_chat_msg_client',
    'SELECT ''[B] uq_chat_msg_client 의 범위를 고칠 것이 없다.'' AS message');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @idx_exists := (
    SELECT COUNT(*) FROM information_schema.statistics
    WHERE table_schema = DATABASE()
      AND table_name = 'chat_message'
      AND index_name = 'uq_chat_msg_client');
SET @stmt := IF(@idx_exists = 0,
    'ALTER TABLE chat_message ADD CONSTRAINT uq_chat_msg_client UNIQUE (room_id, sender_user_id, client_msg_id)',
    'SELECT ''[B] uq_chat_msg_client 는 이미 있다.'' AS message');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @idx_exists := (
    SELECT COUNT(*) FROM information_schema.statistics
    WHERE table_schema = DATABASE()
      AND table_name = 'chat_message'
      AND index_name = 'idx_chat_sender');
SET @stmt := IF(@idx_exists = 0,
    'CREATE INDEX idx_chat_sender ON chat_message (sender_user_id)',
    'SELECT ''[B] idx_chat_sender 는 이미 있다.'' AS message');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- 경계 **안쪽** FK. 방이 지워지면 그 방의 대화도 갈 곳이 없다.
SET @fk_exists := (
    SELECT COUNT(*) FROM information_schema.table_constraints
    WHERE table_schema = DATABASE()
      AND table_name = 'chat_message'
      AND constraint_name = 'fk_chat_room');
SET @stmt := IF(@fk_exists = 0,
    'ALTER TABLE chat_message ADD CONSTRAINT fk_chat_room FOREIGN KEY (room_id) REFERENCES chat_room (id) ON DELETE CASCADE',
    'SELECT ''[B] fk_chat_room 은 이미 있다.'' AS message');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;


-- ── D. 사후 검증 ────────────────────────────────────────────────────────────
-- '반쯤 적용된 채 성공처럼 끝나는' 상태를 막는 마지막 관문이다.
-- ddl-auto=validate 는 UNIQUE 도 인덱스도 FK 도 검사하지 않으므로, 여기서 확인하지 않으면
-- 빠진 사실을 앱도 CI 도 끝까지 알려주지 않는다. uq_chat_room_seq 가 빠진 채 배포해도
-- 앱은 멀쩡히 뜨고, 발급이 틀린 날 조용히 메시지 하나가 사라진다.

SET @msg_table := (
    SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name = 'chat_message');

SET @msg_columns := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'chat_message'
      AND column_name IN ('id', 'room_id', 'room_seq', 'sender_user_id', 'sender_name',
                          'content_type', 'body', 'client_msg_id', 'created_at', 'deleted_at'));

-- UNIQUE 는 컬럼 수로 센다 — 이름만 보면 '한 컬럼만 걸린 UNIQUE' 를 통과시킨다.
-- (room_id) 하나에만 UNIQUE 가 걸리면 한 방에 메시지가 한 줄만 들어간다.
SET @uq_seq := (
    SELECT COUNT(*) FROM information_schema.statistics
    WHERE table_schema = DATABASE() AND table_name = 'chat_message'
      AND index_name = 'uq_chat_room_seq' AND non_unique = 0);
SET @uq_client := (
    SELECT COUNT(*) FROM information_schema.statistics
    WHERE table_schema = DATABASE() AND table_name = 'chat_message'
      AND index_name = 'uq_chat_msg_client' AND non_unique = 0);
SET @idx_sender := (
    SELECT COUNT(*) FROM information_schema.statistics
    WHERE table_schema = DATABASE() AND table_name = 'chat_message'
      AND index_name = 'idx_chat_sender');

SET @inside_fks := (
    SELECT COUNT(*) FROM information_schema.referential_constraints
    WHERE constraint_schema = DATABASE()
      AND table_name = 'chat_message'
      AND referenced_table_name = 'chat_room');

-- 경계 밖으로 나가는 FK. **0이어야 한다** (ADR-0011 결정 4).
SET @outside_fks := (
    SELECT COUNT(*) FROM information_schema.referential_constraints
    WHERE constraint_schema = DATABASE()
      AND table_name LIKE 'chat\_%'
      AND referenced_table_name NOT LIKE 'chat\_%');

SELECT '[D] 사후 검증' AS section,
       @msg_table   AS table_expect_1,
       @msg_columns AS columns_expect_10,
       @uq_seq      AS uq_seq_columns_expect_2,
       @uq_client   AS uq_client_columns_expect_3,
       @idx_sender  AS idx_sender_columns_expect_1,
       @inside_fks  AS inside_fks_expect_1,
       @outside_fks AS outside_fks_expect_0;

SET @abort_msg := CONCAT(
    'ABORT: 반쯤 적용됨 — 표 ', @msg_table, '/1, 컬럼 ', @msg_columns, '/10, UNIQUE ',
    @uq_seq, '/2 ', @uq_client, '/3, 인덱스 ', @idx_sender, '/1, 경계안 FK ',
    @inside_fks, '/1. 위 [D] 참고.');
SET @stmt := IF(@msg_table <> 1 OR @msg_columns <> 10 OR @uq_seq <> 2 OR @uq_client <> 3
                OR @idx_sender <> 1 OR @inside_fks <> 1,
    'CALL heattrip_migration_abort(@abort_msg)',
    'SELECT ''[D] 사후 검증 통과 — 표·컬럼·UNIQUE·인덱스·경계안 FK 모두 적용됨'' AS message');
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
SELECT '[D] 현재 chat_message 행 수 (첫 실행이면 0이다)' AS section;
SELECT COUNT(*) AS rows_count FROM chat_message;

DROP TEMPORARY TABLE IF EXISTS heattrip_chat_seq_precheck;
DROP TEMPORARY TABLE IF EXISTS heattrip_chat_client_precheck;
DROP PROCEDURE IF EXISTS heattrip_migration_abort;

SELECT '09_chat_message.sql 완료' AS message;


-- ── E. 여기서 하지 않는 것 (판단 근거) ──────────────────────────────────────
-- · **chat_room.last_seq 를 지금 값으로 맞추지 않는다.** 이 표가 비어 있는 상태로 생기므로
--   맞출 것이 없다. 이미 메시지가 있는 DB 에 이 스크립트를 돌리는 경우는 dev 에서 Hibernate 가
--   먼저 만든 표뿐이고, 그때는 §0 이 중복을 먼저 본다.
-- · **읽음 커서(last_read_seq) 는 건드리지 않는다.** 그 컬럼은 06 이 이미 만들었고, 값을
--   올리는 것은 #79 의 읽음 엔드포인트다.
-- · **삭제 정리 잡은 없다.** deleted_at 은 톰스톤이라 지우지 않는다 — 조회에서 빼면 그
--   room_seq 가 클라이언트에 도달하지 않아 미읽음 뱃지가 영원히 남는다(ADR-0011).
