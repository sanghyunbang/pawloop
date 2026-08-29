# Bookmarks (저장 장소) — 백엔드 구현 청사진

> 대상 리소스: **Bookmarks**. openapi `/api/bookmarks`(GET/POST), `/api/bookmarks/{placeId}`(DELETE).
> 이 문서는 "무엇을 만들어야 하는지"만 정의한다. **메서드 바디는 개발자가 직접 구현한다**(구현 코드 없음).
> 계약: [openapi.yaml](../../04-api/openapi.yaml) · 데이터: [erd.md](../../03-database/erd.md), [schema.md](../../03-database/schema.md)

---

## 0. 사전 정합성 경고 (반드시 먼저 읽기)

이 리소스는 기존 코드와 **두 가지 이름/설계 충돌**이 있다. 구현 착수 전에 팀 합의가 필요하다.

| 충돌 | 기존(Heat Trip) | 이 계약(Pawloop) | 결정 필요 |
| --- | --- | --- | --- |
| 패키지 `com.heattrip.heat_trip_backend.bookmark` | 이미 존재. `Bookmark`(contentId:String), `BookmarkController`(`@RequestMapping("/bookmarks")`), `BookmarkService`, 컬렉션 기능 등 | `/api/bookmarks`, `placeId` 기반 | **신규 패키지명 분리** 권장(예: `pawloop.bookmark`) 또는 기존 리네임 합의. 클래스명 충돌 방지 필수. |
| 식별자 타입 | `bookmarks.content_id VARCHAR(64)`(KTO contentid 문자열 직접 저장) | `bookmark.place_id BIGINT`(내부 `place.id` FK) + openapi `placeId:string` | 아래 §6 "placeId 매핑" 참조. **DB는 BIGINT FK, API는 string** 이라는 이중성을 서비스에서 흡수. |

> 결론: 아래 청사진은 **schema.md의 `bookmark` 테이블(BIGINT place_id FK)** 과 **openapi 계약(placeId:string)** 을 기준으로 한다. 패키지/클래스명은 기존과 겹치지 않도록 짓는다(문서에서는 `Pawloop*` 접두 또는 별도 하위 패키지로 표기).

---

## 1. 개요

- **책임**: 로그인 사용자가 특정 장소(`place`)를 저장/조회/삭제한다. 사용자-장소 조합은 유니크(중복 저장 시 409). 목록은 `place` 조인으로 장소 카드(`Place` 스키마) 형태로 반환한다.
- **관련 테이블**:
  - `bookmark` (본 리소스 소유. `user_id` + `place_id` UNIQUE) — [schema.md §9](../../03-database/schema.md)
  - `place` (조인 대상, 읽기 전용. `geom POINT`, `SPATIAL INDEX`) — [schema.md §4](../../03-database/schema.md)
  - `app_user` (FK 대상) — [schema.md §1](../../03-database/schema.md)
- **재사용 가능한 기존 자산**:
  - JWT 인증 추출: `UserService.emailFromAuth(authHeader)` + `findByEmail(email)` (AuthController/BookmarkController 패턴), 또는 `JWTProvider.getUserIdFromToken(token)` (SocialController `requireUser` 패턴). **둘 중 프로젝트 표준 하나로 통일**.
  - 커서 페이지네이션 응답: `explore.dto.CursorPageResponse<T>`(items/nextCursor/hasNext) 및 `explore.dto.PageResponse` 참고. **단, openapi Bookmarks GET은 배열 반환(페이지네이션 없음)** — §2 주의.
  - 에러 패턴: `ResponseEntity.badRequest().body(Map.of("error", ...))` + `ResponseStatusException(HttpStatus.*)` (SocialController), 또는 openapi `Error{error:{code,message,traceId}}` 스키마.
  - `place` 좌표→lat/lng 추출: `explore.mapper.PlaceMapper`, `kakao.service.GeoUtils` 참고.

---

## 2. Controller — `BookmarkApiController` (신규, 기존 `BookmarkController`와 클래스명 분리)

`@RestController` + `@RequestMapping("/api/bookmarks")`. 전 엔드포인트 **인증 필요**(SecurityConfig `anyRequest().authenticated()`). userId는 `Authorization` 헤더 → JWT에서 추출.

