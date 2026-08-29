# 마이그레이션 & 스키마 관리 전략

> Pawloop(포루프) MySQL 스키마의 버전 관리·공공데이터 동기화 전략. 현재는 Hibernate `ddl-auto`(dev `update` / prod `validate`)로 스키마를 관리하며, 공공데이터(관광공사 KTO·LOCALDATA·두루누비)는 배치로 `place`/`trail`에 upsert한다. 좌표계 변환(EPSG:5174→WGS84)과 초기 시드 전략을 포함한다. 스키마 구조는 [ERD](./erd.md), 기술 스택은 [기술 스택](../02-architecture/tech-stack.md) 참조.

---

## 1. 현재 상태 (as-is)

실제 백엔드 설정 기준(`backend/src/main/resources/application-*.properties`):

| 항목 | 값 | 근거 |
| --- | --- | --- |
| 스키마 관리 | Hibernate `ddl-auto` | 마이그레이션 툴 미도입 |
| dev 프로필 | `spring.jpa.hibernate.ddl-auto=update` | `application-dev.properties` |
| prod 프로필 | `spring.jpa.hibernate.ddl-auto=validate` | `application-prod.properties` |
| DB | MySQL (`jdbc:mysql://.../heat_trip_db`) | `spring.datasource.url` |
| 런타임 | Java 21 / Spring Boot 3.5.4 | `backend/build.gradle` |
| 시드 로딩 | opencsv (`resources/data/place_traits.csv`) | `build.gradle` opencsv 5.9 |
| POI upsert | JPA `saveAll` 배치(merge) | `PlaceService.saveInBatches(...)` |

> 참고: 스키마·DB 이름은 `heat_trip_db`, 엔티티 테이블은 `places` 등 레거시 명(heattrip 시절)이 잔존한다. 반려 피벗 후 컬럼/의미는 재정의되지만 **이름 rename은 마이그레이션으로 신중히 처리**한다(아래 3장).

### 1.1 `ddl-auto`의 한계 (왜 Flyway가 필요한가)

| 문제 | 설명 |
| --- | --- |
| 비결정적 | `update`는 컬럼 **추가**만 하고 rename/삭제/타입변경/인덱스변경은 안전하게 못 한다. `POINT`/`SPATIAL INDEX`는 사실상 손댈 수 없다. |
| 버전 이력 없음 | "언제 어떤 스키마 변경이 들어갔는지" Git·DB 어디에도 기록이 없다. 롤백 불가. |
| 환경 불일치 | dev(`update`)와 prod(`validate`)가 다른 경로로 스키마를 만든다 → prod 배포 시 `validate` 실패로만 발견. |
| 공간 컬럼 | GPS `LINESTRING`·`POINT`·`SPATIAL INDEX`·`SRID`는 Hibernate 자동 DDL로 정확히 못 만든다. 수동 DDL 필수. |

---

## 2. 목표 전략: Flyway 도입

**결론: Flyway를 도입하고, `ddl-auto`는 dev에서 `validate`(또는 `none`)로 낮춘다.** MVP 1인 개발 규모에서 Liquibase보다 Flyway(순수 SQL, 학습곡선 낮음, MySQL 공간 DDL 그대로 작성 가능)가 적합하다.

### 2.1 프로필별 최종 정책

| 프로필 | `ddl-auto` | Flyway | 의미 |
| --- | --- | --- | --- |
| dev(로컬) | `validate` | `enabled=true` (자동 migrate on boot) | Flyway가 스키마를 만들고, Hibernate는 엔티티↔스키마 일치만 검증 |
| test | `create-drop` 또는 Flyway | (택1) H2 대신 Testcontainers-MySQL 권장 | 공간함수(`ST_*`)는 H2 미지원 → 통합테스트는 MySQL |
| prod | `validate` | `enabled=true`, `baseline-on-migrate` | 부팅 시 미적용 마이그레이션만 실행, 실패 시 부팅 중단 |

> 전환 절차: (1) 현재 dev DB의 스키마를 `V1__baseline.sql`로 덤프 → (2) `flyway_schema_history`에 baseline 등록(`baseline-version=1`) → (3) dev `ddl-auto`를 `update`→`validate`로 낮춤 → (4) 이후 모든 변경은 `V2__`, `V3__` … 마이그레이션으로만.

