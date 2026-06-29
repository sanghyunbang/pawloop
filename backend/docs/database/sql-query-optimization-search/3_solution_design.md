# 3. Solution Design

## 선택한 방향

정석 해법으로 아래 구조를 선택했다.

1. 검색용 텍스트를 한 컬럼으로 펼친다
2. 그 컬럼에 `FULLTEXT INDEX ... WITH PARSER ngram`을 건다
3. 검색 SQL을 `MATCH ... AGAINST` 기반으로 바꾼다

## 왜 `search_text` 컬럼을 도입했는가

기존 검색 대상은 한 테이블에 모여 있지 않았다.

- `places.title`
- `places.cat1`
- `places.cat2`
- `places.cat3`
- `place_trait_snapshots.cat3name`
- `place_trait_snapshots.short_desc1`
- `place_trait_snapshots.short_desc2`

이런 구조에서 매 요청마다 조인/서브쿼리로 검색 대상을 합치는 것은 비효율적이다.
검색 경로에서는 정규화보다 조회 성능과 단순성이 중요하므로, 검색용 텍스트를 미리 펼쳐 저장하는 것이 맞다.

## 왜 Fulltext + ngram인가

MySQL 일반 인덱스는 아래에 강하다.

- `=`
- `BETWEEN`
- `>`
- `LIKE 'abc%'`

반면 이번 문제는 한국어 포함 텍스트 검색이다.
그래서 필요한 것은 일반 인덱스가 아니라 검색용 인덱스다.

`FULLTEXT`는 역색인 기반 검색에 맞고,
한국어/CJK 처리를 위해 `ngram` parser가 필요하다.

예를 들어 `카페`라는 검색어는 ngram 토큰화를 통해 검색 후보를 바로 찾을 수 있다.

## 설계 원칙

이번 작업에서 적용한 원칙은 아래와 같다.

1. 정형 필터와 텍스트 검색을 분리한다
   - `contentTypeId`, `cat3`, `emotionCategoryId`는 기존처럼 정형 조건으로 처리
   - `q`만 Fulltext 검색으로 처리

2. 텍스트 검색 비용을 저장 시점으로 일부 이전한다
   - 요청마다 `EXISTS`를 계산하지 않고
   - `search_text`에 미리 합쳐둔다

3. 영향 범위를 검색 API로 제한한다
   - `search` 경로만 변경
   - `scroll` 목록, 상세 조회 등은 그대로 둔다

## 기대 효과

- 텍스트 검색 후보를 Fulltext 인덱스에서 찾을 수 있음
- `count(*)`가 전체 스캔 + 상관 서브쿼리 반복에서 벗어남
- 검색 SQL이 더 단순해짐
- 검색 성능 병목이 서비스 로직이 아니라 검색 인덱스 구조로 이동함

## 결과적으로 바뀐 개념

변경 전:

```text
요청 시점에 텍스트를 여기저기서 뒤져서 찾음
```

변경 후:

```text
검색 대상 문자열을 미리 모아두고, 검색용 인덱스로 찾음
```
