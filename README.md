# Pawloop(포루프) 🐾

[![CI](https://github.com/sanghyunbang/heattrip/actions/workflows/ci.yml/badge.svg)](https://github.com/sanghyunbang/heattrip/actions/workflows/ci.yml)

> **반려동물과 함께 걷고, 동네 반려인들과 연결되는 공간.**
> 산책 GPS 트래킹 · 반려동반 장소 지도 · 동네 커뮤니티 — Flutter 앱과 Spring Boot 서버를 함께 담은 모노레포입니다.

산책을 wedge로 좁게 시작해 **반려 일상 로그(산책 → 건강·식사·병원·동네) + 동반장소 지도 + 커뮤니티**로 확장합니다.

---

## 무엇을 하는 앱인가

5탭 구조입니다 — 홈 / 지도 / **[산책 FAB]** / 커뮤니티 / 통계.

| | |
| :--- | :--- |
| **산책** | 실시간 경로 기록 · 거리/시간/페이스 라이브 스탯 |
| **지도** | 반려동반 가능 장소 · 동물병원 · 펫샵 · 산책로 레이어 |
| **커뮤니티** | 동네 반려인 게시판 — 글·댓글·반응 |
| **통계** | 주간 산책 거리 차트 · 자주 가는 곳 |
| **프로필** | 반려동물 프로필(견종·크기·나이·중성화) |

> [!NOTE]
> 화면은 전부 동작하지만 데이터는 아직 대부분 더미입니다. 지도의 **반려동반 장소만 관광공사(KTO) 실데이터**로 연결돼 있고, 산책 GPS·커뮤니티·계정은 진행 중입니다.
> 화면·기능별 정확한 상태는 [구현 현황](docs/05-build/implementation-status.md)에 정리돼 있습니다.

---

## 저장소 이름이 `heattrip` 인 이유

이 프로젝트는 2026-07에 **감정 여행 앱 heattrip → 반려 앱 Pawloop(포루프)** 로 피벗했습니다([ADR-0001](docs/99-decisions/decision-log.md#adr-0001--감정여행heattrip--반려앱pawloop-피벗)). 제품·도메인·화면은 전부 교체됐지만, **기술 식별자에는 옛 이름이 남아 있습니다.**

| 남아 있는 곳 | 값 |
| :--- | :--- |
| 저장소 이름 | `heattrip` |
| Android `applicationId` / `namespace` | `com.cetacealab.heattrip` |
| 로그인 콜백 딥링크 스킴 | `heattrip://login-callback` |
| Gradle group / DB 이름 | `com.heattrip` / `heat_trip_db` |

이는 방치가 아니라 **의도된 유지**입니다 — 식별자 변경은 스토어 등록·재서명·OAuth 콘솔 재등록을 연쇄로 요구하므로, 마이그레이션 비용을 피해 **스토어 등록/재서명 시점에 일괄 정리**하기로 결정했습니다([ADR-0002](docs/99-decisions/decision-log.md#adr-0002--앱-이름-pawloop포루프-채택)). 문서와 UI 표기는 항상 **Pawloop(포루프)** 입니다.

---

## 저장소 구조

```
heattrip/
├── app/               Flutter 앱 — 화면 · 지도 · 산책 트래킹 · 소셜 로그인
├── backend/           Spring Boot API 서버 + MySQL · 관측성(Prometheus/Grafana) · k6
├── docs/              기술 문서 — 설계 · 아키텍처 · DB · API 계약 · 빌드 · 테스트 · ADR
├── design_refactor/   피벗 이전 디자인 프로토타입 핸드오프 (정리 대상)
└── .github/           이슈·PR 템플릿 · CI 워크플로
```

- **`docs/`** 는 "코드와 함께 리뷰되어야 하는 문서"만 담습니다. 제품 기획·전략 문서는 저장소 밖에서 관리합니다([ADR-0008](docs/99-decisions/decision-log.md)).
- **`design_refactor/`** 는 감정 여행 앱 시절의 HTML 디자인 프로토타입 2개(+런타임 스크립트, 설명 README)입니다. 2026-06 모노레포 통합 이후 손대지 않았고 현재 코드베이스와 연결점이 없는 **피벗 이전 산출물이라 정리(아카이브 또는 삭제) 대상**입니다.

---

## 스택

### 앱 (`app/`)

| | 버전 | 비고 |
| :--- | :--- | :--- |
| Flutter / Dart | **3.44.4** / 3.12.2 (`sdk: ^3.8.1`) | CI에서 버전 고정 |
| 지도 | `flutter_naver_map` ^1.3.1 | 네이버 Dynamic Map |
| 차트 | `fl_chart` ^1.2.0 | 산책 통계 |
| 라우팅 · 상태 | `go_router` ^16.1.0 · `provider` ^6.1.5 | |
| 인증 | `flutter_web_auth_2` ^4.1.0 · `flutter_secure_storage` ^9.2.4 | 소셜 로그인 · 토큰 보관 |
| 위치 | `geolocator` ^13.0.1 | |
| Android 툴체인 | compileSdk 36 · minSdk 23 · Java 17 | `minSdk 23`은 지도 SDK 요구 |

### 서버 (`backend/`)

| | 버전 | 비고 |
| :--- | :--- | :--- |
| Java | **21** | Gradle toolchain |
| Spring Boot | **3.5.4** | Web · WebFlux · Data JPA · Validation |
| 인증 | Spring Security + OAuth2 Client · JJWT 0.11.5 | 카카오 · 구글 |
| DB | **MySQL 8.0** | 공간형 `POINT`/`LINESTRING` + `SPATIAL INDEX` ([ADR-0003](docs/99-decisions/decision-log.md)) |
| API 문서 | springdoc-openapi 2.7.0 | 계약 원본은 [`docs/04-api/openapi.yaml`](docs/04-api/openapi.yaml) |
| 관측성 · 부하 | Micrometer + Prometheus · Grafana · k6 | |

### 외부 데이터

- **한국관광공사 `KorPetTourService2`** — 반려동반 가능 장소. 현재 유일한 실데이터 레이어이며, 앱이 직접 호출하는 것은 임시 구조입니다(백엔드 프록시로 이전 예정 — [ADR-0006](docs/99-decisions/decision-log.md)).
- **LOCALDATA**(동물병원·펫샵), **두루누비**(산책로) — 연동 예정. 지금은 더미 레이어입니다.

> 감정 여행 시절의 OpenAI 추천 파이프라인(Spring AI 의존성)이 코드에 남아 있으며, 반려 맥락에서 **재검토 대상**입니다. 자세한 내용은 [결정 기록](docs/99-decisions/decision-log.md)을 참고하세요.

---

## 시작하기

설치 도구·환경변수·에뮬레이터·빌드 명령은 **[개발 환경 세팅 문서](docs/05-build/setup.md)** 에 전부 정리돼 있습니다. 아래는 요약입니다.

```bash
git clone https://github.com/sanghyunbang/heattrip.git
cd heattrip

# 앱 — Flutter 3.44.4 필요
cd app
flutter pub get
flutter run               # 키가 없어도 앱은 뜹니다 (지도·공공데이터만 비활성)

# 서버 (선택) — JDK 21 + MySQL 8 필요
cd ../backend
./gradlew bootRun --args='--spring.profiles.active=dev'
```

환경값은 `.env` 파일이 아니라 **컴파일 타임 `--dart-define`** 으로 들어갑니다. 에셋으로 번들된 `.env` 는 APK 안에 원본 그대로 실려 나가기 때문입니다([이슈 #29](https://github.com/sanghyunbang/heattrip/issues/29)).

```bash
cd app
cp dart-define.example.json dart-define.json     # 값을 채웁니다 (gitignore 대상)
flutter run --dart-define-from-file=dart-define.json

# 한두 개만 잠깐 바꾸려면
flutter run --dart-define=API_BASE=http://10.0.2.2:8080
```

검증 명령:

```bash
cd app     && flutter analyze --no-fatal-warnings --no-fatal-infos && flutter test
cd backend && ./gradlew test jacocoTestCoverageVerification   # Docker 필요 (Testcontainers)
```

---

## 현재 상태

**M2 — 로그인(소셜 인증) 진행 중.** 전체 마일스톤은 [로드맵](docs/05-build/roadmap.md)에 있습니다.

| 마일스톤 | 한 줄 | 상태 |
| :--- | :--- | :---: |
| **M0** — 더미 UX 완성 | 5탭 전 화면을 더미 데이터로 완성 | ✅ 완료 |
| **M1** — 실위치 + 실시간 트래킹 | 시뮬 좌표를 실제 GPS로 대체 | ⬜ 예정 |
| **M2** — 로그인(소셜 인증) | 카카오·구글 계정 도입, 서버 동기화의 기반 | 🟡 **진행 중** |
| **M2.5** — 가족 케어 & 채팅 | 가족이 함께 돌본다 | ⬜ 예정 |
| **M3** — 실데이터 + 백엔드 프록시 | 더미 레이어를 공공데이터로, KTO 키를 서버로 | ⬜ 예정 |
| **M4** — 확장 로그 | 산책 wedge를 "반려 일상 로그"로 확장 | ⬜ 예정 |
| **M5** — 출시 | 양대 스토어 정식 배포 | ⬜ 예정 |

M2와 M3는 병렬 진행이 가능합니다. 인증이 막히면 다른 서버 기능이 전부 막히기 때문에 M1보다 M2를 먼저 하고 있습니다.

---

## 문서

전체 인덱스는 **[`docs/README.md`](docs/README.md)** 에 있습니다. 자주 찾는 문서만 추리면:

| | |
| :--- | :--- |
| [개발 환경 세팅](docs/05-build/setup.md) | 설치 · `--dart-define` · 에뮬레이터 · 빌드 · 소셜 로그인 로컬 테스트 |
| [로드맵](docs/05-build/roadmap.md) · [구현 현황](docs/05-build/implementation-status.md) | 마일스톤 · 화면별 실제 상태 |
| [시스템 개요](docs/02-architecture/system-overview.md) · [기술 스택](docs/02-architecture/tech-stack.md) | 구성도 · 버전 표 |
| [ERD](docs/03-database/erd.md) · [스키마](docs/03-database/schema.md) | MySQL 공간형 데이터 모델 |
| [API 명세](docs/04-api/api-spec.md) · [`openapi.yaml`](docs/04-api/openapi.yaml) | 프론트/백엔드 합의 계약 |
| [디자인 시스템](docs/01-design/design-system.md) · [화면 명세](docs/01-design/screen-spec.md) | 오라 배경 · 글래스 카드 · 토큰 |
| [결정 기록(ADR)](docs/99-decisions/decision-log.md) | 피벗 · 네이밍 · RDB · KTO · 문서 범위 |

---

## CI

[`.github/workflows/ci.yml`](.github/workflows/ci.yml) 의 **CI** 워크플로가 PR과 `main` 푸시마다 돕니다.

- **경로 필터** — `backend/**` 가 바뀐 PR에서는 백엔드 잡만, `app/**` 이면 앱 잡만 돕니다.
- **백엔드** — `./gradlew test jacocoTestReport jacocoTestCoverageVerification`. 커버리지 게이트는 인증 패키지에만 걸려 있고 **내리는 것은 금지**입니다. 검색 테스트가 MySQL FULLTEXT 를 Testcontainers 로 실제 실행하므로 **로컬에서도 Docker 가 필요**합니다([#26](https://github.com/sanghyunbang/heattrip/issues/26)).
- **앱** — `flutter analyze` (에러 0건) + `flutter test --coverage`.
- **`CI 통과`** 잡 하나가 최종 판정입니다. 브랜치 보호 규칙에는 이 잡만 등록하면 됩니다.

테스트 정책과 기여 규약은 이슈로 관리합니다 — [규약 #4](https://github.com/sanghyunbang/heattrip/issues/4) · [테스트 정책 #21](https://github.com/sanghyunbang/heattrip/issues/21) · [로드맵 #20](https://github.com/sanghyunbang/heattrip/issues/20).

---

## 라이선스

**아직 라이선스 파일이 없습니다.** 라이선스가 명시되지 않은 저장소는 기본적으로 저작권자에게 모든 권리가 있으며, 복제·수정·재배포가 허용되지 않습니다.

공개 전환 시 어떤 라이선스를 붙일지(또는 붙이지 않을지)는 저장소 소유자가 결정할 사항이라 임의로 고르지 않았습니다. 결정되면 `LICENSE` 파일을 추가하고 이 절을 갱신합니다.

---

*cetaceaLab*
