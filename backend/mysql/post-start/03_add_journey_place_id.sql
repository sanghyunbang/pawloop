-- B2-2(다이어리↔장소 연결): journey 테이블에 place_id 컬럼 추가
-- Flutter 클라이언트가 추천 장소("다녀왔어요 → 기록")에서 다이어리를 작성하면
-- 해당 장소의 contentid 를 place_id 로 전송한다. UGC 감정 집계의 그룹핑 키.
--
-- 이 프로젝트는 Flyway/Liquibase 같은 마이그레이션 도구를 사용하지 않는다.
--   - dev:  spring.jpa.hibernate.ddl-auto=update  → 앱 기동 시 컬럼 자동 생성
--   - prod: spring.jpa.hibernate.ddl-auto=validate → 자동 생성 안 됨, 사전에 본 스크립트 실행 필요
-- 따라서 본 스크립트는 운영(validate) 환경에서 컬럼을 미리 추가하기 위한 멱등 DDL이다.
-- 02_add_places_emotion_columns.sql 의 idempotent 패턴을 따른다.
--
-- 추가 컬럼:
--   place_id BIGINT NULL : 추천 장소에서 기록한 경우의 장소 contentid. 구버전 클라이언트는 생략(NULL).

SET @table_exists := (
    SELECT COUNT(*)
    FROM information_schema.tables
    WHERE table_schema = DATABASE()
      AND table_name = 'journey'
);

SET @col_exists := (
    SELECT COUNT(*)
    FROM information_schema.columns
    WHERE table_schema = DATABASE()
      AND table_name = 'journey'
      AND column_name = 'place_id'
);
SET @ddl := IF(
    @table_exists = 0,
    'SELECT ''journey table does not exist yet. Start the backend app first.'' AS message',
    IF(@col_exists = 0,
       'ALTER TABLE journey ADD COLUMN place_id BIGINT NULL',
       'SELECT ''place_id already exists.'' AS message')
);
PREPARE stmt FROM @ddl;
EXECUTE stmt;
DEALLOCATE PREPARE stmt;