### 2.2 Gradle 의존성 (추가 예정)

```gradle
// build.gradle (dependencies)
implementation 'org.flywaydb:flyway-core'
implementation 'org.flywaydb:flyway-mysql'   // MySQL 8 전용 모듈 (Spring Boot 3.5 필수)
```

### 2.3 설정 (application-*.properties)

```properties
# dev/prod 공통 (application.properties)
spring.flyway.enabled=true
spring.flyway.locations=classpath:db/migration
spring.flyway.baseline-on-migrate=true
spring.flyway.baseline-version=1
spring.flyway.validate-on-migrate=true

# dev: ddl-auto를 낮춤 (기존 update → validate)
spring.jpa.hibernate.ddl-auto=${SPRING_JPA_HIBERNATE_DDL_AUTO:validate}
```

### 2.4 파일 배치 & 네이밍

```
backend/src/main/resources/db/migration/
├── V1__baseline_schema.sql          # 현재 스키마 덤프(app_user/dog/place/...)
├── V2__place_add_geom_point.sql     # mapx/mapy(Double) → geom POINT + SPATIAL INDEX
├── V3__add_walk_trail_spatial.sql   # walk.path / trail.path LINESTRING
├── V4__community_tables.sql         # post/comment/reaction/bookmark
├── R__seed_place_traits.sql         # (반복) 시드 데이터 upsert
└── ...
```

| 규칙 | 값 |
| --- | --- |
| 버전 마이그레이션 | `V{n}__{snake_case}.sql` (한 번만, 순서대로) |
| 반복 마이그레이션 | `R__{name}.sql` (체크섬 변경 시 재실행 — 시드/뷰용) |
| 원칙 | **적용된 마이그레이션은 절대 수정 금지**(체크섬 불일치 → 부팅 실패). 수정은 새 버전으로. |

---

## 3. 공간 컬럼 마이그레이션 (핵심)

현재 `Place` 엔티티는 좌표를 `Double mapx`(경도)·`Double mapy`(위도)로 저장한다(`tour/domain/Place.java`). ERD 목표는 `place.geom POINT` + `SPATIAL INDEX`다. 이 전환은 `ddl-auto`로 불가능하므로 **명시적 마이그레이션**으로 처리한다.

```sql
-- V2__place_add_geom_point.sql
-- 1) SRID 4326(WGS84) POINT 컬럼 추가
ALTER TABLE places
  ADD COLUMN geom POINT SRID 4326 NULL AFTER mapy;

-- 2) 기존 mapx(경도)/mapy(위도)로 POINT 백필
--    MySQL 8은 SRID 4326에서 (위도, 경도) 축순서 → ST_SRID(POINT(lat, lon), 4326)
UPDATE places
SET geom = ST_SRID(POINT(mapy, mapx), 4326)
WHERE mapx IS NOT NULL AND mapy IS NOT NULL;

-- 3) NOT NULL + SPATIAL INDEX (공간 인덱스는 NOT NULL 컬럼에만 가능)
ALTER TABLE places MODIFY geom POINT SRID 4326 NOT NULL;
ALTER TABLE places ADD SPATIAL INDEX spx_places_geom (geom);
```

> **MySQL 8 좌표 축순서 주의**: SRID 4326에서 MySQL은 `POINT(위도, 경도)` 순서로 해석한다(`axis-order`). KTO 응답은 `mapx=경도`, `mapy=위도`이므로 반드시 `POINT(mapy, mapx)`로 넣는다. 거리 계산은 `ST_Distance_Sphere(geom, ST_SRID(POINT(:lat,:lng),4326))`, 범위검색은 `MBRContains(...)`를 쓴다(ERD의 공간쿼리 요약과 일치).

`walk.path`·`trail.path`도 동일 패턴으로 `LINESTRING SRID 4326 NOT NULL` + `SPATIAL INDEX`로 생성한다.

---

## 4. 공공데이터 동기화 배치 (place / trail upsert)

3개 소스를 `place`/`trail`로 정기 동기화한다. 현재 KTO 임포트는 `PlaceImportService.fullImportAllAreas()`가 전 지역(17개 area) 페이지네이션으로 수집해 `PlaceService.saveInBatches(...)`로 저장한다.

### 4.1 소스별 정책

