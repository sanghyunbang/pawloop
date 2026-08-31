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
| [0004](#adr-0004--관광공사-kto-반려동반-apikorpettourservice2-채택) | 관광공사 KTO 반려동반 API(KorPetTourService2) 채택 | 채택 (Accepted) | 2026-07 |
| [0005](#adr-0005--flutter-332--344-업그레이드--fl_chart-도입) | Flutter 3.32 → 3.44 업그레이드 + fl_chart 도입 | 채택 (Accepted) | 2026-07 |
| [0006](#adr-0006--kto-앱에서-직접-호출임시--백엔드-프록시-계획) | KTO 앱에서 직접 호출(임시) → 백엔드 프록시 계획 | 임시 채택 (Accepted, 임시) | 2026-07 |
| [0007](#adr-0007--fluent-emoji-3d-아이콘-채택) | Fluent Emoji 3D 아이콘 채택 | 채택 (Accepted) | 2026-07 |
| [0008](#adr-0008--저장소가-담는-문서의-범위) | 저장소가 담는 문서의 범위 — 기술 문서를 코드와 함께 관리 | 채택 (Accepted) | 2026-08 |
| [0009](#adr-0009--소셜-로그인에-pkce-를-도입하지-않는다) | 소셜 로그인에 PKCE 를 도입하지 않는다 — 백엔드가 공급자와 코드 교환을 수행하는 동안 | 채택 (Accepted) | 2026-08 |
| [0010](#adr-0010--소셜-로그인-공급자와-앱-세션-토큰-전략) | 소셜 로그인 공급자(카카오·구글)와 앱 세션 토큰 전략 — 네이버·Redis 보류 | 채택 (Accepted) | 2026-08 |
| [0011](#adr-0011--채팅은-가족-그룹-종속이-아니라-범용-다중-방이다) | 채팅 아키텍처 — 범용 다중 방 · 방별 room_seq · 폴링 우선, STOMP·Redis 보류 | 채택 (Accepted) | 2026-08 |

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
- **serviceKey 취급 주의**: `--dart-define=YOUR_DECODING_SERVICE_KEY`로 주입하는 값(`Env.tourServiceKey`)은 명칭과 달리 **이미 URL 인코딩된** 키라 재인코딩 금지(재인코딩 시 이중 인코딩 → `SERVICE_KEY_IS_NOT_REGISTERED_ERROR`). 예전에는 이 값이 `.env` 에셋에 있었고 #29 가 `--dart-define` 으로 옮겼다.
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

## ADR-0009 — 소셜 로그인에 PKCE 를 도입하지 않는다

- **상태**: 채택 (Accepted)
- **날짜**: 2026-08
- **관련**: 이슈 #14 · [`docs/04-api/openapi.yaml`](../04-api/openapi.yaml) 의 `POST /auth/oauth/{provider}/callback`

### 맥락

이슈 #14 는 소셜 로그인 딥링크에서 토큰을 걷어내고 **1회용 인가 코드 교환**으로 바꿨다. 그 과정에서 "인가 코드를 다루는데 PKCE 가 없어도 되는가" 라는 질문이 나왔고, 이슈 본문은 그 판단을 **ADR 로 남기라**고 명시했다. 계약 문서 두 곳(`api-spec.md`·`openapi.yaml`)에 한 줄씩 각주가 있었지만, 각주는 ADR 인덱스에 걸리지 않아 다음 사람이 검색할 수 없다. ADR-0008 자체가 "결정 기록이 그 결정을 구현하는 코드 변경과 함께 검토되어야 한다"고 정한 규칙이므로, 각주만 남기는 것은 저장소 자체 규약 위반이기도 하다.

PKCE(RFC 7636)가 푸는 문제는 **공개 클라이언트(앱)가 공급자와 직접 말할 때 인가 코드가 가로채이는 것**이다. 앱이 `code_verifier` 를 만들고 그 해시(`code_challenge`)를 인가 요청에 실어 보내면, 코드를 가로챈 쪽은 원본 `code_verifier` 가 없어 토큰 교환을 완료하지 못한다.

이 저장소의 흐름은 그 모양이 아니다.

1. 앱은 **우리 서버**의 `GET /oauth2/authorization/{provider}` 를 연다.
2. 공급자와의 인가 코드 교환은 **백엔드**(Spring Security `oauth2Login`)가 클라이언트 시크릿으로 끝낸다. 앱은 공급자의 인가 코드를 본 적이 없다.
3. 앱이 딥링크로 받는 `code` 는 공급자의 것이 아니라 **우리가 만든 1회용 난수**(`AuthCodeStore`, 256bit, TTL 60초, 1회 소비)다.

즉 이 흐름에서 `code_verifier` 를 만들 주체(앱)와 그것을 검증할 주체(공급자)가 연결되지 않는다. 앱이 PKCE 파라미터를 만들어도 그것을 받아 줄 상대가 없다.

### 결정

**백엔드가 공급자와의 인가 코드 교환을 수행하는 현 구조에서는 PKCE 를 채택하지 않는다.**

딥링크 구간(우리 서버 → 앱)의 코드 가로채기는 PKCE 가 아니라 다음 셋으로 막는다.

- **1회성** — `AuthCodeStore.consume` 이 꺼내는 즉시 지운다. 정당한 앱이 먼저 교환하면 그 코드는 죽는다.
- **60초 TTL** — 가로채도 쓸 수 있는 창이 사실상 없다.
- **`state` 대조** — 앱이 만든 난수를 앱이 대조한다(응답 바꿔치기·로그인 CSRF). 서버도 코드 발급 시점의 `state` 와 교환 요청의 값을 대조하고, **빈 `state` 로 발급된 코드는 교환하지 않는다** — 그렇지 않으면 검사의 존재 여부를 왕복을 시작한 쪽이 정하게 된다.

### 대안

1. **지금 PKCE 를 도입한다.** 앱이 공급자와 직접 말하지 않으므로 `code_verifier` 를 검증할 주체가 없다. 우리 서버가 스스로 낸 코드에 대해 자기가 만든 challenge 를 자기가 검증하는 형태가 되는데, 그것은 위 세 장치가 이미 하는 일과 겹치면서 이름만 PKCE 인 의식이 된다. 기각.
2. **앱↔공급자 직결로 전환하고 PKCE 를 넣는다.** 리다이렉트 왕복이 한 번 줄고 표준 모바일 패턴에 가까워진다. 그러나 클라이언트 시크릿 관리, 사용자 upsert 위치(`CustomOAuth2UserService`), 이메일 중복 처리(#7), 딥링크 계약이 **전부** 함께 바뀐다. #14 의 범위를 훨씬 넘고, 지금 그 변경을 정당화하는 문제가 없다. 기각(보류).
3. **아무 기록도 남기지 않는다.** 지금 상태다. 조건부 결정("앱이 직접 말하게 되면 PKCE 가 필수")이 계약 각주에만 있어 검색되지 않는다. 기각.

### 결과

- 코드에 PKCE 파라미터를 넣지 않는다. 계약 문서 두 곳의 각주는 이 ADR 로 링크되는 요약으로 남는다.
- **트리거:** 앱이 공급자와 **직접** 말하도록 바꾸는 PR 은 이 ADR 을 `Superseded` 로 바꾸고 PKCE 를 필수로 넣는 새 ADR 을 추가한다. 그 PR 에서 함께 바뀌는 것: 클라이언트 시크릿의 위치, 사용자 upsert 지점, 딥링크 계약, `AuthCodeStore` 의 존재 이유.
- 위 세 장치 중 하나라도 약해지면 이 결정의 전제가 무너진다. 그래서 셋은 각각 독립된 테스트로 잠겨 있다 — `AuthCodeStoreTest`(1회성·만료가 서로 독립), `OAuthCodeExchangeServiceTest`(`state` 부재·불일치), `social_login_callback_test.dart`(앱쪽 대조).

---

## ADR-0010 — 소셜 로그인 공급자와 앱 세션 토큰 전략

- **상태**: 채택 (Accepted)
- **날짜**: 2026-08
- **관련**: Epic #2 · 이슈 #15 · #3 · #7 · #9 · #13 · #14 · ADR-0003(RDB 단일 저장소) · ADR-0009(PKCE)

### 맥락

M2(로그인) Epic 에서 **되돌리기 비싼 결정을 다섯 개** 내렸는데, 그 결정들이 전부 코드에만 남았다. 코드는 "무엇을 했는가" 를 말하지만 "무엇을 하지 않기로 했는가" 는 말하지 않는다. 그래서 안 한 결정(네이버·Redis)이 가장 먼저 잊힌다.

문서와 코드가 이미 서로 다른 말을 하고 있었다.

| 무엇 | 문서가 말한 것 | 실제 |
| --- | --- | --- |
| 소셜 공급자 | 로드맵 M2 는 "카카오/네이버" (5곳) | 앱 로그인 화면은 카카오·구글 둘만 띄운다. 네이버 버튼은 **#3 에서 내렸다** |
| 계약 enum | `parameters.Provider` 와 `User.provider` 가 `naver` 를 포함 | 같은 파일의 설명은 이미 "MVP 는 kakao·google" — **설명과 enum 이 서로 모순** |
| 사용자 테이블 | `schema.md`·`erd.md` 가 `app_user` 를 정의 | 실제 테이블은 `users` (`@Table(name = "users")`). `refresh_token` 은 양쪽 문서에 **0건** |

즉 결정 자체가 없는 것이 아니라, 결정이 **한 곳에 적혀 있지 않아서** 문서마다 다른 시점의 사실이 굳어 있었다. 이 ADR 은 그 다섯 결정을 한자리에 적고, 각각이 어느 파일에서 기계로 잠기는지까지 남긴다.

### 결정

**1. 소셜 공급자는 카카오·구글 둘이다. 네이버는 보류한다.**

계약(`docs/04-api/openapi.yaml`)의 `parameters.Provider` enum 과 `User.provider` enum, 그리고 코드의 `AuthController.SUPPORTED_PROVIDERS` 가 **같은 집합**이어야 한다. 세 곳에서 `naver` 를 뺐다.

> ⚠️ **그 셋만으로는 부족하다.** 앱이 여는 것은 우리 호환 래퍼(`GET /auth/oauth/{provider}`)가
> 아니라 Spring 의 진입점이다 — `social_login_service.dart` 가 `/oauth2/authorization/{provider}` 를
> 직접 연다. 즉 클라이언트 등록이 살아 있으면 `SUPPORTED_PROVIDERS` 를 좁혀도
> `/oauth2/authorization/naver` 가 그대로 열려 있고, 그 경로로 만들어진 계정의
> `GET /auth/me` 응답이 계약 enum 을 위반한다 — **계약이 지킬 수 없는 약속을 하는 상태**다.
>
> 그래서 `application-dev.properties`·`application-prod.properties` 의 네이버 클라이언트
> 등록과 매핑 파서(`NaverOAuth2User`)도 함께 걷어냈다. 되살리면
> `OAuthClientRegistrationsTest` 와 `CustomOAuth2UserServiceTest` 가 빨간불이 되므로,
> 이 ADR 을 먼저 고쳐야 되살릴 수 있다.

**2. JWT 의 `sub` 는 `users.id` 다.** 이메일도 소셜 ID 도 아니다.

카카오의 `account_email` 은 **선택 동의**라서 사용자가 거부하면 이메일이 오지 않고, 나중에 동의를 켜면 값이 생긴다(#7). 시간에 따라 나타났다 사라지는 값은 식별 키가 될 수 없다. 소셜 계정의 식별 키는 `(provider, social_id)` 쌍이고, 토큰이 싣는 주체는 그 행의 `users.id` 하나다.

**3. Refresh Token 은 JWT 가 아니라 불투명 랜덤 문자열 + MySQL 원장이다.**

`SecureRandom` 32바이트를 패딩 없는 Base64URL 로 적은 43자이고, 서버는 원문이 아니라 **SHA-256 해시**를 저장한다(`refresh_token.token_hash`). 회전(refresh 때 새 RT 발급 + 옛 RT 폐기)과 재사용 감지(폐기된 RT 가 다시 오면 그 사용자의 RT 전부 폐기)가 여기에 얹혀 있다(#9). **폐기는 삭제가 아니다** — 행을 남긴 채 `revoked_at` 을 찍는다.

**4. Redis(RT 검증 캐시 · 액세스 토큰 블록리스트)는 이번에 넣지 않는다.**

인증 상태의 진실은 MySQL 원장이다. Redis 는 그 원장의 대체가 아니라 캐시이고, 지금은 캐시가 값을 하지 못한다(→ 대안 5). ADR-0003 이 이미 "캐시(Redis)는 규모 확장 시 옵션" 이라고 정했고, 이 ADR 은 그것을 **인증 맥락에서 재확인**한다. 남은 작업 목록은 `backend/TODO/refresh-token-redis.md` 가 소유한다.

**5. 소셜 로그인 딥링크는 토큰이 아니라 1회용 코드를 싣는다.**

`heattrip://login-callback?code=<1회용 코드>&state=<앱이 만든 난수>` 다(#14). 코드는 우리가 만든 256bit 난수이고 TTL 60초·1회 소비다. 구현이 왕복 한 번만큼 복잡해지는 대가를 치르는 이유: 커스텀 스킴은 어느 앱이든 등록할 수 있고, URL 은 302 의 `Location` 헤더와 브라우저 히스토리에 남는다. 예전에는 그 채널로 1시간짜리 액세스 토큰과 14일짜리 refresh 토큰이 함께 나갔다.

> **PKCE 는 이 ADR 이 다루지 않는다.** 그 판단은 [ADR-0009](#adr-0009--소셜-로그인에-pkce-를-도입하지-않는다) 가 소유한다 — 백엔드가 공급자와 코드 교환을 수행하는 동안에는 `code_verifier` 를 검증할 주체가 없다는 내용이다. 계약 두 곳이 그 번호로 링크를 걸고 있으므로 여기서 다시 쓰지 않는다.

### 대안

**1. 네이버를 지금 켠다.** 기각(보류).

공급자를 하나 더 켜는 비용은 코드가 아니라 **운영과 데이터 모델**에 붙는다.

- 개발자센터 앱 등록·검수, 개인정보 제3자 제공 항목, 프로덕션 시크릿 관리가 하나씩 더 생긴다.
- 식별 키가 `(provider, social_id)` 이므로(#7) **같은 사람이 공급자를 바꾸면 다른 계정**이 된다. 이메일로 합치지 않기로 이미 정했기 때문에 병합은 자동으로 되지 않는다. 공급자가 셋이면 그 갈래가 세 개가 되고, MVP 에서 계정 병합 UX 를 감당할 수 없다.
- 얻는 것은 "네이버로만 가입할 수 있는 사람" 인데, 그 집합은 카카오도 구글도 없는 사람이다. 지금 그 크기를 측정할 방법이 없다. **측정되지 않은 이득을 위해 위 비용을 먼저 치르지 않는다.**

무엇보다 제품은 이미 두 공급자로 돌고 있었다 — 앱 로그인 화면은 **#3 에서 네이버 버튼을 내렸다.** 계약과 로드맵만 셋을 광고하고 있었다. 이 결정은 새로 좁히는 것이 아니라 이미 벌어진 일을 문서에 맞추는 것이다.

**2. 세 공급자를 계약 enum 에 남기고 코드만 좁힌다.** 기각.

계약이 "이 값을 보내도 된다" 고 광고하는데 서버가 400 을 주면, 계약만 보고 만든 클라이언트가 조용히 깨진다. 반대로 코드만 넓으면 계약에 없는 값이 302 로 통과한다. `docs/02-architecture/backend/auth.md` 가 이 불변식을 글로 적어 두었지만 글은 지켜지지 않았다 — 그래서 이번에 테스트로 옮겼다.

**3. JWT 의 `sub` 를 email 또는 소셜 ID 로 둔다.** 기각.

email 은 카카오 경로에서 null 일 수 있고(#7) 사용자가 바꿀 수도 있다. 소셜 ID 는 공급자마다 형식이 다르고 공급자가 바뀌면 같은 사람을 못 알아본다. `users.id` 는 우리가 발급하고 우리가 보증하는 유일한 불변 키다.

**4. Refresh Token 도 JWT 로 만든다.** 기각.

"JWT 면 DB 없이 된다" 는 것이 그대로 문제다. 서명만으로 검증되는 토큰은 **폐기할 수 없다.** 로그아웃·회전·재사용 감지는 전부 "이 토큰이 지금도 살아 있는가" 를 서버가 판정해야 성립하는데, 그 판정에는 상태가 필요하다. 상태를 어차피 둘 것이라면 토큰 안에 클레임을 넣을 이유가 없다 — 불투명 난수가 더 짧고, 유출됐을 때 알려주는 정보도 없다.

**5. Redis 를 지금 넣는다.** 기각(보류).

- 지금 배포 단위는 `backend/docker-compose.yml` 의 `app` 서비스 하나, 즉 **단일 인스턴스**다. 인스턴스 간에 공유할 상태가 없으므로 캐시가 주는 이득이 없고, 운영 요소만 하나 늘어난다.
- 액세스 토큰 블록리스트(`jti`)는 Redis 가 있어야 값을 하는데, 지금 AT 수명이 1시간이라 블록리스트가 줄이는 창이 **최대 1시간**이다. 그 대가로 모든 인증 요청에 조회가 1회 붙는다. MySQL 로 대신하면 그 조회가 DB 로 간다 — 더 나쁘다.
- 재사용 감지에 필요한 것은 캐시가 아니라 **영속 원장**이다(#9). Redis 를 넣어도 MySQL 원장은 남는다. 즉 Redis 는 지금 있는 것을 대체하지 않고 얹히기만 한다.

**6. 딥링크에 토큰을 그대로 싣는다(현행 유지).** 기각 — #14 가 걷어냈다. 이유는 결정 5 에 적었다.

### 결과

- **잠긴 곳.** 이 ADR 의 결정들은 산문이 아니라 테스트로 지켜진다.
  - `OpenApiAuthContractTest` — 계약의 `Provider`·`User.provider` enum 이 `[kakao, google]`(+`local`·`null`)인지, 그리고 **코드의 `AuthController.SUPPORTED_PROVIDERS` 와 같은 집합**인지. `naver` 를 어느 한쪽에 되돌리면 빨간불이다.
  - `DecisionLogTest` — 이 ADR 이 인덱스에 있고 앵커가 살아 있는지, 4개 절과 다섯 결정이 있는지.
  - `AuthSubjectContractSpecTest` — `sub` 가 `users.id` 라는 규약.
  - `RefreshTokenServiceTest`·`AuthTokenRefreshIntegrationTest` — 회전과 재사용 감지.
  - `AuthCodeStoreTest`·`OAuthCodeExchangeServiceTest`·`social_login_callback_test.dart` — 1회용 코드·`state` 대조.
- **아직 덮지 못한 것 — 네이버는 계약에서만 닫혔다.** 백엔드에는 네이버 클라이언트 등록(`application-dev.properties`·`application-prod.properties`)과 `CustomOAuth2UserService` 의 `naver` 분기·`NaverOAuth2User` 가 그대로 있다. 앱이 실제로 여는 것은 `GET /auth/oauth/{provider}` 래퍼가 아니라 스프링 시큐리티 자체 진입점 `/oauth2/authorization/{provider}` 이고(`social_login_service.dart`), 그 경로는 `permitAll` 이다. **따라서 `/oauth2/authorization/naver` 는 지금도 열려 있다.** 이 ADR 은 그 구멍을 닫지 않는다 — 닫는 일은 **#13** 이 소유한다(등록 제거 + 매핑 코드 제거 + `CustomOAuth2UserServiceTest` 의 네이버 블록 제거).
  - 매핑 코드를 이번에 지우지 않은 이유: 등록이 살아 있는 동안 그 분기는 **죽은 코드가 아니다.** 코드만 먼저 지우면 네이버로 들어온 요청이 매핑 예외로 죽는다 — 지금과 다른 실패지 닫힌 상태가 아니다. 등록과 코드는 같은 변경에서 함께 나가야 한다.
- **되돌리는 조건(트리거).**
  - 네이버를 켜려면: 이 ADR 을 갱신하고 계약 enum·`SUPPORTED_PROVIDERS` 를 함께 넓힌다. 한쪽만 넓히면 위 테스트가 막는다.
  - Redis 를 넣으려면: 인스턴스가 둘 이상이 되거나, AT 수명을 늘려 블록리스트의 창이 의미 있어질 때다. 그 시점에 `backend/TODO/refresh-token-redis.md` 의 목록을 실행하고 이 ADR 을 `Superseded` 로 바꾼다.
- 문서 정합도 함께 맞췄다: 로드맵 M2 의 "카카오/네이버" 5곳, `schema.md`·`erd.md` 의 `app_user` → 실제 테이블 `users`(+`refresh_token` 추가), 구현현황의 "로그인 ❌ 미구현".

---

## ADR-0011 — 채팅은 가족 그룹 종속이 아니라 범용 다중 방이다

- **상태**: 채택 (Accepted)
- **날짜**: 2026-08
- **관련**: M2.5 · M2.6 · M2.7 · M2.9 · 이슈 #20(로드맵) · #4(규약) · #21(테스트 정책) · #45 · #9(refresh_token 원장) · ADR-0003(RDB 단일 저장소) · ADR-0010(Redis 보류)

### 맥락

채팅은 그린필드가 아닙니다. **화면이 먼저 커밋돼 있고, 그 화면이 이미 데이터 모양을 정해 놨습니다.**

- `app/lib/v2/domain/pet.dart:437` 의 `kChatRooms` 는 **방이 둘입니다** — `우리 가족`(`tag: '가족'`, `isDefault: true`, `unread: 2`)과 `서울숲 산책 크루`(`tag: '산책 크루'`, `memberCount: 6`). 즉 화면은 "가족 채팅 하나"가 아니라 **여러 방**을 전제합니다.
- `app/lib/v2/screens/main_shell.dart:111` 이 네 번째 탭을 `채팅`으로 배선했고, `chat_list_screen.dart` 는 `kChatRooms` 를 그냥 순회하면서 각 방을 같은 화면(`FamilyChatScreen(title:, subtitle:, messages:)`)으로 넘깁니다. **방별 화면은 이미 범용입니다.** 방 종류는 `tag` 로만 갈립니다.
- 방 목록에는 **방별 미읽음 뱃지**가 붙습니다(`ChatRoom.unread`).

반대편에서 백엔드는 뒤처져 있습니다. 그것도 "덜 만들어진" 것이 아니라 **다른 모양으로 계획돼 있습니다.**

| 무엇 | 문서가 말하는 것 | 실제 |
| --- | --- | --- |
| `chat_message` | `docs/03-database/schema.md:454-478` 이 "가족 그룹 채팅"으로 정의 — `group_id BIGINT NOT NULL` + `fk_chat_group … REFERENCES family_group(id) ON DELETE CASCADE` + `fk_chat_user … REFERENCES users(id) ON DELETE CASCADE`, 커서는 `id` | `backend/mysql/init/01_schema.sql` 의 실제 `CREATE TABLE` **26개에 없습니다** |
| `family_group` | `schema.md:398-418` 에 `invite_code VARCHAR(12) NOT NULL` + `UNIQUE KEY uq_group_invite` | 같습니다 — **정본 스키마에 없습니다** |
| 방의 개수 | 그룹당 하나(`group_id` 가 NOT NULL 이라 가족 그룹 없는 방은 존재할 수 없음) | 화면은 이미 둘을 그립니다 |

그래서 이 ADR 이 하는 일은 **마이그레이션이 아니라 문서를 고쳐 쓰는 일입니다.** 표가 아직 태어나지 않았으니 지금 바꾸면 비용이 텍스트 수정이고, 태어난 뒤에 바꾸면 스키마 변경 + 발급 API 변경 + 참여 API 변경이 한꺼번에 옵니다. `schema.md:19` 가 "§3 이하는 아직 계획"이라고 스스로 밝히고 있어 지금 누구를 오도하지는 않습니다 — 그래서 "당장 폐기"가 아니라 **"만드는 커밋에서 함께 교체"** 입니다.

한 가지가 더 있습니다. 채팅은 이 저장소가 지금까지 만든 어떤 기능과도 다르게 **앱 스토어 심사 게이트를 끌고 옵니다.** 케어 공유(물/밥/산책 체크)에는 안 걸리는 것이 채팅에는 걸립니다. 그래서 안전 장치를 "나중에 여유 되면"으로 미룰 수 없고, 이 ADR 이 그 항목들까지 함께 적습니다.

### 결정

**1. 방 모델은 `chat_room` · `chat_room_member` · `chat_message` 세 장이고, `family_group` 은 FK 가 아니라 불투명 참조로 닿습니다.**

`chat_room` 이 `origin_kind`(`'FAMILY'` 같은 문자열)와 `origin_ref`(그 도메인의 id 를 문자열로) 한 쌍을 들고, `UNIQUE (origin_kind, origin_ref)` 를 겁니다. 가족 그룹이 방을 만들면 `('FAMILY', '<family_group.id>')` 한 행이 생기고, 산책 크루 방은 `origin_kind` 가 다를 뿐 같은 표에 삽니다.

왜 `group_id BIGINT NOT NULL` 이 아닌가 — 계획 DDL(`schema.md:461`)대로 가면 **가족 그룹이 없는 방을 만들 수 없습니다.** 그런데 화면에는 이미 그런 방이 있습니다(`서울숲 산책 크루`). 방 종류가 늘 때마다 nullable FK 가 하나씩 늘어나는 모양이 됩니다.

**멤버십 표는 `chat_room_member` 하나입니다. `group_member` 를 따로 만들지 않습니다.** 둘을 두면 "가족인데 방에 없는 사람" / "방에 있는데 가족이 아닌 사람" 이라는 상태가 생기고, 그걸 막는 코드를 영원히 씁니다. 강퇴·재입장 금지·차단이 전부 `chat_room_member` 에 붙으므로(→ 결정 6), 멤버십이 둘이면 강퇴가 어느 쪽인지를 매번 물어야 합니다. `family_group` 은 이름과 생성 시각만 듭니다.

**이 쌍을 ACL(Anti-Corruption Layer)이라고 부르지 않겠습니다.** ACL 은 두 컨텍스트 사이에 번역 계층을 두는 것이고, 여기 있는 것은 참조를 문자열로 바꾼 것뿐입니다 — 정확히는 "FK 없는 결합 완화"입니다(https://github.com/ddd-crew/context-mapping). 이름을 크게 부르면 없는 계층이 있는 줄 압니다.

**멤버 확인은 한 곳입니다.** 이 저장소에 `@PreAuthorize`·`hasRole`·`@Secured` 가 **0건**입니다(전수 grep). 컨트롤러마다 손으로 쓰면 메서드가 늘 때마다 한 곳씩 빠집니다 — `/api/curation/admin/**` 이 `.authenticated()` 하나에 걸려 있는 것과 같은 형태의 구멍입니다(#45). 서비스 경계에 `requireMember(roomId, userId)` 하나를 두고 모든 진입점이 그것을 지나가게 하며, **남의 방 id 로 403 이 나오는 통합 테스트**를 함께 넣습니다.

**2. 순서·델타·미읽음의 기준은 방별 `room_seq` 입니다. `id` AUTO_INCREMENT 를 커서로 쓰지 않습니다.**

계획 DDL 은 `id` 커서였습니다(`schema.md:456,477`). 이건 폴링과 함께 쓰면 **메시지를 영구히 잃습니다.** AUTO_INCREMENT 값은 INSERT 시점에 배정되지만 다른 세션에 보이는 것은 커밋 시점입니다. id 4 를 배정받은 트랜잭션이 아직 커밋 전인데 id 5 가 먼저 커밋되면, 그 순간 `afterId=5` 로 폴링한 클라이언트에게 **4 는 영원히 오지 않습니다.** 커서는 "내가 본 것보다 큰 것"만 묻지 되돌아가지 않기 때문입니다.

그래서 발급을 우리가 합니다.

```sql
UPDATE chat_room SET last_seq = LAST_INSERT_ID(last_seq + 1) WHERE id = ?;
SELECT LAST_INSERT_ID();
```

MySQL 이 문서화한 시퀀스 에뮬레이션 패턴입니다(https://dev.mysql.com/doc/refman/8.0/en/information-functions.html#function_last-insert-id). `SELECT … FOR UPDATE` 두 문장보다 락 보유 시간이 왕복 한 번만큼 짧고, 부수 효과가 더 중요합니다 — 이렇게 하면 **`chat_room.last_seq` 가 "발급기"이자 "미읽음 계산의 기준"** 둘 다가 되어, 두 값이 서로 다른 문장에서 움직여 어긋날 여지가 사라집니다. `room_seq` 와 `room.last_seq` 는 별개가 아니라 같은 컬럼입니다.

**seq 발급과 메시지 INSERT 는 하나의 트랜잭션입니다.** 발급만 짧은 별도 트랜잭션으로 떼는 최적화를 하지 않습니다 — 그 순간 위의 "4 를 영원히 못 보는" 시나리오가 그대로 돌아옵니다. **이 락은 성능이 아니라 커서의 무결성을 위한 것입니다.** 락은 DB 가 잡으므로 인스턴스가 몇 대든 같은 방의 발급은 직렬화됩니다(https://dev.mysql.com/doc/refman/8.0/en/innodb-locking-reads.html).

받침 셋을 같이 겁니다.

- `UNIQUE (room_id, room_seq)` — 이 저장소는 확인-후-쓰기를 늘 DB 유니크 제약으로 받쳐 왔습니다(`users(provider, social_id)`·`bookmarks(user_id, content_id)`·`card_reaction(card_id, user_id, reaction_type)`). 그리고 `FOR UPDATE|@Lock|LockModeType|@Version|PESSIMISTIC` 전수 grep 이 **0건**이라 `room_seq` 가 이 저장소의 **첫 비관적 락**입니다. 처음 쓰는 도구는 제약으로 받쳐 둡니다 — 발급이 틀렸을 때 조용한 중복 대신 즉시 오류가 납니다.
- **락 순서는 항상 `chat_room` → `chat_room_invite` → `chat_room_member` → `chat_message`.** (이 문장은 처음에 `chat_room` → `chat_room_member` 두 표만 적었습니다. #75 가 초대 잠금을, #78 이 `chat_message` 를 들여오면서 넓어졌습니다 — **정본은 `ChatRoomRepository#lockForMemberChange` javadoc** 이고 `schema.md` §12 가 같은 표를 적습니다.) 전송은 `chat_room`(발급) → `chat_message`(INSERT), 참여는 앞의 셋, 읽음 처리는 `chat_room_member` 만 건드립니다. 넷 중 둘 이상을 잡는 경로는 전부 이 순서를 따르므로 서로 같은 방향의 부분열이고 순환이 없습니다. 반대 순서로 잡는 경로를 하나라도 만들면 그 순간 데드락이 가능해집니다(https://dev.mysql.com/doc/refman/8.0/en/innodb-deadlocks.html). 그리고 **락을 쥔 트랜잭션 안에서 외부 호출(푸시·S3·LLM)을 하지 않습니다** — `innodb_lock_wait_timeout` 기본값이 50초라, 느린 외부 호출 하나가 그 방의 모든 전송을 최대 50초 막습니다.
- `client_msg_id` + `UNIQUE (room_id, client_msg_id)`. 전송은 재시도 가능한 HTTP POST 인데(→ 결정 5) 앱의 `AuthedClient` 경유 호출에 타임아웃이 없어서(`app/lib/core/net/authed_client.dart:290`), 사용자가 답답해 다시 누르면 같은 메시지가 두 번 들어갑니다. 채팅은 중복이 눈에 바로 보이는 도메인입니다. 키는 순수 Dart 로 만듭니다(`Random.secure()` 16바이트 → base64url) — `uuid` 패키지를 넣지 않는 이유는 결정 5 에 적었습니다.

**3. 미읽음은 세지 않고 뺍니다 — `room.last_seq − member.last_read_seq`.**

읽음 상태를 메시지×사용자 표로 만들지 않습니다. 그 표는 방 하나에 메시지 N, 멤버 M 이면 행이 N×M 으로 늡니다. 뺄셈은 정수 둘이고, 방 목록 화면이 필요로 하는 것도 정확히 그 정수 하나입니다(`ChatRoom.unread`).

두 가지를 서버가 조입니다.

- `UPDATE chat_room_member SET last_read_seq = GREATEST(last_read_seq, :seq)` — 읽음 보고는 재시도나 백그라운드 복귀로 **순서가 뒤집혀 도착**합니다. 뒤늦게 온 작은 값이 큰 값을 덮으면 이미 읽은 메시지가 다시 미읽음으로 뜹니다.
- 상한도 함께 `LEAST(:seq, room.last_seq)`. 잘못된 큰 값이 오면 뺄셈이 **음수**가 됩니다.

이 결정이 "채팅은 Redis 를 요구하지 않는다"(→ 결정 11)의 첫 번째 근거입니다.

**4. chat 경계 밖으로 나가는 FK 는 0개입니다.**

`chat_*` 어느 표도 `users`·`family_group`·`dog` 에 FK 를 걸지 않습니다. `chat_message.sender_user_id BIGINT NOT NULL`(FK 없음), `chat_room_invite.created_by`(FK 없음), `chat_report`·`chat_block` 의 사용자 id 도 전부 값만 듭니다.

전례가 있습니다 — **#9 의 `refresh_token.user_id` 가 같은 판단이었습니다.** 그리고 `emotion_card.handle`·`card_comment.handle` 이 이미 "FK 없이 값 + 스냅샷"으로 돌고 있습니다(`01_schema.sql`).

계획 DDL 을 그대로 두면 안 되는 이유가 하나 더 있습니다. `schema.md:470` 의 `fk_chat_user … ON DELETE CASCADE` 는 **한 사람이 탈퇴하는 순간 그 사람이 가족방에 쓴 말을 전부 증발시킵니다.** 조사한 다섯 앱 중 그렇게 하는 곳이 하나도 없습니다(→ 결정 7).

**대가는 정직하게 적습니다. DB 가 막아 주던 것을 우리가 막아야 합니다.**

- `ChatBoundaryArchitectureTest` 로 "chat 패키지의 엔티티에 chat 밖을 가리키는 연관이 0개"를 강제합니다.
- `UNIQUE (origin_kind, origin_ref)` 로 같은 그룹에 방이 둘 생기는 것을 DB 가 막습니다.
- **고아 방 정리 경로를 함께 만듭니다.** `family_group` 이 사라져도 방은 남고 DB 는 막지 않습니다. #9 때 `RefreshTokenPurgeScheduler` 를 만든 것과 같은 이유이고, 멱등한 DELETE 라 인스턴스가 늘어도 안전한 것도 같습니다.

**5. 지금은 폴링(`afterSeq`)이고, 소켓은 날짜가 아니라 트리거로 엽니다.**

폴링 단계에 **새 의존성이 0개**입니다. `backend/build.gradle` 과 `app/pubspec.yaml` 을 열어 확인했습니다. 백엔드는 `web`·`data-jpa`·`validation`·`security`·`mysql-connector-j`·`actuator`+`micrometer-registry-prometheus`, 테스트는 `testcontainers:mysql` 이 이미 있고 `room_seq` 발급도 표준 JPA/JDBC 로 됩니다. 앱은 `Timer.periodic`(`dart:async`, 이미 `walk_tracking_screen.dart:69` 에서 사용)과 `http: ^1.4.0` + `AuthedClient` 로 끝납니다. **새로 들어오는 것은 표 몇 장과 엔드포인트 몇 개뿐입니다.** 멱등키 때문에 `uuid` 를 넣을 뻔했지만 넣지 않습니다 — "신규 의존성 0" 이라는 사실이 UUID 형식보다 값집니다.

같이 거는 것 둘. ① 폴링 경로를 `ApiRateLimitFilter.resolveRule`(`backend/.../security/ApiRateLimitFilter.java:72-119`)의 **새 버킷으로 등록**합니다 — 그 표에 없는 경로는 지금 무제한이고(`POST /auth/signup` 이 정확히 그렇게 빠져 있습니다), 폴링은 사용자당 상시 트래픽이라 빠뜨리면 한도 체계 전체가 무의미해집니다. ② 앱 폴링 호출에 `.timeout()` 을 답니다 — 응답 없는 서버에서 폴링 future 가 쌓입니다.

**소켓은 "실측이 폴링의 부족을 보여줄 때" 엽니다.** 하나라도 넘으면 착수합니다.

- `chat.poll{result=empty}` 비율이 **0.5 밑**(폴링이 거의 매번 새 메시지를 물어 옴 → 간격을 줄여야 하는데 줄이면 부하가 늚)
- `/chat/**` p95 > **500ms** 가 5분 지속
- `hikaricp_connections_pending` > 0 이 **1분 지속** — 이건 동시에 **롤백 조건**입니다. 채팅 하나가 커넥션 풀을 굶기면 앱 전체가 느려집니다.

넣는 날의 모양도 지금 정합니다 — **받기만 소켓, 보내기는 HTTP.** 한 방향만 필요하면 구독·수신확인·목적지 라우팅이 잉여이고, 전송이 HTTP 로 남아야 결정 2 의 멱등키와 rate limit 이 그대로 삽니다. 소켓이 끊기면 폴링으로 되돌아갑니다.

**그리고 nginx 가 코드보다 먼저 막힙니다.** `backend/docs/operations/public-operation-transition/nginx-production-template.conf` 의 location **6개(27·38·49·60·71·82행)가 전부 `proxy_set_header Connection "";`** 이고, `Upgrade` 헤더도 `map $http_upgrade $connection_upgrade` 블록도 없습니다. 이 상태에서 101 Switching Protocols 은 업스트림에 닿지 못합니다. `proxy_read_timeout` 은 120s 라 STOMP 기본 하트비트(10초)보다 충분히 길어 그대로 둡니다. **SockJS 폴백으로 이걸 덮지 않습니다** — nginx 가 고장 난 상태를 감춥니다.

**6. 신고·차단·강퇴를 채팅과 같은 마일스톤에 넣습니다. 이건 제품 판단이 아니라 스토어 심사 요건입니다.**

- **Apple App Store Review Guideline 1.2** — UGC·소셜 기능이 있는 앱은 넷을 반드시 갖춰야 합니다: 부적절한 내용을 거르는 방법 · 신고 창구와 적시 대응 · 문제 사용자 차단 · **공개된 연락처**. (https://developer.apple.com/app-store/review/guidelines/)
- **Google Play User Generated Content 정책** — 인앱 신고·차단을 제공해야 하고, "direct messaging 같은 1:1 상호작용 기능"에는 **차단이 필수**이며, **UGC 를 만들기 전에 약관 동의**를 받으라고 요구합니다. (https://support.google.com/googleplay/android-developer/answer/9876937)

국내 법령은 이걸 요구하지 않습니다. 정보통신망법 제44조의2 는 대상이 "일반에게 공개를 목적으로 제공된 정보"라 초대코드 전용 비공개 방이 빠지고, 전기통신사업법의 사전조치의무사업자 기준(시행령 제30조의6: 전년 매출 10억원 또는 일평균 이용자 10만명)에도 해당하지 않습니다. **그래서 "법적으로는 안 해도 되지 않나"는 통하지 않습니다 — 스토어에서 막힙니다.**

세부는 여섯 앱의 공통 동작을 그대로 따릅니다.

- **신고의 단위는 메시지이고 최대 3개**입니다(카카오 1:1·그룹 채팅방과 같은 수 — https://cs.kakao.com/helps_html/1073199392, https://cs.kakao.com/helps_html/1073199393). 방 단위 신고는 넣지 않습니다.
- **서버에 스냅샷을 남깁니다.** 고른 메시지의 `room_id`·`room_seq`·`sender_id`·**본문 사본**·`created_at`·`content_type` 을 복사하고, **앞뒤 각 5개의 `room_seq` 범위**를 함께 기록합니다. 원본 참조만 하면 지워졌을 때 판단이 불가능합니다 — 왓츠앱이 본문뿐 아니라 전송 시각과 유형까지 받는 이유이고(https://faq.whatsapp.com/1142481766359885), 라인이 고른 메시지 ± 앞뒤 9건을 함께 보내는 이유입니다(https://help.line.me/line/smartphone?contentId=20000298&lang=ja). 여성가족부의 랜덤채팅앱 고시가 최소 안전장치로 "대화 저장"을 꼽는 것도 같은 이야기입니다(우리는 랜덤 매칭이 아니라 직접 적용 대상은 아닙니다 — https://www.korea.kr/briefing/policyBriefingView.do?newsId=148880823).
- **신고자는 익명이고 피신고자에게는 아무 알림도 가지 않습니다.** 왓츠앱·카카오·라인·디스코드 넷 다 문서에 명시합니다(https://discord.com/safety/360044103651-reporting-abusive-behavior-to-discord).
- **신고와 차단·나가기를 한 화면에 둡니다.** 신고만 하고 아무 일도 안 일어나는 앱은 없습니다. **다만 자동 차단은 하지 않습니다** — 카카오는 자동 차단이고 "신고 후에는 신고를 취소할 수 없습니다"라고 경고까지 답니다(https://cs.kakao.com/helps_html/1073199401). 가족방에서 그건 되돌릴 수 없는 사고입니다. 체크박스로 두고 기본값은 꺼 둡니다.
- **차단은 원래 1:1 전용이고 그룹에는 통하지 않습니다.** 왓츠앱이 도움말에 문장으로 적어 뒀습니다 — 차단해도 같이 있는 그룹에서는 서로의 메시지가 보이고, 그룹은 차단 자체가 안 됩니다(https://faq.whatsapp.com/414631957536067). 카카오·라인도 같습니다. **여기서 한 곳만 벗어납니다**: 우리 방은 초대코드 전용이고 사용자에게 방이 둘뿐이라 "나가라"가 답이 되지 않습니다. `chat_block(blocker_id, blocked_id)` 한 장을 두고 그 사람의 **과거·미래 메시지를 모두 접어서** 내려줍니다(카카오 오픈채팅의 "가리기"와 같은 동작). **삭제하지 않습니다** — 다른 사람 화면에는 그대로 남습니다.
- **강퇴는 방장(`chat_room_member.role = OWNER`)만** 합니다. 멤버 행을 **지우지 말고** `removed_at`·`removed_by` 를 찍습니다 — 미읽음이 그 행의 `last_read_seq` 뺄셈이라(결정 3) 행을 지우면 되돌릴 수 없습니다. **강퇴당한 사람의 메시지는 남깁니다.** 지우면 신고 근거가 사라집니다(디스코드도 "최근 N일 삭제" 옵션을 kick 이 아니라 ban 에만 붙였습니다).
- **강퇴 = 재입장 금지입니다.** 초대코드를 다시 받아도 못 들어오고, 방장이 나중에 풀 수 있습니다. 카카오 오픈채팅이 "내보내기 + 재입장 차단"이고, 라인 오픈챗은 이걸 **12.9.0 에서 나중에 따로 붙였습니다**(https://openchat-jp.line.me/other/notice_block_left_abusers) — "내보냈는데 링크로 다시 들어온다"가 실제로 생기는 문제라는 뜻입니다.
- **설정 화면 하단에 운영자 연락처를 고정**하고, **채팅 첫 진입에 이용약관·운영정책 동의**를 받습니다. 각각 Apple 1.2 의 네 번째 항목과 Google Play 의 "UGC 생성 전 동의" 요구입니다. 빼면 심사에서 막힙니다.

**7. 탈퇴한 사용자의 메시지는 남기고, 이름만 "알 수 없음"으로 바꿉니다.**

`chat_message` 는 `sender_user_id BIGINT NOT NULL`(FK 없음, 결정 4)과 **`sender_name VARCHAR(255) NOT NULL`(작성 시점 `users.nickname` 스냅샷)** 을 함께 듭니다. 폭은 `users.nickname varchar(255)` 와 같게 맞추고, 모양은 `emotion_card.handle`·`card_comment.handle` 이 이미 쓰는 것과 같습니다.

응답의 `senderName` 규칙을 여기서 고정합니다 — **`users` 에 있으면 현재 닉네임, 없으면(탈퇴) "알 수 없음"** 입니다. **"익명"은 쓰지 않습니다**: `feed_screen.dart:132` 와 `together_feed.dart:192,548` 에서 그 단어가 이미 "이름을 안 붙인 것"을 뜻하고 있어, 여기에 두 번째 뜻을 얹으면 화면 두 곳이 서로 다른 말을 하게 됩니다. `senderAvatarUrl` 은 null 로 내려보냅니다 — 앱의 `_avatar(name)`(`family_chat_screen.dart:171,206`)이 이름 첫 글자로 아바타를 그리므로 앱은 고칠 것이 없습니다.

레퍼런스가 한 방향입니다. 슬랙은 계정을 비활성화해도 "Messages and files you've sent won't be deleted" 라고 적고(https://slack.com/help/articles/203953146-Deactivate-your-Slack-account), 디스코드는 계정 삭제 시 식별정보만 지우고 나머지는 익명화한 채 계속 보여준다고 적습니다(https://discord.com/privacy — 보존 기간 문서는 직접 fetch 가 403 이라 검색 결과 스니펫으로만 확인했습니다). 카카오는 탈퇴 시 **본인 계정에서** 채팅 목록과 대화 내용을 지우는 것이지 상대 방에서 지우는 것이 아닙니다(https://cs.kakao.com/helps_html/1073209556?locale=ko).

**따라오는 정합 작업을 같이 적습니다. 이걸 안 하면 문서가 거짓말을 합니다.**

- `account_delete_screen.dart:66,122` 의 "모든 데이터가 삭제되며 복구할 수 없습니다" 를 고칩니다. 채팅 본문을 남기기로 한 이상 지금 문구는 사실이 아닙니다.
- `app/assets/terms/privacy_ko.md` 3항(보유 및 파기)에 한 줄 — 본문은 남고 발신자 식별정보는 파기하며 표시가 "알 수 없음"으로 바뀐다는 것. 개인정보 보호법 제21조의 파기 의무는 **식별정보**에 걸립니다.
- `SocialService.mapCard`/`mapComment` 가 `users` 를 보지 않아 커뮤니티 카드·댓글에 탈퇴자 닉네임이 계속 뜹니다. 페이지의 `user_id` 집합을 한 번 조회해(`MAX_LIMIT` 100 이라 조회 1회) 없는 id 의 `handle` 을 "알 수 없음"으로 바꿉니다. **안 하면 탈퇴 정책이 채팅과 커뮤니티에 두 개가 됩니다.**

**8. 초대코드는 별도 표에 두고, 유효기간·사용횟수·회수를 처음부터 갖춥니다.**

`chat_room_invite(id, room_id, code, created_by, expires_at, max_uses, used_count, revoked_at, created_at)` 에 `UNIQUE (code)`. `expires_at` NULL 은 무기한, `max_uses` NULL 은 무제한입니다.

왜 `family_group.invite_code`(`schema.md:406`)가 아닌가 — 그건 **그룹당 코드 하나가 영구히 사는 모양**입니다. 만료·사용횟수·폐기를 걸 자리가 없고, 코드를 바꾸려면 그룹 행을 UPDATE 해야 해서 **누가 언제 발급했는지가 남지 않습니다.** 조사한 여섯 앱 중 초대를 그룹 행의 컬럼 하나로 둔 곳이 없습니다.

기본값은 **7일 · 사용 횟수 무제한**입니다. 디스코드 API 가 `max_age` 기본 86400·범위 0~604800(0=never), `max_uses` 기본 0(무제한)이고(https://docs.discord.com/developers/resources/channel), 클라이언트 UI 기본은 7일입니다(https://support.discord.com/hc/en-us/articles/208866998-Invites-101 — 직접 fetch 가 403 이라 검색 색인이 보여준 본문으로 확인했습니다). 슬랙은 "Each invite link is active for 30 days, and can be used by up to 400 people" 로 다른 값을 쓰지만(https://slack.com/help/articles/201330256-Invite-new-members-to-your-workspace), 가족 초대는 한 번 보내고 곧 쓰므로 짧은 쪽을 택합니다. 무기한은 컬럼으로 가능하되 기본값으로 쓰지 않습니다.

**회수·재발급이 1단계입니다.** 방장이 재발급하면 **이전 코드는 즉시 무효(`revoked_at`)이고 기존 멤버는 그대로 남습니다** — 왓츠앱 Reset link, 텔레그램 revoke(https://core.telegram.org/api/invites), 디스코드 초대 삭제가 전부 같은 동작입니다. 이게 코드가 유출됐을 때의 유일한 대응 수단입니다. 폐기한 `code` 는 UNIQUE 라 재사용하지 않습니다(디스코드도 삭제한 초대 코드는 재생성되지 않습니다). 가입 승인제는 2단계로 미룹니다.

`created_by` 에 FK 를 걸지 않는 것은 결정 4 그대로입니다.

**9. 만 14세 미만은 방 생성과 초대코드 참여를 막고, 채팅 진입 시점에 법정대리인 동의를 확인합니다.**

**개인정보 보호법 제22조의2** 는 만 14세 미만 아동의 개인정보를 처리하려 동의를 받아야 할 때 법정대리인의 동의를 받고 **동의했는지 확인**하도록 합니다(https://casenote.kr/법령/개인정보보호법/제22조의2). 그리고 `users.age_group enum('OVER14','UNDER14')` 이 `01_schema.sql:395` 에 **이미 실재합니다.** 값을 들고 있으면서 아무 데도 쓰지 않던 컬럼인데, **채팅을 켜는 시점이 이 확인을 해야 하는 지점입니다.** 국내 법령이 초대코드 전용 비공개 채팅에 요구하는 최소치는 사실상 이것 하나입니다.

게이트를 거는 자리는 방 안이 아니라 **모르는 사람과 연결되는 지점**입니다 — 방 생성과 초대코드로 새 방 참여를 막고, **가족방(`origin_kind` 가 가족)만 예외로 허용**합니다. 카카오의 미성년자 보호조치가 정확히 "오픈채팅방 생성 및 신규 참여 불가"이고 방 안 대화는 건드리지 않습니다(https://cs.kakao.com/helps_html/1073202354). 여섯 앱을 겹쳐 봐도 **닫힌 방 안에서 미성년자에게 다르게 동작하는 앱을 하나도 찾지 못했습니다.** 가족은 이미 법정대리인이 있는 관계라 예외로 두는 것이 자연스럽습니다.

한 가지 다릅니다 — **카카오는 신청제이고 우리는 자동입니다.** 카카오는 본인·법정대리인이 신청해야 보호조치가 걸립니다(https://talksafety.kakao.com/policy/usersafety/protectminor). 우리는 `age_group` 을 이미 들고 있고 신청 창구를 운영할 여력이 없습니다.

**확인하지 못한 것**: 구 정보통신망법 제23조의2 에서 개인정보 보호법 제22조의2 로의 이관 관계 자체는 조문으로 확인하지 못했습니다. 현행 조문이 개인정보 보호법 제22조의2 에 있다는 것만 확인했습니다.

**10. 사용자당 방 개수에 상한을 두지 않습니다. 플랜은 `ChatLimits` 인터페이스 하나로만 대비합니다.**

방 개수 상한을 두는 곳은 디스코드(가입 서버 100, Nitro 200 — https://discord.com/nitro)와 텔레그램인데, 디스코드의 숫자는 **클라이언트 성능** 때문이지 과금 설계에서 출발한 것이 아닙니다. 우리에게는 지금 그 제약이 없습니다. **방 정원은 50명**으로 정합니다 — 카카오 3,000·라인 500 은 우리 용도와 무관하고(카카오 관계자도 정원 선정에 "특별한 이유는 없다"고 했습니다 — https://www.mediatoday.co.kr/news/articleView.html?idxno=204671), 이미 만들어진 화면이 3명·6명입니다.

**지금 만들지 않는 것부터 적습니다.** `users.plan` 컬럼(값이 하나뿐인 컬럼은 나중에 어차피 지웁니다), `plan`/`plan_feature`/`user_entitlement` 표, 기능 플래그 시스템, 결제 SDK — 넷 다 만들지 않습니다. `01_schema.sql` 26개 표에 plan·subscription·tier·entitlement 가 0건이고 이 상태를 유지합니다. 결제 SDK 는 넣는 순간 구독 복원·가격 표시·해지 경로 같은 심사 항목이 따라옵니다.

대신 한도를 한 곳에 모읍니다.

```java
public interface ChatLimits {
    int maxMembersPerRoom(long userId);
    Duration inviteTtl(long userId);
    Integer maxInviteUses(long userId);   // null = 무제한
}
```

**지금 구현체는 인자를 무시하고 상수를 돌려줍니다.** 요점은 시그니처가 처음부터 사용자 기준이라는 것, 그래서 **호출부가 플랜을 모른다는 것**입니다. 나중에 이 구현체 하나만 DB 를 읽게 바꾸면 호출부는 그대로입니다. 텔레그램이 `channels_limit_default`/`channels_limit_premium` 쌍을 `help.getAppConfig` 로 클라이언트에 내려주는 것(한도가 코드가 아니라 서버 데이터 — https://core.telegram.org/api/premium), 스트라이프 Entitlements 가 플랜 이름 대신 `lookup_key` 로 검사하라는 것(https://docs.stripe.com/billing/entitlements.md)이 같은 이유입니다. 기능 플래그로 대신하지 않는 것도 여기서 갈립니다 — 플래그는 코드의 상태라 단명하고, entitlement 는 계약의 상태라 플랜만큼 오래 삽니다. 둘을 같은 통에 넣으면 나중에 **지워야 할 것과 지우면 안 될 것이 섞입니다.**

**한도 위반 응답 코드도 지금 정합니다** — `ROOM_MEMBER_LIMIT`(409) · `INVITE_EXPIRED`(410) · `INVITE_REVOKED`(410) · `INVITE_USES_EXHAUSTED`(409). 나중에 유료 유도 화면이 붙을 분기점이라 앱이 문자열이 아니라 코드로 갈라야 합니다. **봉투를 새로 만들지 않습니다** — `ApiRateLimitFilter` 가 이미 `GlobalExceptionHandler.ErrorResponse`(`{error:{code,message,traceId}}`)를 그대로 쓰고 앱이 `error.code` 로 분기합니다. 사본을 만들면 한쪽만 낡습니다.

**대가는 인터페이스 하나와 표 하나**입니다. 상수 세 개면 될 일에 간접층을 씌우는 값이고, 치르는 이유는 표가 아직 없는 지금이 가장 싼 시점이기 때문입니다.

**11. 채팅은 Redis 를 요구하지 않습니다.**

이 문장을 명시적으로 적습니다. **안 하기로 한 결정이 가장 먼저 잊히기 때문입니다** — ADR-0010 이 쓰인 이유가 그것이고, 다음에 이 문서를 여는 사람은 "채팅 = Redis" 통념을 들고 옵니다.

근거는 앞의 결정들입니다. 미읽음은 정수 뺄셈이라 캐시할 것이 없고(결정 3), 최근 메시지 조회는 `(room_id, room_seq)` 인덱스의 끝 범위 스캔이며(결정 2), 폴링 부하는 적응형 간격·ETag 조건부 요청·전용 rate limit 버킷으로 풉니다(결정 5). 그리고 **폴링 단계에서 새로 들어오는 의존성이 0개**입니다.

**ADR-0010 을 뒤집지 않습니다.** 그 ADR 의 되돌리기 조건은 "인스턴스가 둘 이상이 되거나, AT 수명을 늘려 블록리스트의 창이 의미 있어질 때" 인데, 채팅은 이 둘 중 어느 것도 건드리지 않습니다. 상태는 `채택` 그대로입니다.

**바뀌는 것은 하나입니다 — 옮길 항목의 개수.** ADR-0010 은 Redis 를 "RT 검증 캐시 + AT 블랙리스트"라는 인증 맥락에서만 기각했는데, 이제 소비자가 하나 더 생겼습니다. 인스턴스를 2대로 늘리는 날 함께 옮겨야 할 것이 **네 개**입니다: `AuthCodeStore` · rate limit 카운터 · Security 인가요청 저장소 · **소켓 팬아웃**. 적을 자리는 이 ADR 도 ADR-0010 본문도 아니라 **`backend/TODO/refresh-token-redis.md`** 입니다 — ADR-0010 이 그 파일을 되돌리기 목록의 소유자로 명시했기 때문입니다. 소유 관계를 스스로 어기지 않습니다.

**폴링 단계에서 인스턴스 지역 상태를 만들지 않습니다.** 그러려면 셋을 범위에서 빼야 합니다 — **타이핑 표시 · 온라인/접속 표시 · 인메모리 미읽음 캐시.** 셋 다 "화면에 있으면 예쁜데 서버에 상태를 만드는" 것들입니다. 소켓 단계는 다릅니다 — WebSocket 세션 자체가 인스턴스 지역 상태이고, 구독자가 붙은 인스턴스와 전송 HTTP 를 받은 인스턴스가 다르면 메시지가 안 갑니다. **그때가 ADR-0010 이 보류한 Redis 를 되살리는 결정입니다.** 그러니 소켓을 여는 날의 작업 목록에 이 항목을 처음부터 넣어 둡니다.

### 대안

**1. 강의 자료의 5테이블 범용 방 + STOMP + Redis pub/sub 구성을 그대로 따릅니다.** 기각(일부만 채택).

출발점으로 삼은 것은 맞습니다. "방을 도메인에서 떼어 범용으로 둔다" 는 뼈대는 그 자료에서 가져왔고, 그게 우리 앱 화면과 이미 같은 모양이었습니다(`app/lib/v2/domain/pet.dart:437` 의 `kChatRooms` 가 '우리 가족'(`isDefault`)과 '서울숲 산책 크루' 둘, `tag` 로 방 종류를 나눕니다). 그런데 나머지 셋은 우리 상황에서 값을 하지 못합니다.

- **테이블 다섯 장 중 둘을 안 만듭니다.** 읽음 표는 아래 4번에서, 첨부 표는 지금 보낼 파일이 없어서 뺍니다. 남는 것이 `chat_room` · `chat_room_member` · `chat_message` 셋입니다.
- **STOMP 와 Redis pub/sub 는 인스턴스가 여러 대라는 전제 위에 서 있습니다.** 우리 배포 단위는 `backend/docker-compose.yml` 의 `app` 서비스 하나입니다. 단일 인스턴스에서 simple broker 는 in-JVM 루프백이라 이득이 정확히 0이고, pub/sub 은 자기 자신에게 보냈다가 자기가 받는 일이 됩니다.
- 그리고 **그 조합 자체가 성립하지 않습니다.** Spring 레퍼런스(`web/websocket/stomp/handle-broker-relay`)가 `enableStompBrokerRelay` 의 대상으로 드는 것은 RabbitMQ 와 ActiveMQ 이고 **Redis 는 없습니다** — Redis 가 STOMP 를 말하지 못하기 때문입니다. 같은 문서가 simple broker 를 "not suitable for clustering" 이라고 적습니다. "STOMP + Redis" 로 가려면 simple broker 를 두고 릴레이를 **직접 짜야** 합니다. 이건 의존성 한 줄이 아닙니다.

일반적으로 옳은 구성이라는 것과 **지금 우리 배포에서 값을 한다는 것**은 다른 말입니다.

**2. 채팅을 가족 그룹에 종속시킨 채로 둡니다.** 기각.

이미 커밋된 계획 DDL 이 그 모양입니다 — `docs/03-database/schema.md:459-471` 의 `chat_message` 가 `group_id BIGINT NOT NULL` + `CONSTRAINT fk_chat_group ... REFERENCES family_group (id) ON DELETE CASCADE` 를 들고, `roadmap.md:105` 와 이슈 #20 의 표가 `GET|POST /api/groups/{groupId}/messages` 를 적습니다. 그룹당 채팅 하나라는 전제입니다.

**그 전제는 이미 깨져 있습니다.** 앱이 방을 둘 들고 있고 그중 하나('서울숲 산책 크루')는 가족이 아닙니다. `main_shell.dart:111` 에서 채팅은 이미 1급 탭입니다. 종속을 유지하면 산책 크루 방을 붙이는 날 `chat_message.group_id` 의 의미를 바꾸는 마이그레이션이 옵니다 — 그때는 데이터가 들어 있습니다. 지금은 `01_schema.sql` 에 `chat_message` 도 `family_group` 도 **없어서** 마이그레이션이 아니라 문서를 고쳐 쓰는 일입니다. **가장 싼 시점입니다.**

그래서 방과 그룹을 불투명 쌍(`origin_kind`/`origin_ref`)으로만 잇고 `UNIQUE(origin_kind, origin_ref)` 로 같은 그룹에 방이 둘 생기는 것을 DB 가 막게 했습니다. 이건 #9 에서 `refresh_token.user_id` 에 FK 를 안 건 것과 같은 계열입니다.

**3. 커서를 `id` AUTO_INCREMENT 로 둡니다.** 기각. **이 결정이 이번에서 가장 되돌리기 비쌉니다.**

계획 DDL 이 `id` 를 커서로 쓰고 있고, 흔한 선택입니다. 그런데 AUTO_INCREMENT 값은 **INSERT 시점에 배정되고 커밋 시점에 보입니다.** 두 시점이 다릅니다. id 4 를 받은 트랜잭션이 아직 커밋 전인데 id 5 가 먼저 커밋되면, 그 순간 `afterId=5` 로 폴링한 클라이언트는 **메시지 4 를 영영 못 봅니다.** 폴링 커서는 "내가 본 것보다 큰 것" 만 묻기 때문에 되돌아가지 않습니다. 실패가 조용하고, 재현이 안 되고, 데이터로 남지도 않습니다.

그래서 방별 `room_seq` 를 씁니다. 그리고 **같은 함정을 seq 에서도 피하려면 조건이 하나 붙습니다** — seq 발급과 메시지 INSERT 가 **하나의 트랜잭션**이어야 합니다. 발급만 짧은 별도 트랜잭션으로 떼는 최적화를 하면 id 커서와 똑같은 구멍이 생깁니다. 이 락은 성능이 아니라 **커서의 무결성**을 위한 것입니다.

**4. 메시지별 읽음 테이블(`chat_message_read`)을 둡니다.** 기각.

누가 어느 메시지를 읽었는지 행으로 남기면 "1" 표시(안 읽은 사람 수)까지 갈 수 있습니다. 대가가 큽니다 — 행이 **메시지 × 멤버**로 늘고, 미읽음 개수를 낼 때마다 COUNT 가 붙습니다. 지금 우리 미읽음은 `room.last_seq − member.last_read_seq` **뺄셈**이고, 그 두 컬럼은 방 목록 조회가 **이미 읽어 오는 값**입니다. 추가 쿼리가 0입니다.

읽음 표가 필요해지는 날의 트리거는 "읽은 사람이 누구인지를 화면에 그린다" 입니다. 그날 표를 추가하는 것은 뺄셈을 유지한 채로도 됩니다 — 지금 넣으면 쓰지도 않는 행을 메시지마다 곱해서 쌓습니다.

**5. 지금 STOMP(웹소켓)를 넣습니다.** 기각(보류, M2.9 로).

**코드보다 nginx 가 먼저 막힙니다.** `backend/docs/operations/public-operation-transition/nginx-production-template.conf` 의 location **6개(27·38·49·60·71·82행)가 전부 `proxy_set_header Connection "";`** 이고, `Upgrade` 헤더도 `map $http_upgrade $connection_upgrade` 블록도 없습니다. 이 상태에서 101 Switching Protocols 은 업스트림에 닿지 못합니다. 즉 지금 소켓을 넣으면 **로컬에서만 초록불**입니다.

그리고 지금 넣어야 할 근거가 없습니다. 방 둘·멤버 3~6명 규모에서 폴링이 부족하다는 실측이 없습니다. 폴링의 비용은 "DB 를 읽는 것" 이 아니라 "아무것도 없는데 왕복하는 것" 이고, 그건 적응형 간격 → ETag 조건부 요청 → 롱폴링 순으로 훨씬 싸게 줄어듭니다. 소켓은 그 셋을 다 쓰고도 모자랄 때의 도구입니다.

**6. 지금 Redis 를 넣습니다.** 기각(보류). **ADR-0010 을 뒤집지 않습니다.**

Redis 를 부를 것 같은 자리를 하나씩 봤습니다. **채팅이 새로 만드는 Redis 사유는 0개입니다.**

| 자리 | 판정 |
| --- | --- |
| 소켓 팬아웃 | 지금 소켓이 없습니다. 그리고 위 1번대로 **Redis 가 답이 아닙니다.** 트리거는 인스턴스 2대 |
| 연결/세션 상태 | 인스턴스가 하나면 "누가 어느 인스턴스에 붙었는가" 라는 질문이 성립하지 않습니다 |
| 미읽음 개수 캐시 | 뺄셈이라 **없앨 쿼리가 없습니다.** 캐시를 넣으면 발행마다 무효화가 붙어 순증입니다 |
| 최근 메시지 캐시 | `(room_id, room_seq)` 인덱스 끝 50행 범위 스캔 하나입니다. 같은 이유로 순증입니다 |
| 폴링 부하 | 캐시는 왕복을 못 없앱니다. 간격·ETag·롱폴링이 답입니다 |
| rate limit 카운터 공유 | **채팅과 무관하게 지금 이미 있는 성질입니다** — `ApiRateLimitFilter` 의 `counters` 가 `ConcurrentHashMap` 이라 인스턴스가 N대면 실효 한도가 N배입니다 |
| `AuthCodeStore`(#14) | 이미 인메모리이고 클래스 javadoc 이 스스로 적어 뒀습니다. 채팅이 그 시점을 앞당기지 않습니다 |

남은 넷(팬아웃 · 세션 상태 · rate limit · `AuthCodeStore`)이 전부 **"인스턴스 2대"** 하나로 환원되는데, 그건 ADR-0010 이 이미 적어 둔 되돌리기 조건과 **글자 그대로 같습니다.** 그러니 ADR-0010 에 얹을 트리거가 없습니다. 상태도 `채택` 그대로입니다.

**7. 공개 방 목록(방 찾기)을 만듭니다.** 기각.

"산책 크루" 가 있으니 동네 방을 찾아 들어가는 화면이 자연스러워 보입니다. **그런데 방을 공개하는 순간 규제 등급이 바뀝니다.** 정보통신망법 제44조의2(임시조치 30일)와 전기통신사업법 제22조의5(불법촬영물등 유통방지)는 둘 다 대상이 "**일반에게 공개**" 된 정보입니다(casenote.kr/법령/정보통신망_이용촉진_및_정보보호_등에_관한_법률/제44조의2). 초대코드 전용 비공개 방의 대화는 여기 들어가지 않습니다. 공개 목록을 만들면 들어갑니다.

여성가족부 랜덤채팅앱 청소년유해매체물 고시(2020-12-11 시행)가 회원관리·대화 저장·신고 기능 셋을 최소 안전장치로 꼽는 것도 같은 방향의 신호입니다. 우리는 랜덤 매칭이 아니라 직접 적용 대상이 아니지만, **모르는 사람이 들어오는 방**을 여는 것과 초대코드로만 들어오는 방을 여는 것은 감당해야 할 것이 다릅니다. 신고를 처리하는 사람이 저 하나인 동안에는 열지 않습니다.

**8. 1:1 채팅(DM)을 만듭니다.** 기각(보류).

데이터 모델은 이미 준비돼 있습니다 — `origin_kind='dm'` 이면 됩니다. 방을 범용으로 둔 덕에 `chat_*` 테이블을 하나도 안 건드리고 붙습니다. 그런데 **붙이는 날 따라오는 것이 스토어 요건입니다.** Google Play UGC 정책이 "direct messaging, tagging, mentioning 같은 1:1 상호작용 기능" 에 **차단을 필수**로 못 박습니다(support.google.com/googleplay/android-developer/answer/9876937). 우리 차단은 "방 안 가리기" 라 1:1 에서는 의미가 다릅니다 — 1:1 에서 상대를 가리면 남는 것이 빈 방입니다.

그리고 지금 앱 화면에 DM 진입점이 없습니다. 없는 화면을 위해 스토어 요건을 먼저 지지 않습니다.

**9. `users.plan` 컬럼을 넣습니다.** 기각.

나중에 유료 플랜을 붙일 것을 대비해 컬럼 하나를 미리 두자는 것인데, **값이 하나뿐인 컬럼은 나중에 어차피 지웁니다.** `01_schema.sql` 에 plan·subscription·tier 어느 것도 없고 이 상태를 유지합니다. 조사한 여섯 앱 중 **방 정원(인원수)을 파는 곳이 없었습니다** — 파는 것은 히스토리 보관 기간·파일 크기·개수 한도·기능 잠금입니다.

대신 **호출부가 플랜을 모르게** 두는 자리만 비웁니다: `ChatLimits` 인터페이스 하나(`maxMembersPerRoom` · `inviteTtl` · `maxInviteUses`)이고, 지금 구현체는 인자를 무시하고 상수를 돌려줍니다. 텔레그램이 `channels_limit_default`/`_premium` 을 `help.getAppConfig` 로 서버에서 내려주고(core.telegram.org/api/premium), 스트라이프 Entitlements 가 플랜 이름 대신 `lookup_key` 로 검사하라고 하는 것이 같은 이유입니다. 기능 플래그 시스템도 넣지 않습니다 — 플래그는 **지워야 할 것**이고 entitlement 는 **지우면 안 되는 것**인데, 둘 다 없는 상태에서 플래그부터 넣으면 그 둘이 같은 통에 섞입니다.

**10. `group_member` 를 따로 만듭니다.** 기각.

가족 멤버십과 방 멤버십을 나누면 "가족인데 방에 없는 사람" · "방에 있는데 가족이 아닌 사람" 이라는 상태가 생기고, 그걸 막는 코드를 계속 써야 합니다. 강퇴·재입장 금지·차단이 전부 `chat_room_member` 에 붙는 이상 멤버십이 둘이면 **강퇴가 어느 쪽인지 매번 물어야 합니다.** 멤버십은 `chat_room_member` 하나로 갑니다. 대가는 정직하게 적습니다 — **가족 그룹이 방을 전제하게 됩니다.** `family_group` 은 이름과 생성 시각만 듭니다.

### 결과

**얻는 것.** 이미 만들어져 있는 채팅 화면(`chat_list_screen.dart` · `family_chat_screen.dart`)이 더미를 걷어내고 서버에 붙습니다. 가족 방과 산책 크루 방이 **같은 코드로** 돌고, 방 종류는 `tag` 로만 다릅니다. 새 방 종류(장소별 방, 나중의 DM)를 붙일 때 `chat_*` 테이블을 건드리지 않습니다. 그리고 **폴링 단계의 신규 의존성이 0개**입니다 — 백엔드는 이미 있는 `spring-boot-starter-web`/`data-jpa`/`validation`/`security` + `mysql-connector-j` 로 끝나고, 프론트는 `http: ^1.4.0` + `AuthedClient`(401 자동 갱신·single-flight 가 이미 거기 있습니다) + `dart:async` 의 `Timer.periodic`(이미 `walk_tracking_screen.dart:69` 에서 씁니다)로 끝납니다. 전송 멱등키에 `uuid` 도 넣지 않습니다 — `Random.secure()` 16바이트를 base64url 로 적으면 순수 Dart 로 됩니다. 새로 들어오는 것은 **테이블 3장과 엔드포인트 넷**뿐입니다.

**잃는 것.** 실시간이 아닙니다. 방을 보고 있어도 최선이 3초 지연이고, 앱을 닫아 두면 알림이 없습니다(푸시는 M2.8, 소켓은 M2.9). 그리고 방 정원 50명·초대코드 7일 같은 상수를 `ChatLimits` 라는 간접층 뒤에 둡니다 — 지금 당장은 상수 세 개면 될 일입니다. 그 값을 치르는 이유는 하나입니다: 지금은 마이그레이션이 아니라 문서 수정이고, 나중에 하면 스키마 변경 + 발급 API 변경 + 참여 API 변경이 한꺼번에 옵니다.

#### 하지 않기로 한 것과 되돌리는 트리거

안 하기로 한 결정이 가장 먼저 잊힙니다. 그래서 각각에 **무엇을 보면 되돌리는가**를 붙입니다.

| 하지 않은 것 | 되돌리는 트리거 |
| --- | --- |
| **웹소켓/STOMP** | `chat.poll{result=empty}` 비율이 **0.5 밑**으로 내려가거나, `/chat/**` p95 > **500ms** 가 5분 지속되거나, `hikaricp_connections_pending` > 0 이 **1분 지속**. 하나라도 넘으면 M2.9 를 엽니다. 트리거 없이 착수하지 않습니다. 그날 **nginx 를 먼저 고칩니다** |
| **Redis** | ADR-0010 의 문장 그대로입니다 — 인스턴스가 둘 이상이 되거나, AT 수명을 늘려 블록리스트의 창이 의미 있어질 때. **채팅은 여기에 아무것도 더하지 않습니다** |
| **미읽음/최근 메시지 캐시** | 없습니다. 뺄셈에는 없앨 쿼리가 없고 캐시는 무효화만 순증입니다. 되살리려면 **실측 근거**를 함께 붙이십시오 |
| **메시지별 읽음 테이블** | "누가 읽었는지" 를 화면에 그리기로 정하는 날 |
| **공개 방 목록** | 열려면 정보통신망법 제44조의2·전기통신사업법 제22조의5 의 "일반에게 공개" 요건을 먼저 검토하고, 신고를 처리할 사람이 저 말고 더 있을 때 |
| **1:1 채팅** | 앱에 DM 진입점을 만들기로 하는 날. 그 PR 에 Google Play UGC 의 차단 요건이 함께 옵니다 |
| **`users.plan`·플랜 테이블·결제 SDK·기능 플래그** | 실제로 팔 물건이 정해질 때. 그날 고치는 것은 `ChatLimits` 구현체 하나입니다 |
| **푸시(FCM/APNs)** | M2.8. **애플 개발자 계정 유무를 먼저 확인해야 합니다** — 지금 확인하지 못했습니다 |
| **모더레이션 도구(관리자 화면)** | 신고가 실제로 쌓이기 시작할 때. 그때까지는 DB 직접 조회입니다 |
| **자동 차단 · 누적 신고 자동 조치 · 이의제기 창구 · 부방장** | 오탐이 곧바로 가족방 사고가 됩니다. 사람이 처리할 수 없는 양이 될 때 |
| **메시지 '나에게서만 삭제'** | 만들지 않습니다. 서버가 유일한 사본이라 멤버별 숨김 표가 하나 더 필요하고 값에 비해 비쌉니다 |

#### 마일스톤 재편 — M2.5 하나를 다섯으로 펼칩니다

M2.5(가족 케어 & 채팅)는 이슈가 **0개**입니다. 만들어진 적이 없어서 지금 모양을 바꾸는 비용이 가장 쌉니다. **번호는 다시 매기지 않습니다** — 소수점 밴드를 그대로 씁니다.

| # | 제목 | 이 마일스톤이 닫는 질문 | 의존 |
| --- | --- | --- | --- |
| **M2.5** | 가족 그룹 & 케어 공유 | 그룹·초대·케어 공유. **방·멤버십·초대 3테이블(`chat_room`·`chat_room_member`·`chat_room_invite`)이 여기서 태어납니다** — 초대코드를 `family_group.invite_code` 컬럼에서 뗀 이상 가족 그룹이 방을 먼저 필요로 합니다 | M2 |
| **M2.6** | 채팅 (폴링) | `chat_message` + `room_seq`, 폴링 API 4종, 적응형 간격 + ETag, 채팅 전용 rate limit 버킷, 커스텀 메트릭 3종 | M2.5 |
| **M2.7** | 채팅 안전 & 스토어 요건 | 신고·차단·강퇴·재입장 금지·만 14세 미만 게이트·운영자 연락처·약관 동의. **M5(출시)의 하드 전제** | M2.6 |
| **M2.8** | 알림 (푸시) | FCM/APNs, `device_token`, 알림 설정 화면. 코드보다 계정·인프라가 대부분입니다 | M2.6 (M2.7 과 병렬) |
| **M2.9** | 실시간 (소켓) · **트리거 기반** | nginx 웹소켓 경로 + 받기만 소켓. **조건이 충족될 때만 엽니다** | M2.6 + 트리거 |

**왜 다시 매기지 않는가.** 다시 매기면 살아 있는 편집이 18곳입니다(로드맵 32건은 어차피 다시 쓰므로 실비용 0). 못 할 일은 아닌데 **그 대가로 사는 것이 없습니다** — 다음에 또 끼울 것이 생기면 같은 18곳을 또 밉니다. 소수점은 매번 0곳입니다. 그리고 **고칠 수 없는 곳이 7건 있습니다**: 닫힌 이슈 #26(3곳)·#29(4곳)가 M3 를 본문에서 판단 근거로 씁니다. 닫힌 이슈는 그때 무엇을 근거로 판단했는가의 기록이라, 고치면 기록이 아니게 되고 안 고치면 틀린 말이 됩니다. 소수점을 쓰면 이 문제가 아예 생기지 않습니다 — M3 는 여전히 KTO 프록시입니다.

**밴드가 꽉 찬다는 것은 인정합니다.** M2.5~M2.9 는 다섯 자리이고 다섯을 다 씁니다. 그래서 규칙을 같이 못 박습니다: **2.x 밴드는 여기서 닫습니다. 더 나눌 일이 생기면 마일스톤이 아니라 그 마일스톤 안의 Epic 이슈로 쪼갭니다.** (M2.10 은 문자열 정렬에서 M2.5 앞으로 갈 위험이 있는데, GitHub 마일스톤 목록의 실제 정렬 규칙은 확인하지 못했습니다 — due date 가 전부 null 입니다.)

**M4 의 진입 조건도 바뀝니다.** 지금 로드맵은 `M2.5 → M4` 인데 M4 가 실제로 필요로 하는 것은 M2.5 의 `care_log` 뿐입니다. 채팅 밴드는 M4 의 전제가 아닙니다. 화살표를 `M2.5 → M4` 로 그대로 두고 채팅 밴드는 M5 로만 잇습니다 — **채팅이 늦어져도 확장 로그가 막히지 않습니다.**

#### 인스턴스를 2대로 늘리는 날 함께 옮겨야 하는 것은 넷입니다

ADR-0010 은 Redis 를 **인증 맥락**(RT 검증 캐시 · AT 블록리스트)에서만 보류했습니다. 이번에 소비자가 하나 더 생겼으니, 그날 함께 깨지는 것이 인증 것 몇 개가 아니라 **넷**이라는 사실이 어딘가에 적혀야 합니다.

1. **`AuthCodeStore`(#14)** — `ConcurrentHashMap`, TTL 60초. 안 옮기면 **정상 로그인이 절반쯤 401 이 됩니다.** 클래스 javadoc 이 이 문장을 이미 적고 있습니다.
2. **`ApiRateLimitFilter` 카운터** — `ConcurrentHashMap`, 열쇠 `IP|버킷`. 안 옮기면 실효 한도가 인스턴스 수만큼 곱해집니다. **채팅과 무관하게 지금 이미 있는 문제입니다.**
3. **Security 인가요청 저장소** — `HttpSessionOAuth2AuthorizationRequestRepository`(기본값, 세션). 같은 javadoc 이 "이미 있던 제약" 이라고 지목합니다.
4. **소켓 팬아웃** — 소켓을 넣은 **뒤에만** 문제가 됩니다. ⚠️ 그리고 **Redis 로는 안 됩니다**(위 대안 1·6).

**이 목록의 소유자는 `backend/TODO/refresh-token-redis.md` 입니다.** ADR 본문이 아닙니다 — ADR-0010 이 그 파일을 되돌리기 목록의 소유자로 **명시**했기 때문입니다. 그 파일 §2 뒤에 "인스턴스가 2대가 되는 날 함께 옮겨야 하는 것 (인증 밖)" 절을 새로 만들어 넷을 표로 적습니다. 인증 항목과 섞지 않습니다. 파일 제목("TODO: Redis(RT 검증캐시 · AT 블랙리스트)")은 넓히지 않습니다 — 넓히면 그 소유 관계가 흐려집니다. 대신 새 절의 제목이 "인증 밖" 이라고 스스로 말하게 둡니다.

같은 파일에서 낡은 줄 하나를 함께 고칩니다: §5 의 "401 시 자동 재발급(dio 인터셉터)" 은 틀렸습니다. `app/pubspec.yaml` 에 `dio` 가 없고, 실제 구현은 `http` 위의 `AuthedClient`(`app/lib/core/net/authed_client.dart`)이며 single-flight 도 거기 있습니다.

#### 채팅은 새 인스턴스 지역 상태를 추가하지 않습니다

위 넷이 **채팅 때문에 생긴 것이 아니라는 점**이 중요합니다. 이번 설계는 인메모리 상태를 하나도 만들지 않습니다.

- **`room_seq` 는 DB 락입니다.** 락을 잡는 것은 MySQL 이므로 인스턴스가 몇 대든 같은 방의 발급은 직렬화됩니다. 애플리케이션 메모리에 아무것도 안 둡니다. 이 저장소에는 명시적 락이 지금 **0건**이라 이게 첫 비관적 락이고, 그래서 `UNIQUE (room_id, room_seq)` 를 backstop 으로 겁니다 — 발급 로직이 틀렸을 때 조용한 중복 대신 즉시 오류가 납니다. 데드락 순서도 지금 못 박습니다: **락 순서는 항상 `chat_room` → `chat_room_invite` → `chat_room_member` → `chat_message`** (위 결정에 적은 대로 #75·#78 로 넓어진 표입니다. 정본은 `ChatRoomRepository#lockForMemberChange` javadoc), 그리고 락을 잡은 트랜잭션 안에서 외부 호출(푸시·S3)을 하지 않습니다(`innodb_lock_wait_timeout` 기본 50초).
- **폴링은 무상태입니다.** 상태가 전부 DB 에 있어서 어느 인스턴스가 요청을 받아도 같은 답이 나옵니다.

**그래서 처음부터 빼 두는 것이 셋 있습니다: 타이핑 표시 · 온라인 표시 · 인메모리 미읽음 캐시.** 셋 다 화면에 있으면 예쁜데 **서버에 지역 상태를 만듭니다.** 한 번 들어가면 위 목록에 줄이 늘어납니다. 소켓 단계는 다릅니다 — WebSocket 세션 자체가 인스턴스 지역 상태입니다. 그래서 팬아웃이 위 목록의 4번으로 들어가 있습니다.

#### 잠기는 곳

- `ChatBoundaryArchitectureTest` — chat 경계 밖 FK 0개. `SchemaDdlDriftTest` 와 함께 겁니다(#9 의 `refresh_token` 전례).
- `DecisionLogTest` — 이 ADR 이 인덱스에 있고 앵커가 살아 있는지, 4개 절이 있는지.
- **통합 테스트 하나** — 남의 방 id 로 403. 이 저장소에는 `@PreAuthorize`·`hasRole`·`@Secured` 가 **0건**이라, 멤버십 인가를 컨트롤러마다 손으로 쓰면 메서드가 늘 때마다 한 곳씩 빠집니다. 서비스 경계에 `requireMember(roomId, userId)` 하나를 두고 모든 진입점이 통과하게 합니다.
- **테스트 컨텍스트 증가 0** — 폴링은 그냥 HTTP GET 입니다. 지금 `@SpringBootTest @AutoConfigureMockMvc`(4번 컨텍스트, 5개 클래스 공유) 조합을 글자 그대로 맞추면 하나도 안 늡니다. 소켓을 넣는 날에만 6 → 7 로 늘고, 그건 피할 수 없습니다(실제 포트가 필요합니다).

#### 알려진 한계

- **실기기에서 검증하지 못했습니다.** 지금 근거는 코드·설정·문서를 읽은 것과 레퍼런스 조사입니다. 폴링 간격·ETag 의 효과도 실측이 아니라 쿼리 모양에서 나온 추론입니다. 그래서 M2.6 착수 **전에** 기준선을 찍습니다 — 지금 grafana 로 평상시 `MySQL Queries/s` · `hikaricp_connections_active` · HTTP p95 하루치. 안 찍으면 나중에 "채팅 때문에 늘었다" 를 증명할 방법이 없고, 이건 코드 없이 오늘 할 수 있습니다.
- **모더레이션 도구가 없습니다.** 신고는 받는데 그걸 보는 화면이 없습니다. 처리하는 사람이 저 하나인 동안은 DB 직접 조회로 갑니다. 그래서 디스코드처럼 **처리 목표 시간을 공개하지 않습니다** — 공개하면 못 지킵니다. Apple 1.2 의 "신고에 대한 적시 대응" 을 사람이 하는 사후 조치만으로 통과할 수 있는지는 **확인하지 못했습니다.** 막히면 단순 금칙어 목록부터 붙입니다.
- **보관·삭제 정책은 정하지 않았습니다. 이 "정하지 않았다" 를 결정으로 적습니다.** 정한 것은 셋뿐입니다 — ① 방이 사는 동안 무기한 보관(방이 지워지면 그 방 메시지도 지웁니다. `chat_room` → `chat_message` FK 는 chat 경계 **안**이라 규칙에 안 걸립니다), ② '모두에게서 삭제' 창 **5분** 규약을 문서에 적되 **구현은 M2.7 에서 하지 않습니다**, ③ 흔적은 "삭제된 메시지입니다" 를 남기고 행은 지우지 않습니다(`deleted_at` 을 채우고 `body` 를 비웁니다 — `room_seq` 가 빈틈 없어야 델타 폴링과 미읽음 뺄셈이 성립합니다).
  안 정한 것은 **백업 보관 기간의 상한**과 **`chat_report` 스냅샷의 보존 기간**입니다. 근거가 될 법령 확인이 덜 됐습니다: 표준 개인정보 보호지침 제10조의 "5일 이내" 는 law.go.kr 본문을 열지 못하고 검색 요약으로만 봤고, 역일인지 영업일인지도 모릅니다. Pawloop 이 통신비밀보호법상 전기통신사업자에 해당하는지도 확인하지 못했습니다 — 해당한다면 접속 로그 3개월 보관 의무가 생기고, `privacy_ko.md` 3항의 "접속 로그 3개월 이상" 이 근거를 얻습니다. 지금 그 문구가 검토를 거친 것인지 관행을 베낀 것인지 모릅니다. **모르는 것을 아는 것처럼 적는 대신, 정하지 않았다는 사실과 무엇을 확인해야 정할 수 있는지를 적어 둡니다.**
- **레퍼런스 조사에는 원문을 못 읽은 항목이 있습니다.** cs.kakao.com·faq.whatsapp.com·help.line.me 는 JS 렌더링이나 403 이라 2차 출처 또는 검색 스니펫에 의존한 것이 있습니다. 어느 것이 그런지는 각 이슈 본문의 "확인하지 못한 것" 목록이 소유합니다.

> 인덱스 행의 앵커는 본문 제목이 `## ADR-0011 — 채팅 아키텍처` 일 때의 값입니다(GitHub 규칙: 소문자화 → 글자·숫자·`_`·공백·`-` 외 제거 → 공백을 `-` 로. em dash 가 지워지면서 양옆 공백 둘이 하이픈 둘로 남습니다). 제목을 다르게 쓰면 `DecisionLogTest.index_anchorsResolveToRealHeadings` 가 빨간불이 되니 앵커를 함께 고쳐야 합니다.

---

## 부록 — ADR 작성 규칙

- 새 결정은 이 로그 하단에 **다음 번호**로 추가하고, 상단 [ADR 인덱스](#adr-인덱스) 표에 한 줄 등록한다.
- 각 ADR은 **맥락 · 결정 · 대안 · 결과** 4개 항목을 반드시 포함한다.
- 기존 결정을 뒤집을 때는 원본 ADR을 지우지 말고 **상태를 폐기(Superseded by ADR-XXXX)**로 바꾸고, 대체 ADR을 새로 추가한다.
- 사실은 실제 코드/설정(`app/pubspec.yaml`, `app/lib/v2`, `android/*.gradle.kts`, `app/.env`)에 정렬한다.
