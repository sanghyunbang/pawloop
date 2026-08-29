# Places (장소/지도) — 백엔드 구현 청사진

> 이 문서는 **구현 청사진**이다. 메서드 바디(실제 로직)는 포함하지 않는다. 개발자가 직접 구현한다.
> 담당 리소스: `GET /api/places/nearby`, `GET /api/places/{contentId}`.
> 계약: [openapi.yaml](../../04-api/openapi.yaml) Places 태그 / 데이터 모델: [erd.md](../../03-database/erd.md), [schema.md](../../03-database/schema.md).
> 컨벤션 준거: `social/*`(record DTO·`ResponseEntity<?>`), `user/controller/AuthController`(JWT), `tour/service/TourApiClient`(공공데이터 프록시), `config/WebClientConfig`(WebClient 빈).

---

## 1. 개요

### 리소스 책임
- **주변 장소 조회**: 현위치(lat/lng) 기준 반경 내 반려동반 장소를 거리순 반환. `source`(kto/vet/shop/trail) + `category` 필터.
- **장소 상세**: `contentId`로 단건 조회. KTO 장소는 반려동반 상세(`detailPetTour2`)를 병합해 반환.
- **공공데이터 프록시 + 캐싱**: 프론트가 KTO를 직접 호출하는 현 구조를 백엔드 캐시(`place` 테이블)로 전환. 외부 API를 매 요청마다 때리지 않고 `place`에 upsert 후 공간쿼리로 서빙.

### 관련 테이블
| 테이블 | 용도 | 공간 컬럼 |
| --- | --- | --- |
| `place` | KTO 동반장소 + LOCALDATA 병원/펫샵 POI 캐시 | `geom POINT` (SRID 4326, SPATIAL INDEX) |
| `trail` | 두루누비 산책로 코스 | `path LINESTRING` (SRID 4326, SPATIAL INDEX) |

> ⚠️ 주의: `place` 테이블은 이 리소스에서 **새로 정의**하는 스키마([schema.md §4](../../03-database/schema.md))이며, 기존 `tour.domain.Place`(테이블 `places`, PK=`contentid`, `mapx`/`mapy` Double)와는 **별개 테이블**이다. 기존 `places`는 관광공사 감정추천용, 여기 `place`는 반려동반 지도용. 패키지 충돌 방지를 위해 엔티티 클래스명을 `PetPlace`로 두는 것을 권장(테이블명은 `place`).

### 기존 재사용 가능한 것
| 항목 | 위치 | 재사용 방법 |
| --- | --- | --- |
| KTO WebClient 빈 | `config/WebClientConfig.tourApiWebClient` | baseUrl이 `KorService2`. KorPetTourService2는 base가 다르므로(§6 참고) **새 빈 추가** 필요. 코덱/버퍼 설정은 복붙. |
| 공공데이터 호출 패턴 | `tour/service/TourApiClient` | `@Qualifier` WebClient + `@Value` serviceKey + `.block()` 동기 호출 그대로 답습. |
| XML 파싱 | `tour/util/XmlParser` | DOM 파서 방식(`getElementsByTagName("item")`, `getStr/getDouble`) 복제해 KorPet 응답 파싱. |
| Sanitizer | `tour/util/Sanitizers` | tel/문자열 정리·truncate. |
| JWT 추출 | `social/controller/SocialController.requireUser()` | Places 읽기는 비인증이라 불필요. (북마크 등 인증 리소스는 별도 담당) |
| 에러 응답 | `social` 컨트롤러 `Map.of("error", ...)` 패턴 | openapi `Error` 스키마(`{error:{code,message}}`)로 통일 권장. |

---

## 2. Controller

**클래스**: `com.heattrip.heat_trip_backend.place.controller.PlaceController`
`@RestController` + `@RequestMapping("/api/places")`. 읽기 전용 → **전 엔드포인트 비인증**(openapi `security: []`). `PublicSecurityConfig`/`SecurityConfig`에 `/api/places/**` permitAll 등록 필요(§6).

