-- B1-2: places 테이블에 감정 데이터 컬럼 추가
-- docs/04, docs/07 §4-2 참고. Phase 2 UGC 집계의 저장 위치를 마련한다.
--
-- 이 프로젝트는 Flyway/Liquibase 같은 마이그레이션 도구를 사용하지 않는다.
--   - dev:  spring.jpa.hibernate.ddl-auto=update  → 앱 기동 시 컬럼 자동 생성
--   - prod: spring.jpa.hibernate.ddl-auto=validate → 자동 생성 안 됨, 사전에 본 스크립트 실행 필요
-- 따라서 본 스크립트는 운영(validate) 환경에서 컬럼을 미리 추가하기 위한 멱등 DDL이다.
-- 01_add_places_search_fulltext.sql 의 idempotent 패턴을 따른다.
--
-- 추가 컬럼:
--   seed_emotion JSON NULL            : 감정→가중치 맵. 공공데이터 + LLM 1회 배치. nullable.
--   ugc_emotion  JSON NULL            : 감정→가중치 맵. 사용자 다이어리 기분 집계. nullable.
--   ugc_count    INT NOT NULL DEFAULT 0 : UGC 데이터포인트 수. 5 미만이면 seed만 노출(가드 로직은 본 티켓 범위 밖).

SET @table_exists := (
    SELECT COUNT(*)
    FROM information_schema.tables
    WHERE table_schema = DATABASE()
      AND table_name = 'places'
);

-- seed_emotion
SET @col_exists := (
    SELECT COUNT(*)
    FROM information_schema.columns
    WHERE table_schema = DATABASE()
      AND table_name = 'places'
      AND column_name = 'seed_emotion'
);
SET @ddl := IF(
    @table_exists = 0,
    'SELECT ''places table does not exist yet. Start the backend app first.'' AS message',
    IF(@col_exists = 0,
       'ALTER TABLE places ADD COLUMN seed_emotion JSON NULL',
       'SELECT ''seed_emotion already exists.'' AS message')
);
PREPARE stmt FROM @ddl;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- ugc_emotion
SET @col_exists := (
    SELECT COUNT(*)
    FROM information_schema.columns
    WHERE table_schema = DATABASE()
      AND table_name = 'places'
      AND column_name = 'ugc_emotion'
);
SET @ddl := IF(
    @table_exists = 0,
    'SELECT ''places table does not exist yet. Start the backend app first.'' AS message',
    IF(@col_exists = 0,
       'ALTER TABLE places ADD COLUMN ugc_emotion JSON NULL',
       'SELECT ''ugc_emotion already exists.'' AS message')
);
PREPARE stmt FROM @ddl;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;

-- ugc_count
SET @col_exists := (
    SELECT COUNT(*)
    FROM information_schema.columns
    WHERE table_schema = DATABASE()
      AND table_name = 'places'
      AND column_name = 'ugc_count'
);
SET @ddl := IF(
    @table_exists = 0,
    'SELECT ''places table does not exist yet. Start the backend app first.'' AS message',
    IF(@col_exists = 0,
       'ALTER TABLE places ADD COLUMN ugc_count INT NOT NULL DEFAULT 0',
       'SELECT ''ugc_count already exists.'' AS message')
);
PREPARE stmt FROM @ddl;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;
