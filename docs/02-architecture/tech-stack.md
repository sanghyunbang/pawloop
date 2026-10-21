# 기술 스택 (Tech Stack)

> Pawloop(포루프) 반려동물 산책·동반장소·커뮤니티 앱의 프론트/백엔드/안드로이드 툴체인/외부 서비스 전체 기술 스택 정리. 버전은 실제 `app/pubspec.yaml`·`android/*.gradle.kts` 기준이고, 앱 환경값의 키 목록은 `app/dart-define.example.json`·`app/lib/core/config/env.dart` 기준이다.

---

## 1. 개요

| 레이어 | 핵심 기술 |
| --- | --- |
| 프론트엔드 | Flutter 3.44.4 / Dart 3.12.2 (SDK `^3.8.1`), go_router, ValueNotifier |
| 백엔드 | Spring Boot(Java 21) + MySQL(공간형) — 원격 `api.pawloop.app` |
| 지도 | flutter_naver_map(네이버 Dynamic Map) |
| 공공데이터 | 관광공사 KorPetTourService2, LOCALDATA, 두루누비 |
| 안드로이드 툴체인 | AGP 8.11.1 / Kotlin 2.2.20 / Gradle 8.13 / compileSdk 36 / Java 17 |

---

## 2. 프론트엔드 (Flutter / Dart)

- **Flutter**: 3.44.4
- **Dart SDK**: 3.12.2 (`environment.sdk: ^3.8.1`)
- **앱 버전**: 2.0.0+1 (`pubspec.yaml`)
- **상태관리**: `ValueNotifier` + `ValueListenableBuilder`(경량) — 별도 상태관리 프레임워크 미도입, `provider`는 DI 용도
- **라우팅**: `go_router` → `main.dart` → MainShell 진입, 화면은 `lib/v2/` 하위
- **폰트**: Pretendard(로컬 `.otf` 400~800), `google_fonts` 병용
- **환경변수**: 컴파일 타임 `--dart-define` **단독**. `flutter_dotenv`·`.env` 는 #29 에서 걷어냈다(에셋으로 번들된 `.env` 는 APK 안에 원본 그대로 실려 나갔다). 단일 진입점은 `lib/core/config/env.dart` 의 `Env`이고, 값 묶음은 `app/dart-define.example.json` 을 복사해 `--dart-define-from-file` 로 준다 → [세팅 문서 3절](../05-build/setup.md)
- **미주입 시 동작**: 모든 키가 `String.fromEnvironment(..., defaultValue: '')` 라 값이 없어도 앱이 죽지 않는다. `Env.apiBase` 는 `http://10.0.2.2:8080`(에뮬레이터→호스트) 로 폴백하고, 지도·KTO 는 비활성 상태로 뜬다

### 2.1 주요 패키지 (dependencies)

| 패키지 | 버전 | 용도 |
| --- | --- | --- |
| `flutter_naver_map` | ^1.3.1 | 지도 SDK(네이버 Dynamic Map) — 장소 지도 · 산책 트래킹 |
| `geolocator` | ^13.0.1 | 실시간 위치/GPS(산책 트래킹 확장) |
| `fl_chart` | ^1.2.0 | 산책 통계 차트(주간 막대 등) |
| `http` | ^1.4.0 | REST API 호출(백엔드/공공데이터) |
| `flutter_secure_storage` | ^9.2.4 | 토큰 등 보안 저장(Bearer 주입) |
| `shared_preferences` | ^2.5.3 | 경량 로컬 설정 저장 |
| `flutter_web_auth_2` | ^4.1.0 | 소셜 로그인 웹 인증 플로우 |
| `image_picker` | ^1.1.2 | 사진 선택(프로필/게시글) |
| `cached_network_image` | ^3.3.1 | 네트워크 이미지 캐싱 |
| `flutter_svg` | ^2.2.0 | SVG 아이콘(google/kakao) |
| `google_fonts` | ^8.1.0 | 웹폰트 |
| `provider` | ^6.1.5 | 의존성 주입(MultiProvider) |
| `go_router` | ^16.1.0 | 선언형 라우팅 |

> 2026-09-06 #94 로 레거시 셸을 지우면서 그 셸만 쓰던 열 개(`lottie` · `table_calendar` · `intl` · `meta` · `flutter_staggered_grid_view` · `visibility_detector` · `flutter_animate` · `iconsax` · `url_launcher` · `cupertino_icons`)를 뺐다 — `lib`·`test` 에 import 가 0건이었다.

### 2.2 개발 의존성 (dev_dependencies)

| 패키지 | 버전 | 용도 |
| --- | --- | --- |
| `flutter_test` | (sdk) | 단위/위젯 테스트 |
| `flutter_lints` | ^5.0.0 | 린트 규칙 |
| `flutter_launcher_icons` | ^0.13.1 | 앱 아이콘 생성(Android 적응형/iOS/웹/데스크톱) |

### 2.3 에셋

