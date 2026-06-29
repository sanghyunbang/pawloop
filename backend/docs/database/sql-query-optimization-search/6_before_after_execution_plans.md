# 6. Before And After Execution Plans

## 변경 전 `q=카페` 목록 조회

요약 실행계획:

```text
Limit: 20
  -> Filter: ((lower(p.title) like '%카페%') or ... or exists(select #2))
      -> Index scan on p using PRIMARY (reverse)
      -> Select #2 (subquery in condition; dependent)
          -> Single-row index lookup on pts2 using PRIMARY (cat3=p.cat3)
```

의미:

- `PRIMARY` 역방향 스캔으로 일부 정렬 이점은 있었음
- 하지만 각 후보마다 `LIKE`와 `EXISTS`를 반복 평가
- 조건이 가벼운 구조는 아니었음

## 변경 전 `q=카페` count

요약 실행계획:

```text
Aggregate: count(p.contentid)
  -> Filter: ((lower(p.title) like '%카페%') or ... or exists(select #2))
      -> Table scan on p
      -> Select #2 (subquery in condition; dependent)
          -> Single-row index lookup on pts2 using PRIMARY (cat3=p.cat3)
```

관찰 포인트:

- `places` 전체 스캔
- `EXISTS` 반복 수행
- 약 `755ms`

이번 작업의 가장 중요한 타겟은 바로 이 count 쿼리였다.

## 변경 후 `q=카페` 목록 조회

실제 확인한 결과:

```text
Limit: 20
  -> Sort row IDs: p.contentid DESC
      -> Filter: (match p.search_text against ('카페' in boolean mode))
          -> Full-text index search on p using ft_places_search_text
```

핵심 변화:

- 더 이상 `LIKE '%카페%'`를 쓰지 않음
- 더 이상 `EXISTS(place_trait_snapshots ...)`를 매 요청마다 반복하지 않음
- `ft_places_search_text` Fulltext 인덱스에서 후보를 직접 찾음

관찰값:

- 후보 약 `3468`건
- 전체 약 `4.9ms`

## 변경 후 `q=카페` count

실제 확인한 결과:

```text
Rows fetched before execution
```

의미:

- 변경 전처럼 `places` 전체 스캔 + dependent subquery가 남지 않음
- count 경로 비용이 매우 크게 줄어듦

## 왜 목록 조회는 수치상 더 느려 보일 수 있는가

경우에 따라 변경 전 `LIMIT 20` 목록 쿼리만 비교하면
숫자상 기존이 더 빨라 보일 수 있다.

하지만 그 비교는 전체 검색 경로를 설명하지 못한다.

이유:

- 실제 API는 목록만이 아니라 count도 함께 처리
- 기존의 진짜 병목은 count
- 변경 후에는 가장 비싼 부분이 제거됨

즉 성능 판단은 목록 한 줄 숫자보다
"검색 전체 경로가 어떤 일을 하느냐"로 봐야 한다.

## 실행계획 해석 기준 변화

변경 전의 `LIKE/EXISTS` 실행계획은 이제 현재 코드의 `q` 검색을 설명하는 자료로는 쓰지 않는다.
이유는 코드가 더 이상 그 SQL을 만들지 않기 때문이다.

현재 기준:

- `q`가 있는 케이스: `MATCH ... AGAINST` 실행계획으로 본다
- 정형 필터만 있는 케이스: 현재 백엔드가 실제 생성하는 SQL 기준으로 본다

즉 실행계획도 "현재 코드가 실제로 만드는 SQL"에 맞춰 해석해야 한다.
