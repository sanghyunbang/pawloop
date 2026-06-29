# 1. Problem And Baseline

## 대상 API

- 경로: `GET /api/explore/places/search`
- 주요 파라미터:
  - `q`
  - `contentTypeId`
  - `cat3`
  - `emotionCategoryId`
  - `page`
  - `size`
  - `sort`

## 프론트 사용 맥락

이 API는 홈 검색 쪽에서 사용한다.
테마 카드 목록은 별도 커서 기반 API `GET /api/explore/places/scroll`을 사용하므로,
이번 최적화의 주 대상은 `search` 경로였다.

## 초기 문제

문제의 핵심은 `q`가 들어오는 텍스트 검색이었다.

예:

```http
GET /api/explore/places/search?q=카페&page=0&size=20
```

초기 구현은 대략 아래 조건을 사용했다.

```sql
LOWER(p.title) LIKE '%카페%'
OR LOWER(p.cat1) LIKE '%카페%'
OR LOWER(p.cat2) LIKE '%카페%'
OR LOWER(p.cat3) LIKE '%카페%'
OR EXISTS (
    SELECT 1
    FROM place_trait_snapshots pts2
    WHERE pts2.cat3 = p.cat3
      AND LOWER(pts2.cat3name) LIKE '%카페%'
)
```

## 관찰된 증상

- `%keyword%` 검색이므로 일반 B-Tree 인덱스를 활용하지 못함
- `LOWER(column)`을 사용해 일반 인덱스 활용이 더 어려움
- `cat3name` 검색을 위해 `EXISTS` 상관 서브쿼리가 반복됨
- 목록 조회보다 `COUNT(*)`가 훨씬 느림

## 초기 구조에서 중요했던 포인트

기존 검색은 단순히 결과 목록만 느린 것이 아니었다.
페이지네이션 응답을 위해 `COUNT(*)`도 같이 계산해야 했고,
이때 전체 테이블을 훑는 비용이 커졌다.

즉 병목은 아래 두 가지가 합쳐진 구조였다.

1. 텍스트 검색이 인덱스를 못 탐
2. count 쿼리가 전체 스캔 + 반복 서브쿼리를 수행함

## 왜 이 문서가 필요한가

이 작업은 단순한 인덱스 추가가 아니라, 검색 경로의 SQL 모델 자체를 바꾼 사례다.
따라서 "무엇을 바꿨는가"보다 "왜 기존 방식으로는 해결되지 않았는가"를 먼저 기록해야
이후 유지보수나 회귀 판단이 가능하다.