| # | HTTP · 경로 | 메서드 시그니처 (파라미터 타입) | 반환 DTO | 인증 | openapi |
| --- | --- | --- | --- | --- | --- |
| 1 | `GET /api/bookmarks` | `list(@RequestHeader("Authorization") String authHeader)` | `ResponseEntity<List<BookmarkPlaceDto>>` (200) | ✅ | `/api/bookmarks` GET → `array<Place>` |
| 2 | `POST /api/bookmarks` | `add(@RequestHeader("Authorization") String authHeader, @RequestBody BookmarkCreateRequest req)` | `ResponseEntity<Void>` (201 / 409 / 400) | ✅ | `/api/bookmarks` POST |
| 3 | `DELETE /api/bookmarks/{placeId}` | `remove(@RequestHeader("Authorization") String authHeader, @PathVariable("placeId") String placeId)` | `ResponseEntity<Void>` (204) | ✅ | `/api/bookmarks/{placeId}` DELETE |

**주의**
- openapi에서 GET `/api/bookmarks` 응답은 **`Place` 배열**(커서 페이지네이션 아님). 따라서 반환은 `List<BookmarkPlaceDto>`이며 `CursorPageResponse`로 감싸지 않는다. (프로젝트 공통 규칙상 커서 페이지네이션은 목록형에 권장되나, **이 엔드포인트는 계약이 배열이므로 계약 우선**. 향후 목록이 커지면 계약을 `Page`로 개정 후 커서 방식으로 전환.)
- POST 성공은 **201**(바디 없음, openapi `'201': { description: 추가됨 }`). 중복이면 **409**(`Conflict`). `placeId` 누락/무효면 **400**.
- DELETE는 **204**(멱등). 존재하지 않아도 204로 처리할지, 404로 할지 정책 결정 — openapi엔 404 정의 없음 → **멱등 204 권장**.
- `{placeId}`는 경로 문자열. 내부 매핑은 §6 참조.

---

## 3. DTO (record) — openapi schema 매핑

### 요청

**`BookmarkCreateRequest`** (POST body) — openapi inline `{ required:[placeId], placeId:string }`

| 필드 | 타입 | 비고 |
| --- | --- | --- |
| `placeId` | `String` | 필수. openapi `placeId:string`. 서비스에서 §6 규칙으로 내부 `place.id`로 해석. |

### 응답

**`BookmarkPlaceDto`** (GET 목록 요소) — openapi `#/components/schemas/Place` 와 1:1 매핑. `bookmark` 조인 `place` 행을 `Place` 카드로 투영.

| 필드 | 타입 | openapi Place 필드 | 소스 |
| --- | --- | --- | --- |
| `contentId` | `String` | `contentId` | `place.external_id` (없으면 `place.id` 문자열) — §6 |
| `title` | `String` | `title` | `place.name` |
| `source` | `String` | `source`(kto/vet/shop/trail) | `place.source` → 계약 enum 매핑(`kto_pet`→`kto`, `localdata_vet`→`vet`, `localdata_shop`→`shop`) |
| `category` | `String` | `category`(PlaceCategory) | `place.category` |
| `contentTypeId` | `String` | `contentTypeId` | `place.category`가 KTO 타입일 때 동일값(12/14/28/32/38/39), 레이어면 null |
| `lat` | `double` | `lat` | `ST_Y(place.geom)` (POINT Y = 위도) |
| `lng` | `double` | `lng` | `ST_X(place.geom)` (POINT X = 경도) |
| `addr` | `String` | `addr` | `place.addr` |
| `tel` | `String`(nullable) | `tel` | `place.tel` |
| `image` | `String`(nullable) | `image` | `place.raw_json`에서 추출 또는 null(MVP는 null 허용) |
| `distM` | `Double`(nullable) | `distM` | 북마크 목록엔 기준점이 없으므로 **null/미포함**(distM은 nearby 전용) |

> 공통 DTO는 **참조만**: 에러는 `#/components/schemas/Error`, 페이지는 `#/components/schemas/Page`(이 리소스는 미사용). `Place`/`PlaceCategory` 스키마는 Places 리소스와 공유하므로 **동일 record를 재사용**하는 것이 이상적(중복 정의 금지). Places 청사진의 `PlaceDto`가 이미 있으면 그것을 재사용하고 `BookmarkPlaceDto`는 만들지 않는다.

---

## 4. Service — `BookmarkService` (신규, 기존과 분리) — 메서드 시그니처 + 한 줄 책임

`@Service`, 클래스 `@Transactional(readOnly = true)`, 쓰기 메서드에 `@Transactional`.