| # | HTTP · 경로 | 메서드 시그니처 (파라미터 타입) | 반환 DTO | 인증 | openapi paths |
| --- | --- | --- | --- | --- | --- |
| 1 | `GET /api/places/nearby` | `nearby(@RequestParam("lat") double lat, @RequestParam("lng") double lng, @RequestParam(value="radius", defaultValue="8000") int radius, @RequestParam(value="category", required=false) String category, @RequestParam(value="limit", defaultValue="80") int limit)` → `ResponseEntity<?>` | `List<PlaceDto>` | 없음 | `/api/places/nearby` GET |
| 2 | `GET /api/places/{contentId}` | `detail(@PathVariable("contentId") String contentId)` → `ResponseEntity<?>` | `PlaceDetailDto` | 없음 | `/api/places/{contentId}` GET |

**응답 규약**
- 1번: 성공 시 `ResponseEntity.ok(List<PlaceDto>)`. 좌표 검증 실패(lat/lng 범위·radius>20000·limit>200) → 400 `Error`. KTO 일일 한도 초과 프록시 실패 시 → **429**(openapi `RateLimited`). 캐시 hit이면 429 상황이라도 캐시로 응답.
- 2번: 존재하지 않으면 404 `Error`(openapi `NotFound`).
- 에러 바디는 openapi `Error` 스키마 준수: `{ "error": { "code": "...", "message": "...", "traceId": "..." } }`. (기존 social의 `Map.of("error", msg)`보다 계약 우선.)

---

## 3. DTO (record)

패키지 `com.heattrip.heat_trip_backend.place.dto`. 응답은 `record`(social `CardDto` 스타일), 공통 `Error`는 참조만.

### 3.1 응답 `PlaceDto` — openapi `Place` 매핑
| 필드 : 타입 | openapi 필드 | 비고 |
| --- | --- | --- |
| `contentId : String` | `contentId` | `place.external_id`(KTO contentid) 또는 `place.id` 문자열. |
| `title : String` | `title` | `place.name` |
| `source : String` | `source` | `kto` \| `vet` \| `shop` \| `trail` (DB `source`는 `kto_pet`/`localdata_vet`/… → 프론트 키로 축약 매핑) |
| `category : String` | `category` | KTO contentTypeId('12'/'14'/'28'/'32'/'38'/'39') 또는 `vet`/`shop`/`trail` |
| `contentTypeId : String` | `contentTypeId` | KTO만. vet/shop/trail은 null. |
| `lat : double` | `lat` | `geom` Y (위도) |
| `lng : double` | `lng` | `geom` X (경도) |
| `addr : String` | `addr` | `place.addr` |
| `tel : String` | `tel` | nullable |
| `image : String` | `image` | KTO firstimage. nullable. |
| `distM : double` | `distM` | `ST_Distance_Sphere` 결과(m). |

### 3.2 응답 `PlaceDetailDto` — openapi `PlaceDetail` 매핑
`PlaceDetail = Place allOf + { overview, petInfo }`. record 합성 구조는 다음 중 택1(구현자 재량):
- (권장) `PlaceDetailDto(PlaceDto place, String overview, PetInfoDto petInfo)` — 중첩.
- 또는 `PlaceDto`의 전 필드 + `overview`/`petInfo`를 평탄화한 단일 record.

| 필드 : 타입 | openapi 필드 |
| --- | --- |
| (Place 전 필드 상속/포함) | `#/schemas/Place` |
| `overview : String` | `overview` (nullable, KTO detailCommon 개요) |
| `petInfo : PetInfoDto` | `petInfo` |

### 3.3 응답 `PetInfoDto` — openapi `PlaceDetail.petInfo`
| 필드 : 타입 | openapi 필드 | 설명 |
| --- | --- | --- |
| `acmpyPsblCpam : String` | `acmpyPsblCpam` | 동반 가능 반려동물 (KTO detailPetTour2 원본 필드) |
| `acmpyNeedMtr : String` | `acmpyNeedMtr` | 동반 시 필요사항 |
| `etcAcmpyInfo : String` | `etcAcmpyInfo` | 기타 유의사항 |

