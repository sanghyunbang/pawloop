-- ============================================================================
-- 17_report_target_to_snapshot.sql — 신고의 좌표를 부모에서 자식으로 내린다 (이슈 #254)
--
-- 왜 옮기나
--
-- 신고 표가 둘이었다. `report`(커뮤니티)와 `chat_report`(채팅)가 같은 것을 다르게 들고
-- 있어서 운영자가 두 군데를 봐야 했다.
--
-- 합치려는데 모양이 안 맞았다. `report` 는 부모가 대상을 **하나** 든다(target_type +
-- target_id). 채팅 신고는 한 건에 메시지가 **최대 셋**이라 부모 한 칸으로는 안 담긴다.
--
-- ADR-0016 은 "target_type 축이 있으면 채팅 신고를 합치는 것이 재설계가 아니라
-- INSERT ... SELECT 다" 라고 적었는데, **그 산정이 틀렸다.** 부모↔자식 재배치라 두
-- 단계이고, SQL 로 그냥 옮기면 대상 줄이 셋이 되어 Reports.file 의 "대상 종류가 하나,
-- 상한 이하" 규칙과 DB 가 서로 다른 말을 하게 된다.
--
-- 무엇을 하나
--
--   [A] report_snapshot 에 좌표 칸을 만든다 — target_type · target_id · target_ordinal ·
--       content_type. body 를 nullable 로 내린다(좌표만 담는 맥락 줄이 생긴다).
--   [B] 기존 report 행의 좌표를 자식으로 백필한다.
--   [C] report 에서 target_type · target_id · 인덱스 · CHECK 를 걷는다.
--   [D] 자식에 CHECK 셋과 인덱스를 건다.
--
-- 15_report.sql 을 먼저 돌린다. [0] 이 확인하고 아니면 멈춘다.
--
-- 실행
--
--   mysql -u root -p heat_trip_db < mysql/post-start/17_report_target_to_snapshot.sql
--
-- 멱등하다 — 이미 옮겨졌으면 [0] 이 알아보고 [A]~[D] 를 전부 건너뛴다.
--
-- 되돌리기
--
--   좌표를 부모로 되돌리는 것은 **대상이 하나인 신고에서만** 가능하다. 채팅 신고가 한 건이라도
--   들어온 뒤에는 되돌릴 수 없다 — 부모 한 칸에 셋을 못 넣는다. 그래서 이 스크립트는
--   chat_report 에 행이 있으면 아예 시작하지 않는다.
--
-- chat_report 를 지우지 않는다
--
--   이 스크립트는 표를 하나도 안 지운다. `chat_report`·`chat_reported_message` 는 쓰는 코드가
--   없어져 빈 채로 남는다. **지울지 말지는 사람이 정한다** — 지우는 것은 되돌릴 수 없고,
--   그 판단에 필요한 것(운영자 화면·보존 기간)이 아직 없다.
-- ============================================================================

SET NAMES utf8mb4;

DROP PROCEDURE IF EXISTS heattrip_migration_abort;
CREATE PROCEDURE heattrip_migration_abort(IN msg VARCHAR(255) CHARACTER SET utf8mb4)
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = msg;

-- ── 0. 사전 점검 ────────────────────────────────────────────────────────────
-- 여기서 걸리면 스키마는 한 글자도 안 바뀐다.

SET @has_report := (
    SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name = 'report');
SET @has_snapshot := (
    SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name = 'report_snapshot');

-- 이미 옮겨졌는가. 컬럼 하나의 존재로 센다 — 멱등 표시자다.
SET @absorbed := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'report_snapshot'
      AND column_name = 'target_type');

-- chat_report 에 행이 있으면 멈춘다. 신고는 사용자가 우리에게 맡긴 기록이라 다시 만들 수
-- 없고(15_report.sql), 그 행들을 어떻게 옮길지는 사람이 정해야 한다.
SET @has_chat_report := (
    SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name = 'chat_report');
SET @chat_rows := 0;
SET @stmt := IF(@has_chat_report = 1,
    'SELECT COUNT(*) INTO @chat_rows FROM chat_report',
    'DO 0');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SELECT '[0] 사전 점검' AS section,
       @has_report AS report_1, @has_snapshot AS snapshot_1,
       @absorbed AS already_done, @chat_rows AS chat_report_rows;

SET @stmt := IF(@has_report = 1 AND @has_snapshot = 1,
    'SELECT ''[0] 표 확인'' AS message',
    'CALL heattrip_migration_abort(''ABORT: report/report_snapshot 이 없다. 15_report.sql 을 먼저 돌려라.'')');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @stmt := IF(@chat_rows = 0,
    'SELECT ''[0] chat_report 0행'' AS message',
    'CALL heattrip_migration_abort(''ABORT: chat_report 에 행이 있다. 신고는 다시 만들 수 없는 기록이라 사람이 이관 방법을 정해야 한다.'')');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- 맥락 줄의 좌표를 복원할 수 있는가. 커뮤니티 맥락 줄은 댓글 신고에 딸린 부모 글이라
