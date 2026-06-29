# 7. Validation And Regression

## 코드 검증

수행한 검증:

```bash
./gradlew compileJava --console=plain
```

결과:

- 컴파일 성공

## 테스트 검증

대상 테스트:

- `src/test/java/com/heattrip/heat_trip_backend/explore/web/ExploreSearchSqlLogTest.java`

실행 명령:

```bash
./gradlew test --tests "com.heattrip.heat_trip_backend.explore.web.ExploreSearchSqlLogTest" --rerun-tasks --info --console=plain
```

## 테스트 중 겪은 일

초기에는 `Case 5`, `Case 6`이 실패했다.

원인:

- DB에 `FULLTEXT` 인덱스가 아직 없었음
- 에러: `Can't find FULLTEXT index matching the column list`

의미:

- 코드 로직 오류가 아니라 마이그레이션 미완료 상태

## DB 검증

실제 DB에서 확인한 것:

- `search_text` 컬럼 존재
- `search_text` 값 백필 완료
- `ft_places_search_text` 인덱스 생성 완료
- `MATCH(search_text) AGAINST('카페' IN BOOLEAN MODE)` 쿼리 실행 가능

## 회귀 영향 범위

영향이 큰 부분:

- `GET /api/explore/places/search`에서 `q`가 있는 텍스트 검색

직접 영향이 적은 부분:

- `scroll` 목록
- 상세 조회
- 홈 테마 카드 경로
- 감정 조회/피드백

## 남은 확인 포인트

배포 전 혹은 후속 검증에서 아래를 확인하는 것이 좋다.

1. `q=카페`
2. `q=힐링`
3. 짧은 검색어
4. 공백 포함 검색어
5. `q + contentTypeId`
6. `q + cat3`
7. `q + emotionCategoryId`

## 결과 해석 주의점

Fulltext 검색은 `LIKE '%keyword%'`와 100% 동일한 의미가 아니다.
따라서 아래는 결과가 일부 달라질 수 있다.

- 한 글자 검색
- 특수문자 포함 검색
- 토큰화 경계가 애매한 검색어

이건 버그라기보다 검색 방식 차이이므로,
성능 최적화와 검색 의미 보존 사이의 트레이드오프로 관리해야 한다.