> 세 필드 모두 자유텍스트·nullable. KTO detailPetTour2 응답 필드명을 그대로 사용.

### 3.4 요청 DTO
- **없음**. 두 엔드포인트 모두 GET + query/path 파라미터. `@RequestParam`/`@PathVariable`로 직접 받는다. (별도 `XxxRequest` record 불필요)

### 3.5 공통 DTO (참조만)
- `Error` — openapi `#/components/schemas/Error`. 전역 `@RestControllerAdvice` 또는 공용 record로 별도 정의(이 리소스가 소유하지 않음).
- `Page` — openapi `#/components/schemas/Page`. Places는 커서 페이지네이션 **미사용**(nearby는 배열 직접 반환, limit로 상한). 참조만.

---

## 4. Service

**클래스**: `com.heattrip.heat_trip_backend.place.service.PlaceService` (`@Service`, `@Transactional(readOnly = true)` 기본, 캐시 upsert 메서드만 `@Transactional`)

| 메서드 시그니처 | 한 줄 책임 (무엇을) |
| --- | --- |
| `List<PlaceDto> findNearby(double lat, double lng, int radius, String category, int limit)` | 캐시(`place`/`trail`)에서 반경 내 장소를 거리순으로 조회해 DTO 목록 반환(카테고리 필터 적용). |
| `PlaceDetailDto findDetail(String contentId)` | 단건 장소 + 반려동반 상세(petInfo)·개요를 병합해 반환. 없으면 미존재 신호. |
| `void refreshKtoCache(int areaCode)` | KorPetTourService2에서 반려동반 장소 목록을 받아 `place`(source=kto)로 upsert(캐시 워밍). 스케줄러/부트스트랩에서 호출. |
| `PetInfoDto fetchPetInfo(String contentId)` | KTO detailPetTour2 프록시 호출 → 반려동반 상세 파싱(상세 조회 시 on-demand, 캐시 가능). |
| `void importLocalData(String source)` | LOCALDATA 병원/펫샵 원본을 좌표변환(EPSG:5174→4326) 후 `place`(source=vet/shop)로 적재. 배치. |
| `void importTrails()` | 두루누비 산책로를 `trail`(LINESTRING) 적재. 배치. |

**별도 클래스(§1 재사용 패턴 따라 신설)**
| 클래스 | 책임 |
| --- | --- |
| `place.service.KorPetTourClient` | KorPetTourService2 프록시(`TourApiClient` 패턴). detailPetTour2 / 반려동반 목록 엔드포인트 동기 호출 후 원문(XML/JSON) 반환. |
| `place.util.KorPetXmlParser` | KorPet 응답 파싱(`XmlParser` 복제). |
| `place.util.CoordTransform` | EPSG:5174(중부원점 TM) → WGS84(4326) 좌표 변환 유틸(LOCALDATA 병원/펫샵용). |

> "어떻게(변환식·프록시 URL 조립·쿼리 실행)"는 구현자 몫. 서비스는 상기 시그니처와 책임만 확정.

---

## 5. Entity & Repository

### 5.1 Entity `PetPlace` (테이블 `place`)
패키지 `com.heattrip.heat_trip_backend.place.entity`. `@Entity @Table(name="place")`. Lombok `@Getter/@Setter/@NoArgsConstructor/@AllArgsConstructor/@Builder`(social 스타일).

| 필드 : 타입 | 컬럼 | 매핑/제약 |
| --- | --- | --- |
| `id : Long` | `id` | `@Id @GeneratedValue(IDENTITY)` |
| `source : String` | `source` | NOT NULL. `kto_pet`/`localdata_vet`/`localdata_shop` |
| `externalId : String` | `external_id` | KTO contentid 등. `uq_place_src(source, external_id)` |
| `category : String` | `category` | contentTypeId 또는 vet/shop/trail. INDEX |
| `name : String` | `name` | NOT NULL, len 150 |
| `geom : org.locationtech.jts.geom.Point` | `geom` | **// 공간 컬럼 POINT SRID 4326, NOT NULL, SPATIAL INDEX.** JTS `Point`(hibernate-spatial) 또는 `@Column(columnDefinition="POINT SRID 4326")`. 좌표 순서 `POINT(lng, lat)`. |
| `addr : String` | `addr` | nullable |
| `tel : String` | `tel` | nullable |
| `rawJson : String`(또는 Map + JSON 컨버터) | `raw_json` | `@Column(columnDefinition="json")`. 공공데이터 원본. `tour.domain.EmotionWeightMapJsonConverter` 방식 참고. |
| `updatedAt : LocalDateTime` | `updated_at` | `@PreUpdate`/`@PrePersist`로 now 또는 DB default. |

