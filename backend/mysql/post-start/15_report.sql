-- ============================================================================
-- 15_report.sql — 신고 표 둘 (이슈 #166, ADR-0016 결정 1 의 뒤집힌 판)
--
-- 왜 지금인가
--
-- ADR-0016 결정 1 은 "신고·차단을 지금 옮기지 않는다" 였고 방아쇠를 "M5 심사 준비를
-- 시작하는 날" 로 뒀다. **공모전 배포가 곧 그 날이다.** Apple 1.2 와 Google Play 의 UGC
-- 정책이 인앱 신고 창구를 요구하고, 글·댓글을 쓰는 앱에 그것이 없으면 심사에서 걸린다.
--
-- 왜 이름이 report 인가 (community_report 가 아니라)
--
-- 신고 대상이 될 UGC 가 커뮤니티 하나가 아니다. emotion_card·card_comment 가 정본에
-- 살아 있고 /api/social/cards 로 서빙된다. 이름을 커뮤니티로 좁히면 그 축을 또 못 담는다.
-- ADR-0016 이 그 이유로 이름을 정해 뒀다.
--
-- 무엇을 하나
--
--   report            신고 한 건. 무엇을(target_type·target_id) 누가(reporter) 왜(reason)
--   report_snapshot   신고 시점의 사본. 원본이 지워진 뒤에 읽는 기록이라 본문까지 벤다
--
-- 실행
--
--   mysql -u root -p heat_trip_db < mysql/post-start/15_report.sql
--
-- **04_users_social_account_model.sql 이 먼저다** (users 의 id 를 값으로 든다 — FK 는
-- 안 걸지만, 사전 점검이 그 표의 존재를 확인한다).
-- 멱등하다 — 두 번 돌려도 같은 상태로 끝난다.
--
-- 되돌리기
--
--   DROP TABLE report_snapshot; DROP TABLE report;
--
-- 순서가 있다 — report_snapshot 이 report 를 참조한다. 되돌리면 **접수된 신고가 전부
-- 사라진다.** 신고는 사용자가 우리에게 맡긴 기록이라 다시 만들 수 없다.
--
-- ----------------------------------------------------------------------------
-- 결정 다섯을 여기 적어 둔다 — 표를 짜기 전에 정한 것들이다
--
-- 1) UNIQUE 를 걸지 않는다. 같은 사람이 같은 것을 여러 번 신고할 수 있다.
--
--    처음에는 UNIQUE(target_type, target_id, reporter_user_id) + 409 로 막으려 했다.
--    **글이 수정된다는 것을 빠뜨렸다** — #211 이 PATCH 를 열었다. 신고한 뒤 작성자가
--    본문을 더 나쁜 것으로 고치면, 재신고가 409 로 막히고 운영자에게 남는 기록은
--    **고치기 전 본문**뿐이다. 실제로 문제인 글을 못 보게 된다.
--
--    chat_report 에도 UNIQUE 가 없고(01_schema.sql), 그래야 ADR-0016 이 적어 둔
--    "채팅 신고를 합치는 것이 재설계가 아니라 INSERT ... SELECT" 가 성립한다 — 같은
--    신고자가 같은 메시지를 두 번 신고한 기존 행이 있으면 그 INSERT 가 중복키로 죽는다.
--
--    도배는 레이트리밋이 막는다. report 버킷 분당 10 이다.
--
-- 2) users 로 FK 를 걸지 않는다. reporter_user_id·reported_user_id 는 값이다.
--
--    chat_report 와 같은 모양이다. moderation 모듈이 아무 도메인도 안 부른다는 것이
--    이 설계의 불변식이고, FK 를 걸려면 @ManyToOne User 가 필요해 그것이 깨진다.
--
--    그리고 신고 기록에는 값이 더 낫다. SET NULL 로 두면 탈퇴한 사람이 누구를 신고했는지
--    ·누가 신고당했는지가 함께 사라진다 — 운영자가 "이 사람이 반복 신고당했다" 를 셀 수
--    없게 된다. id 는 재사용되지 않으므로 값으로 남겨도 다른 사람을 가리키지 않는다.
--
-- 3) report_snapshot.role 로 대상과 맥락을 가른다.
--
--    댓글을 신고하면 운영자가 보는 것이 댓글 한 줄뿐이면 판단이 안 된다 — 무슨 글에 달린
--    말인지 모른다. 게다가 글을 지우면 fk_comment_post 가 CASCADE 라 댓글이 함께 사라져
--    되짚을 수도 없다. 그래서 **댓글 신고는 부모 글을 context 로 함께 벤다.**
--
--    채팅이 같은 이유로 context_from_seq·context_to_seq 를 남긴다 — "원본 참조만 하면
--    지워졌을 때 판단이 불가능하다".
--
-- 4) 제목까지 벤다.
--
--    제목에 욕설·광고가 실린 신고가 정확히 그 자리인데, 본문만 베면 원본이 지워진 뒤
--    무엇을 신고했는지 기록에 없다. post.title 이 VARCHAR(200) NOT NULL 이라 같은 폭이고,
--    댓글에는 제목이 없으므로 NULL 을 허용한다.
--
-- 5) author_name 은 VARCHAR(255) 다 — users.nickname 과 같은 폭이다.
--
--    #170 이 post.handle 을 VARCHAR(50) 으로 잡아, 51자 닉네임을 가진 사람의 **모든
--    글쓰기가 영구히 500** 이 된 적이 있다(14_community.sql [B-6]). 참조하는 쪽이 원본보다
--    좁으면 안 된다. 여기서 좁으면 그 사람이 쓴 글을 **아무도 신고할 수 없게** 된다.
-- ============================================================================

