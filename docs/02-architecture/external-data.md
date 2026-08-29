# 외부 공개데이터 연동

> Pawloop(포루프)이 지도·산책로 레이어를 채우기 위해 사용하는 외부 공개데이터(관광공사 반려동물 동반여행, 행안부 LOCALDATA 동물병원·펫샵, 두루누비 걷기여행길)의 엔드포인트·필드·좌표계·인증·한계와 `place`/`trail` 캐싱 전략을 정리한다.

관련 문서: [ERD](../03-database/erd.md) · [시스템 아키텍처](./system-overview.md) · [API 명세](../04-api/api-spec.md)

---

## 0. 한눈에 보기

| 소스 | 제공기관 | 채우는 레이어(카테고리 key) | 좌표계 | 현재 상태 |
|---|---|---|---|---|
| **KorPetTourService2** | 한국관광공사 | 여행지`12`·문화`14`·레포츠`28`·숙박`32`·쇼핑`38`·카페/식당`39` | WGS84 (경위도) | **실연동** (앱이 직접 호출, 서울 ~45곳) |
| **LOCALDATA 인허가** | 행정안전부 | 병원`vet`·펫샵`shop` | **EPSG:5174** → WGS84 변환 필요 | 더미 (미연동) |
| **두루누비 걷기여행길** | 한국관광공사 | 산책로`trail` | WGS84 (GPX/좌표) | 더미 폴리라인 (미연동) |

