# 기술 스택 (Tech Stack)

> Pawloop(포루프) 반려동물 산책·동반장소·커뮤니티 앱의 프론트/백엔드/안드로이드 툴체인/외부 서비스 전체 기술 스택 정리. 버전은 실제 `app/pubspec.yaml`·`android/*.gradle.kts`·`.env` 기준.

---

## 1. 개요

| 레이어 | 핵심 기술 |
| --- | --- |
| 프론트엔드 | Flutter 3.44.4 / Dart 3.12.2 (SDK `^3.8.1`), go_router, ValueNotifier |
| 백엔드 | Spring Boot(Java/Kotlin) + MySQL(공간형) — 원격 `api.heattrip.link` |
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
- **환경변수**: `flutter_dotenv`로 `.env` 로드(없어도 앱이 죽지 않게 try-catch), `--dart-define` 병행 가능

### 2.1 주요 패키지 (dependencies)

| 패키지 | 버전 | 용도 |
| --- | --- | --- |
| `flutter_naver_map` | ^1.3.1 | 지도 SDK(네이버 Dynamic Map) — 감정지도/장소 지도 |
| `geolocator` | ^13.0.1 | 실시간 위치/GPS(산책 트래킹 확장) |
| `fl_chart` | ^1.2.0 | 산책 통계 차트(주간 막대 등) |
| `lottie` | ^3.4.0 | Lottie 애니메이션 |
| `http` | ^1.4.0 | REST API 호출(백엔드/공공데이터) |
| `flutter_secure_storage` | ^9.2.4 | 토큰 등 보안 저장(Bearer 주입) |
| `shared_preferences` | ^2.5.3 | 경량 로컬 설정 저장 |
| `flutter_web_auth_2` | ^4.1.0 | 소셜 로그인 웹 인증 플로우 |
| `image_picker` | ^1.1.2 | 사진 선택(프로필/게시글) |
| `cached_network_image` | ^3.3.1 | 네트워크 이미지 캐싱 |
| `flutter_svg` | ^2.2.0 | SVG 아이콘(google/kakao/naver) |
| `google_fonts` | ^8.1.0 | 웹폰트 |
| `table_calendar` | ^3.0.9 | 캘린더 UI |
| `intl` | ^0.18.1 | 날짜/숫자 국제화 포맷 |
| `provider` | ^6.1.5 | 의존성 주입(MultiProvider) |
| `go_router` | ^16.1.0 | 선언형 라우팅 |
| `flutter_staggered_grid_view` | ^0.7.0 | 스태거드 그리드 레이아웃 |
| `visibility_detector` | ^0.4.0+2 | 위젯 가시성 감지 |
| `flutter_animate` | ^4.5.2 | 선언형 애니메이션 |
| `iconsax` | ^0.0.8 | 아이콘 세트 |
| `url_launcher` | ^6.3.2 | 외부 URL/전화(장소 tel) 실행 |
| `cupertino_icons` | ^1.0.8 | iOS 스타일 아이콘 |

### 2.2 개발 의존성 (dev_dependencies)

| 패키지 | 버전 | 용도 |
| --- | --- | --- |
| `flutter_test` | (sdk) | 단위/위젯 테스트 |
| `flutter_lints` | ^5.0.0 | 린트 규칙 |
| `flutter_launcher_icons` | ^0.13.1 | 앱 아이콘 생성(Android 적응형/iOS/웹/데스크톱) |

### 2.3 에셋

- 아이콘: `assets/icons/`(google/kakao/naver SVG), 로고 `assets/Logo4.png`
- 이모지: `assets/emoji/`(Fluent Emoji 3D PNG)
- Lottie: `assets/lottie/`
- 약관: `assets/terms/`(terms/privacy/marketing ko.md)
- 폰트: `assets/fonts/Pretendard-*.otf`

---

## 3. 백엔드 (Spring / DB)

| 구분 | 기술 | 비고 |
| --- | --- | --- |
| 프레임워크 | Spring Boot (Java/Kotlin 혼용) | 패키지 `tour`(관광 장소)/`curation`(추천)/`social`(커뮤니티)/`auth` |
| DB | MySQL (공간형) | `POINT`/`LINESTRING`, `SPATIAL INDEX`, `ST_Distance_Sphere`/`MBRContains` |
| 배포 엔드포인트 | `https://api.heattrip.link` | 앱 `.env`의 `API_BASE_URL` — 현재 **원격** 백엔드 사용 |
| 레거시 추천 | FastAPI + OpenAI | 감정여행 시절 추천 파이프라인. `.env`의 `API_RECSYS_URL`는 주석 처리(비활성), 반려 맥락 재검토 대상 |

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
| applicationId / namespace | `com.cetacealab.heattrip` | (레거시 패키지명 유지) |

### 4.1 서명·빌드 정책

- **디버그 빌드**: `key.properties` 없이 항상 빌드 가능(기본 `debug.keystore`).
- **릴리스 빌드**: `android/key.properties`가 있을 때만 release 서명 구성 생성. 릴리스 태스크인데 키가 없으면 의도적으로 `GradleException` 발생(보안 우선).
- **릴리스 최적화**: `isMinifyEnabled`/`isShrinkResources` ON + ProGuard(`proguard-android-optimize.txt` + `proguard-rules.pro`).

---

## 5. 외부 서비스

### 5.1 지도 — 네이버 (flutter_naver_map)

- `.env`의 `NAVER_MAP_CLIENT_ID`로 `main.dart`에서 `FlutterNaverMap().init(...)` 초기화.
- Client ID 미설정 시 지도 비활성(안내문 표시)하고 앱은 계속 동작.

### 5.2 공공데이터

| 서비스 | 제공처 | 용도 | 현재 상태 |
| --- | --- | --- | --- |
| KorPetTourService2 (반려동물 동반여행) | 관광공사(data.go.kr, PK 15135102) | 반려동반 가능 장소(관광/문화/레포츠/숙박/쇼핑/음식점) | **실연동**(서울 45곳). `.env`의 `YOUR_DECODING_SERVICE_KEY`(인코딩 키)로 앱이 직접 호출 |
| LOCALDATA (행안부 인허가) | 행정안전부 | 동물병원 전국 ~9,445건, 펫샵/미용/호텔 | **더미**(좌표 EPSG:5174→WGS84 변환 필요) |
| 두루누비 (걷기여행길) | 관광공사 | 산책로 코스 좌표/GPX | **더미 폴리라인** |

- KorPetTourService2 응답: `mapx`(경도)/`mapy`(위도), `contenttypeid`(12관광지/14문화/28레포츠/32숙박/38쇼핑/39음식점), `addr1`/`tel`/`firstimage`.
- 오퍼레이션: `locationBasedList2`/`areaBasedList2`/`searchKeyword2`/`detailPetTour2`.
- **주의**: 1,000콜/일 제한 → 향후 백엔드 프록시 + 캐싱 권장(현재는 앱이 직접 호출).

---

## 6. 참고

- 데이터 모델/공간쿼리 상세: [ERD](../03-database/erd.md)
- 앱 화면·구조는 `app/lib/v2/` 하위(screens/domain/data/widgets/theme).
