-- ============================================================================
-- 08_care_log.sql
-- 케어 로그와 산책 주의사항 — 이슈 #76 (근거: ADR-0011 · 📌 #86)
-- 대상: MySQL 8.x (운영/개발 공통)
--
-- ─────────────────────────────────────────────────────────────────────────────
-- 실행 순서
--
--   1. 07_family_group.sql 을 먼저 실행한다 (family_group 표)
--   2. 이 스크립트를 실행한다 (앱 배포 **전**)
--   3. 그 다음 새 애플리케이션을 배포한다
--
-- 1 이 앞인 것은 이번에는 **진짜 FK 때문**이다. 07 과 다르다 — 여기서 만드는 두 표는
-- family_group(id) 와 users(id) 로 FK 를 건다. 부모 표가 없으면 CREATE 자체가 실패한다.
--
-- 3 은 사실상 강제된다 — prod 는 ddl-auto=validate 라 엔티티가 요구하는 표가 없으면
-- 부팅 자체가 실패한다. 되돌릴 때는 반대로, 앱을 먼저 내린다.
--
-- 빈 DB 를 새로 세우는 경우에는 이 파일이 필요 없다. mysql/init/01_schema.sql 이
-- 두 표를 이미 담고 있다(#58).
--
-- ─────────────────────────────────────────────────────────────────────────────
-- ⚠️ 트랜잭션으로 감쌀 수 없다 — 실패해도 되돌아가지 않는다
--
-- MySQL 의 DDL 은 **암묵적 커밋**을 일으킨다. 그래서 04~07 과 같이 앞뒤로 관문을 둔다.
--   · §0 사전 점검 : 같은 이름의 표가 **다른 모양**으로 이미 있으면 아무것도 바꾸기 전에 멈춘다.
--   · §D 사후 검증 : 표·컬럼·FK·UNIQUE 와 **경계**가 전부 맞는지 확인하고, 하나라도 어긋나면
--                    실패로 끝낸다. validate 는 FK 도 UNIQUE 도 CHECK 도 안 본다.
--
-- ─────────────────────────────────────────────────────────────────────────────
-- users 로 가는 FK 둘은 ON DELETE **SET NULL** 이다 — CASCADE 였다가 고쳤다
--
-- care_log.done_by 와 walk_note.updated_by 는 2026-08 까지 ON DELETE CASCADE 였다.
-- 그 상태에서 DELETE /auth/me (users 행 하드 삭제) 한 번이면
--   · 그 사람이 마지막으로 고친 **가족 공유 산책 주의사항 한 장이 통째로** 사라지고
--     (남은 가족의 화면은 '아직 주의사항이 없어요' 라 지워진 줄도 모른다),
--   · 그 사람이 남긴 케어 기록도 함께 사라져 '오늘 누가 무엇을 했나' 가 거짓이 된다.
-- 두 컬럼은 문서의 소유자가 아니라 **메타데이터**다. 메모의 주인은 group_id 이고 그 그룹은
-- 살아 있다. care_log.group_id 가 이미 같은 질문에 SET NULL 로 답했다.
-- 이름은 응답에서 '알 수 없음'(User.UNKNOWN_DISPLAY_NAME)으로 떨어진다.
--
-- 이 스크립트를 CASCADE 시절에 이미 돌린 DB 가 있으므로 §B 가 그것을 고친다.
--
-- ─────────────────────────────────────────────────────────────────────────────
-- ⚠️ care_log.dog_id 에 FK 가 없다 — 판단이 아니라 사실이다
--
-- 이슈 본문은 dog_id FK 라고 적었지만 **dog 표가 정본 스키마에 없다.**
-- mysql/init/01_schema.sql 에 CREATE TABLE dog 가 0건이고(docs/03-database/schema.md §3 은
-- 계획으로만 적혀 있다), 앱의 DogProfile·kMyPets 는 전부 클라이언트 더미라 서버 쪽 강아지
-- id 자체가 존재하지 않는다. 없는 표에는 FK 를 걸 수 없다.
--
-- 그래서 컬럼은 NULL 허용으로 지금 넣고 값은 항상 NULL 이다. 지금 넣는 이유는 나중에
-- 넣으면 운영 데이터 위의 ALTER 가 되기 때문이고, dog 표가 생기는 날 그 자리에 FK 를 건다.
--
-- **#9 의 '일부러 FK 를 안 걸었다' 와 같은 것이 아니다.** #9(refresh_token)는 users 표가
-- 있는데도 걸지 않은 판단이고(탈퇴 경로가 DB 삭제 순서에 묶이는 것을 피했다), 여기는
-- 참조할 표가 아직 없는 것이다. 그날이 오면 여기는 걸고 #9 는 안 건다.
--
-- ─────────────────────────────────────────────────────────────────────────────
-- walk_note 는 **그룹당 한 장**이다 — 문서 셋이 반대말을 하고 있었다
--
-- 이슈 #76 이 정한 모양은 walk_note(id, group_id, body, updated_by, updated_at) 한 장이다.
-- schema.md §16 · openapi.yaml · api-spec.md 는 1:N 목록(행마다 created_at, PUT 은
-- {notes:[...]} 전량 교체)으로 적혀 있었고, 이 커밋이 셋을 이슈에 맞췄다.
-- 목록을 전량 교체로 다루면 PUT 때마다 행을 지우고 다시 넣게 되어 updated_by 가
-- 아무것도 가리키지 않게 된다. §0 이 옛 모양(created_at 컬럼)이 남아 있으면 중단한다.
--
-- ─────────────────────────────────────────────────────────────────────────────
-- 되돌리기(DOWN) — 실행하지 말 것. 되돌려야 할 때만 손으로 골라 쓴다.
--
--   DROP TABLE care_log;
--   DROP TABLE walk_note;
--
-- 되돌리면 케어 기록과 주의사항이 사라진다. **그룹·방·대화는 남는다** — 화살표가 이쪽에서
-- 저쪽으로만 가기 때문이다. DOWN 전에 새 애플리케이션을 먼저 내려야 한다.
-- ============================================================================


-- ── 0. 사전 점검 ────────────────────────────────────────────────────────────
-- 여기서 걸리면 스키마는 한 글자도 바뀌지 않는다.
--
-- CREATE TABLE IF NOT EXISTS 는 **이미 있는 표를 고치지 않는다.** 그래서 이름만 같고
-- 모양이 다른 표가 있으면 이 스크립트는 조용히 성공하고, 그 차이는 prod 부팅
-- (ddl-auto=validate)에서야 드러난다. 그 전에 여기서 멈춘다.

DROP PROCEDURE IF EXISTS heattrip_migration_abort;
CREATE PROCEDURE heattrip_migration_abort(IN msg VARCHAR(128))
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = msg;

-- 0-0. 부모 표가 있어야 FK 를 건다. 없으면 CREATE 가 죽는데, 그때 나오는 메시지
--      (errno 150)는 원인을 안 알려준다. 여기서 사람 말로 멈춘다.
SET @parents := (
    SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name IN ('family_group', 'users'));

-- MESSAGE_TEXT 는 128자가 상한이라 문구를 짧게 유지한다(넘기면 원인 대신 '데이터가 길다' 가 뜬다).
SET @abort_msg := CONCAT(
    'ABORT: 부모 표가 ', @parents, '/2 다. 07_family_group.sql 을 먼저 실행하라.');
SET @stmt := IF(@parents <> 2,
    'CALL heattrip_migration_abort(@abort_msg)',
    'SELECT ''[0-0] 부모 표 확인 — family_group · users'' AS message');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- 0-1. care_log 가 문서의 옛 계획대로 이미 만들어져 있는지.
--      옛 계획은 dog_id BIGINT NOT NULL + fk_carelog_dog 였다. dog 표가 없으므로 그 모양이면
--      이 앱은 어차피 못 쓴다(엔티티는 dog_id 를 nullable 로 요구한다).
SET @carelog_exists := (
    SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name = 'care_log');

SET @carelog_dog_not_null := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'care_log'
      AND column_name = 'dog_id' AND is_nullable = 'NO');