-- comment 에서 되짚는데, 글이 지워지면 fk_comment_post 가 CASCADE 라 댓글도 사라진다.
-- comment 표가 없을 수 있다 — 14_community.sql 이 아직 안 돈 DB 다. 그러면 되짚을 것도
-- 없으므로 이 검사를 건너뛴다. 맥락 줄이 실제로 남아 있으면 [B] 의 @b_null 이 잡는다.
SET @has_comment := (
    SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name = 'comment');

SET @unmappable := 0;
SET @stmt := IF(@absorbed = 0 AND @has_comment = 1,
    'SELECT COUNT(*) INTO @unmappable FROM report_snapshot s
       JOIN report r ON r.id = s.report_id
      WHERE s.role = ''context''
        AND (r.target_type <> ''community_comment''
             OR NOT EXISTS (SELECT 1 FROM comment c WHERE c.id = r.target_id))',
    'DO 0');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SELECT '[0] 맥락 복원' AS section, @has_comment AS comment_table, @unmappable AS unmappable_0;

SET @stmt := IF(@unmappable = 0,
    'SELECT ''[0] 통과'' AS message',
    'CALL heattrip_migration_abort(''ABORT: 좌표를 복원할 수 없는 맥락 줄이 있다. 그 신고들을 사람이 먼저 판단하라.'')');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- ── A. 자식에 좌표 칸을 만든다 ──────────────────────────────────────────────

SET @stmt := IF(@absorbed = 0,
    'ALTER TABLE report_snapshot
       ADD COLUMN target_type    VARCHAR(24) NULL AFTER role,
       ADD COLUMN target_id      BIGINT      NULL AFTER target_type,
       ADD COLUMN target_ordinal BIGINT      NULL AFTER target_id,
       ADD COLUMN content_type   VARCHAR(16) NULL AFTER body,
       MODIFY COLUMN body TEXT NULL',
    'DO 0');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SELECT '[A] 칸 만들기' AS section,
       IF(@absorbed = 0, '만듦', '건너뜀 — 이미 있다') AS result;

-- ── B. 좌표를 자식으로 옮긴다 ───────────────────────────────────────────────
-- 대상 줄은 부모의 좌표를 그대로 받는다. 맥락 줄은 댓글 신고의 부모 글이므로 comment 에서
-- 되짚는다 — [0] 이 복원 가능성을 이미 확인했다.

SET @stmt := IF(@absorbed = 0,
    'UPDATE report_snapshot s JOIN report r ON r.id = s.report_id
        SET s.target_type = r.target_type, s.target_id = r.target_id
      WHERE s.role = ''target''',
    'DO 0');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @stmt := IF(@absorbed = 0 AND @has_comment = 1,
    'UPDATE report_snapshot s
        JOIN report r ON r.id = s.report_id
        JOIN comment c ON c.id = r.target_id
        SET s.target_type = ''community_post'', s.target_id = c.post_id
      WHERE s.role = ''context''',
    'DO 0');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @b_orphans := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'report_snapshot'
      AND column_name = 'target_type');
SET @b_null := 0;
SET @stmt := IF(@b_orphans = 1,
    'SELECT COUNT(*) INTO @b_null FROM report_snapshot WHERE target_type IS NULL',
    'DO 0');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SELECT '[B] 백필' AS section, @b_null AS still_null_0;

SET @stmt := IF(@b_null = 0,
    'SELECT ''[B] 통과'' AS message',
    'CALL heattrip_migration_abort(''ABORT: 좌표가 안 채워진 사본이 남았다. 위 [B] 숫자를 확인하라.'')');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @stmt := IF(@absorbed = 0,
    'ALTER TABLE report_snapshot
       MODIFY COLUMN target_type VARCHAR(24) NOT NULL,
       MODIFY COLUMN target_id   BIGINT      NOT NULL',
    'DO 0');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- ── C. 부모에서 좌표를 걷는다 ───────────────────────────────────────────────

SET @has_parent_check := (
    SELECT COUNT(*) FROM information_schema.table_constraints
    WHERE constraint_schema = DATABASE() AND table_name = 'report'
      AND constraint_name = 'chk_report_target_type');
SET @stmt := IF(@has_parent_check = 1,
    'ALTER TABLE report DROP CHECK chk_report_target_type', 'DO 0');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @has_parent_idx := (
    SELECT COUNT(DISTINCT index_name) FROM information_schema.statistics
    WHERE table_schema = DATABASE() AND table_name = 'report'
      AND index_name = 'idx_report_target');
