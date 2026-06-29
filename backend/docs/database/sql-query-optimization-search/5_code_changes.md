# 5. Code Changes

## 변경 개요

이번 최적화는 주로 검색 경로와 검색 텍스트 동기화 경로에 한정된다.

바뀐 파일:

- `src/main/java/com/heattrip/heat_trip_backend/explore/adapter/jpa/ExploreSearchJpaAdapter.java`
- `src/main/java/com/heattrip/heat_trip_backend/tour/domain/Place.java`
- `src/main/java/com/heattrip/heat_trip_backend/tour/repository/PlaceRepository.java`
- `src/main/java/com/heattrip/heat_trip_backend/tour/service/TraitSnapshotService.java`
- `docs/search_fulltext_mysql.sql`

## 1. `Place` 엔티티 변경

파일:

- [`Place.java`](../../src/main/java/com/heattrip/heat_trip_backend/tour/domain/Place.java)

변경 내용:

- `search_text` 컬럼 대응 필드 `searchText` 추가
- 컬럼 정의를 `LONGTEXT`로 명시
- `@PrePersist`, `@PreUpdate` 시점에 기본 검색 텍스트를 생성

의도:

- 새로운 place 저장/갱신 시 기본 검색어는 자동으로 유지
- title/cat1/cat2/cat3 정도는 별도 백필 없이 반영되게 함

주의:

- `cat3Name`, `shortDesc` 등 snapshot 기반 값은 entity alone으로 알 수 없으므로
  snapshot 재빌드 후 repository update로 보강한다

## 2. `PlaceRepository` 변경

파일:

- [`PlaceRepository.java`](../../src/main/java/com/heattrip/heat_trip_backend/tour/repository/PlaceRepository.java)

추가 메서드:

- `refreshAllSearchTexts()`
- `refreshSearchTextsByCat3Codes(...)`

역할:

- `places`와 `place_trait_snapshots`를 조인해서 `search_text`를 재생성
- `title`, `cat1`, `cat2`, `cat3`, `cat3name`, `short_desc1`, `short_desc2`를 합쳐 저장

왜 repository native update인가:

- 이 작업은 조회가 아니라 대량 갱신이기 때문
- entity 단건 루프보다 DB에서 한 번에 갱신하는 것이 맞음

## 3. `TraitSnapshotService` 변경

파일:

- [`TraitSnapshotService.java`](../../src/main/java/com/heattrip/heat_trip_backend/tour/service/TraitSnapshotService.java)

변경 내용:

- snapshot 재빌드 후 `placeRepo.refreshAllSearchTexts()` 호출 추가

의도:

- `place_trait_snapshots`가 바뀌면 그 값을 사용한 `search_text`도 다시 맞춰야 함
- 검색용 denormalized data를 snapshot 리빌드 흐름에 같이 묶음

## 4. `ExploreSearchJpaAdapter` 변경

파일:

- [`ExploreSearchJpaAdapter.java`](../../src/main/java/com/heattrip/heat_trip_backend/explore/adapter/jpa/ExploreSearchJpaAdapter.java)

변경 전:

- JPA Criteria API 기반
- `LIKE '%q%'`
- `EXISTS`로 `cat3Name` 확인
- DTO 조립을 위해 상관 서브쿼리 사용

변경 후:

- native SQL 기반
- `LEFT JOIN place_trait_snapshots`
- `q`가 있을 때 `MATCH(p.search_text) AGAINST (:keyword IN BOOLEAN MODE)`
- `contentTypeId`, `cat3`, `emotionCategoryId`는 동적 조건으로 유지
- `count(*)`도 같은 조건을 공유

### 왜 native SQL로 바꿨는가

이번 작업의 핵심은 MySQL Fulltext 기능 사용이다.
이 기능을 JPA Criteria로 표현하는 것도 이론상 가능하지만,
실제로는 아래 이유로 native가 더 단순하고 명확했다.

- `MATCH ... AGAINST`를 직접 제어 가능
- `BOOLEAN MODE`를 명시적으로 사용 가능
- MySQL Fulltext 중심 설계를 우회하지 않음
- 검색 전용 경로만 분리하므로 영향 범위가 제한적

## 5. 바뀌지 않은 것

- `scroll` API
- `list` API
- 상세 조회
- 감정 관련 조회/피드백 API

즉, 이번 최적화는 전체 탐색 도메인 개편이 아니라 `search` 경로 개편이다.
