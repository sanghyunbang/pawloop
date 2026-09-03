# Walks 백엔드 구현 청사진 (산책 기록/통계)

> 이 문서는 **구현 코드(메서드 바디)를 담지 않는다.** 개발자가 직접 구현할 때 읽을 구조/시그니처/DTO 필드/엔티티 매핑/쿼리 개요만 정의한다.
> 계약: [openapi.yaml](../../04-api/openapi.yaml) `Walks` 태그 (`/api/walks`, `/api/walks/{walkId}`, `/api/walks/stats/weekly`)
> 데이터 모델: [erd.md](../../03-database/erd.md) `walk`, [schema.md](../../03-database/schema.md) §3 `walk`
> 컨벤션 참조: `backend/.../social`(controller/service/repository/entity/dto, record DTO, ResponseEntity), `.../user/controller/AuthController.java`(JWT userId 추출), `.../config/WebClientConfig.java`

---

## 1. 개요

| 항목 | 내용 |
| --- | --- |
| 책임 | 산책 1건의 GPS 경로·거리·시간 저장/조회, 내 반려견 산책 이력 목록(커서 페이지네이션), 주간(월~일) 거리 통계 집계 |
| 관련 테이블 | `walk`(주), `dog`(소유 검증 FK), `users`(소유 사용자) |
| 공간 컬럼 | `walk.path` = `LINESTRING SRID 4326` **NULL 허용** (GPS 폴리라인). [ADR-0015](../../99-decisions/decision-log.md#adr-0015--산책-경로는-linestring-으로-저장하되-spatial-index-는-만들지-않는다) |
| 인증 | **전부 인증 필요.** openapi에서 Walks 경로는 `security: []` 미지정 → 전역 `bearerAuth` 적용. 소유권은 `walk → dog → dog.user_id == 요청 userId`로 확인 |
| 재사용 가능한 것 | JWT 필터/`userId` 추출 규약(`AuthController` 참조), `Error`/`Page` 공통 응답 패턴, `dog` 엔티티/`DogRepository`(소유 검증), 프로젝트 표준 `record` DTO + `ResponseEntity<?>` 스타일 |
| 재사용 **불가**(신규) | `Walk` 엔티티/매핑, `WalkRepository`, 좌표배열↔JTS `LineString` 변환 유틸, 주간 요일별 집계 로직 |
| 패키지 | `com.heattrip.heat_trip_backend.walk.{controller,service,repository,entity,dto}` |

---

## 2. Controller

**클래스명:** `WalkController` — `@RestController @RequestMapping("/api/walks")`

| HTTP · 경로 | 메서드 시그니처 (파라미터 타입) | 반환 DTO | 인증 |
| --- | --- | --- | --- |
| `GET /api/walks` | `list(@CurrentUser User user, Long dogId, String cursor, Integer limit)` | `WalkPageResponse` (`items: List<WalkResponse>` · `nextCursor` · `hasMore`) | O |
| `POST /api/walks` | `save(@CurrentUser User user, @Valid @RequestBody WalkRequest request)` | `ResponseEntity<WalkResponse>` (201) | O |
| `GET /api/walks/stats/weekly` | `stats(@CurrentUser User user, Long dogId)` | `WalkStatsResponse` | O |
| `GET /api/walks/{walkId}` | `detail(@CurrentUser User user, long walkId)` | `WalkResponse` — **경로가 실리는 유일한 응답이다** | O |
| `PUT /api/walks/{walkId}/memo` | `rewriteMemo(@CurrentUser User user, long walkId, @Valid @RequestBody WalkMemoRequest request)` | `WalkResponse` (#187) | O |
| `DELETE /api/walks/{walkId}` | `delete(@CurrentUser User user, long walkId)` | `void` (204) | O |

> 메모: `GET /{walkId}` 의 `401` 은 계약에 추가됐다(#24 · #145). **타인 산책과 없는 산책은 똑같이 404 다** — 403 을 주면 "그 id 는 존재한다" 를 알려 주는 셈이라 id 를 훑어 남의 기록 수를 셀 수 있다.
>
> `userId` 는 `@CurrentUser User me` 로 받는다. `HttpServletRequest` 에서 직접 꺼내는 것은 **금지**이며 `AuthSubjectContractSpecTest` 가 소스 스캔으로 막는다(§6 참조). 

---

## 3. DTO (record)

패키지 `...walk.dto`. **자바 쪽 이름은 요청 `XxxRequest`, 응답 `XxxResponse`** 이고(`WalkRequest`·`WalkResponse`·`WalkPageResponse`·`WalkStatsResponse`·`WalkMemoRequest`), **계약(openapi)의 스키마 이름은 `WalkInput`·`Walk`** 다. 둘이 다른 것은 의도다 — 계약은 언어를 안 고르고, 자바는 자기 관용을 따른다. 아래 절들이 어느 쪽 이름을 말하는지 매번 밝힌다. 공통 `Error` 는 기존 것 참조, 페이지 응답은 `Page` 스키마(`items`/`nextCursor`/`hasMore`)와 매핑.

### 3.1 요청

**`WalkRequest`** (자바) — 계약의 `WalkInput` 스키마와 매핑 (required: dogId, startedAt, distanceM, durationS)

| 필드 | 타입 | 비고 |
| --- | --- | --- |
| `dogId` | `Long` | 필수. 소유 검증 대상 |
| `startedAt` | `OffsetDateTime` (또는 `Instant`) | 필수. date-time |
| `endedAt` | `OffsetDateTime` | 선택 |
| `distanceM` | `Integer` | 필수. 총 거리(m) |
| `durationS` | `Integer` | 필수. 총 소요(초) |
| `path` | `List<List<Double>>` | 선택. `[[lng, lat], ...]` (GeoJSON coordinates 순서 = 경도, 위도) |
| `memo` | `String` | 선택. ≤ 500자 |
| `weather` | `String` | 선택. ≤ 30자 |

### 3.2 응답

**`WalkResponse`** (자바) — 계약의 `Walk` 스키마와 매핑

| 필드 | 타입 | 비고 |
| --- | --- | --- |
| `id` | `Long` | |
| `dogId` | `Long` | |
| `startedAt` | `OffsetDateTime` | |
| `endedAt` | `OffsetDateTime` | nullable |
| `distanceM` | `Integer` | |
| `durationS` | `Integer` | |
| `path` | `List<List<Double>>` | `[[lng, lat], ...]`. LINESTRING → 배열 역변환 |
| `memo` | `String` | nullable |
| `weather` | `String` | nullable |

> 목록(`GET /api/walks`) 응답의 `path`는 페이로드 절감을 위해 생략/빈 배열 정책 고려 가능(상세에서만 완전 경로 반환). 정책 선택은 구현 노트 참조.

**`WalkPageResponse`** (자바) — 계약의 `Page`(allOf) 와 매핑 (커서 페이지네이션)

| 필드 | 타입 | 비고 |
| --- | --- | --- |
| `items` | `List<WalkResponse>` | |
| `nextCursor` | `String` | nullable. 다음 페이지 커서(불투명 토큰) |
| `hasMore` | `boolean` | |

**`WalkStatsResponse`** (자바) — 계약의 `WalkStats` 스키마와 매핑

| 필드 | 타입 | 비고 |
| --- | --- | --- |
| `weekKm` | `List<Double>` | 길이 7. 월~일 요일별 거리(km) |
| `totalKm` | `Double` | 주간 합계 km |
| `walkCount` | `Integer` | 주간 산책 건수 |
| `avgKm` | `Double` | 건당 평균 km |
| `topPlaces` | `List<TopPlaceDto>` | 자주 간 곳 상위 |

**`TopPlaceDto`** — `WalkStats.topPlaces[]` 매핑

| 필드 | 타입 | 비고 |
| --- | --- | --- |
| `place` | `String` | 장소명 |
| `count` | `Integer` | 방문 횟수 |

> `topPlaces`는 MVP에서 산출 근거 데이터(`walk`↔`place` 연결)가 없다. 구현 노트 참조 — 초기엔 빈 배열 반환 또는 후순위 처리 권장.

---

## 4. Service

**클래스명:** `WalkService` (`@Service`, 쓰기 메서드 `@Transactional`)

| 메서드 시그니처 | 한 줄 책임 |
| --- | --- |
| `Saved save(long userId, WalkRequest request)` | dog 소유 검증 → 좌표 배열을 LINESTRING 으로, 점별 시각을 `path_t` 로 변환해 저장. **`Saved.created`** 로 "새로 만들었나" 를 알린다 — 멱등키가 같으면 기존 것을 그대로 돌려준다 |
| `WalkPageResponse page(long userId, Long dogId, String cursor, Integer limit)` | 요청자 소유 산책만 커서로 페이징. **경로는 안 싣는다** |
| `WalkResponse detail(long userId, long walkId)` | 단건 + 소유권 확인. **경로가 실리는 유일한 응답이다**. 없거나 타인 소유면 똑같이 404 |
| `WalkResponse rewriteMemo(long userId, long walkId, String memo)` | 회고 메모 덮어쓰기(#187) |
| `void delete(long userId, long walkId)` | 소유권 확인 후 삭제. 멱등키 때문에 같은 산책을 다시 저장할 수 없으므로 **지울 길이 반드시 있어야 한다** |
| `WalkStatsResponse stats(long userId, Long dogId)` | 이번 주(KST 월~일) 요일별 거리 + 전체 기간 합계. **화면 둘이 이 하나로 채워진다** |

> `limit` 상한(openapi 기본 20 / 최대 100) 클램프, `dogId` 미지정 시 요청자 소유 전체 dog 대상으로 확장 — 이 결정은 Service에서 처리(Controller는 얇게 유지).

---

## 5. Entity & Repository

### 5.1 Entity — `Walk` (`@Entity @Table(name = "walk")`)

| Java 필드 | 컬럼 | 타입/매핑 메모 |
| --- | --- | --- |
| `id` | `id` | `@Id @GeneratedValue(IDENTITY)` `Long` |
| `dogId` | `dog_id` | `Long` (FK→`dog.id`). `@ManyToOne Dog` 대신 FK id 직접 매핑도 가능 — 컨벤션에 맞춰 택1 |
| `startedAt` | `started_at` | `LocalDateTime`/`OffsetDateTime` |
| `endedAt` | `ended_at` | nullable |
| `distanceM` | `distance_m` | `Integer` (기본 0) |
| `durationS` | `duration_s` | `Integer` (기본 0) |
| `path` | `path` | **`LINESTRING SRID 4326 NOT NULL`** (공간 컬럼). JPA 기본 매핑 불가 — 컬럼 정의만 두고 저장/조회는 native 쿼리로 처리(아래 참조). `@Column(columnDefinition = "LINESTRING SRID 4326", ...)` 주석 처리 권장 |
| `memo` | `memo` | `String` nullable (≤500) |
| `weather` | `weather` | `String` nullable (≤30) |
| `createdAt` | `created_at` | `LocalDateTime` (DB 기본 now) |

**인덱스(스키마 기준):** `KEY idx_walk_dog (dog_id, started_at)`(주간 집계), `KEY idx_walk_dog_created (dog_id, created_at, id)`(목록 커서), `UNIQUE KEY uq_walk_client (dog_id, client_walk_id)`(멱등).

**`SPATIAL INDEX` 는 만들지 않는다**(ADR-0015). 저장소에 `walk` 를 공간으로 묻는 질의가 하나도 없고, 그 인덱스는 `path NOT NULL` 을 요구하는데 **경로 없는 산책이 실제로 있다.**
**FK:** `fk_walk_dog (dog_id) → dog(id) ON DELETE CASCADE`.

> ~~`path`는 SPATIAL INDEX 요건상 `NOT NULL`.~~ **뒤집혔다(ADR-0015).** `path` 는 NULL 을 허용한다. 점이 0개거나 1개면(LINESTRING 은 점 1개로 만들 수 없다) 경로 없이 저장한다 — 400 으로 거부하지 않는다. 손입력 기록과 위치 권한을 거부한 기록이 그 경우다.

### 5.2 Repository — `WalkRepository extends JpaRepository<Walk, Long>`

공간 컬럼 삽입/조회는 native `@Query`로. 아래는 **시그니처 개요만**(바디/실제 SQL 세부는 구현자 담당).

| 메서드 | 종류 | 개요 |
| --- | --- | --- |
| `List<Walk> findOwnedPage(Long userId, Long dogId, Long cursorId, int limit)` | 파생/`@Query` | 소유 dog의 walk를 `id DESC` (또는 `started_at DESC, id DESC`) 기준으로 커서 이후 `limit+1`건 조회. `walk JOIN dog` on `dog.user_id = :userId` |
| `Optional<Walk> findOwnedById(Long userId, Long walkId)` | `@Query` | `walk JOIN dog`로 소유권 포함 단건 조회 |
| `(native) Long insertWalk(...)` **또는** `saveWithPath(...)` | **native `@Query`** | `INSERT INTO walk(..., path) VALUES (..., ST_GeomFromText(:wkt, 4326))` — 좌표배열을 WKT `LINESTRING(lng lat, ...)`로 만들어 삽입. path 조회는 `ST_AsText(path)` / `ST_AsGeoJSON(path)`로 반환 |
| `(native) String selectPathAsText(Long walkId)` | **native `@Query`** | `SELECT ST_AsText(path)` — DTO 역변환용 경로 텍스트 획득(엔티티에 LINESTRING 직접 매핑 안 할 경우) |
| `List<Object[]> aggregateWeekly(Long userId, Long dogId, LocalDate weekStart, LocalDate weekEnd)` | `@Query` | 주간 범위 내 소유 walk를 `DAYOFWEEK(started_at)`(또는 요일 파생)별 `SUM(distance_m)`·`COUNT(*)`로 집계. 월요일 시작 정렬은 앱단/쿼리단 택1 |

> 공간 컬럼을 Hibernate Spatial 없이 순수 JPA로 다룰 때: `path`를 엔티티에서 `insertable=false, updatable=false`(또는 `@Transient`)로 두고, 삽입은 native `INSERT`, 조회는 별도 native `ST_AsText`로 분리하는 패턴이 가장 함정이 적다. Hibernate Spatial + JTS `LineString` 매핑을 쓰면 엔티티 직접 매핑도 가능하나 의존성/SRID 설정 확인 필요.

---

## 6. 구현 노트 (함정 위주)

- **좌표 순서 (가장 흔한 버그).** openapi `path` = `[[lng, lat], ...]`(경도, 위도). MySQL `POINT(x, y) = POINT(lng, lat)`, WKT `LINESTRING(lng lat, lng lat, ...)`도 `경도 위도` 순. 배열 그대로 `x=배열[0], y=배열[1]`로 WKT 조립하면 일치. **lat/lng를 뒤집지 말 것.** 앱이 `[lat, lng]`로 보내는지 반드시 계약대로 `[lng, lat]`인지 재확인.
- **SRID 필수.** `walk.path`는 `SRID 4326` 고정. 삽입 시 `ST_GeomFromText(:wkt, 4326)`로 SRID를 반드시 명시. SRID 누락/불일치 시 `SPATIAL INDEX`·거리 연산이 오동작하거나 삽입 오류.
- **path 는 NULL 을 허용한다(ADR-0015).** **LINESTRING 은 점 1개로 만들 수 없다** — 점이 0~1개면 `path = NULL` 로 저장한다. 시작점을 두 번 넣어 가짜 선을 만들지 않는다(길이 0 짜리 경로가 지도에 찍힌다). 400 으로 거부하지도 않는다 — 실내 산책과 위치 권한 거부는 **정상적인 사용**이고, 그때 거절하면 사용자가 기록을 통째로 잃는다.
- **JPA와 공간타입 — 분리 패턴이 필요 없다(ADR-0015에서 실측).** `org.hibernate.orm:hibernate-spatial` 을 넣으면 엔티티가 JTS `LineString` 을 직접 든다. 스파이크에서 확인한 것: Hibernate 6.6.22 가 `linestring /*!80003 SRID 4326 */` 을 발행하고, 3점을 넣고 영속성 컨텍스트를 비운 뒤 다시 읽어 좌표와 `getSRID() == 4326` 이 그대로 돌아왔다.

  **`@Column(columnDefinition = "linestring srid 4326")` 을 반드시 명시할 것.** 빼면 Hibernate 가 `geometry` 로 만든다 — 점이든 다각형이든 받고 SRID 도 없다.

  **JTS 는 `(x, y) = (경도, 위도)` 다.** `new Coordinate(lng, lat)` 이다. 뒤집으면 조용히 틀린다.
- **JWT userId 추출.** `@CurrentUser User me` 파라미터 하나로 받는다(#5). 인증 주체 해석은 `CurrentUserArgumentResolver` 한 곳뿐이고, 실패는 전부 **본문 없는 401** 이다 — 컨트롤러가 `Authorization` 헤더를 다시 읽거나 `findByEmail` 로 주체를 찾는 것은 금지이며 `AuthSubjectContractSpecTest` 가 소스 스캔으로 막는다. Walks 전 엔드포인트 공통. 미인증 → **본문 없는 401**(`Error` 스키마가 아니다 — `openapi.yaml` 의 `components/responses/Unauthorized` 참조).
- **소유권 검증.** `walk`에는 `user_id`가 없고 `dog_id`만 있다. 반드시 `walk → dog → dog.user_id == userId`로 확인. 타인 산책 조회/목록 노출 금지. `save` 도 `dogId` 가 요청자 소유인지 먼저 검증한다 — **아니면 `404` 다**(남의 것과 없는 것이 같다. 위 §2 메모·ADR-0017 규약 3).
- **커서 페이지네이션.** 커서는 불투명 토큰(예: base64로 감싼 `{"id":123}`) — openapi `nextCursor` 예시(`eyJpZCI6MTIzfQ==`)가 그 형태. `id DESC` 단일 키 또는 `started_at DESC, id DESC` 복합 키 중 택1(복합이면 커서에 두 값 인코딩). `limit+1`건 조회해 초과분 존재로 `hasMore` 판정 후 마지막 항목 커서를 `nextCursor`로.
- **주간 통계 요일 정렬.** `weekKm`은 **월요일 시작 길이 7 배열**. MySQL `DAYOFWEEK()`는 일요일=1 기준이므로 월~일 인덱스 매핑 시 오프셋 주의(`WEEKDAY()`는 월요일=0 → 이 배열과 직접 맞음). "이번 주" 경계는 앱 로컬 타임존 기준으로 월요일 00:00 ~ 일요일 24:00 계산. 거리 m→km 변환(÷1000) 및 소수 자릿수 반올림 정책 통일.
- **totalKm/avgKm 파생.** `totalKm = SUM(distance_m)/1000`, `avgKm = totalKm / walkCount`(0건이면 0, 0 나눗셈 방지). `weekKm` 합과 `totalKm`가 반올림으로 미세 불일치할 수 있으니 산출 순서/반올림 시점 통일.
- **topPlaces (MVP 미지원 데이터).** 현재 `walk` 스키마에 방문 장소(place) 연결 컬럼이 없다. 정직하게 **빈 배열 반환**하거나 후속 확장(향후 `walk.place_id` 또는 경로 종점↔`place` 공간 근접 매칭)으로 미룰 것. 없는 데이터를 억지로 만들지 말 것.
- **트랜잭션.** `createWalk`만 쓰기 트랜잭션(`@Transactional`). native INSERT + 후속 SELECT(생성 id/`ST_AsText`)를 한 트랜잭션 안에서 처리해 반환 DTO 일관성 확보. 조회/통계는 읽기 전용(`@Transactional(readOnly = true)`) 권장.
- **에러 패턴.** 계약의 `Error` 스키마(`{ error: { code, message, traceId } }`) 준수. `NOT_FOUND`(없는 walk), `FORBIDDEN`(타인 소유), `VALIDATION`(좌표<2, 필수 누락)으로 매핑한다. **`code` 를 직접 적지 마라** — `GlobalExceptionHandler.codeOf` 가 HTTP 상태에서 파생하고, 그 어휘는 계약의 `Error.code` enum 이 소유한다(#10). 예전 이 줄에 있던 `VALIDATION_ERROR` 는 그 enum 에 없는 값이다. **미인증은 `UNAUTHORIZED` 코드가 아니라 본문 없는 401** 이다(#5) — 401 에 본문을 실으면 `GeneratedOpenApiSpecTest` 가 빨간불을 낸다.
- **좌표계 변환(참고).** `walk.path`는 앱에서 이미 WGS84(4326)로 들어오므로 EPSG:5174→WGS84 변환 불필요(그 변환은 `place`의 LOCALDATA 병원/펫샵 삽입 시에만 해당). Walks에서는 SRID를 4326으로 고정만 하면 된다.

---
