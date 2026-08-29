# 의사결정 기록 (ADR 로그)

> Pawloop(포루프) — 반려동물 산책·동반장소·커뮤니티 앱 — 의 주요 아키텍처/제품 결정을 시간순으로 기록한 ADR(Architecture Decision Record) 목록. 각 결정은 **맥락 · 결정 · 대안 · 결과**로 정리한다. 결정의 근거는 실제 코드/설정(`app/pubspec.yaml`, `app/lib/v2`, `android/*.gradle.kts`, `app/.env`)에 정렬한다.

관련 문서: [기술 스택](../02-architecture/tech-stack.md) · [외부 공개데이터 연동](../02-architecture/external-data.md) · [ERD](../03-database/erd.md)

---

## ADR 인덱스

| # | 결정 | 상태 | 날짜 |
|:---:|:---|:---|:---|
| [0001](#adr-0001--감정여행heattrip--반려앱pawloop-피벗) | 감정여행(heattrip) → 반려앱(Pawloop) 피벗 | 채택 (Accepted) | 2026-07 |
| [0002](#adr-0002--앱-이름-pawloop포루프-채택) | 앱 이름 Pawloop(포루프) 채택 | 채택 (Accepted) | 2026-07 |
| [0003](#adr-0003--rdbmysql-공간형-중심-nosql-보류) | RDB(MySQL 공간형) 중심, NoSQL 보류 | 채택 (Accepted) | 2026-07 |
| [0004](#adr-0004--관광공사-kto-반려동반-api-korpettourservice2-채택) | 관광공사 KTO 반려동반 API(KorPetTourService2) 채택 | 채택 (Accepted) | 2026-07 |
| [0005](#adr-0005--flutter-332--344-업그레이드--fl_chart-도입) | Flutter 3.32 → 3.44 업그레이드 + fl_chart 도입 | 채택 (Accepted) | 2026-07 |
| [0006](#adr-0006--kto-앱에서-직접-호출임시--백엔드-프록시-계획) | KTO 앱에서 직접 호출(임시) → 백엔드 프록시 계획 | 임시 채택 (Accepted, 임시) | 2026-07 |
| [0007](#adr-0007--fluent-emoji-3d-아이콘-채택) | Fluent Emoji 3D 아이콘 채택 | 채택 (Accepted) | 2026-07 |
| [0008](#adr-0008--저장소가-담는-문서의-범위) | 저장소가 담는 문서의 범위 — 기술 문서를 코드와 함께 관리 | 채택 (Accepted) | 2026-08 |

> 상태 범례: **채택(Accepted)** = 현재 유효 · **임시(Accepted, 임시)** = 채택했으나 대체 계획 존재 · (필요 시) 폐기(Superseded)/거절(Rejected).

---

## ADR-0001 — 감정여행(heattrip) → 반려앱(Pawloop) 피벗

- **상태**: 채택 (Accepted)
- **날짜**: 2026-07

### 맥락
기존 제품은 "감정 여행(heattrip)" — 사용자의 감정 상태에 맞춰 장소를 추천하는 감정 기반 여행 앱이었다. 감정 매칭은 (1) 사용자가 자기 감정을 매번 입력해야 하는 진입 마찰, (2) "감정→장소" 매칭의 검증 어려움·설득력 부족, (3) 좁고 명확한 반복 사용 고리(retention loop)의 부재라는 문제를 안고 있었다. 반면 개발자가 이미 확보한 자산(관광공사 장소 데이터 연동, 지도, 커뮤니티/추천 파이프라인 골격)은 "위치 기반 생활 서비스"에 그대로 재활용 가능했다.

### 결정
2026-07, 감정 여행 앱을 **반려동물(강아지 중심) 산책·동반장소·커뮤니티 앱**으로 피벗한다. **감정 요소는 전부 제거**한다. 산책(실시간 GPS 트래킹)을 wedge로 좁게 시작해 "반려 일상 로그(산책→건강·식사·병원·동네) + 동반장소 지도 + 커뮤니티"로 확장한다.

### 대안
1. **감정앱 존속·개선**: 감정 입력 마찰과 매칭 설득력 문제가 구조적이라 반복 사용 고리가 약함. 기각.
2. **일반 여행/로컬 추천 앱으로 순화**: 차별점이 사라지고 대형 플랫폼과 정면 경쟁. 기각.
3. **반려 앱으로 피벗(채택)**: 산책은 매일 반복되는 강한 사용 고리를 제공하고, 반려동반 장소·동물병원 등 위치 데이터 수요가 명확하며, 기존 지도/장소/커뮤니티 자산을 재활용할 수 있음.

### 결과
- 제품 정체성 재정의: "반려동물과 함께 걷고, 동네 반려인들과 연결되는 공간". 회사 cetaceaLab.
- 감정 관련 화면/도메인 제거, 신규 화면은 `app/lib/v2/` 하위로 재구축(홈/지도/산책 트래킹/통계/커뮤니티/프로필).
- 도메인 모델을 반려 중심으로 재설계: `app_user`/`dog`/`walk`/`place`/`trail`/`post`/`comment`/`reaction`/`bookmark` (→ [ERD](../03-database/erd.md)).
- **레거시 잔재**: 감정여행 시절의 FastAPI+OpenAI 추천 파이프라인과 일반 관광 `TourApiClient`는 코드에 남아 있으며 반려 맥락에서 **재검토 대상**(→ ADR-0004, ADR-0006). Android `applicationId`/`namespace`는 `com.cetacealab.heattrip`를 유지(마이그레이션 비용 회피).

---

## ADR-0002 — 앱 이름 Pawloop(포루프) 채택

- **상태**: 채택 (Accepted)
- **날짜**: 2026-07

### 맥락
피벗(ADR-0001)으로 제품명이 필요해졌다. 이름은 (1) 반려/산책 정체성을 담고, (2) 국문·영문 모두 자연스럽고, (3) 앱스토어 검색·브랜딩에 유리해야 했다. 제품의 핵심 반복성(매일 산책·케어 루틴, 동네 커뮤니티, 산책 경로)을 하나의 상징으로 묶고 싶었다.

### 결정
앱 이름을 **Pawloop(한국어명 포루프)**로 채택한다. `Paw`(발/반려동물) + `loop`(반복 고리)의 합성어.

- 앱스토어명: **Pawloop: Pet Walk & Community** / **포루프: 반려동물 산책 커뮤니티**
- `loop`의 3중 의미: ① 매일 반복되는 산책·케어 루틴 기록 loop ② 동네 반려인 커뮤니티 loop ③ 산책 경로(경로 자체가 loop) loop
- 문서/UI 표기 규칙: 항상 **"Pawloop(포루프)"**.

### 대안
- 직역/일반명("펫워크", "멍산책" 등): 검색 경쟁 심하고 확장성(케어/커뮤니티) 표현 약함. 기각.
- 감정앱 브랜드(heattrip) 재사용: 반려 정체성과 불일치. 기각.

### 결과
- 브랜드 상징을 `loop`로 통일 — 제품 서사(반복 사용 고리)와 로고/네이밍이 일관됨.
- 내부 기술 식별자는 당장 바꾸지 않음: Android `applicationId` `com.cetacealab.heattrip`, KTO 호출 파라미터 `MobileApp=heattrip`(`pet_places_repository.dart`) 등 레거시 문자열 잔존 → 스토어 등록/재서명 시점에 일괄 정리 예정.

---

## ADR-0003 — RDB(MySQL 공간형) 중심, NoSQL 보류

- **상태**: 채택 (Accepted)
- **날짜**: 2026-07

### 맥락
Pawloop의 데이터는 대부분 **공간(geo) 데이터**다: 산책 경로(LINESTRING), 장소 POI(POINT), 산책로(LINESTRING). 지도 bbox/반경 조회, "내 주변 동반장소"가 핵심 쿼리다. 1인 개발 포트폴리오 겸 실서비스로, 운영 복잡도를 낮추면서 공간질의를 안정적으로 처리할 저장소가 필요했다.

### 결정
초기 저장소를 **MySQL(공간형) 단일 RDB**로 간다. NoSQL/전용 검색엔진/캐시는 **규모 확장 시점까지 보류**한다.

- 공간 타입: `POINT`(장소), `LINESTRING`(산책 경로·산책로) + `SPATIAL INDEX`.
- 공간질의: `ST_Distance_Sphere` / `MBRContains` (반경·bbox 조회).
- GPS 경로는 **`walk.path` 단일 컬럼**(LINESTRING/인코딩 폴리라인)에 저장 — 포인트를 행마다 쪼개지 않음.

### 대안
1. **MongoDB 등 도큐먼트 NoSQL**: GPS 시계열/유연 스키마에 유리하나, 트랜잭션·조인(커뮤니티·프로필 관계형)에서 손해. 운영 요소 추가. 보류.
2. **PostgreSQL + PostGIS**: 공간 기능은 가장 강력하나, 팀 친숙도/기존 스택(MySQL) 고려 시 초기 이득 대비 전환 비용. 보류(후보로 유지).
3. **Elasticsearch(장소 검색) + Redis(캐시) 조합 선반영**: MVP 규모(서울 수십~수백 POI)에 과설계. 보류.
4. **MySQL 공간형 단일 RDB(채택)**: 관계형(커뮤니티/프로필)과 공간질의를 하나의 저장소에서 처리, 운영 단순, MVP 규모에 충분.

### 결과
- 하나의 트랜잭션 경계 안에서 관계형+공간 데이터를 다룸 → 운영/백업 단순화.
- 대량 GPS 시계열/장소 검색(ES)·캐시(Redis)·NoSQL은 **규모 확장 시 옵션**으로 명시(초기엔 RDB-only). (→ [ERD](../03-database/erd.md), [기술 스택 §3](../02-architecture/tech-stack.md))
- 리스크: 초대량 GPS/동시성이 커지면 시계열 분리 필요 → 그 시점에 재평가(이 ADR 갱신).

---

## ADR-0004 — 관광공사 KTO 반려동반 API(KorPetTourService2) 채택

- **상태**: 채택 (Accepted)
- **날짜**: 2026-07

### 맥락
지도의 "반려동반 가능 장소" 레이어를 채울 실데이터가 필요했다. 반려동반 가능 여부가 검증된, 좌표·주소·이미지를 갖춘 공개데이터가 요구됐다. 자체 데이터 구축은 비현실적이었다.

### 결정
한국관광공사 **반려동물 동반여행 서비스 `KorPetTourService2`**(data.go.kr, 데이터 PK `15135102`)를 동반장소 레이어의 소스로 채택한다.

- Base URL: `https://apis.data.go.kr/B551011/KorPetTourService2`
- 사용 오퍼레이션: `locationBasedList2`(좌표 반경 내 거리순) — 현재 사용. `areaBasedList2`/`searchKeyword2`/`detailPetTour2`는 후보.
- 응답 필드 매핑: `mapx`=경도, `mapy`=위도, `contenttypeid`(12관광지/14문화/28레포츠/32숙박/38쇼핑/39음식점), `addr1`/`tel`/`firstimage`.
- 좌표계는 **WGS84** → 변환 불필요.

### 대안
1. **자체 반려동반 DB 구축/크라우드소싱**: 초기 데이터 확보 불가, 검증 비용 과다. 기각.
2. **LOCALDATA(행안부 인허가)만 사용**: 동물병원/펫샵은 커버하나 "반려동반 관광/카페/숙박"은 커버 못 함. 또한 좌표가 **EPSG:5174**라 변환 필요. → 별도 레이어로 병행(대체가 아님).
3. **네이버/카카오 로컬 등 상용 API**: 반려동반 여부 필드가 없고 호출 비용/약관 부담. 기각.
4. **KTO KorPetTourService2(채택)**: 반려동반이 검증된 관광 POI를 좌표와 함께 무료 제공.

### 결과
- 서울 ~45곳을 **실연동**해 지도에 표시(유일한 실데이터 레이어). 병원/펫샵(LOCALDATA)·산책로(두루누비)는 **더미** 상태로 남아 향후 연동 대상(→ [외부 공개데이터 연동](../02-architecture/external-data.md)).
- **호출 한도 1,000 calls/day**(개발계정) → 프리로드/캐시 전제, 앱 직접 호출은 임시(→ ADR-0006).
- **serviceKey 취급 주의**: `.env`의 `YOUR_DECODING_SERVICE_KEY`는 명칭과 달리 **이미 URL 인코딩된** 키라 재인코딩 금지(재인코딩 시 이중 인코딩 → `SERVICE_KEY_IS_NOT_REGISTERED_ERROR`).
- 응답 형태 불안정(`items` 빈 문자열, `item` 객체/배열 혼재) → 방어적 파싱 구현(`pet_places_repository.dart`의 `_parse`).

---

## ADR-0005 — Flutter 3.32 → 3.44 업그레이드 + fl_chart 도입

- **상태**: 채택 (Accepted)
- **날짜**: 2026-07

### 맥락
반려 앱 재구축(ADR-0001)과 함께 최신 툴체인/패키지 요구가 생겼다. 특히 산책 통계 화면(주간 막대·요약)에 차트 위젯이 필요했고, `fl_chart` 최신 버전과 다른 신규 의존성(`flutter_naver_map`, `lottie`, `google_fonts` 등)이 최신 Dart/Flutter SDK와 Android 툴체인을 요구했다.

### 결정
- **Flutter 3.44.4 / Dart 3.12.2**(SDK `^3.8.1`)로 업그레이드한다.
- 산책 통계 차트에 **`fl_chart ^1.2.0`**을 도입한다.
- 이에 맞춰 Android 툴체인을 상향: **AGP 8.11.1 / Kotlin 2.2.20 / Gradle 8.13 / compileSdk 36 / minSdk 23 / Java 17**.

### 대안
- **기존 Flutter 3.32 유지**: 신규 패키지(특히 `flutter_naver_map`, `fl_chart ^1.x`)와 SDK/Android 툴체인 제약 충돌. 기각.
- **차트 라이브러리로 `syncfusion_flutter_charts` / `charts_flutter`**: `charts_flutter`는 사실상 유지보수 중단, syncfusion은 라이선스 부담. `fl_chart` 채택.

### 결과
- `pubspec.yaml` 앱 버전 **2.0.0+1**, `environment.sdk: ^3.8.1`.
- 산책 통계 화면에서 `fl_chart` 주간 막대 차트 + 요약 + 자주 가는 곳 구현.
- `minSdk 23`은 `flutter_naver_map` 요구(→ [Android 빌드/기술 스택 §4](../02-architecture/tech-stack.md)).
- 업그레이드가 다른 신규 의존성(`flutter_naver_map ^1.3.1`, `geolocator ^13.0.1`, `lottie ^3.4.0`, `google_fonts ^8.1.0`)의 전제가 됨.

---

## ADR-0006 — KTO 앱에서 직접 호출(임시) → 백엔드 프록시 계획

- **상태**: 임시 채택 (Accepted, 임시) — 백엔드 프록시로 이전 예정
- **날짜**: 2026-07

### 맥락
ADR-0004로 KTO를 채택했으나, KTO는 **1,000 calls/day 한도**와 응답 형태 불안정을 갖고, **serviceKey가 앱 번들에 노출**되며, 지도 이동마다 사용자별 직접 호출 시 한도가 금세 소진된다. 반면 MVP 단계에서 백엔드 프록시+캐시(`place` 테이블) 구축은 아직 진행 전이었다.

### 결정
- **당장은 앱이 KTO를 직접 호출**한다(`lib/v2/data/pet_places_repository.dart` → `PetPlacesRepository.fetchNearby()`). 개발 속도 우선.
- 단, 이를 **명시적으로 임시**로 규정하고, **백엔드 프록시 + `place`/`trail` 캐싱**으로 이전하는 것을 목표 아키텍처로 확정한다.

### 대안
1. **처음부터 백엔드 프록시 구축 후 연결**: 정석이나 MVP 속도 저해, 백엔드 스키마·배치 선행 필요. 지금은 보류(목표로 유지).
2. **앱 직접 호출 영구 유지**: 한도 소진·키 노출·응답 정규화 부담이 사용자 증가 시 치명적. 기각.
3. **앱 직접 호출(임시) + 프록시 계획(채택)**: 지금은 빠르게 실데이터를 보여주고, 확장 시 프록시로 전환.

### 결과
- 현재: KTO만 앱이 직접 호출, 병원/펫샵·산책로는 더미.
- **목표 아키텍처**: 앱 `GET /api/places?bbox=&category=` → Spring Boot `place/trail` API → MySQL(`place.geom`/`trail.path` + SPATIAL INDEX). 동기화 배치가 KTO/LOCALDATA/두루누비를 주기 수집·좌표변환·정규화해 캐시.
- 이전 로드맵: ① KTO 프록시 엔드포인트 신설 → 앱 전환 ② LOCALDATA 배치(EPSG:5174→WGS84) → `place`(vet/shop) 적재 ③ 두루누비 배치 → `trail` 적재. (상세 → [외부 공개데이터 연동 §5·§6](../02-architecture/external-data.md))
- 참고: 백엔드에 레거시 `TourApiClient`(일반 관광 `areaBasedList2`)가 있어, 반려 프록시는 이 `WebClient`+`serviceKey` 패턴을 재사용 가능.

---

## ADR-0007 — Fluent Emoji 3D 아이콘 채택

- **상태**: 채택 (Accepted)
- **날짜**: 2026-07

### 맥락
디자인 시스템(파스텔 오라 그라데이션 배경 + 반투명 글래스 카드, 따뜻한 그라데이션 `#FFA96B→#FF7E8A`)에 맞는 **따뜻하고 친근한 아이콘 세트**가 필요했다. 카테고리/감정 표현·강조 포인트에 쓸 일관된 3D 그래픽이 요구됐다.

### 결정
**Microsoft Fluent Emoji의 3D PNG 에셋**을 앱 아이콘 그래픽으로 채택한다. 에셋은 `assets/emoji/`에 번들하고, 폰트는 Pretendard로 통일한다.

### 대안
1. **머티리얼/Cupertino 벡터 아이콘만 사용**: 톤이 밋밋하고 글래스+파스텔 무드와 덜 어울림. (보조로는 `iconsax`/`flutter_svg` 병행)
2. **커스텀 일러스트 제작**: 1인 개발 리소스로 일관성/물량 확보 어려움. 기각.
3. **다른 오픈 이모지(Noto/Twemoji 등)**: 3D 질감·무드 적합도에서 Fluent Emoji가 우위. 기각.
4. **Fluent Emoji 3D(채택)**: 오픈 라이선스, 3D 질감이 따뜻한 무드와 정합, 물량·일관성 확보.

### 결과
- `assets/emoji/`에 Fluent Emoji 3D PNG 번들, `pubspec.yaml` 에셋 등록(`assets/emoji/`).
- 벡터가 필요한 곳은 `flutter_svg`(google/kakao/naver 로그인 아이콘)·`iconsax`로 병행.
- 디자인 토큰(T)·글래스 카드(GlassCard)·오라 배경(AuroraBackground)과 함께 브랜드 룩앤필을 구성(→ [디자인 시스템](../01-design/design-system.md)).

---

## ADR-0008 — 저장소가 담는 문서의 범위

- **상태**: 채택 (Accepted)
- **날짜**: 2026-08

### 맥락

문서가 두 세계로 갈라져 있었다. `backend/docs/`(백엔드 운영·아키텍처 문서)는 저장소에 추적되는 반면, 루트 `docs/`는 통째로 `.gitignore`에 들어 있어 GitHub에서 볼 수 없었다.

그 결과 세 가지가 막혔다.

1. **이슈·PR에서 API 계약을 링크할 수 없다.** `docs/04-api/openapi.yaml`은 프론트와 백엔드가 합의한 계약인데, 그 변경 이력이 코드 이력과 분리되어 있었다. 소셜 로그인 작업(#2)에서 계약 정합을 다루는 이슈들이 경로를 링크가 아닌 코드 표기로만 남겨야 했다.
2. **ADR이 PR 리뷰 대상이 되지 않는다.** 결정 기록이 그 결정을 구현하는 코드 변경과 함께 검토되지 않는다.
3. **로드맵과 개발 환경 세팅 문서가 저장소 밖에 있다.** 새 참여자에게 따로 전달해야 한다.

한편 `.gitignore`의 `docs/` 규칙은 **앵커가 없어 모든 depth의 `docs` 디렉터리**를 잡고 있었다 — `app/docs/`, `app/lib/docs/`, `backend/docs/`까지. `backend/docs/`가 추적되고 있던 것은 규칙이 추가되기 *전에* 커밋됐기 때문이지 의도한 결과가 아니었다. 즉 규칙 자체가 의도보다 넓게 걸려 있었다.

### 결정

**이 저장소의 `docs/`는 기술 문서 세트로 정의한다.** 코드와 함께 버전 관리되고, PR에서 함께 리뷰되어야 하는 문서를 담는다.

| 폴더 | 내용 |
| --- | --- |
| `01-design/` | 디자인 시스템 · 화면 명세 · 정보구조 · 사용자 플로우 |
| `02-architecture/` | 시스템 개요 · 백엔드/프론트 구조 · 도메인별 구현 청사진 |
| `03-database/` | ERD · 스키마 · 마이그레이션 |
| `04-api/` | **`openapi.yaml` — 프론트/백엔드 합의 계약** · API 명세 |
| `05-build/` | 로드맵 · MVP 범위 · 구현 현황 · 개발 환경 세팅 |
| `06-testing/` | 테스트 체크리스트 |
| `99-decisions/` | ADR 로그 (이 문서) |

**제품 기획·전략 문서는 저장소 범위 밖에서 관리한다.** 코드 변경과 함께 리뷰될 성격이 아니고, 변경 주기와 독자가 다르다.

**생성물은 추적하지 않는다.** `backend/generated-reference/`(OpenAPI 제너레이터가 만든 Java 참조 코드)는 소스가 아니라 산출물이므로 `.gitignore`에 넣는다.

`.gitignore`의 넓은 `docs/` 규칙은 **루트 앵커가 붙은 구체적 경로**로 교체한다. 그래야 `backend/docs/`나 `app/lib/docs/` 같은 다른 위치의 문서가 우연히 걸리지 않는다.

추적 전환 전 대상 문서 전체를 자격증명 기준으로 스캔했다(api key · secret · password · token · AKIA · PEM 헤더 · 32자 이상 base64). 실제 키·토큰·비밀번호는 없었고, 검색에 걸린 것은 변수명과 파일 경로뿐이었다.

### 대안

1. **현행 유지(루트 `docs/` 전체 제외)**: 위 세 가지 문제가 그대로 남는다. 특히 계약(`openapi.yaml`)이 버전 관리 밖에 있는 것은 프론트/백엔드 정합에 직접적인 위험이다. 기각.
2. **계약과 ADR만 추적**(`04-api`·`99-decisions`): 가장 좁은 범위. 그러나 `05-build/setup.md`(개발 환경 세팅)와 `roadmap.md`가 빠지면 새 참여자가 저장소만 보고 시작할 수 없고, 마일스톤 설명을 매번 이슈 본문에 복사해야 한다. 기각.
3. **별도 문서 저장소**: 분리는 되지만 코드와 문서의 커밋이 어긋나고 저장소 두 개를 동기화해야 한다. 문서가 코드 변경과 함께 리뷰되어야 한다는 목적에 반한다. 기각.

### 결과

- 이슈·PR에서 `openapi.yaml`·`auth.md`·`erd.md`를 링크로 걸 수 있다. 소셜 로그인 Epic(#2)의 서브이슈들이 코드 표기로만 남겨둔 경로를 실제 링크로 교체한다.
- ADR이 PR 리뷰 대상이 된다. 이 ADR 자체가 첫 사례다(#16 → PR).
- 새 문서를 만들 때 **"이건 코드와 함께 리뷰될 문서인가"** 를 기준으로 위치를 정한다. 그렇다면 `docs/` 아래, 아니면 저장소 밖.
- `docs/README.md`의 폴더 인덱스는 저장소에 실제로 있는 문서만 나열한다.

---

## 부록 — ADR 작성 규칙

- 새 결정은 이 로그 하단에 **다음 번호**로 추가하고, 상단 [ADR 인덱스](#adr-인덱스) 표에 한 줄 등록한다.
- 각 ADR은 **맥락 · 결정 · 대안 · 결과** 4개 항목을 반드시 포함한다.
- 기존 결정을 뒤집을 때는 원본 ADR을 지우지 말고 **상태를 폐기(Superseded by ADR-XXXX)**로 바꾸고, 대체 ADR을 새로 추가한다.
- 사실은 실제 코드/설정(`app/pubspec.yaml`, `app/lib/v2`, `android/*.gradle.kts`, `app/.env`)에 정렬한다.
