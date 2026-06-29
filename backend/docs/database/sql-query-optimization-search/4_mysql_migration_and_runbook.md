# 4. MySQL Migration And Runbook

## 개요

코드 변경만으로는 Fulltext 검색이 작동하지 않는다.
MySQL 쪽에 아래 작업이 필요했다.

1. `search_text` 컬럼 준비
2. 기존 데이터 백필
3. `FULLTEXT INDEX ... WITH PARSER ngram` 생성
4. 필요한 보조 인덱스 확인

## 실제 SQL 스크립트

원본 스크립트 파일:

- [`docs/search_fulltext_mysql.sql`](../../docs/search_fulltext_mysql.sql)

## 실제 적용 중 만난 이슈와 대응

### 1. Duplicate column name `search_text`

상황:

```sql
ALTER TABLE places ADD COLUMN search_text LONGTEXT NULL;
```

결과:

- `Error Code: 1060. Duplicate column name 'search_text'`

원인:

- 애플리케이션 설정에 `spring.jpa.hibernate.ddl-auto=update`가 있어
  애플리케이션/테스트 기동 시 Hibernate가 컬럼을 이미 생성했음

대응:

- 컬럼 추가는 건너뛰고 다음 단계로 진행

### 2. Safe update mode

상황:

```sql
UPDATE places ...
```

결과:

- `Error Code: 1175. You are using safe update mode ...`

원인:

- MySQL Workbench 세션의 safe update mode

대응:

```sql
SET SQL_SAFE_UPDATES = 0;
```

작업 후 필요하면 다시:

```sql
SET SQL_SAFE_UPDATES = 1;
```

### 3. Data too long for column `search_text`

상황:

- 백필 `UPDATE` 수행 중

결과:

- `Error Code: 1406. Data too long for column 'search_text'`

원인:

- Hibernate가 만든 `search_text`가 충분히 큰 타입이 아니었음

대응:

```sql
ALTER TABLE places
MODIFY COLUMN search_text LONGTEXT NULL;
```

그 후 다시 백필

### 4. FULLTEXT 생성 시 warning

상황:

```sql
CREATE FULLTEXT INDEX ft_places_search_text
ON places (search_text) WITH PARSER ngram;
```

결과:

- `0 row(s) affected, 1 warning(s): 124 InnoDB rebuilding table to add column FTS_DOC_ID`

해석:

- 실패가 아니라 정상 생성
- InnoDB가 내부 Fulltext용 보조 컬럼과 메타 구조를 만들며 테이블을 재구성한 것

### 5. Duplicate key name

상황:

```sql
CREATE INDEX idx_places_cat3 ON places (cat3);
```

결과:

- `Error Code: 1061. Duplicate key name 'idx_places_cat3'`

원인:

- 이미 같은 이름 인덱스가 존재

대응:

- 무시하고 진행
- 필요 시 `SHOW INDEX`로 확인

## 권장 실행 순서

1. `search_text` 컬럼 존재 여부 확인

```sql
SHOW COLUMNS FROM places LIKE 'search_text';
```

2. 컬럼 타입이 충분히 큰지 확인하고, 아니면 `LONGTEXT`로 수정

```sql
ALTER TABLE places
MODIFY COLUMN search_text LONGTEXT NULL;
```

3. 백필

```sql
SET SQL_SAFE_UPDATES = 0;

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

SET SQL_SAFE_UPDATES = 1;
```

4. Fulltext 인덱스 생성

```sql
CREATE FULLTEXT INDEX ft_places_search_text
ON places (search_text) WITH PARSER ngram;
```

5. 보조 인덱스 확인

```sql
SHOW INDEX FROM places WHERE Key_name = 'idx_places_cat3';
SHOW INDEX FROM places WHERE Key_name = 'idx_places_contenttypeid';
SHOW INDEX FROM cat3_category_mapping WHERE Key_name = 'idx_cat3_category_mapping_category_cat3';
```

## 확인용 SQL

백필 확인:

```sql
SELECT contentid, title, search_text
FROM places
WHERE search_text IS NOT NULL
LIMIT 5;
```

Fulltext 인덱스 확인:

```sql
SHOW INDEX FROM places WHERE Key_name = 'ft_places_search_text';
```

Fulltext 검색 확인:

```sql
SELECT contentid, title
FROM places
WHERE MATCH(search_text) AGAINST('카페' IN BOOLEAN MODE)
LIMIT 20;
```

## 운영 메모

- `ngram_token_size=2`가 필요하면 MySQL 설정 파일 반영과 재시작이 필요할 수 있다
- 본 작업은 스키마 변경이 포함되므로 운영 적용 시 실행 시점과 테이블 리빌드 시간을 고려해야 한다