- 카테고리 key는 `lib/v2/domain/pet.dart`의 `kPetCategories` SSOT를 그대로 사용한다. 숫자 key(`12`/`14`/`28`/`32`/`38`/`39`)는 KTO `contenttypeid`, 문자 key(`vet`/`shop`/`trail`)는 별도 공공데이터 레이어(`kLayerKeys`)다.
- 현재 KTO는 **앱이 직접 호출**(`lib/v2/data/pet_places_repository.dart`). 나머지 두 소스는 아직 더미이며, 셋 다 **백엔드 프록시 + `place`/`trail` 캐싱**으로 옮기는 것을 목표로 한다(→ [6. 캐싱·동기화](#6-캐싱동기화-전략placetrail)).

---

## 1. KTO KorPetTourService2 (반려동물 동반여행)

한국관광공사 "반려동물 동반여행 서비스"(data.go.kr, 데이터 PK `15135102`). 반려동반 가능 관광지·카페·숙박 등을 좌표와 함께 제공한다. Pawloop 지도의 **동반가능 장소** 레이어를 채우는 유일한 실연동 소스다.

### 1.1 기본 정보

| 항목 | 값 |
|---|---|
| Base URL | `https://apis.data.go.kr/B551011/KorPetTourService2` |
| 인증 | 쿼리 파라미터 `serviceKey` (data.go.kr 발급) |
| 응답 포맷 | `_type=json` (기본 XML) |
| 호출 한도 | 개발계정 기준 **1,000 calls/day** (운영계정 신청 시 상향) |
| 앱 호출 위치 | `lib/v2/data/pet_places_repository.dart` → `PetPlacesRepository.fetchNearby()` |

### 1.2 오퍼레이션

| 오퍼레이션 | 용도 | Pawloop 사용 |
|---|---|---|
| `locationBasedList2` | 좌표 반경 내 장소(거리순) | **사용 중** (내 주변 동반장소) |
| `areaBasedList2` | 지역코드 기반 목록 | 향후 배치 수집(도시 단위 프리로드)에 적합 |
| `searchKeyword2` | 키워드 검색 | 미사용 |
| `detailPetTour2` | 반려동반 상세정보(동반조건 등) | 미사용 (장소 상세 확장 시 후보) |

> 참고: 백엔드에는 감정여행 레거시의 일반 관광 `TourApiClient`가 남아 `areaBasedList2`를 호출한다(`backend/.../tour/service/TourApiClient.java`). 반려 전용 프록시는 이 패턴(`WebClient` + `serviceKey`)을 재사용해 `KorPetTourService2`로 붙이면 된다.

### 1.3 요청 파라미터 (`locationBasedList2`)

실제 앱 코드가 조립하는 쿼리스트링(`fetchNearby`) 기준:

| 파라미터 | 예시값 | 설명 |
|---|---|---|
| `serviceKey` | (인코딩 키) | **이미 인코딩된 키를 그대로** 붙인다(재인코딩 금지 — 아래 1.6) |
| `MobileOS` | `ETC` | 필수. 앱은 `ETC` 사용 |
| `MobileApp` | `heattrip` | 필수. 서비스 식별자 |
| `_type` | `json` | 응답 포맷 |
| `numOfRows` | `80` | 페이지당 건수 (앱 기본 80) |
| `pageNo` | `1` | 페이지 번호 |
| `mapX` | `127.04` | **경도(lng)** |
| `mapY` | `37.54` | **위도(lat)** |
| `radius` | `8000` | 반경(m). 앱 기본 8km |
| `arrange` | `E` | 정렬 — `E`=거리순(이미지 우선) |
| `contentTypeId` | `39` | (선택) 카테고리 필터. 없으면 전체 |

주의: KTO 파라미터는 `mapX`=경도, `mapY`=위도로 **경도가 먼저**다. 앱은 `mapX=$lng&mapY=$lat`로 넘긴다(뒤바꾸면 결과 0건).

### 1.4 호출 예시

```
GET https://apis.data.go.kr/B551011/KorPetTourService2/locationBasedList2
  ?serviceKey={ENCODED_KEY}
  &MobileOS=ETC&MobileApp=heattrip&_type=json
  &numOfRows=80&pageNo=1
  &mapX=127.0396&mapY=37.5443&radius=8000&arrange=E
  &contentTypeId=39
```

앱 측 실코드(요약):

```dart
final uri = Uri.parse(
  '$_base/locationBasedList2?serviceKey=$key'
  '&MobileOS=ETC&MobileApp=heattrip&_type=json'
  '&numOfRows=$numOfRows&pageNo=1'
  '&mapX=$lng&mapY=$lat&radius=$radius&arrange=E'
  '${contentTypeId != null ? "&contentTypeId=$contentTypeId" : ""}',
);
final res = await http.get(uri).timeout(const Duration(seconds: 12));
```

### 1.5 응답 필드 매핑

응답 구조는 `response.body.items.item[]`. 단건이면 `item`이 배열이 아니라 객체로 오므로 배열 정규화가 필요하다(앱 `_parse`가 처리). `items`가 빈 문자열/문자열이면 결과 0건으로 간주한다.

| 응답 필드 | 앱 모델(`PetPlace`) | 비고 |
|---|---|---|
| `contentid` | `contentId` | 고유 ID |
| `title` | `title` | 장소명 |
| `contenttypeid` | `contentTypeId` | 카테고리(→ `petCatByType`로 `PetCategory` 매핑) |
| `addr1` | `addr` | 주소 |
| `firstimage` / `firstimage2` | `image` | 대표 이미지(없을 수 있음) |
| `tel` | `tel` | 전화 |
| `mapy` | `lat` | **위도** |
| `mapx` | `lng` | **경도** |
| `dist` | `distM` | 기준점으로부터 거리(m). `locationBasedList2`만 제공 |

- `contenttypeid` 코드표: `12`관광지 · `14`문화시설 · `28`레포츠 · `32`숙박 · `38`쇼핑 · `39`음식점. 매핑에 없는 값은 "기타"로 폴백.
- `lat`/`lng`가 0인 항목(좌표 결측)은 앱에서 걸러낸다.

### 1.6 서비스키 취급 (중요)

- 키는 `.env`의 `YOUR_DECODING_SERVICE_KEY`에 있고, `Env.tourServiceKey`로 읽는다(`lib/core/config/env.dart`).
- **명칭은 "Decoding"이지만 실제로는 인코딩(URL-encoded)된 키**가 들어있다. 그래서 앱은 `Uri.encodeQueryComponent` 없이 쿼리스트링에 **문자열 그대로** 붙인다. 재인코딩하면 `%2B`가 `%252B`로 이중 인코딩되어 `SERVICE_KEY_IS_NOT_REGISTERED_ERROR`가 난다.
- 키가 비어있으면 `fetchNearby`는 빈 리스트를 반환(앱 크래시 없음).
- 키는 앱 번들에 노출되므로(공개데이터 특성상 치명적이진 않으나) 남용/한도 방지를 위해 **백엔드 프록시로 이전 권장**(→ 6장).

### 1.7 한계·주의

- **호출 한도 1,000/day**: 사용자마다 지도 이동 시 직접 호출하면 금세 소진. 서울 45곳도 프리로드/캐시가 전제.
- **응답 형태 불안정**: `items`가 빈 문자열, `item`이 객체/배열 혼재 → 방어적 파싱 필수(구현됨).
- **이미지 결측** 잦음(`firstimage` 없음) → UI 플레이스홀더 필요.
- 좌표는 WGS84라 별도 변환 불필요(LOCALDATA와 대비).

---

## 2. LOCALDATA 인허가 (동물병원 · 펫샵)

행정안전부 지방행정 인허가데이터(LOCALDATA). 동물병원은 전국 약 **9,445건**, 그 외 동물미용·펫샵·펫호텔 업종이 있다. 지도의 `vet`/`shop` 레이어를 채운다. **현재 앱은 더미**이며, 좌표계 변환이 최대 관문이다.

### 2.1 좌표계 변환 — EPSG:5174 → WGS84 (필수)

LOCALDATA 좌표(`x`, `y`)는 경위도가 아니라 **EPSG:5174 (중부원점 TM, Bessel 타원체)** 미터 좌표다. 지도(WGS84 경위도)에 찍으려면 반드시 변환해야 하며, 안 하면 한반도 밖(혹은 바다)에 찍힌다.

| 필드 | 의미 |
|---|---|
| `x` | TM 동쪽(easting), meter |
| `y` | TM 북쪽(northing), meter |

- **원본**: `EPSG:5174` (Korea 2000 / Central Belt, 중부원점, Bessel 1841)
- **목표**: `EPSG:4326` (WGS84 경위도)
- 주의: 5174는 5186(GRS80 중부원점)과 **타원체가 달라(Bessel vs GRS80)** 혼용 시 수십~수백 m 오차. LOCALDATA는 5174가 맞다.

변환은 **백엔드 배치에서 1회 수행 후 `place.geom`에 WGS84로 저장**하는 것을 권장(앱은 변환 부담 없음). 예: PROJ / GeoTools / proj4 계열.

```
# proj4 정의 (EPSG:5174)
+proj=tmerc +lat_0=38 +lon_0=127.0028902777778 +k=1 +x_0=200000 +y_0=500000
+ellps=bessel +units=m +no_defs
+towgs84=-115.80,474.99,674.11,1.16,-2.31,-1.63,6.43
```

### 2.2 주요 필드 (인허가 공통 스키마)

| 필드 | 의미 | `place` 매핑 |
|---|---|---|
| `bplcNm` | 사업장명 | `name` |
| `siteWhlAddr` / `rdnWhlAddr` | 지번/도로명 주소 | `addr` |
| `x`, `y` | EPSG:5174 좌표 | 변환 후 `geom(POINT)` |
| `trdStateNm` | 영업상태(영업/폐업) | 필터(영업 중만) |
| `siteTel` | 전화 | `raw_json` |
| `uptaeNm` | 업태(동물병원/미용 등) | `category` 판별 |

- **폐업 필터 필수**: `trdStateNm`(또는 `trdStateGbn`)로 영업 중만 적재. 안 하면 폐업 병원이 지도에 남음.
- 업종별로 파일/서비스가 나뉘므로(동물병원, 동물판매업 등) `source`를 `localdata_vet`/`localdata_shop`으로 구분해 저장.

### 2.3 상태·한계

- 현재 지도의 병원/펫샵은 **하드코딩 더미**(`kLayerKeys = {vet, shop, trail}` 레이어).
- 좌표 변환 + 폐업 필터 + 주기적(월 단위) 재적재가 실연동의 전제.

---

## 3. 두루누비 걷기여행길 (산책로)

한국관광공사 두루누비(walk trail) 데이터. 걷기여행길 코스의 경로 좌표/GPX를 제공한다. 지도의 `trail` 레이어(폴리라인)와 `trail` 테이블을 채운다.

| 항목 | 값 |
|---|---|
| 제공 | 한국관광공사 두루누비 |
| 형식 | 코스 좌표열 / GPX 트랙 |
| 좌표계 | WGS84 (변환 불필요) |
| 매핑 | 코스명 → `trail.name`, 좌표열 → `trail.path(LINESTRING)`, 총거리 → `trail.length_m` |
| 현재 상태 | **더미 폴리라인**(실데이터 미연동) |

- GPX/좌표열을 `LINESTRING`으로 변환해 `trail.path`에 저장, `length_m`는 사전 계산해 넣는다(지도 렌더 시 재계산 회피).
- 두루누비 코스는 도시 산책 규모보다 긴 트레킹 코스가 많아, MVP 지도에는 **도심 근처 코스만 선별 적재** 권장.

---

## 4. 좌표계 요약

| 소스 | 원본 좌표계 | 처리 |
|---|---|---|
| KTO KorPetTourService2 | WGS84(경위도, `mapx`/`mapy`) | 그대로 사용 |
| LOCALDATA 인허가 | **EPSG:5174 (Bessel TM)** | **→ WGS84 변환 필수(백엔드 배치)** |
| 두루누비 | WGS84 | 그대로 사용 |

지도 SDK(`flutter_naver_map`)와 DB `POINT`/`LINESTRING`은 모두 WGS84 기준으로 통일한다.

---

## 5. 데이터 흐름 (현재 vs 목표)

**현재** — KTO만 앱이 직접 호출, 나머지 더미:

```mermaid
flowchart LR
  App[Flutter 앱\nlib/v2] -->|locationBasedList2| KTO[(KTO KorPetTourService2)]
  App -. 더미 .-> Vet[병원/펫샵]
  App -. 더미 .-> Trail[산책로]
```

**목표** — 백엔드 프록시 + `place`/`trail` 캐시:

```mermaid
flowchart LR
  App[Flutter 앱] -->|/places?bbox| API[Spring Boot\nplace/trail API]
  API --> DB[(MySQL\nplace.geom / trail.path\nSPATIAL INDEX)]
  Sync[동기화 배치] -->|주기 수집·좌표변환·정규화| DB
  Sync --> KTO[(KTO KorPetTourService2)]
  Sync --> LD[(LOCALDATA 인허가)]
  Sync --> DN[(두루누비)]
```

---

## 6. 캐싱·동기화 전략(`place`/`trail`)

세 소스 모두 **호출 한도·좌표변환·응답 불안정** 이슈가 있어, 앱이 직접 외부 API를 때리지 않고 **백엔드가 미리 수집·정규화해 `place`/`trail`에 캐시**하는 구조를 목표로 한다.

### 6.1 캐시 테이블 (→ [ERD](../03-database/erd.md))

| 테이블 | 컬럼(핵심) | 채우는 소스 |
|---|---|---|
| `place` | `source`, `category`, `name`, `geom POINT`, `addr`, `tel`, `raw_json`, `updated_at` | `kto_pet` / `localdata_vet` / `localdata_shop` |
| `trail` | `source`, `name`, `path LINESTRING`, `length_m` | 두루누비 |

- `source`로 출처 구분: `kto_pet`, `localdata_vet`, `localdata_shop`.
- `raw_json`에 원본 응답을 보관해 스키마 변경/재파싱에 대비.
- 공간질의는 `ST_Distance_Sphere` / `MBRContains` + `SPATIAL INDEX`(→ 지도 bbox·반경 조회).

### 6.2 동기화 주기

| 소스 | 갱신 성격 | 권장 주기 |
|---|---|---|
| KTO 반려동반 | 저빈도 변경 | 주 1회 배치(도시별 `areaBasedList2` 페이지네이션 수집) |
| LOCALDATA | 인허가 변동(개·폐업) | 월 1회 재적재 + 폐업 필터 |
| 두루누비 | 거의 정적 | 분기/수동 |

### 6.3 갱신 규칙

- **upsert 키**: KTO는 `contentid`, LOCALDATA는 관리번호/사업장 식별자. 동일 키는 `updated_at` 갱신.
- **좌표 변환은 적재 시 1회**(LOCALDATA 5174→WGS84) → 조회·렌더는 변환 부담 0.
- **호출 한도 회피**: KTO 1,000/day는 배치가 한 번에 페이지네이션으로 소진하고, 사용자 요청은 전부 캐시(`place`)에서 응답.
- 이미지/전화 등 결측은 캐시 단계에서 정규화(빈 문자열 통일)해 앱 분기 단순화.

### 6.4 이전 로드맵

1. KTO 프록시 엔드포인트 신설(`GET /api/places?bbox=&category=`) → 앱을 직접 호출에서 프록시로 전환.
2. LOCALDATA 배치(좌표변환 포함) → `place`(`vet`/`shop`) 적재 → 더미 제거.
3. 두루누비 배치 → `trail` 적재 → 더미 폴리라인 제거.

---

## 부록 A. 관련 코드 위치

| 파일 | 역할 |
|---|---|
| `app/lib/v2/data/pet_places_repository.dart` | KTO `locationBasedList2` 호출·파싱(`PetPlace`) |
| `app/lib/v2/domain/pet.dart` | 카테고리 SSOT(`kPetCategories`, `kLayerKeys`, `petCatByType`) |
| `app/lib/core/config/env.dart` | `tourServiceKey`(`YOUR_DECODING_SERVICE_KEY`) 로드 |
| `app/.env` | `YOUR_DECODING_SERVICE_KEY`(인코딩된 KTO 키), `NAVER_MAP_CLIENT_ID` |
| `backend/.../tour/service/TourApiClient.java` | 레거시 `areaBasedList2` 프록시 패턴(반려 프록시 참고) |