> geom을 JTS 타입으로 매핑하려면 `hibernate-spatial` 의존성 필요. 부담되면 geom은 native 쿼리 전용으로 두고 엔티티엔 매핑하지 않는 선택도 가능(그 경우 nearby는 전부 native projection).

### 5.2 Entity `Trail` (테이블 `trail`)
| 필드 : 타입 | 컬럼 | 매핑/제약 |
| --- | --- | --- |
| `id : Long` | `id` | `@Id @GeneratedValue(IDENTITY)` |
| `source : String` | `source` | 기본 `durunubi` |
| `name : String` | `name` | NOT NULL |
| `path : org.locationtech.jts.geom.LineString` | `path` | **// 공간 컬럼 LINESTRING SRID 4326, NOT NULL, SPATIAL INDEX.** |
| `lengthM : Integer` | `length_m` | nullable |

### 5.3 Repository

**`PetPlaceRepository extends JpaRepository<PetPlace, Long>`** (native `@Query` 시그니처만; 바디 없음)

| 메서드 시그니처 | 쿼리 개요 |
| --- | --- |
| `List<Object[]> findNearby(@Param("lng") double lng, @Param("lat") double lat, @Param("radius") int radius, @Param("category") String category, @Param("limit") int limit)` | native. `MBRContains(ST_Buffer(point,...))` 또는 bbox(`ST_MakeEnvelope`)로 SPATIAL INDEX 프루닝 → `ST_Distance_Sphere(geom, ST_SRID(POINT(:lng,:lat),4326))` 계산·필터(≤ :radius) → `ORDER BY dist_m ASC LIMIT :limit`. `category` null이면 조건 생략(또는 `(:category IS NULL OR category=:category)`). 컬럼: id, external_id, source, category, name, X(geom), Y(geom), addr, tel, dist_m. |
| `Optional<PetPlace> findBySourceAndExternalId(String source, String externalId)` | 파생 쿼리. contentId 상세·캐시 upsert 시 중복 확인. |
| `List<Object[]> findNearbyProjected(...)` | (선택) DTO projection 인터페이스로 대체 가능(`ST_X/ST_Y/ST_Distance_Sphere` alias 매핑). |

> `Object[]` 대신 Spring Data **projection 인터페이스**(`getContentId()`/`getDistM()` 등)를 native 쿼리에 붙이면 매핑이 깔끔하다(권장).

**`TrailRepository extends JpaRepository<Trail, Long>`**

| 메서드 시그니처 | 쿼리 개요 |
| --- | --- |
| `List<Object[]> findNearbyTrails(@Param("lng") double lng, @Param("lat") double lat, @Param("radius") int radius, @Param("limit") int limit)` | native. `ST_Distance_Sphere(path, POINT(:lng,:lat))` 또는 `MBRContains` bbox로 근접 코스 조회. category='trail'일 때만 nearby에 포함. |

**인덱스 요약** (schema.md 기준)
- `place`: `uq_place_src(source, external_id)` UNIQUE, `idx_place_category(category)`, `spx_place_geom(geom)` **SPATIAL**.
- `trail`: `spx_trail_path(path)` **SPATIAL**.

---

## 6. 구현 노트 (함정 위주)