- 아이콘: `assets/icons/`(google/kakao SVG), 로고 `assets/Logo4.png`(디버그 이메일 로그인 화면)
- 이모지: `assets/emoji/`(Fluent Emoji 3D PNG — cat·dog·paw. 감정 여섯 개는 #94 로 셸과 함께 지웠다)
- 약관: `assets/terms/`(terms/privacy/marketing ko.md)
- 폰트: `assets/fonts/Pretendard-*.otf`

---

## 3. 백엔드 (Spring / DB)

| 구분 | 기술 | 비고 |
| --- | --- | --- |
| 프레임워크 | Spring Boot (Java 21) | 패키지 `place`(장소 프록시·카탈로그·레이어) · `walk` · `dog` · `care` · `group` · `chat`/`chatweb` · `community` · `user`/`OAuth`(인증). 감정 여행 패키지(`tour`·`curation`·`social` …)와 Kotlin 은 2026-09-06 #94 로 지웠다 |
| DB | MySQL (공간형) | `POINT`/`LINESTRING`, `SPATIAL INDEX`, `ST_Distance_Sphere`/`MBRContains` |
| 배포 엔드포인트 | `https://api.pawloop.app` | 앱은 `--dart-define=API_BASE_URL` 로 주입 — 현재 **원격** 백엔드 사용. `--dart-define=API_BASE` 가 있으면 그쪽이 우선(로컬/스테이징 전환용) |
| 레거시 추천 | FastAPI + OpenAI | 감정여행 시절 추천 파이프라인. **현재 앱에 연결점이 없다** — 예전 `.env` 에 있던 `API_RECSYS_URL` 은 #29 에서 `.env` 를 걷어낼 때 함께 사라졌고 `Env` 에도 대응 키가 없다. 반려 맥락 재검토 대상 |

- GPS 경로는 `walk.path` 단일 컬럼(LINESTRING/인코딩 폴리라인)에 저장.
- 초기엔 RDB-only. 대량 GPS 시계열/장소검색(ES)·캐시(Redis)·NoSQL은 규모 확장 시 옵션.

---

## 4. 안드로이드 툴체인

| 항목 | 값 | 출처 |
| --- | --- | --- |
| Android Gradle Plugin (AGP) | 8.11.1 | `android/settings.gradle.kts` |
| Kotlin | 2.2.20 | `android/settings.gradle.kts` |
| Gradle | 8.13 | `gradle/wrapper/gradle-wrapper.properties` (gradle-8.13-all) |
| compileSdk | 36 | `app/build.gradle.kts` |
| minSdk | 23 | `maxOf(flutter.minSdkVersion, 23)` — flutter_naver_map 요구 |
| targetSdk | `flutter.targetSdkVersion` | Flutter 기본값 상속 |
| NDK | 27.0.12077973 | `app/build.gradle.kts` |
| Java / JVM 타깃 | 17 | `sourceCompatibility`/`targetCompatibility`/`jvmTarget` |
| applicationId / namespace | `app.pawloop` | 도메인 `pawloop.app` 을 뒤집은 것 (#597) |

### 4.1 서명·빌드 정책

- **디버그 빌드**: `key.properties` 없이 항상 빌드 가능(기본 `debug.keystore`).
- **릴리스 빌드**: `android/key.properties`가 있을 때만 release 서명 구성 생성. 릴리스 태스크인데 키가 없으면 의도적으로 `GradleException` 발생(보안 우선).
- **릴리스 최적화**: `isMinifyEnabled`/`isShrinkResources` ON + ProGuard(`proguard-android-optimize.txt` + `proguard-rules.pro`).

---

## 5. 외부 서비스

### 5.1 지도 — 네이버 (flutter_naver_map)

- `--dart-define=NAVER_MAP_CLIENT_ID` 로 주입한 값을 `Env.naverMapClientId` 로 읽어 `main.dart` 에서 `FlutterNaverMap().init(...)` 초기화.
- Client ID 미설정 시 지도 비활성(안내문 표시)하고 앱은 계속 동작.

### 5.2 공공데이터

| 서비스 | 제공처 | 용도 | 현재 상태 |
| --- | --- | --- | --- |
| KorPetTourService2 (반려동물 동반여행) | 관광공사(data.go.kr, PK 15135102) | 반려동반 가능 장소(관광/문화/레포츠/숙박/쇼핑/음식점) | **실연동**(서울 45곳). **백엔드가 부른다**([#40](https://github.com/sanghyunbang/pawloop/issues/40)) — 서비스키는 서버 환경변수 `TOUR_API_SECRET` 로만 존재하고 앱 바이너리에 없다.<br>일 1,000콜 한도는 `kto_call_budget` 표가 게이트로 지킨다 |
| LOCALDATA (행안부 인허가) | 행정안전부 | 동물병원 전국 ~9,445건, 펫샵/미용/호텔 | **더미**(좌표 EPSG:5174→WGS84 변환 필요) |
| 두루누비 (걷기여행길) | 관광공사 | 산책로 코스 좌표/GPX | **더미 폴리라인** |

- KorPetTourService2 응답: `mapx`(경도)/`mapy`(위도), `contenttypeid`(12관광지/14문화/28레포츠/32숙박/38쇼핑/39음식점), `addr1`/`tel`/`firstimage`.
- 오퍼레이션: `locationBasedList2`/`areaBasedList2`/`searchKeyword2`/`detailPetTour2`.
- **주의**: 1,000콜/일 제한. **백엔드 프록시 + 0.02° 격자 캐시로 해결됐다**(#40 · [ADR-0013](../99-decisions/decision-log.md#adr-0013--kto-프록시는-격자-캐시와-일일-호출-예산으로-간다)) — 앱은 `GET /api/places/nearby` 만 부르고 서비스키를 들지 않는다.

---

## 6. 참고

- 데이터 모델/공간쿼리 상세: [ERD](../03-database/erd.md)
- 앱 화면·구조는 `app/lib/v2/` 하위(screens/domain/data/widgets/theme).
