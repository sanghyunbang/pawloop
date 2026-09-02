-- ============================================================================
-- 14_community.sql — 커뮤니티 표 셋 (이슈 #169, ADR-0016)
--
-- 왜 표가 먼저인가
--
-- application-prod.properties 는 ddl-auto=validate 다. 표 없이 엔티티만 올리면
-- **prod 부팅이 죽는다.** dev 는 update 라 Hibernate 가 표를 만들어 버리고, 그러면
-- SchemaDdlDriftTest 가 정본과의 차이를 빨간불로 낸다. 순서를 지키면 둘 다 안 겪는다.
--
-- 왜 14 인가
--
-- 13 은 #155 의 13_walk_path_t.sql 이 이미 쓴다. 이슈 본문과 로드맵이 13_community.sql
-- 이라고 적었는데 그건 #155 가 나가기 전에 쓰인 것이다.
--
-- 무엇을 하나
--
--   post      글. 게시판·제목·본문·연결 장소·작성 시점 닉네임 스냅샷
--   comment   댓글. post 로의 FK (CASCADE)
--   reaction  반응. **사용자당 글마다 여러 type** (ADR-0016 결정 2)
--
-- 실행
--
--   mysql -u root -p heattrip < mysql/post-start/14_community.sql
--
-- **04_users_social_account_model.sql 이 먼저다** (users 로 FK 를 건다).
-- 멱등하다 — 두 번 돌려도 같은 상태로 끝난다.
--
-- 되돌리기
--
--   DROP TABLE reaction; DROP TABLE comment; DROP TABLE post;
--
-- 순서가 있다 — reaction·comment 가 post 를 참조한다. 되돌리면 **글·댓글·반응이 전부
-- 사라지고 다시 만들 수 없다.**
--
-- ----------------------------------------------------------------------------
-- 결정 셋을 여기 적어 둔다 — 표를 짜기 전에 정한 것들이다
--
-- 1) reaction 의 UNIQUE 는 (post_id, user_id, type) 다.
--
--    사용자당 글마다 **여러 반응**을 가질 수 있다. 도움돼요·귀여워요·공감은 서로
--    배타적인 개념이 아니다 — 한 글이 도움도 되고 귀엽기도 하다. ADR-0016 결정 2 이고,
--    레거시 card_reaction(01_schema.sql:66)도 같은 모양이다.
--
--    (post_id, user_id) 로 좁히면 라디오가 되고, 나중에 넓히려면 계약의 파괴적 변경이다.
--    반대로 지금 넓게 두었다가 좁히려면 **행을 지우는** 마이그레이션이라 어느 반응을
--    남길지 제품이 다시 답해야 한다. 넓은 쪽이 되돌리기 싸다.
--
-- 2) board 는 ASCII 키다 — walk_review · pet_place · health · free · brag.
--
--    2026-09 이전 계약은 값 자체가 한글 표시 문자열이었다("산책로 후기" 등).
--    이 값은 query 파라미터로 나가고 **이 컬럼에 들어간다.** 표시 문구를 저장하면
--    게시판 이름을 다듬는 날 쌓인 행을 전부 고쳐야 한다. CareType 이 이미 같은 모양이다.
--
-- 3) 장소 참조는 content_id VARCHAR(64) 이고 **FK 를 걸지 않는다.**
--
--    계약의 Post.contentId 는 string 이고 Place.contentId 와 같은 키다(ADR-0017).
--    반려 앱의 장소는 KTO 프록시 캐시(pet_place_detail, PK content_id varchar(64))에서
--    오는데 그건 **캐시**다 — 사용자가 고른 장소의 캐시 행이 아직 없거나 지워질 수 있다.
--    FK 를 걸면 그때 글 작성이 실패한다.
--
--    레거시 places 표(contentid bigint)에는 걸지 않는다. 감정 여행 시절의 다른 키 공간이다.
--
-- 4) handle 은 **작성 시점 닉네임 스냅샷**이고 응답에는 싣지 않는다.
--
--    응답의 author 는 PersonRef{userId, nickname} 이고 그 nickname 은 **조회 시점의
--    현재 값**이다(ADR-0017 규약 5). 탈퇴한 계정이면 userId=0 · "알 수 없음" 이다.
--    handle 은 그 조회가 실패했을 때를 위한 저장 기록이지 표시용이 아니다 — 저장은
--    스냅샷, 표시는 현재값 두 규칙이 한 화면에서 만나지 않게 하는 것이 요점이다.
--
-- ----------------------------------------------------------------------------
-- 여기서 하지 않는 것
--
-- E-1. 엔티티 밖의 것 — 리포지토리·서비스·컨트롤러는 #170 이다.
--      엔티티 셋은 **같은 PR 에 있다.** SchemaDdlDriftTest 가 "엔티티에 없는 테이블이
--      커밋된 스키마에 있다" 를 빨간불로 내기 때문에, 정본을 갱신하는 순간 엔티티가
--      함께 있어야 한다. 이슈 본문의 "엔티티를 만들지 않습니다" 는 그 검사를 안 본 것이다.
--
-- E-2. 신고·차단 표를 만들지 않는다 — ADR-0016 결정 1 이 미뤘다. 만드는 날의 모양은
--      report(target_type, target_id, ...) 이고 방아쇠는 "M5 심사 준비를 시작하는 날" 이다.
--
-- E-3. 이미지 업로드 컬럼을 넣지 않는다 — mvp-scope.md 의 Out-of-scope 다.
--
-- E-4. emotion_card·card_comment·card_reaction 을 지우거나 옮기지 않는다.
--      #94 의 레거시 셸 결정이 소유한다.
--
-- E-5. 글·댓글 수정/삭제용 컬럼(updated_at·deleted_at)을 넣지 않는다.
--      계약에 그 오퍼레이션이 없고(#211 Community-medium-4), **넣는 날은 컬럼 추가가
--      아니라 삭제 정책 결정이다** — 지운 글의 댓글을 어떻게 할지가 먼저다.
-- ============================================================================

-- 이 파일은 UTF-8 이고 중단 메시지가 한글이다. **세션 문자셋을 먼저 고정한다.**
--
-- 안 하면 클라이언트 기본값을 물려받는데, 윈도우 mysql 클라이언트는 그것이 euckr 다
-- (실측 2026-09-02: `SELECT @@character_set_client` → euckr). 그러면 중단이 걸리는
-- 순간 정작 이유는 안 보이고 **ERROR 1366 (Incorrect string value)** 만 남는다 —
-- "왜 멈췄나" 를 알려 주려고 쓴 메시지가 "왜 멈췄는지 모르게" 만든다.
--
-- 실행 옵션(`--default-character-set=utf8mb4`)으로도 되지만, 그건 **부르는 사람이
-- 기억해야 하는 것**이다. 파일이 스스로 고정한다.
SET NAMES utf8mb4;

-- ── 0. 사전 점검 ────────────────────────────────────────────────────────────
-- 여기서 걸리면 스키마는 한 글자도 바뀌지 않는다.

-- 파라미터에도 CHARACTER SET utf8mb4 를 적는다. SET NAMES 가 세션을 바꿔도, 프로시저는
-- **만들어질 때의** 문자셋을 굳혀 들기 때문에 둘 다 필요하다.
DROP PROCEDURE IF EXISTS heattrip_migration_abort;
CREATE PROCEDURE heattrip_migration_abort(IN msg VARCHAR(128) CHARACTER SET utf8mb4)
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = msg;

-- 0-1. users 가 있어야 FK 를 걸 수 있다.
SET @has_users := (
    SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name = 'users');
SET @stmt := IF(@has_users = 1,
    'SELECT ''[0-1] users 확인'' AS message',
    'CALL heattrip_migration_abort(''ABORT: users 표가 없다. post-start/04_users_social_account_model.sql 을 먼저 적용하라.'')');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- 0-2. 이미 있는지 본다(= 재실행이거나 Hibernate 가 먼저 만들었는지).
--      dev 는 ddl-auto=update 라 **앱이 먼저 뜨면 Hibernate 가 표를 이미 만들어 둔다.**
SET @has_post := (
    SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name = 'post');
SET @has_comment := (
    SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name = 'comment');
SET @has_reaction := (
    SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name = 'reaction');

SELECT '[0-2] 기존 표 확인' AS section,
       @has_post AS post, @has_comment AS `comment`, @has_reaction AS reaction;

-- 0-3. reaction 이 이미 있다면 UNIQUE 가 (post_id, user_id, type) 인지 본다.
--      2 컬럼짜리로 서 있으면 **사용자당 하나** 모양이라 ADR-0016 결정 2 와 반대다.
--      그대로 통과시키면 앱이 두 번째 반응을 눌렀을 때 조용히 409/500 이 난다.
SET @reaction_uq_cols := (
    SELECT COUNT(*) FROM information_schema.statistics
    WHERE table_schema = DATABASE() AND table_name = 'reaction'
      AND index_name = 'uq_reaction');
SET @stmt := IF(@has_reaction = 0 OR @reaction_uq_cols = 3,
    'SELECT ''[0-3] reaction UNIQUE 확인'' AS message',
    'CALL heattrip_migration_abort(''ABORT: reaction 이 있는데 uq_reaction 이 3컬럼이 아니다. ADR-0016 결정 2 와 다른 모양이다 — 손으로 확인하라.'')');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- ── A. 표 생성 ──────────────────────────────────────────────────────────────
-- CREATE TABLE IF NOT EXISTS 라 재실행이 안전하다. 이미 있으면 아무것도 안 한다.

CREATE TABLE IF NOT EXISTS post (
  id          BIGINT       NOT NULL AUTO_INCREMENT,
  user_id     BIGINT       NOT NULL COMMENT '작성자. users 로 FK',
  board       VARCHAR(20)  NOT NULL COMMENT 'ASCII 키 — walk_review/pet_place/health/free/brag. 화면 문구는 앱이 든다',
  title       VARCHAR(200) NOT NULL,
  body        TEXT         NOT NULL,
  content_id  VARCHAR(64)  NULL COMMENT '연결 장소. Place.contentId 와 같은 키. FK 는 없다 — 장소는 캐시라 행이 없을 수 있다',
  loc         VARCHAR(100) NULL COMMENT '표시용 장소 이름. content_id 와 별개다',
  handle      VARCHAR(50)  NULL COMMENT '작성 시점 닉네임 스냅샷. 응답에는 안 싣는다 — 표시는 현재값이다(ADR-0017 규약 5)',
  created_at  DATETIME(6)  NOT NULL,
  PRIMARY KEY (id),
  CONSTRAINT fk_post_user FOREIGN KEY (user_id) REFERENCES users (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS comment (
  id          BIGINT       NOT NULL AUTO_INCREMENT,
  post_id     BIGINT       NOT NULL,
  user_id     BIGINT       NOT NULL,
  body        TEXT         NOT NULL,
  handle      VARCHAR(50)  NULL COMMENT 'post.handle 과 같은 이유',
  created_at  DATETIME(6)  NOT NULL,
  PRIMARY KEY (id),
  CONSTRAINT fk_comment_post FOREIGN KEY (post_id) REFERENCES post (id) ON DELETE CASCADE,
  CONSTRAINT fk_comment_user FOREIGN KEY (user_id) REFERENCES users (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

CREATE TABLE IF NOT EXISTS reaction (
  id          BIGINT       NOT NULL AUTO_INCREMENT,
  post_id     BIGINT       NOT NULL,
  user_id     BIGINT       NOT NULL,
  type        VARCHAR(20)  NOT NULL COMMENT 'help/cute/empathy',
  created_at  DATETIME(6)  NOT NULL,
  PRIMARY KEY (id),
  CONSTRAINT fk_reaction_post FOREIGN KEY (post_id) REFERENCES post (id) ON DELETE CASCADE,
  CONSTRAINT fk_reaction_user FOREIGN KEY (user_id) REFERENCES users (id)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;

-- ── B. 인덱스·제약 ─────────────────────────────────────────────────────────
-- CREATE TABLE 안이 아니라 여기서 거는 이유: 표가 이미 있는 DB(Hibernate 가 먼저 만든
-- dev)에서도 같은 결과로 끝나야 한다. IF NOT EXISTS 는 인덱스에 못 쓰므로 조건부 실행이다.

-- B-1. reaction 의 UNIQUE — 이 표의 불변식이다.
--      같은 사람이 같은 글에 같은 반응을 두 번 넣지 못한다. 멱등한 POST 가 이것을 딛는다.
SET @exists := (
    SELECT COUNT(*) FROM information_schema.statistics
    WHERE table_schema = DATABASE() AND table_name = 'reaction' AND index_name = 'uq_reaction');
SET @stmt := IF(@exists = 0,
    'ALTER TABLE reaction ADD CONSTRAINT uq_reaction UNIQUE (post_id, user_id, type)',
    'SELECT ''[B-1] uq_reaction 이미 있음 — 건너뜀'' AS message');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- B-2. 목록이 딛는 인덱스. 계약의 커서 페이지네이션이 (created_at, id) 내림차순이다.
SET @exists := (
    SELECT COUNT(*) FROM information_schema.statistics
    WHERE table_schema = DATABASE() AND table_name = 'post' AND index_name = 'idx_post_board_created');
SET @stmt := IF(@exists = 0,
    'CREATE INDEX idx_post_board_created ON post (board, created_at, id)',
    'SELECT ''[B-2] idx_post_board_created 이미 있음 — 건너뜀'' AS message');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- B-3. 댓글 목록도 커서다.
SET @exists := (
    SELECT COUNT(*) FROM information_schema.statistics
    WHERE table_schema = DATABASE() AND table_name = 'comment' AND index_name = 'idx_comment_post_created');
SET @stmt := IF(@exists = 0,
    'CREATE INDEX idx_comment_post_created ON comment (post_id, created_at, id)',
    'SELECT ''[B-3] idx_comment_post_created 이미 있음 — 건너뜀'' AS message');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- ── D. 사후 검증 ───────────────────────────────────────────────────────────
-- 여기까지 왔는데 숫자가 다르면 **반쯤 적용된 것**이다. 성공처럼 끝내지 않는다.

SET @d_tables := (
    SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name IN ('post', 'comment', 'reaction'));

SET @d_post_cols := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'post');

SET @d_uq_cols := (
    SELECT COUNT(*) FROM information_schema.statistics
    WHERE table_schema = DATABASE() AND table_name = 'reaction' AND index_name = 'uq_reaction');

-- comment·reaction 은 post 가 사라지면 함께 사라져야 한다. 안 그러면 지운 글의 댓글이
-- 부모 없는 행으로 남아 목록에 안 뜨면서 자리만 차지한다.
SET @d_cascade := (
    SELECT COUNT(*) FROM information_schema.referential_constraints
    WHERE constraint_schema = DATABASE()
      AND constraint_name IN ('fk_comment_post', 'fk_reaction_post')
      AND delete_rule = 'CASCADE');

-- users 로의 FK 는 CASCADE 가 **아니어야** 한다. 탈퇴 한 번에 그 사람이 쓴 글이 전부
-- 사라지면 대화의 앞뒤가 끊긴다 — 채팅이 users 로 FK 를 안 낸 것과 같은 이유다.
--
-- 값은 'NO ACTION' 이다. ON DELETE 를 안 적은 FK 를 MySQL 은 RESTRICT 로 동작시키면서
-- information_schema 에는 **NO ACTION 으로 적는다**(실측 2026-09-02). RESTRICT 로 세면
-- 항상 0 이 나와 이 검사가 조용히 못 지킨다.
SET @d_user_no_cascade := (
    SELECT COUNT(*) FROM information_schema.referential_constraints
    WHERE constraint_schema = DATABASE()
      AND constraint_name IN ('fk_post_user', 'fk_comment_user', 'fk_reaction_user')
      AND delete_rule = 'NO ACTION');

SET @d_idx := (
    SELECT COUNT(DISTINCT index_name) FROM information_schema.statistics
    WHERE table_schema = DATABASE()
      AND index_name IN ('idx_post_board_created', 'idx_comment_post_created'));

SELECT '[D] 사후 검증' AS section,
       @d_tables AS tables_3, @d_post_cols AS post_cols_9, @d_uq_cols AS uq_cols_3,
       @d_cascade AS cascade_2, @d_user_no_cascade AS user_noaction_3, @d_idx AS idx_2;

SET @stmt := IF(@d_tables = 3 AND @d_post_cols = 9 AND @d_uq_cols = 3
                AND @d_cascade = 2 AND @d_user_no_cascade = 3 AND @d_idx = 2,
    'SELECT ''[D] 통과'' AS message',
    'CALL heattrip_migration_abort(''ABORT: 사후 검증 실패. 위 [D] 행의 숫자를 확인하라.'')');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

DROP PROCEDURE IF EXISTS heattrip_migration_abort;