1. **KorPetTourService2 = KTO의 별도 서비스 (base URL 다름).**
   - `WebClientConfig.tourApiWebClient`는 `.../B551011/KorService2`. 반려동반은 `.../B551011/KorPetTourService2`.
   - `WebClientConfig`에 **새 빈**(`@Bean("korPetWebClient")`) 추가 후 `KorPetTourClient`에서 `@Qualifier("korPetWebClient")`로 주입. 코덱 `maxInMemorySize` 설정 복제.
   - serviceKey는 `@Value("${TOUR.API.SECRET}")` 재사용(동일 키). `MobileOS=WEB`, `MobileApp=HeatTrip`, `_type=json` 파라미터 컨벤션 유지.

2. **외부 API 프록시/캐싱 정책.**
   - nearby는 **캐시(`place`) 우선 서빙**. 외부 호출은 스케줄러/부트스트랩(`refreshKtoCache`)에서 미리 채우거나, 캐시 miss·stale(`updated_at`) 시에만 on-demand.
   - detailPetTour2는 응답 데이터가 크지 않고 자주 안 바뀌므로 `raw_json`/별도 캐시에 저장 후 재사용.
   - **KTO 일일 1000콜 한도**: 프록시 실패(한도 초과)를 감지하면 429(`RateLimited`)로 매핑하되, 캐시가 있으면 캐시로 폴백.

3. **좌표계 & 좌표 순서 (가장 흔한 버그).**
   - MySQL `POINT(x, y) = POINT(경도 lng, 위도 lat)`. KTO `mapx=경도(lng)`, `mapy=위도(lat)` → `POINT(mapx, mapy)`.
   - 공간 컬럼은 **SRID 4326 고정**. 삽입 시 `ST_GeomFromText('POINT(127.0 37.5)', 4326)` 또는 `ST_SRID(POINT(:lng,:lat), 4326)`. SRID 안 맞으면 `ST_Distance_Sphere`가 오작동/에러.
   - **LOCALDATA 병원/펫샵 좌표는 EPSG:5174(중부원점 TM)** → 반드시 **WGS84(4326)로 변환** 후 저장(`CoordTransform`). 변환 없이 넣으면 좌표가 지구 반대편에 찍힘. (proj4j 등 라이브러리 활용 권장.)

4. **주변 조회 성능 — SPATIAL INDEX를 태워라.**
   - `ST_Distance_Sphere`만 걸면 풀스캔. 먼저 **bounding box**(`MBRContains(ST_MakeEnvelope(...), geom)`)로 SPATIAL INDEX를 태워 후보를 좁힌 뒤 정확 거리(`ST_Distance_Sphere`)로 필터·정렬. schema.md §4 예제 쿼리 참고.
   - radius로 bbox를 대략(위경도 델타 ≈ radius/111320 등) 잡거나 `ST_Buffer` 사용. limit 상한 200.

5. **JWT 추출 — Places는 불필요.**
   - openapi에서 Places 두 엔드포인트는 `security: []`(비인증). `SocialController.requireUser()` 패턴은 여기 **미적용**.
   - 단, `SecurityConfig`가 `anyRequest().authenticated()`이면 `/api/places/**`를 **permitAll**로 열어야 401이 안 난다(`PublicSecurityConfig`/`PublicSecurityProperties` 화이트리스트에 추가).

6. **트랜잭션.**
   - 조회 메서드는 `@Transactional(readOnly = true)`. 캐시 upsert(`refreshKtoCache`/`importLocalData`/`importTrails`)만 쓰기 트랜잭션.
   - 대량 배치는 한 트랜잭션에 다 묶지 말고 청크 단위 커밋(메모리·락 회피).

7. **엔티티/테이블 네이밍 충돌.**
   - 기존 `tour.domain.Place`(테이블 `places`)와 **다른 테이블**(`place`)이다. 클래스명 `PetPlace`로 분리(§1). 리포지토리·서비스도 `place` 패키지에 격리해 `tour` 패키지와 섞지 말 것.

8. **에러 바디 계약.**
   - social의 `Map.of("error", msg)` 대신 openapi `Error` 스키마(`{error:{code,message,traceId}}`)를 따른다. 전역 `@RestControllerAdvice` 하나로 400/404/429 매핑 권장.

완료: C:/Users/mm206/git_projects/heattrip/docs/02-architecture/backend/places.md