SET @carelog_columns := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'care_log'
      AND column_name IN ('id', 'dog_id', 'group_id', 'type', 'done_by',
                          'occurred_at', 'memo', 'created_at'));

-- 0-2. walk_note 의 옛 모양(1:N 목록). created_at 이 있으면 그 모양이다.
SET @walknote_exists := (
    SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name = 'walk_note');

SET @walknote_legacy := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'walk_note'
      AND column_name = 'created_at');

SET @walknote_columns := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'walk_note'
      AND column_name IN ('id', 'group_id', 'body', 'updated_by', 'updated_at'));

SELECT '[0] 사전 점검' AS section,
       @carelog_exists       AS care_log_exists,
       @carelog_dog_not_null AS dog_id_not_null_expect_0,
       @carelog_columns      AS care_log_columns_expect_0_or_8,
       @walknote_exists      AS walk_note_exists,
       @walknote_legacy      AS walk_note_created_at_expect_0,
       @walknote_columns     AS walk_note_columns_expect_0_or_5;

SET @abort_msg := 'ABORT: care_log.dog_id 가 NOT NULL 이다. dog 표가 없어 채울 수 없다 — NULL 허용으로 바꿔라.';
SET @stmt := IF(@carelog_dog_not_null > 0,
    'CALL heattrip_migration_abort(@abort_msg)',
    'SELECT ''[0-1] care_log 옛 dog_id 모양 없음'' AS message');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @abort_msg := CONCAT(
    'ABORT: care_log 컬럼이 ', @carelog_columns,
    '/8 이다. IF NOT EXISTS 는 표를 고치지 않는다 — 손으로 맞춰라.');