| 소스 | 대상 테이블 | 키(멱등성) | 좌표 | 규모/제한 | 현재 상태 |
| --- | --- | --- | --- | --- | --- |
| 관광공사 KorPetTourService2 (반려동반) | `place` (source=`kto_pet`) | `contentid` | `mapx`/`mapy`=WGS84 (변환 불필요) | 1000콜/일 | **실연동**(`TourApiClient`) |
| LOCALDATA 동물병원 | `place` (source=`localdata_vet`) | 인허가번호(관리번호) | **EPSG:5174 → WGS84 변환 필요** | 전국 ~9,445건 | 미연동(앱 더미) |
| LOCALDATA 펫샵/미용 | `place` (source=`localdata_shop`) | 인허가번호 | EPSG:5174 → WGS84 변환 | — | 미연동 |
| 두루누비 걷기여행길 | `trail` (source=`durunubi`) | 코스ID | GPX/좌표(WGS84) | — | 미연동(더미 폴리라인) |

### 4.2 Upsert 전략

현재는 JPA `saveAll`이 PK(`contentid`) 기준으로 merge하는 방식이다. **대량 upsert는 네이티브 `INSERT ... ON DUPLICATE KEY UPDATE`가 훨씬 빠르고 원자적**이므로 배치 경로에 도입한다(`PlaceService` 주석에도 명시된 개선안).

```sql
-- place upsert (source별 자연키 + upsert)
INSERT INTO places (contentid, source, category, title, geom, addr1, tel, raw_json, updated_at)
VALUES (:contentid, :source, :category, :title,
        ST_SRID(POINT(:lat, :lng), 4326), :addr, :tel, :raw, NOW())
ON DUPLICATE KEY UPDATE
  title = VALUES(title),
  geom  = VALUES(geom),
  addr1 = VALUES(addr1),
  tel   = VALUES(tel),
  raw_json = VALUES(raw_json),
  updated_at = NOW();
```

| 원칙 | 내용 |
| --- | --- |
| 멱등성 | 자연키(KTO=`contentid`, LOCALDATA=인허가번호) 유니크 제약 → 재실행해도 중복 없음 |
| 원본 보존 | 응답 원문을 `place.raw_json`(JSON)에 그대로 저장 → 스키마 확장/재파싱 대비 |
| 소프트 스테일 | 매 실행 `updated_at` 갱신. **폐업 감지**는 이번 배치에서 안 온 레코드를 즉시 삭제하지 말고 `is_active=false` 또는 `stale_since`로 표시(soft delete) |
| 배치 크기 | 200건 chunk + flush (현재 `saveInBatches` 기본값 유지). KTO 페이지 `numOfRows=1000` |
| 레이트리밋 | KTO 1000콜/일 → area×page 호출 수 상한, 호출 간 delay(카카오 백필의 `delay-ms=250` 패턴 재사용) |

### 4.3 스케줄

| 소스 | 주기 | 방식 |
| --- | --- | --- |
| KTO 반려동반 | 주 1회(변경 적음) | `@Scheduled` 또는 수동 트리거 엔드포인트 |
| LOCALDATA 병원/펫샵 | 월 1회(월간 스냅샷 배포) | 파일 다운로드 → ETL |
| 두루누비 산책로 | 분기 1회 | GPX 파싱 → LINESTRING |

> MVP 단계에서는 **관리자 수동 트리거(1회성 풀임포트)**로 충분하다. `@Scheduled` 자동화는 데이터 안정화 후 도입한다. KTO는 향후 앱 직접호출 → 백엔드 프록시+캐시로 이전(1000콜/일 보호).

---

## 5. 좌표 변환 파이프라인 (EPSG:5174 → WGS84)

LOCALDATA(행안부 인허가) 좌표는 **EPSG:5174(구 중부원점 TM, Bessel)**로 제공되어 지도(WGS84/EPSG:4326)에 바로 쓸 수 없다. KTO(`mapx`/`mapy`)와 두루누비는 이미 WGS84라 변환 불필요.

### 5.1 파이프라인 단계

```
LOCALDATA CSV/API (EPSG:5174 x,y)
   │  1) 파싱 (opencsv — build.gradle에 이미 존재)
   ▼
좌표 유효성 검사 (0/공백/범위 밖 제거)
   │  2) 좌표 변환 EPSG:5174 → EPSG:4326
   ▼  (프록시 라이브러리 예: geotools / proj4j)
(lon, lat) WGS84
   │  3) 한반도 바운딩박스 검증 (lat 33~39, lon 124~132)
   ▼
place upsert → ST_SRID(POINT(lat, lon), 4326)   ← 4.2 네이티브 upsert
```

