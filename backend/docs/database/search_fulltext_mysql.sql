-- 1) places 검색 전용 컬럼 추가
ALTER TABLE places
  ADD COLUMN search_text LONGTEXT NULL;

-- 2) place_trait_snapshots 텍스트를 포함해 검색 텍스트 백필
UPDATE places p
LEFT JOIN place_trait_snapshots s ON s.cat3 = p.cat3
SET p.search_text = TRIM(CONCAT_WS(' ',
    NULLIF(TRIM(p.title), ''),
    NULLIF(TRIM(p.cat1), ''),
    NULLIF(TRIM(p.cat2), ''),
    NULLIF(TRIM(p.cat3), ''),
    NULLIF(TRIM(s.cat3name), ''),
    NULLIF(TRIM(s.short_desc1), ''),
    NULLIF(TRIM(s.short_desc2), '')
));

-- 3) 한국어 검색용 FULLTEXT 인덱스
-- ngram_token_size 는 MySQL 서버 변수라서 필요하면 my.cnf/my.ini 에 설정 후 재시작해야 함.
-- 예: ngram_token_size=2
CREATE FULLTEXT INDEX ft_places_search_text
  ON places (search_text) WITH PARSER ngram;

-- 4) 필터 보조 인덱스가 부족하면 추가
CREATE INDEX idx_places_contenttypeid ON places (contenttypeid);
CREATE INDEX idx_places_cat3 ON places (cat3);
CREATE INDEX idx_cat3_category_mapping_category_cat3
  ON cat3_category_mapping (category_id, cat3_code);
