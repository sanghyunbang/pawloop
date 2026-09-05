-- ============================================================================
-- 11_dog.sql — 반려동물 프로필 표 (이슈 #145)
--
-- 왜 지금인가
--
-- 계약의 WalkInput.dogId 가 **필수**라, 이 표가 없으면 산책을 저장할 수 없다.
-- M1 의 잔여가 "경로 저장" 인데 그 앞에 이 표가 막고 서 있었다.
--
-- care_log.dog_id 도 이 표를 기다리고 있었다 — 컬럼은 08_care_log.sql 이 NULL 허용으로
-- 미리 넣어 뒀고 값은 항상 NULL 이다. **다만 이 파일은 그 FK 를 걸지 않는다**(§E-3).
--
-- 무엇을 하나
--
--   dog 표 하나. users 1:N dog.
--
-- 실행
--
--   mysql -u root -p heattrip < mysql/post-start/11_dog.sql
--
-- 멱등하다. 두 번 돌려도 같은 상태로 끝난다.
--
-- 되돌리기
--
--   DROP TABLE dog;
--
-- **되돌리면 사용자가 등록한 반려동물이 전부 사라진다.** 그리고 12_walk.sql 이 이미
-- 적용됐다면 walk 가 이 표를 FK 로 참조하므로 DROP 이 거부된다 — walk 를 먼저 지워야
-- 하고, 그러면 산책 이력도 함께 사라진다. 앱을 먼저 내려라.
-- ============================================================================


-- ── 0. 사전 점검 ────────────────────────────────────────────────────────────
-- 여기서 걸리면 스키마는 한 글자도 바뀌지 않는다.

-- 이 파일은 UTF-8 이고 중단 메시지가 한글이다. 세션 문자셋을 먼저 고정한다 —
-- 안 하면 클라이언트 기본값(윈도우 mysql 은 euckr)을 물려받아, 중단이 걸리는 순간
-- 이유는 안 보이고 ERROR 1366 (Incorrect string value) 만 남는다. 실측 2026-09-02, #169.
SET NAMES utf8mb4;

DROP PROCEDURE IF EXISTS heattrip_migration_abort;
CREATE PROCEDURE heattrip_migration_abort(IN msg VARCHAR(128))
  SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = msg;

-- 0-1. users 가 있어야 FK 를 걸 수 있다. 없으면 01_schema.sql 부터다.
SET @has_users := (
    SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name = 'users');
SET @stmt := IF(@has_users = 1,
    'SELECT ''[0-1] users 확인'' AS message',
    'CALL heattrip_migration_abort(''ABORT: users 표가 없다. init/01_schema.sql 을 먼저 적용하라.'')');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- 0-2. dog 가 이미 있는지 본다(= 재실행이거나 Hibernate 가 먼저 만들었는지).
--      dev 는 ddl-auto=update 라 **앱이 먼저 뜨면 Hibernate 가 표를 이미 만들어 둔다.**
SET @has_dog := (
    SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name = 'dog');

SELECT '[0-2] 기존 표 확인' AS section, @has_dog AS dog;

-- 0-3. dog 가 이미 있다면 species 컬럼이 있는지 확인한다.
--      #145 이전 설계(schema.md §3 초안)에는 이 컬럼이 없었다. 그 모양으로 만들어진 표를
--      그대로 통과시키면 **고양이를 등록하는 순간 Unknown column 으로 500 이 난다.**
SET @has_species := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'dog' AND column_name = 'species');
SET @stmt := IF(@has_dog = 1 AND @has_species = 0,
    'ALTER TABLE dog ADD COLUMN species VARCHAR(10) NOT NULL DEFAULT ''dog'' AFTER name',
    'SELECT ''[0-3] species 사전 점검 통과'' AS message');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;
-- 기존 행은 전부 개로 본다: 이 컬럼이 없던 때는 개밖에 등록할 수 없었다.


-- ── A. 표 생성 (멱등) ───────────────────────────────────────────────────────

