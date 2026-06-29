# 2. Root Cause Analysis

## 기존 검색 SQL의 본질

기존 `q` 검색은 아래 세 가지 비용이 동시에 있었다.

1. 문자열 함수
   - `LOWER(p.title)`
   - `LOWER(p.cat1)`
   - `LOWER(p.cat2)`
   - `LOWER(p.cat3)`

2. 앞쪽 와일드카드
   - `LIKE '%카페%'`

3. 상관 서브쿼리
   - `EXISTS (SELECT 1 FROM place_trait_snapshots ... WHERE pts2.cat3 = p.cat3 ...)`

이 조합은 MySQL 입장에서 "후보를 먼저 빠르게 찾는" 쿼리가 아니라
"일단 읽고 나서 조건을 평가하는" 쿼리로 흘러가기 쉽다.

## 변경 전 목록 쿼리 해석

요약된 실행계획:

```text
Limit: 20
  -> Filter: ((lower(p.title) like '%카페%') or ... or exists(select #2))
      -> Index scan on p using PRIMARY (reverse)
      -> Select #2 (dependent)
          -> Single-row index lookup on pts2 using PRIMARY (cat3=p.cat3)
```

해석:

- `ORDER BY p.contentid DESC LIMIT 20` 때문에 `PRIMARY` 역방향 스캔은 어느 정도 활용됨
- 하지만 각 행마다 텍스트 필터를 평가해야 함
- `cat3name` 확인을 위한 `EXISTS`가 행마다 붙음
- 이 때문에 목록 쿼리는 제한된 결과만 가져와도 조건 평가가 누적됨

## 변경 전 count 쿼리 해석

요약된 실행계획:

```text
Aggregate: count(p.contentid)
  -> Filter: ((lower(p.title) like '%카페%') or ... or exists(select #2))
      -> Table scan on p
      -> Select #2 (dependent)
          -> Single-row index lookup on pts2 using PRIMARY (cat3=p.cat3)
```

실제 관찰 포인트:

- `places` 전체 스캔
- `EXISTS` 서브쿼리 약 4.9만 번 반복
- 약 `755ms` 수준의 count 비용

이게 핵심 병목이었다.

## 왜 일반 인덱스 추가만으로 안 풀렸는가

`contenttypeid`, `cat3` 같은 정형 조건은 일반 인덱스로 보완할 수 있다.
하지만 `q=카페`의 본질은 텍스트 검색이므로 다음 문제가 남는다.

- `LIKE '%카페%'`는 앞쪽 와일드카드 때문에 B-Tree 인덱스를 못 탐
- `LOWER(column)`까지 겹치면 일반 인덱스 사용 가능성이 더 낮아짐
- `cat3name`가 다른 테이블에 있어 `EXISTS` 반복이 발생

즉 일부 필터 인덱스를 추가해도 진짜 큰 병목인 텍스트 검색과 count 비용은 그대로 남는다.

## 결론

문제의 중심은 "정형 필터"가 아니라 "텍스트 검색 경로"였다.
따라서 해결책도 정형 인덱스 튜닝이 아니라 검색 구조 자체를 바꾸는 방향이어야 했다.