SET @stmt := IF(@has_parent_idx = 1,
    'ALTER TABLE report DROP INDEX idx_report_target', 'DO 0');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @has_parent_cols := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'report'
      AND column_name IN ('target_type', 'target_id'));
SET @stmt := IF(@has_parent_cols = 2,
    'ALTER TABLE report DROP COLUMN target_type, DROP COLUMN target_id', 'DO 0');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SELECT '[C] 부모 정리' AS section,
       IF(@has_parent_cols = 2, '걷음', '건너뜀 — 이미 없다') AS result;

-- ── D. 자식에 제약과 인덱스를 건다 ──────────────────────────────────────────

SET @has_child_type_check := (
    SELECT COUNT(*) FROM information_schema.table_constraints
    WHERE constraint_schema = DATABASE() AND table_name = 'report_snapshot'
      AND constraint_name = 'chk_report_snapshot_target_type');
SET @stmt := IF(@has_child_type_check = 0,
    'ALTER TABLE report_snapshot ADD CONSTRAINT chk_report_snapshot_target_type
       CHECK (target_type in (''community_post'',''community_comment'',''chat_message'',''chat_room''))',
    'DO 0');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- 대상 줄에는 본문이 있어야 한다. 좌표만 남은 대상은 원본이 지워지면 아무것도 못 말하는데,
-- 그것이 이 표가 존재하는 이유다. 맥락 줄은 좌표만일 수 있다 — 채팅의 방이 그렇다.
SET @has_child_body_check := (
    SELECT COUNT(*) FROM information_schema.table_constraints
    WHERE constraint_schema = DATABASE() AND table_name = 'report_snapshot'
      AND constraint_name = 'chk_report_snapshot_target_has_body');
SET @stmt := IF(@has_child_body_check = 0,
    'ALTER TABLE report_snapshot ADD CONSTRAINT chk_report_snapshot_target_has_body
       CHECK (role <> ''target'' or body is not null)',
    'DO 0');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @has_child_idx := (
    SELECT COUNT(DISTINCT index_name) FROM information_schema.statistics
    WHERE table_schema = DATABASE() AND table_name = 'report_snapshot'
      AND index_name = 'idx_report_snapshot_target');
SET @stmt := IF(@has_child_idx = 0,
    'ALTER TABLE report_snapshot ADD INDEX idx_report_snapshot_target (target_type, target_id)',
    'DO 0');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- ── E. 사후 검증 ────────────────────────────────────────────────────────────
-- **이름으로 센다.** 표의 전체 컬럼 수를 리터럴과 견주면 다음 마이그레이션이 컬럼을 하나
-- 더하는 순간 이 스크립트를 다시 못 돌린다 (#267).

SET @e_parent_cols := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'report'
      AND column_name IN ('target_type', 'target_id'));

SET @e_child_cols := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'report_snapshot'
      AND column_name IN ('target_type', 'target_id', 'target_ordinal', 'content_type'));

SET @e_child_checks := (
    SELECT COUNT(*) FROM information_schema.table_constraints
    WHERE constraint_schema = DATABASE() AND table_name = 'report_snapshot'
      AND constraint_type = 'CHECK'
      AND constraint_name IN ('chk_report_snapshot_role',
                              'chk_report_snapshot_target_type',
                              'chk_report_snapshot_target_has_body'));

SET @e_child_idx := (
    SELECT COUNT(DISTINCT index_name) FROM information_schema.statistics
    WHERE table_schema = DATABASE() AND table_name = 'report_snapshot'
      AND index_name = 'idx_report_snapshot_target');

-- 대상 줄에 본문이 없는 행이 하나라도 있으면 CHECK 가 안 걸린 것이다.
SET @e_bodyless := (
    SELECT COUNT(*) FROM report_snapshot WHERE role = 'target' AND body IS NULL);

SELECT '[E] 사후 검증' AS section,
       @e_parent_cols AS parent_target_cols_0, @e_child_cols AS child_target_cols_4,
       @e_child_checks AS child_checks_3, @e_child_idx AS child_idx_1,
       @e_bodyless AS bodyless_targets_0;

SET @stmt := IF(@e_parent_cols = 0 AND @e_child_cols = 4 AND @e_child_checks = 3
                AND @e_child_idx = 1 AND @e_bodyless = 0,
    'SELECT ''[E] 통과'' AS message',
    'CALL heattrip_migration_abort(''ABORT: 사후 검증 실패. 위 [E] 행의 숫자를 확인하라.'')');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

DROP PROCEDURE IF EXISTS heattrip_migration_abort;