| 메서드 시그니처 | 책임 (한 줄, "무엇을"만) |
| --- | --- |
| `List<BookmarkPlaceDto> listByUser(Long userId)` | 사용자의 북마크를 `place` 조인해 최신순(`bookmark.created_at DESC`) `Place` 카드 목록으로 반환. |
| `void add(Long userId, String placeIdParam)` | `placeIdParam`을 내부 `place.id`로 해석하고, 미존재 place면 예외, 이미 북마크면 409용 예외, 아니면 저장. |
| `void remove(Long userId, String placeIdParam)` | `placeIdParam`을 내부 `place.id`로 해석해 `(userId, placeId)` 북마크 삭제(멱등). |
| `Long resolvePlaceId(String placeIdParam)` (private helper) | API의 문자열 `placeId`(external_id 또는 내부 id)를 내부 `place.id`(BIGINT)로 해석(§6). 미존재면 null/예외. |

**예외 → HTTP 매핑 규약**
- place 미존재 → `IllegalArgumentException`(Controller가 400/404로 변환) 또는 `ResponseStatusException(NOT_FOUND)`.
- 중복 북마크 → 전용 예외 또는 `ResponseStatusException(CONFLICT)` → **409**. (DB `uq_bookmark` 유니크 위반을 잡거나, 사전 `existsByUserIdAndPlaceId`로 선검사.)

---

## 5. Entity & Repository

### Entity — `Bookmark` (테이블 `bookmark`)

> ⚠️ 기존 `bookmark.entity.Bookmark`(테이블 `bookmarks`, content_id)와 **다른 테이블/다른 클래스**. 패키지 분리 필수.

| 엔티티 필드 | 타입 | 컬럼 | 매핑/제약 |
| --- | --- | --- | --- |
| `id` | `Long` | `id` | `@Id @GeneratedValue(IDENTITY)` |
| `userId` | `Long` | `user_id` | `@Column(nullable=false)`. FK→`app_user.id`. (연관 대신 스칼라 FK 권장 — Social `EmotionCard.userId` 패턴) |
| `placeId` | `Long` | `place_id` | `@Column(nullable=false)`. FK→`place.id`. |
| `createdAt` | `LocalDateTime` | `created_at` | `@Column(nullable=false, updatable=false)`, `@PrePersist`에서 `now()` (EmotionCard 패턴) |

- 테이블 제약: `UNIQUE KEY uq_bookmark (user_id, place_id)`, `KEY idx_bookmark_place (place_id)` — schema.md §9. **엔티티에 `@Table(uniqueConstraints=@UniqueConstraint(columnNames={"user_id","place_id"}))`** 명시(기존 Bookmark 스타일과 동일).
- **공간 컬럼 없음**(bookmark 자체엔 geom 없음). 좌표는 조인한 `place.geom(POINT, SRID 4326, SPATIAL INDEX)`에서 읽는다.
- FK `ON DELETE CASCADE`(user/place 삭제 시 북마크 정리) — DDL에 이미 정의됨. JPA에선 DB 제약에 위임(앱단 cascade 불필요).

### Repository — `BookmarkRepository extends JpaRepository<Bookmark, Long>`

| 메서드 | 종류 | 개요 |
| --- | --- | --- |
| `boolean existsByUserIdAndPlaceId(Long userId, Long placeId)` | 파생 쿼리 | 중복(409) 사전 검사. |
| `Optional<Bookmark> findByUserIdAndPlaceId(Long userId, Long placeId)` | 파생 쿼리 | 삭제 대상 단건. |
| `void deleteByUserIdAndPlaceId(Long userId, Long placeId)` | 파생 쿼리 | 멱등 삭제(`@Modifying @Transactional` 필요). |
| `List<BookmarkPlaceRow> findBookmarkedPlaces(@Param("userId") Long userId)` | **native `@Query`** | 목록 조인. 아래 개요. |

**native 조인 쿼리 개요** (바디는 개발자 작성):
```
SELECT
  p.id            AS placeInternalId,
  p.external_id   AS externalId,
  p.name          AS title,
  p.source        AS source,
  p.category      AS category,
  ST_Y(p.geom)    AS lat,      -- POINT Y = 위도
  ST_X(p.geom)    AS lng,      -- POINT X = 경도
  p.addr          AS addr,
  p.tel           AS tel
FROM bookmark b
JOIN place p ON p.id = b.place_id
WHERE b.user_id = :userId
ORDER BY b.created_at DESC
```
- 반환은 **인터페이스 프로젝션**(`BookmarkPlaceRow`) 권장 — `PlaceQueryRepository.findNextByCursor` + `PlaceSummaryProjection` 패턴(별칭↔getter 이름 일치). 서비스에서 `BookmarkPlaceDto`로 변환(source enum 매핑, image/distM 처리).
- `place.geom`은 SPATIAL 컬럼이므로 **`ST_X`/`ST_Y`로 좌표 추출**(엔티티에 POINT 필드를 두면 JPA 매핑이 번거로움 → native SELECT에서 스칼라로 뽑는 편이 안전).
- 인덱스 활용: `WHERE b.user_id`는 `uq_bookmark(user_id, place_id)` 선두 컬럼으로 커버. SPATIAL 인덱스는 이 목록 쿼리엔 불필요(전 지점 조인, 반경 검색 아님).