SET @stmt := IF(@carelog_exists = 1 AND @carelog_columns <> 8,
    'CALL heattrip_migration_abort(@abort_msg)',
    'SELECT ''[0-1] care_log 사전 점검 통과'' AS message');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @abort_msg := 'ABORT: walk_note 에 created_at 이 있다 — 옛 목록 모양이다. #76 은 그룹당 한 장이다.';
SET @stmt := IF(@walknote_legacy > 0,
    'CALL heattrip_migration_abort(@abort_msg)',
    'SELECT ''[0-2] walk_note 옛 목록 모양 없음'' AS message');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @abort_msg := CONCAT(
    'ABORT: walk_note 컬럼이 ', @walknote_columns,
    '/5 이다. IF NOT EXISTS 는 표를 고치지 않는다 — 손으로 맞춰라.');
SET @stmt := IF(@walknote_exists = 1 AND @walknote_columns <> 5,
    'CALL heattrip_migration_abort(@abort_msg)',
    'SELECT ''[0-2] walk_note 사전 점검 통과'' AS message');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;


-- ── A. 표 생성 (멱등) ───────────────────────────────────────────────────────
-- 컬럼 타입은 엔티티(care/entity/CareLog.java · WalkNote.java)가 만들 모양과 같아야 한다.
-- prod 의 ddl-auto=validate 가 타입 불일치로 부팅을 막기 때문이다. 정본은
-- mysql/init/01_schema.sql 이고 그 파일은 엔티티에서 뽑은 것이다.
--   · datetime 은 전부 DATETIME(6) — Hibernate 는 LocalDateTime 을 그렇게 만든다.
--   · type 은 VARCHAR(10) 이고 저장 값은 **소문자**다(water|meal|walk|med|vet).
--     계약(openapi.yaml)과 앱의 Dart enum 이 소문자라, 여기만 대문자면 같은 값에 표기가
--     둘이 된다 — CareType.Codec 이 그 한 벌을 만든다.