-- 이 파일은 UTF-8 이고 중단 메시지가 한글이다. **세션 문자셋을 먼저 고정한다.**
-- 안 하면 클라이언트 기본값을 물려받는데, 윈도우 mysql 클라이언트는 그것이 euckr 라
-- 중단이 걸리는 순간 이유 대신 ERROR 1366 만 남는다 (14_community.sql 과 같은 이유).
SET NAMES utf8mb4;

-- ── 0. 사전 점검 ────────────────────────────────────────────────────────────
-- 여기서 걸리면 스키마는 한 글자도 바뀌지 않는다.

DROP PROCEDURE IF EXISTS heattrip_migration_abort;
CREATE PROCEDURE heattrip_migration_abort(IN msg VARCHAR(128) CHARACTER SET utf8mb4)
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = msg;

SET @has_users := (
    SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name = 'users');

SELECT '[0] 사전 점검' AS section, @has_users AS users_1;

SET @stmt := IF(@has_users = 1,
    'SELECT ''[0] 통과'' AS message',
    'CALL heattrip_migration_abort(''ABORT: users 표가 없다. post-start/04_users_social_account_model.sql 을 먼저 적용하라.'')');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- ── A. 표 ──────────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS report (
  id                BIGINT       NOT NULL AUTO_INCREMENT,
  target_type       VARCHAR(24)  NOT NULL COMMENT '무엇을 신고했나 — community_post/community_comment. 이 축이 있어야 채팅 신고를 INSERT...SELECT 로 흡수한다',
  target_id         BIGINT       NOT NULL COMMENT '그 도메인 안의 id. FK 는 없다 — 원본이 지워져도 신고는 남아야 한다',
  reporter_user_id  BIGINT       NOT NULL COMMENT '신고한 사람. 값이다 — 결정 2',
  reported_user_id  BIGINT       NULL     COMMENT '신고당한 사람. 탈퇴한 사람의 글이면 NULL',
  reason            VARCHAR(16)  NOT NULL COMMENT 'spam/abuse/sexual/fraud/other. 채팅과 같은 어휘다',
  memo              VARCHAR(500) NULL     COMMENT '자유 서술. 넘치면 400 이 아니라 잘린다 — 채팅과 같다',
  created_at        DATETIME(6)  NOT NULL,
  PRIMARY KEY (id),
  KEY idx_report_target (target_type, target_id),
  KEY idx_report_reported (reported_user_id),
  KEY idx_report_reporter (reporter_user_id),
  CONSTRAINT chk_report_target_type CHECK (target_type in ('community_post','community_comment')),
  CONSTRAINT chk_report_reason CHECK (reason in ('spam','abuse','sexual','fraud','other'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS report_snapshot (
  id                BIGINT       NOT NULL AUTO_INCREMENT,
  report_id         BIGINT       NOT NULL,
  role              VARCHAR(8)   NOT NULL COMMENT 'target 또는 context. 댓글 신고는 부모 글을 context 로 함께 벤다 — 결정 3',
  author_user_id    BIGINT       NULL     COMMENT '그 글·댓글을 쓴 사람. 탈퇴했으면 NULL',
  author_name       VARCHAR(255) NULL     COMMENT '신고 시점 표시 이름. 폭은 users.nickname 과 같다 — 결정 5',
  title             VARCHAR(200) NULL     COMMENT '글이면 제목, 댓글이면 NULL — 결정 4',
  body              TEXT         NOT NULL COMMENT '신고 시점 본문 사본. 원본이 지워져도 남는다',
  occurred_at       DATETIME(6)  NOT NULL COMMENT '그 글·댓글이 쓰인 시각(UTC)',
  PRIMARY KEY (id),
  KEY idx_report_snapshot_report (report_id),
  CONSTRAINT fk_report_snapshot_report FOREIGN KEY (report_id) REFERENCES report (id) ON DELETE CASCADE,
  CONSTRAINT chk_report_snapshot_role CHECK (role in ('target','context'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- ── D. 사후 검증 ───────────────────────────────────────────────────────────
-- 여기까지 왔는데 숫자가 다르면 **반쯤 적용된 것**이다. 성공처럼 끝내지 않는다.

SET @d_tables := (
    SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name IN ('report', 'report_snapshot'));

SET @d_report_cols := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'report');

SET @d_snapshot_cols := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'report_snapshot');

-- 스냅샷은 신고가 사라지면 함께 사라져야 한다. 부모 없는 사본이 남으면 어느 신고의
-- 것인지 모르는 채 본문만 쌓인다.
SET @d_cascade := (
    SELECT COUNT(*) FROM information_schema.referential_constraints
    WHERE constraint_schema = DATABASE()
      AND constraint_name = 'fk_report_snapshot_report'
      AND delete_rule = 'CASCADE');

-- 값이 정해진 세 컬럼의 CHECK. 서비스 상수만 있고 DB 가 비어 있으면 그 상수를 안 거치는
-- 모든 경로가 무방비다 (📌 #86 원칙 5).
SET @d_checks := (
    SELECT COUNT(*) FROM information_schema.table_constraints
    WHERE constraint_schema = DATABASE() AND constraint_type = 'CHECK'
      AND constraint_name IN ('chk_report_target_type', 'chk_report_reason',
                              'chk_report_snapshot_role'));

-- author_name 은 users.nickname 과 같은 폭이어야 한다. 좁으면 긴 닉네임을 가진 사람이
-- 쓴 글을 아무도 신고할 수 없다 — 결정 5.
SET @d_name_width := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'report_snapshot'
      AND column_name = 'author_name' AND character_maximum_length >= 255);

SELECT '[D] 사후 검증' AS section,
       @d_tables AS tables_2, @d_report_cols AS report_cols_8,
       @d_snapshot_cols AS snapshot_cols_8, @d_cascade AS cascade_1,
       @d_checks AS checks_3, @d_name_width AS name_width_1;

SET @stmt := IF(@d_tables = 2 AND @d_report_cols = 8 AND @d_snapshot_cols = 8
                AND @d_cascade = 1 AND @d_checks = 3 AND @d_name_width = 1,
    'SELECT ''[D] 통과'' AS message',
    'CALL heattrip_migration_abort(''ABORT: 사후 검증 실패. 위 [D] 행의 숫자를 확인하라.'')');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

DROP PROCEDURE IF EXISTS heattrip_migration_abort;