---

## 6. 구현 노트 (함정 위주)

1. **`placeId` 문자열↔BIGINT 이중성 (가장 큰 함정)**
   openapi `placeId:string`(POST body & DELETE path)이지만 DB `bookmark.place_id`는 **BIGINT FK → `place.id`**. Places 리소스가 `Place.contentId`로 무엇을 노출하는지에 따라 두 해석이 있다:
   - (A) API `placeId` = 내부 `place.id`의 문자열 표현 → `Long.parseLong` 후 그대로 사용. (구현 단순)
   - (B) API `placeId` = `place.external_id`(KTO contentid 등) → `place`에서 `external_id`로 조회해 내부 `id` 해석.
   **Places 청사진의 `Place.contentId` 정의와 반드시 일치**시킬 것. openapi 예시 `contentId: "2733967"`(KTO contentid)는 **(B) external_id** 를 시사한다. 결정 후 `resolvePlaceId`를 그 규칙으로 고정하고, GET 응답 `contentId`도 동일 규칙으로 역매핑(왕복 일관성).

2. **좌표계·좌표 순서**
   - DB `POINT(x, y) = POINT(lng, lat)`. 응답 매핑 시 **`lat = ST_Y`, `lng = ST_X`** (뒤바꾸면 지도가 엉킴).
   - `place`는 조회만 하므로 이 리소스에서 좌표 삽입은 없다. 단, `place` 적재 파이프라인(Places 리소스)에서 LOCALDATA 좌표는 **EPSG:5174→WGS84(4326)** 변환 후 저장됨을 전제(schema.md §4). Bookmarks는 변환에 관여하지 않는다.
   - `ST_Distance_Sphere`는 이 리소스에서 **불필요**(북마크 목록엔 거리 기준점 없음, distM=null). 거리 계산은 Places `/nearby`의 몫.

3. **중복(409) 처리 경합**
   `existsByUserIdAndPlaceId` 선검사 후 저장하는 사이 동시요청이 오면 유니크 위반(`DataIntegrityViolationException`) 가능. **선검사 + DB 유니크 위반 캐치 이중 방어** 권장. 유니크 위반을 잡아 **409**로 변환(500 노출 금지).

4. **JWT userId 추출 표준 통일**
   두 패턴이 공존한다: (a) `UserService.emailFromAuth(authHeader)`→`findByEmail`→`getId()` (BookmarkController/AuthController), (b) `JWTProvider.getUserIdFromToken(token)`(SocialController `requireUser`, 토큰 subject=email). **한 가지로 통일**하고 Bookmarks도 그 규칙을 따를 것. 토큰 subject는 email이므로 최종적으로 `User.getId()`(BIGINT)를 얻어 `bookmark.user_id`에 저장.

5. **트랜잭션 경계**
   - `add`/`remove`는 `@Transactional`(쓰기). `deleteBy...` 파생 삭제는 `@Modifying` + 트랜잭션 필수(아니면 삭제 미수행).
   - `listByUser`는 `readOnly=true`. native 프로젝션 조회는 트랜잭션 필수 아님.

6. **외부 API·캐싱 무관**
   Bookmarks는 **외부 공공데이터(KTO/LOCALDATA)를 직접 호출하지 않는다**(TourApiClient/WebClientConfig 불필요). 오직 이미 적재된 `place` 캐시를 조인할 뿐. RateLimited(429)는 이 리소스와 무관. `image` 필드는 `place.raw_json` 파싱이 필요하면 Places 쪽 매퍼(`explore.mapper.PlaceMapper`) 재사용, MVP는 null 허용.

7. **패키지/클래스명 충돌 회피 (재강조)**
   기존 `bookmark` 패키지에 `Bookmark`/`BookmarkController`/`BookmarkService`/`BookmarkRepository`가 **이미 있다**. 컴파일 충돌·라우팅 충돌(`/bookmarks` vs `/api/bookmarks`)을 피하려면 **새 하위 패키지(예: `bookmark.place` 또는 `pawloop.bookmark`)** 로 분리하거나, 기존을 리네임하는 리팩터를 선행. 문서상 클래스명은 예시이며 최종 네이밍은 팀 합의로 확정.

---

완료: C:/Users/mm206/git_projects/heattrip/docs/02-architecture/backend/bookmarks.md