-- A-1. 반려동물 프로필. schema.md §3 그대로다.
--
--      표 이름이 dog 인데 고양이도 들어온다 — species 가 종을 구분한다. 이름을 pet 으로
--      옮기지 않은 이유는 walk.dog_id · care_log.dog_id · /api/dogs · WalkInput.dogId 가
--      이미 여러 곳에 박혀 있어서, 이름을 바꾸면 그 전부를 같은 변경에서 함께 옮겨야
--      하기 때문이다.
--
--      ON DELETE CASCADE 인 이유: UserService.deleteMe 가 users 행을 **물리 삭제**한다
--      (UserService.java:229). RESTRICT 로 두면 반려동물을 한 번이라도 등록한 사람은
--      **영구히 탈퇴 불가**가 된다(MySQL 1451).
--
--      나이를 개월로 저장하지 않는다 — 저장하는 순간 낡는다. 정본은 birth 이고
--      개월은 응답에서 파생한다.
CREATE TABLE IF NOT EXISTS dog (
    id         BIGINT       NOT NULL AUTO_INCREMENT,
    user_id    BIGINT       NOT NULL,
    name       VARCHAR(50)  NOT NULL,
    species    VARCHAR(10)  NOT NULL DEFAULT 'dog' COMMENT 'dog|cat|other',
    breed      VARCHAR(50)  NULL COMMENT '품종 (예: 믹스견)',
    size       VARCHAR(10)  NOT NULL DEFAULT 'small' COMMENT 'small|medium|large',
    birth      DATE         NULL,
    neutered   BIT(1)       NOT NULL DEFAULT b'0',
    avatar     VARCHAR(255) NULL COMMENT 'S3 objectKey. 완성된 URL 이 아니다',
    created_at DATETIME(6)  NOT NULL,
    PRIMARY KEY (id),
    KEY idx_dog_user (user_id),
    CONSTRAINT fk_dog_user FOREIGN KEY (user_id)
      REFERENCES users (id) ON DELETE CASCADE,
    CONSTRAINT ck_dog_species CHECK (species IN ('dog','cat','other')),
    CONSTRAINT ck_dog_size CHECK (size IN ('small','medium','large'))
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_0900_ai_ci;


-- ── B. 인덱스·FK 가드 ───────────────────────────────────────────────────────
-- CREATE TABLE IF NOT EXISTS 는 **표가 이미 있으면 아무것도 하지 않는다** — 컬럼도
-- 인덱스도 손대지 않는다. 그래서 Hibernate 가 먼저 만든 표에는 빠진 것이 있을 수 있다.

SET @has_idx := (
    SELECT COUNT(*) FROM information_schema.statistics
    WHERE table_schema = DATABASE() AND table_name = 'dog' AND index_name = 'idx_dog_user');
SET @stmt := IF(@has_idx = 0,
    'ALTER TABLE dog ADD KEY idx_dog_user (user_id)',
    'SELECT ''[B] idx_dog_user 이미 있음'' AS message');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- FK 도 같은 이유로 따로 본다. 없으면 탈퇴가 dog 행을 남기고 고아를 만든다.
--
-- **이 가드는 있는지만 보고 모드는 안 본다.** 이미 RESTRICT 로 서 있으면 여기서 고치지
-- 않고 그냥 넘어가고, 아래 [D] 가 fk_cascade_1 = 0 으로 잡아 중단시킨다. 일부러 그렇게
-- 뒀다 — 운영 표의 FK 를 조용히 DROP 하고 다시 만드는 것이 중단시키고 사람에게 알리는
-- 것보다 위험하다. (실측: RESTRICT 로 바꿔 두고 돌리니 [D] 에서 ERROR 1644 로 멈췄다.)
SET @has_fk := (
    SELECT COUNT(*) FROM information_schema.referential_constraints
    WHERE constraint_schema = DATABASE() AND table_name = 'dog'
      AND constraint_name = 'fk_dog_user');
SET @stmt := IF(@has_fk = 0,
    'ALTER TABLE dog ADD CONSTRAINT fk_dog_user FOREIGN KEY (user_id) REFERENCES users (id) ON DELETE CASCADE',
    'SELECT ''[B] fk_dog_user 이미 있음'' AS message');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;


-- ── D. 사후 검증 ────────────────────────────────────────────────────────────
-- '반쯤 적용된 채 성공처럼 끝나는' 상태를 막는 마지막 관문이다.
-- ddl-auto=validate 는 PK 도 인덱스도 FK 도 검사하지 않으므로, 여기서 확인하지 않으면
-- 빠진 사실을 앱도 CI 도 끝까지 알려주지 않는다.

SET @d_table := (
    SELECT COUNT(*) FROM information_schema.tables
    WHERE table_schema = DATABASE() AND table_name = 'dog');

SET @d_cols := (
    SELECT COUNT(*) FROM information_schema.columns
    WHERE table_schema = DATABASE() AND table_name = 'dog'
      AND column_name IN ('id', 'user_id', 'name', 'species', 'breed', 'size',
                          'birth', 'neutered', 'avatar', 'created_at'));

-- PK 는 **컬럼 수로** 센다 — 이름만 보면 잘못된 모양을 통과시킨다.
SET @d_pk := (
    SELECT COUNT(*) FROM information_schema.statistics
    WHERE table_schema = DATABASE() AND table_name = 'dog' AND index_name = 'PRIMARY');

SET @d_idx := (
    SELECT COUNT(*) FROM information_schema.statistics
    WHERE table_schema = DATABASE() AND table_name = 'dog' AND index_name = 'idx_dog_user');

-- FK 는 **CASCADE 여야 한다.** RESTRICT 로 서 있으면 탈퇴가 MySQL 1451 로 죽는다 —
-- 그리고 그 사실은 탈퇴를 실제로 눌러 보기 전까지 아무도 모른다.
SET @d_fk_cascade := (
    SELECT COUNT(*) FROM information_schema.referential_constraints
    WHERE constraint_schema = DATABASE() AND table_name = 'dog'
      AND constraint_name = 'fk_dog_user' AND delete_rule = 'CASCADE');

-- CHECK 둘도 이름으로 본다. 이름을 나눠 붙인 이유가 여기다 — 하나로 합치면 Hibernate 가
-- dog_chk_1 로 만들고, 그러면 **어느 쪽이 빠졌는지** 이 검증이 말해 주지 못한다.
SET @d_checks := (
    SELECT COUNT(*) FROM information_schema.table_constraints
    WHERE constraint_schema = DATABASE() AND table_name = 'dog'
      AND constraint_type = 'CHECK'
      AND constraint_name IN ('ck_dog_species', 'ck_dog_size'));

SELECT '[D] 사후 검증' AS section,
       @d_table AS table_1, @d_cols AS cols_10, @d_pk AS pk_1,
       @d_idx AS idx_1, @d_fk_cascade AS fk_cascade_1, @d_checks AS checks_2;

SET @stmt := IF(@d_table = 1 AND @d_cols = 10 AND @d_pk = 1
                AND @d_idx = 1 AND @d_fk_cascade = 1 AND @d_checks = 2,
    'SELECT ''[D] 통과'' AS message',
    'CALL heattrip_migration_abort(''ABORT: 사후 검증 실패. 위 [D] 행의 숫자를 확인하라.'')');
PREPARE stmt FROM @stmt;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

DROP PROCEDURE IF EXISTS heattrip_migration_abort;


-- ── E. 여기서 하지 않는 것 (판단 근거) ──────────────────────────────────────
--
-- 1. **삭제(DELETE /api/dogs)를 구현하지 않는다.** 계약에 선언돼 있지만 #145 는 만들지
--    않는다. 만드는 날 **반드시 소프트 삭제(dog.deleted_at)여야 한다** — walk.fk_walk_dog
--    가 CASCADE 라, 이 행을 물리 삭제하면 **그 반려동물의 산책 이력 전부가 조용히 함께
--    사라진다.** 되돌릴 수 없고 사용자는 "프로필만 지웠다" 고 생각한다.
--
--    FK 를 RESTRICT 로 바꾸는 것은 답이 아니다 — 그러면 탈퇴가 막힌다(위 A-1).
--    개 삭제의 안전은 FK 가 아니라 deleted_at 으로 사야 한다.
--
-- 2. **부분 수정(PATCH)도 구현하지 않는다.** 계약이 생성용 DogInput 을 그대로 재사용하는데
--    그 스키마는 required: [name, size] 라 **계약대로면 부분 수정이 불가능**하다.
--    DogPatch 를 나누는 것은 이슈 #24 가 소유한다.
--
-- 3. **care_log.dog_id 에 FK 를 걸지 않는다.** (→ 그 뒤 #154 가 22_care_log_dog_fk.sql 에서
--    SET NULL 로 걸었다. 아래는 이 스크립트를 쓸 때의 판단이다.) CareLog 의 javadoc 이 "dog 표가 생기는 날
--    그 자리에 FK 를 건다" 고 적어 뒀지만, 지금 거는 것이 오히려 나쁘다.
--
--    init/01_schema.sql 은 살아 있는 DB 에서 SHOW CREATE TABLE 로 **뽑은** 파일이고, 그 DB 는
--    Hibernate 가 엔티티로 만든 것이다. CareLog 는 dog_id 를 스칼라 Long 으로 들고 있어서
--    Hibernate 가 그 FK 를 만들지 않는다. 즉 여기서 ALTER 로 FK 를 더하면 **운영 DB 에는
--    있고 커밋된 스키마에는 없는** 제약이 생기고, 다음 재생성 때 조용히 사라진다.
--
--    FK 를 제대로 걸려면 CareLog 가 @ManyToOne Dog 를 들어야 하고, 그건 care 모듈이
--    dog 모듈을 참조한다는 뜻이라 별도 판단이 필요하다. 지금 dog_id 는 **항상 NULL** 이라
--    무결성 위험이 없다 — 미룬 것이 안전한 드문 경우다.
--
-- 4. **아바타 업로드를 구현하지 않는다.** 컬럼만 둔다. 나중에 넣으면 운영 데이터 위의
--    ALTER 가 되기 때문이고, care_log.dog_id 를 미리 넣어 둔 것과 같은 판단이다.
--    값은 항상 NULL 이다. 넣는 날 저장할 것은 **S3 objectKey** 이지 완성된 URL 이 아니다.
--
-- 5. **한 계정의 마리 수 상한을 DB 에 두지 않는다.** DogService.MAX_PETS 다. CHECK 로는
--    "다른 행의 수" 를 볼 수 없고, 트리거는 이 저장소에 한 건도 없다.
-- ============================================================================