CREATE TABLE IF NOT EXISTS care_log (
    id          BIGINT       NOT NULL AUTO_INCREMENT,
    dog_id      BIGINT       NULL COMMENT '대상 강아지. dog 표가 아직 없어 FK 없이 항상 NULL 이다 (#76)',
    group_id    BIGINT       NULL COMMENT '가족 그룹 공유(nullable — 미소속 시 개인 기록)',
    type        VARCHAR(10)  NOT NULL COMMENT 'water|meal|walk|med|vet',
    done_by     BIGINT       NULL COMMENT '수행자(users.id) — 토큰의 사용자다. 탈퇴하면 NULL 이다',
    occurred_at DATETIME(6)  NOT NULL,
    memo        VARCHAR(500) NULL,
    created_at  DATETIME(6)  NOT NULL DEFAULT CURRENT_TIMESTAMP(6),
    PRIMARY KEY (id),
    KEY idx_carelog_group (group_id, occurred_at),
    KEY idx_carelog_doneby (done_by),
    CONSTRAINT fk_carelog_group FOREIGN KEY (group_id)
      REFERENCES family_group (id) ON DELETE SET NULL,
    CONSTRAINT fk_carelog_doneby FOREIGN KEY (done_by)
      REFERENCES users (id) ON DELETE SET NULL,
    CONSTRAINT ck_carelog_type CHECK (type IN ('water','meal','walk','med','vet'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS walk_note (
    id         BIGINT       NOT NULL AUTO_INCREMENT,
    group_id   BIGINT       NOT NULL,
    body       VARCHAR(500) NOT NULL COMMENT '산책 시 주의사항 — 그룹당 한 장',
    updated_by BIGINT       NULL COMMENT '마지막으로 고친 사람(users.id). 탈퇴하면 NULL 이다',
    updated_at DATETIME(6)  NOT NULL,
    PRIMARY KEY (id),
    UNIQUE KEY uq_walknote_group (group_id),
    KEY fk_walknote_updatedby (updated_by),
    CONSTRAINT fk_walknote_group FOREIGN KEY (group_id)
      REFERENCES family_group (id) ON DELETE CASCADE,
    CONSTRAINT fk_walknote_updatedby FOREIGN KEY (updated_by)
      REFERENCES users (id) ON DELETE SET NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;


-- ── B. 이미 만들어진 표 고치기 (멱등) ───────────────────────────────────────
-- CREATE TABLE IF NOT EXISTS 는 **이미 있는 표를 고치지 않는다.** 이 스크립트를 먼저
-- 돌려 본 개발 DB 에는 done_by·updated_by 가 NOT NULL + ON DELETE CASCADE 로 남아 있다.
-- 그 상태를 그대로 두면 사용자 한 명의 탈퇴가 가족의 케어 기록과 산책 주의사항을
-- 지운다 — 그 자리를 여기서 SET NULL 로 내린다.
--
-- 왜 SET NULL 인가: 두 컬럼은 **문서의 소유자가 아니라 메타데이터**다. 메모의 주인은
-- group_id 이고 그 그룹은 살아 있다. '마지막으로 고친 사람' 하나 때문에 가족이 함께 보는
-- 안전 메모('계단 피하기')와 '오늘 엄마가 산책을 다녀왔다' 를 지우면, 남은 가족의 화면은
-- 한 번도 안 쓴 상태와 구별되지 않는다. care_log.group_id 가 이미 같은 질문에 SET NULL 로
-- 답했고(가족 해산이 개인 기록을 지우지 않는다) 두 컬럼도 같은 답을 쓴다.
-- 이름은 응답에서 '알 수 없음' 으로 떨어진다(User.UNKNOWN_DISPLAY_NAME).
--
-- 순서가 정해져 있다: FK 를 먼저 떼야 컬럼을 NULL 허용으로 바꿀 수 있고, 컬럼을 바꿔야
-- SET NULL 로 다시 걸 수 있다. 방금 §A 가 새로 만든 표라면 셋 다 이미 맞아서 아무 일도
-- 일어나지 않는다.

SET @carelog_fk_wrong := (
    SELECT COUNT(*) FROM information_schema.referential_constraints
    WHERE constraint_schema = DATABASE() AND table_name = 'care_log'
      AND constraint_name = 'fk_carelog_doneby' AND delete_rule <> 'SET NULL');

SET @walknote_fk_wrong := (
    SELECT COUNT(*) FROM information_schema.referential_constraints
    WHERE constraint_schema = DATABASE() AND table_name = 'walk_note'
      AND constraint_name = 'fk_walknote_updatedby' AND delete_rule <> 'SET NULL');

SELECT '[B] 옛 CASCADE 점검' AS section,
       @carelog_fk_wrong  AS carelog_doneby_needs_fix,
       @walknote_fk_wrong AS walknote_updatedby_needs_fix;

-- B-1. care_log.done_by : FK 떼기 → 컬럼 NULL 허용 → SET NULL 로 다시 걸기
SET @stmt := IF(@carelog_fk_wrong > 0,
    'ALTER TABLE care_log DROP FOREIGN KEY fk_carelog_doneby',
    'SELECT ''[B-1] care_log.done_by 는 이미 SET NULL 이다'' AS message');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @stmt := IF(@carelog_fk_wrong > 0,
    'ALTER TABLE care_log MODIFY done_by BIGINT NULL COMMENT ''수행자(users.id) — 토큰의 사용자다. 탈퇴하면 NULL 이다''',
    'SELECT ''[B-1] care_log.done_by 컬럼 그대로'' AS message');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @stmt := IF(@carelog_fk_wrong > 0,
    'ALTER TABLE care_log ADD CONSTRAINT fk_carelog_doneby FOREIGN KEY (done_by) REFERENCES users (id) ON DELETE SET NULL',
    'SELECT ''[B-1] care_log.done_by FK 그대로'' AS message');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- B-2. walk_note.updated_by : 같은 순서
SET @stmt := IF(@walknote_fk_wrong > 0,
    'ALTER TABLE walk_note DROP FOREIGN KEY fk_walknote_updatedby',
    'SELECT ''[B-2] walk_note.updated_by 는 이미 SET NULL 이다'' AS message');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @stmt := IF(@walknote_fk_wrong > 0,
    'ALTER TABLE walk_note MODIFY updated_by BIGINT NULL COMMENT ''마지막으로 고친 사람(users.id). 탈퇴하면 NULL 이다''',
    'SELECT ''[B-2] walk_note.updated_by 컬럼 그대로'' AS message');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @stmt := IF(@walknote_fk_wrong > 0,
    'ALTER TABLE walk_note ADD CONSTRAINT fk_walknote_updatedby FOREIGN KEY (updated_by) REFERENCES users (id) ON DELETE SET NULL',
    'SELECT ''[B-2] walk_note.updated_by FK 그대로'' AS message');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;


-- ── D. 사후 검증 ────────────────────────────────────────────────────────────
-- '반쯤 적용된 채 성공처럼 끝나는' 상태를 막는 마지막 관문이다.

SET @tables := (
    SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name IN ('care_log', 'walk_note'));

SET @carelog_columns := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'care_log'
      AND column_name IN ('id', 'dog_id', 'group_id', 'type', 'done_by',
                          'occurred_at', 'memo', 'created_at'));

SET @walknote_columns := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'walk_note'
      AND column_name IN ('id', 'group_id', 'body', 'updated_by', 'updated_at'));

-- FK 넷. 이 이슈는 chat 경계 **밖**이라 FK 를 정상적으로 건다 — 없으면 그룹을 지운 뒤
-- 아무도 못 보는 행이 남고, 탈퇴한 계정의 기록이 이름 없이 떠돈다.
SET @fks := (
    SELECT COUNT(*) FROM information_schema.referential_constraints
    WHERE constraint_schema = DATABASE()
      AND constraint_name IN ('fk_carelog_group', 'fk_carelog_doneby',
                              'fk_walknote_group', 'fk_walknote_updatedby'));

-- users 로 가는 FK 둘의 **삭제 규칙**. 둘 다 SET NULL 이어야 한다 — CASCADE 면 한 사람의
-- 탈퇴가 가족의 케어 기록과 산책 주의사항을 지운다(§B 참고). 이것도 validate 는 안 본다.
SET @user_fk_cascade := (
    SELECT COUNT(*) FROM information_schema.referential_constraints
    WHERE constraint_schema = DATABASE()
      AND constraint_name IN ('fk_carelog_doneby', 'fk_walknote_updatedby')
      AND delete_rule <> 'SET NULL');

-- 같은 판단의 컬럼 쪽. SET NULL 은 NULL 허용 컬럼에만 걸 수 있다.
SET @user_cols_not_null := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND is_nullable = 'NO'
      AND ((table_name = 'care_log'  AND column_name = 'done_by')
        OR (table_name = 'walk_note' AND column_name = 'updated_by')));

-- '그룹당 한 장' 을 지키는 것은 애플리케이션이 아니라 이 UNIQUE 다 (📌 #86 원칙 5).
SET @walknote_unique := (
    SELECT COUNT(*) FROM information_schema.statistics
    WHERE table_schema = DATABASE() AND table_name = 'walk_note'
      AND index_name = 'uq_walknote_group' AND non_unique = 0);

-- 경계 ①: dog 로 가는 FK. dog 표가 없으니 **0이어야 한다.**
SET @dog_fks := (
    SELECT COUNT(*) FROM information_schema.referential_constraints
    WHERE constraint_schema = DATABASE() AND referenced_table_name = 'dog');

-- 경계 ②: 이 두 표와 chat_* 사이의 FK. **양방향 모두 0이어야 한다** (ADR-0011 결정 4).
-- 케어는 그룹 단위로 공유되고 방을 통해 인가만 받는다 — 표끼리 묶으면 방 삭제가 케어 기록
-- 삭제 순서에 묶이고, 산책 크루 방이 케어 컬럼을 NULL 로 들고 다니게 된다.
SET @chat_fks := (
    SELECT COUNT(*) FROM information_schema.referential_constraints
    WHERE constraint_schema = DATABASE()
      AND ((table_name IN ('care_log', 'walk_note') AND referenced_table_name LIKE 'chat\_%')
        OR (table_name LIKE 'chat\_%' AND referenced_table_name IN ('care_log', 'walk_note'))));

SELECT '[D] 사후 검증' AS section,
       @tables           AS tables_expect_2,
       @carelog_columns  AS care_log_columns_expect_8,
       @walknote_columns AS walk_note_columns_expect_5,
       @fks              AS foreign_keys_expect_4,
       @walknote_unique  AS walk_note_unique_expect_1,
       @dog_fks          AS fks_to_dog_expect_0,
       @chat_fks         AS fks_between_care_and_chat_expect_0;

SET @abort_msg := CONCAT(
    'ABORT: 반쯤 적용됨 — 표 ', @tables, '/2, care_log ', @carelog_columns,
    '/8, walk_note ', @walknote_columns, '/5. 위 [D] 참고.');
SET @stmt := IF(@tables <> 2 OR @carelog_columns <> 8 OR @walknote_columns <> 5,
    'CALL heattrip_migration_abort(@abort_msg)',
    'SELECT ''[D] 사후 검증 통과 — 표·컬럼 적용됨'' AS message');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @abort_msg := CONCAT(
    'ABORT: FK ', @fks, '/4, walk_note UNIQUE ', @walknote_unique,
    '/1. validate 는 이 둘을 안 본다.');
SET @stmt := IF(@fks <> 4 OR @walknote_unique <> 1,
    'CALL heattrip_migration_abort(@abort_msg)',
    'SELECT ''[D] FK 4개 · walk_note UNIQUE 확인'' AS message');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @abort_msg := CONCAT(
    'ABORT: users FK 중 ', @user_fk_cascade, '개가 SET NULL 이 아니고 컬럼 ',
    @user_cols_not_null, '개가 NOT NULL 이다. 탈퇴 한 번에 가족 기록이 지워진다.');
SET @stmt := IF(@user_fk_cascade > 0 OR @user_cols_not_null > 0,
    'CALL heattrip_migration_abort(@abort_msg)',
    'SELECT ''[D] done_by · updated_by 는 NULL 허용 + ON DELETE SET NULL'' AS message');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

SET @abort_msg := CONCAT(
    'ABORT: 경계 위반 — dog 로 가는 FK ', @dog_fks, '개, care-chat FK ',
    @chat_fks, '개. 둘 다 0이어야 한다.');
SET @stmt := IF(@dog_fks > 0 OR @chat_fks > 0,
    'CALL heattrip_migration_abort(@abort_msg)',
    'SELECT ''[D] 경계 검증 통과 — dog·chat 으로 가는 FK 0개'' AS message');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- 참고용. 실패시키지 않는다.
SELECT '[D] 현재 행 수 (첫 실행이면 0이다)' AS section;
SELECT (SELECT COUNT(*) FROM care_log)  AS care_log_rows,
       (SELECT COUNT(*) FROM walk_note) AS walk_note_rows;

DROP PROCEDURE IF EXISTS heattrip_migration_abort;

SELECT '08_care_log.sql 완료' AS message;
