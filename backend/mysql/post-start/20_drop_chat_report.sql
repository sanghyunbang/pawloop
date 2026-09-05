-- ============================================================================
-- 20_drop_chat_report.sql
-- 옛 채팅 신고 표 둘을 지운다 — 이슈 #281
-- 대상: MySQL 8.x (운영/개발 공통)
--
-- ─────────────────────────────────────────────────────────────────────────────
-- 무엇을 지우나
--
--   chat_report          — "누가 어느 방에서 왜" 한 건 (#82)
--   chat_reported_message — 신고된 메시지의 사본, 최대 3개. chat_report 로 FK(ON DELETE CASCADE)
--
-- 커뮤니티 신고가 생기면서 신고 표를 하나로 합쳤고(#254, 15·17), 채팅 신고도 그 새 표
-- (report · report_snapshot)에 적힌다. 그 뒤로 이 두 표에는 **아무것도 안 쓴다.** 17 은
-- "지울지 말지는 사람이 정한다" 로 남겨 두었는데, 그 판단이 #281 이다 — 지운다.
--
-- ─────────────────────────────────────────────────────────────────────────────
-- 실행 순서
--
--   1. 새 애플리케이션을 먼저 배포한다 (엔티티 ChatReport·ChatReportedMessage 가 사라진 것)
--   2. 그 다음 이 스크립트를 실행한다
--
-- 19 까지와 **반대 순서**다. 표를 더할 때는 표가 먼저여야 validate 가 통과하고, 표를 뺄 때는
-- 코드가 먼저여야 한다 — 옛 코드가 아직 돌고 있는데 표를 지우면 그 코드가 validate 에서
-- 죽는다. 새 코드는 이 두 표가 있든 없든 상관하지 않는다(validate 는 엔티티가 요구하는
-- 표만 본다).
--
-- 빈 DB 를 새로 세우는 경우에는 이 파일이 필요 없다. mysql/init/01_schema.sql 에서 두 표가
-- 이미 사라졌다(#58).
--
-- ─────────────────────────────────────────────────────────────────────────────
-- 멈추는 조건 — 행이 하나라도 있으면 한 글자도 안 바꾼다
--
-- 신고는 사용자가 우리에게 맡긴 기록이라 다시 만들 수 없다(15_report.sql, 17). 행이 있다면
-- 그것을 report · report_snapshot 으로 옮길지, 어떻게 옮길지는 사람이 정해야 한다. 이
-- 스크립트는 그 판단을 대신하지 않는다 — 멈추고 숫자를 보여 준다.
--
-- 2026-09-05 실측: dev DB 두 표 모두 0행. 운영 DB 는 아직 없다.
--
-- 트랜잭션으로 감쌀 수 없다 — MySQL 의 DDL 은 암묵적 커밋을 일으킨다.
--    그래서 앞뒤로 관문을 둔다: §0 사전 점검 · §D 사후 검증.
--
-- 멱등: 표가 이미 없으면 "이미 없음" 을 찍고 지나간다. 두 번 돌려도 같은 상태로 끝난다.
-- 순서: 자식(chat_reported_message)을 먼저 지운다. FK 가 부모를 잡고 있다.
--
-- ─────────────────────────────────────────────────────────────────────────────
-- 되돌리기(DOWN) — 없다.
--
-- 표만 되살려서는 아무 의미가 없다. 그것을 읽고 쓰던 코드가 같은 PR 에서 사라졌고, 그 코드는
-- 커밋 이력에 있다. 되돌려야 한다면 코드를 먼저 되돌리고 01_schema.sql 의 옛 판에서 두 표의
-- CREATE TABLE 을 가져온다. 행은 어차피 없었다(위 실측) — 이 스크립트는 0행일 때만 지나간다.
-- ============================================================================


-- ── 0. 사전 점검 ────────────────────────────────────────────────────────────
SET NAMES utf8mb4;

DROP PROCEDURE IF EXISTS heattrip_migration_abort;
CREATE PROCEDURE heattrip_migration_abort(IN msg VARCHAR(128))
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = msg;

SET @has_report := (
    SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name = 'chat_report');
SET @has_msg := (
    SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name = 'chat_reported_message');

-- 행 수는 표가 있을 때만 센다 — 없는 표를 SELECT 하면 그 자체가 오류다.
SET @report_rows := 0;
SET @stmt := IF(@has_report = 1,
    'SELECT COUNT(*) INTO @report_rows FROM chat_report',
    'DO 0');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @msg_rows := 0;
SET @stmt := IF(@has_msg = 1,
    'SELECT COUNT(*) INTO @msg_rows FROM chat_reported_message',
    'DO 0');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

-- 새 신고 표가 있어야 한다. 없으면 15 가 안 돈 DB 다 — 옛 표를 지우면 신고를 적을 곳이
-- 아예 없어진다. 이것을 사후 검증이 아니라 여기서 보는 이유: 멈춤은 항상 한 글자도 안 바꾼
-- 상태여야 한다. 지운 뒤에 멈추면 되돌릴 것이 없다.
SET @has_new := (
    SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name IN ('report', 'report_snapshot'));

SELECT '[0] 사전 점검' AS section,
       @has_report AS chat_report_exists, @report_rows AS chat_report_rows,
       @has_msg AS chat_reported_message_exists, @msg_rows AS chat_reported_message_rows,
       @has_new AS new_report_tables_2;

SET @stmt := IF(@has_new = 2,
    'SELECT ''[0] 새 신고 표 둘 확인'' AS message',
    'CALL heattrip_migration_abort(''ABORT: report/report_snapshot 이 없다. 15_report.sql 을 먼저 돌려라.'')');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

SET @stmt := IF(@report_rows = 0 AND @msg_rows = 0,
    'SELECT ''[0] 두 표 모두 0행 — 지워도 잃는 것이 없다'' AS message',
    'CALL heattrip_migration_abort(''ABORT: 옛 신고 표에 행이 있다. 신고는 다시 만들 수 없는 기록이라 사람이 이관 방법을 정해야 한다.'')');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;


-- ── A. chat_reported_message (자식 먼저) ────────────────────────────────────
SET @stmt := IF(@has_msg = 1,
    'DROP TABLE chat_reported_message',
    'SELECT ''[A] chat_reported_message 이미 없음'' AS message');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;


-- ── B. chat_report ──────────────────────────────────────────────────────────
SET @stmt := IF(@has_report = 1,
    'DROP TABLE chat_report',
    'SELECT ''[B] chat_report 이미 없음'' AS message');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;


-- ── D. 사후 검증 ────────────────────────────────────────────────────────────
SET @d_left := (
    SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema = DATABASE()
      AND table_name IN ('chat_report', 'chat_reported_message'));

-- 새 신고 표는 손대지 않았어야 한다 — §0 에서 둘이었고 여기서도 둘이어야 한다.
SET @d_report_kept := (
    SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name IN ('report', 'report_snapshot'));

SELECT '[D] 사후 검증' AS section,
       @d_left AS old_tables_0, @d_report_kept AS new_report_tables_2;

SET @stmt := IF(@d_left = 0 AND @d_report_kept = 2,
    'SELECT ''[D] 통과 — 옛 표 0 · 새 신고 표 2 그대로'' AS message',
    'CALL heattrip_migration_abort(''ABORT: 사후 검증 실패. 위 [D] 행의 숫자를 확인하라.'')');
PREPARE stmt FROM @stmt; EXECUTE stmt; DEALLOCATE PREPARE stmt;

DROP PROCEDURE IF EXISTS heattrip_migration_abort;