| 단계 | 도구/방법 | 비고 |
| --- | --- | --- |
| 파싱 | opencsv 5.9 (이미 의존성 존재) | LOCALDATA 월간 CSV |
| 변환 | `proj4j` 또는 `geotools`(EPSG:5174→4326) | 신규 의존성. Bessel 타원체·datum shift 정확도 확인 필요 |
| 검증 | 한반도 BBox 필터 | 변환 실패/원점 튐(0,0) 방지 |
| 거리 산출 | `GeoUtils.haversineMeters(...)`(이미 존재) | 검증·근사거리용. DB 저장 후엔 `ST_Distance_Sphere` |

> **정확도 주의**: EPSG:5174는 datum shift(구 Bessel → WGS84) 파라미터에 따라 수 m~수십 m 오차가 날 수 있다. 변환 결과를 KTO 근처 알려진 POI와 대조해 오프셋을 1회 검증한 뒤 배치를 확정한다. 변환은 **적재 시 1회만** 수행하고 DB에는 WGS84만 저장한다(원본 5174 좌표는 `raw_json`에 보관).

### 5.2 배치 코드 위치(제안)

| 컴포넌트 | 위치(제안) | 역할 |
| --- | --- | --- |
| `LocalDataImportService` | `tour/service/`(KTO와 병렬) | CSV 파싱 + 변환 + upsert 오케스트레이션 |
| `CoordinateConverter` | `kakao/service/` 또는 `tour/util/` | 5174→4326 변환(proj4j 래퍼) |
| upsert 쿼리 | `PlaceRepository` 네이티브 | `ON DUPLICATE KEY UPDATE` |

---

## 6. 초기 시드 (seed)

| 시드 | 방법 | 현재 |
| --- | --- | --- |
| `place_traits.csv` | opencsv 로더 → `R__seed_place_traits.sql`(Flyway 반복) 또는 부트 러너 | **존재**(`resources/data/place_traits.csv`) |
| KTO 서울 동반장소 | 풀임포트 배치 1회(`fullImportAllAreas`) | **실연동**(앱 지도 서울 45곳) |
| 게시판(board) 코드 | `V1` 마이그레이션에 enum 값/기본 게시판 INSERT | 코드 상수 |
| 개발용 더미 유저/강아지 | dev 전용 시드(`R__dev_seed.sql`, prod 제외) | 앱 샘플데이터(`lib/v2/domain/pet.dart`) |

### 시드 원칙

- **환경 분리**: 공용 시드(게시판 코드 등)는 `V`/`R` 마이그레이션, dev 전용 더미는 prod 배포에서 제외(별도 location 또는 `spring.flyway.locations` 프로필 분기).
- **멱등 시드**: 반복 시드는 `INSERT ... ON DUPLICATE KEY UPDATE`/`MERGE`로 작성 → 재실행 안전.
- **대용량 POI는 시드가 아니라 배치**: KTO/LOCALDATA 수천~수만 건은 마이그레이션 파일에 넣지 말고 4장 동기화 배치로 채운다(마이그레이션은 스키마 전용으로 유지).

---

## 7. 요약 체크리스트

| 단계 | 액션 |
| --- | --- |
| 1 | Flyway 의존성 추가(`flyway-core` + `flyway-mysql`) |
| 2 | 현재 dev 스키마 → `V1__baseline_schema.sql` 덤프 + baseline 등록 |
| 3 | dev `ddl-auto`: `update` → `validate`, prod 유지(`validate`) |
| 4 | `V2`: `place.mapx/mapy(Double)` → `geom POINT SRID 4326` + `SPATIAL INDEX` 백필 |
| 5 | `place`/`trail` 네이티브 `ON DUPLICATE KEY UPDATE` upsert 경로 도입 |
| 6 | LOCALDATA 좌표 변환(EPSG:5174→4326) 파이프라인 + BBox 검증 |
| 7 | 시드: 공용은 마이그레이션, dev 더미는 프로필 분리 |

> 관련 문서: [ERD](./erd.md) · [기술 스택](../02-architecture/tech-stack.md)
