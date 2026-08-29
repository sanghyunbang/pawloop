# Heat Trip Flutter

감정과 취향을 기반으로 여행지를 탐색하고, 추천 결과를 일정과 여행 기록으로 연결하는 Heat Trip 서비스의 Flutter 클라이언트입니다.

[![Flutter](https://img.shields.io/badge/Flutter-3.x-02569B?style=flat-square&logo=flutter&logoColor=white)](https://flutter.dev/)
[![Dart](https://img.shields.io/badge/Dart-3.8+-0175C2?style=flat-square&logo=dart&logoColor=white)](https://dart.dev/)
[![Android](https://img.shields.io/badge/Android-supported-3DDC84?style=flat-square&logo=android&logoColor=white)](https://developer.android.com/)
[![iOS](https://img.shields.io/badge/iOS-supported-000000?style=flat-square&logo=apple&logoColor=white)](https://developer.apple.com/ios/)

## 주요 프로젝트 링크

| 구분 | 역할 | 링크 |
| --- | --- | --- |
| 스토리보드 | 프로젝트 배경, 문제 정의, 결과물 소개 | [Heat Trip Notion](https://app.notion.com/p/Heat-Trip-321b82bc8b718166a51fd382c51d96b5?source=copy_link) |
| 백엔드 | Spring Boot API 서버 | [Heat Trip Backend](https://github.com/sanghyunbang/Heat_Trip_Spring_Boot_BE) |
| 기술 Wiki | 구현 상세, 테스트 결과, 기술 의사결정 기록 | [Backend Wiki](https://github.com/sanghyunbang/Heat_Trip_Spring_Boot_BE/wiki) |

## 관련 리포지토리

| 리포지토리 | 역할 |
| --- | --- |
| [Heat_Trip_Spring_Boot_BE](https://github.com/sanghyunbang/Heat_Trip_Spring_Boot_BE) | Spring Boot 백엔드 API, 인증, 검색, 큐레이션, 일정, 미디어 관리 |
| [heat_trip_flutter](https://github.com/sanghyunbang/heat_trip_flutter) | Flutter 클라이언트 애플리케이션 |
| [heattrip_rec_py](https://github.com/sanghyunbang/heattrip_rec_py) | Python 기반 추천 서버, LLM 추천 엔진 |


## 프로젝트 소개

Heat Trip Flutter는 사용자가 여행지를 탐색하고, 감정 기반 추천을 받고, 북마크와 일정, 여행 기록까지 관리할 수 있도록 설계된 모바일 앱입니다.

앱은 Spring Boot 백엔드와 REST API로 통신하며, 관광지 상세 정보 일부는 공공데이터포털 Tour API를 사용합니다. 인증은 이메일 로그인과 소셜 로그인 흐름을 고려하고, 로그인 후 발급된 토큰을 이용해 북마크, 컬렉션, 일정, 미디어 업로드 API에 접근합니다.

## 핵심 기능

- 여행지 홈, 테마 카드, 지역/카테고리 기반 탐색
- 여행지 목록, 상세 정보, 이미지 갤러리, 감정/특징 정보 표시
- 감정과 취향 기반 추천 플로우
- 북마크와 컬렉션 기반 장소 저장
- 일정 생성, 조회, 수정, 삭제
- 여행 일지 작성, 상세 보기, 이미지 첨부
- 프로필 조회와 수정
- 이메일 로그인, 회원가입, 소셜 로그인 진입 흐름
- 미디어 선택과 업로드 API 연동 구조

## 앱 구조

```mermaid
flowchart LR
    App[Flutter App] --> Router[go_router]
    App --> Providers[Provider / MultiProvider]
    App --> Env[Env / --dart-define]

    Router --> Start[Start]
    Router --> Auth[Auth]
    Router --> Explore[Explore]
    Router --> ForYou[For You]
    Router --> Record[Record]
    Router --> Journey[Journey]
    Router --> Profile[Profile / Bookmark]

    Explore --> TourAPI[Tour API]
    Explore --> Backend[Spring Boot Backend]
    ForYou --> Backend
    Record --> Backend
    Journey --> Backend
    Profile --> Backend
    Auth --> Backend
    Bookmark[Bookmark / Collection] --> Backend

    Providers --> Media[MediaRepository / MediaApiClient]
    Media --> Backend
```

## 기술 스택

- Flutter / Dart
- go_router
- provider
- http
- shared_preferences
- flutter_secure_storage
- flutter_web_auth_2
- image_picker
- geolocator
- cached_network_image
- flutter_svg
- table_calendar

## 디렉터리 구조

```text
lib/
  app/                 # MaterialApp, go_router 설정
  core/                # 공통 설정, 테마, 네트워크, 레이아웃 위젯
  features/
    auth/              # 로그인, 회원가입, 토큰 저장, 소셜 로그인
    explore/           # 여행지 홈, 목록, 상세, 검색, Tour API 연동
    foryou/            # 기존 추천 UI
    foryou_v2/         # 개선된 추천 플로우
    bookmark/          # 북마크, 컬렉션
    record/            # 일정 생성/편집/조회
    journey/           # 여행, 일정, 다이어리
    profile/           # 프로필, 설정, 약관, 피드백
    start/             # 시작 화면
  shared/
    media/             # 미디어 선택, 업로드, 공통 미디어 위젯
assets/
  icons/               # 소셜 로그인 아이콘, 앱 아이콘
  terms/               # 약관/개인정보처리방침/마케팅 문서
```

## 빠른 시작

### 1. Flutter 환경 확인

```bash
flutter doctor
```

이 프로젝트는 Dart SDK `^3.8.1` 환경을 기준으로 합니다.

### 2. 의존성 설치

```bash
flutter pub get
```

### 3. 환경 변수 준비 (`--dart-define`)

환경값은 전부 컴파일 타임 `--dart-define`으로 주입합니다. 예전에는 `.env`를 `pubspec.yaml`의 `assets`에 올려 런타임에 읽었지만, 에셋은 APK 안에 원본 그대로 실려 나가므로 걷어냈습니다(이슈 #29).

값이 여러 개라 매번 타이핑하기 번거로우면 템플릿을 복사해 파일로 넘깁니다. `dart-define.json`은 Git에 커밋하지 않습니다.

```bash
cp dart-define.example.json dart-define.json   # 값을 채운다
flutter run --dart-define-from-file=dart-define.json
```

`YOUR_DECODING_SERVICE_KEY`는 공공데이터포털 서비스 키입니다. 인코딩된 키와 디코딩된 키를 모두 처리할 수 있도록 앱에서 정규화합니다.

> `--dart-define`은 완화책이지 해결이 아닙니다. 값은 여전히 빌드 산출물 안의 문자열입니다. 관광공사 서비스 키를 앱에서 완전히 없애는 것은 백엔드 프록시 작업(M3, 이슈 #29 B)입니다.

### 4. 앱 실행

아무 값도 주지 않으면 `Env.apiBase`는 `http://10.0.2.2:8080`(에뮬레이터 → 호스트 로컬)으로 폴백합니다.

Android 에뮬레이터에서 로컬 백엔드를 사용할 때:

```bash
flutter run --dart-define=API_BASE=http://10.0.2.2:8080
```

배포 서버를 사용할 때:

```bash
flutter run --dart-define=API_BASE=https://your-backend.example.com
```

`API_BASE`는 `API_BASE_URL`보다 우선합니다. 템플릿 파일에 운영 주소를 `API_BASE_URL`로 넣어두고, 잠깐 로컬로 붙일 때만 `--dart-define=API_BASE=...`로 덮어쓰는 식으로 씁니다.

## 개발 명령

```bash
flutter analyze
flutter test
dart format lib test
```

앱 아이콘을 다시 생성해야 하는 경우:

```bash
dart run flutter_launcher_icons
```

## 환경 변수

전부 `--dart-define` 키입니다(`lib/core/config/env.dart`의 `Env`).

| 이름 | 설명 | 예시 |
| --- | --- | --- |
| `API_BASE` | 백엔드 주소 override. `API_BASE_URL`보다 우선 | `http://10.0.2.2:8080` |
| `API_BASE_URL` | Spring Boot 백엔드 API 주소 | `https://your-backend.example.com` |
| `YOUR_DECODING_SERVICE_KEY` | 공공데이터포털 Tour API 서비스 키 | 커밋 금지 |
| `MOBILE_OS` | Tour API 요청용 OS 값 | `ETC` |
| `MOBILE_APP` | Tour API 요청용 앱 이름 | `HeatTrip` |

## 보안 메모

- `dart-define.json`, keystore, Firebase 설정 파일, 서비스 계정 JSON은 Git에 커밋하지 않습니다. 추적되는 것은 값이 빈 `dart-define.example.json`뿐입니다.
- Android release signing 파일은 `android/key.properties`와 keystore로 관리하고, 저장소에는 올리지 않습니다.
- 실제 운영 API 주소와 서비스 키는 빌드 시 `--dart-define`으로 주입합니다. `.env`를 에셋으로 번들링하던 방식은 폐기했습니다(이슈 #29).
- 다만 `--dart-define` 값도 빌드 산출물 안에 문자열로 남습니다. 쿼터·과금이 걸린 자격증명(관광공사 서비스 키)을 앱에서 실제로 없애려면 백엔드 프록시가 필요합니다(M3).
- public 저장소에서는 secret scan 경고가 나올 수 있는 예시 값을 README에 넣지 않습니다.

## 현재 라우트 개요

| 경로 | 기능 |
| --- | --- |
| `/start` | 시작 화면 |
| `/auth/login` | 로그인 |
| `/auth/sign-up` | 회원가입 |
| `/explore` | 여행지 홈 |
| `/explore/list` | 여행지 목록 |
| `/explore/:contentId/:contentTypeId` | 여행지 상세 |
| `/record` | 일정 |
| `/foryou_v2` | 추천 플로우 |
| `/journey` | 여행/다이어리 |
| `/profile` | 프로필 |
| `/bookmarks` | 북마크 컬렉션 |

## 문서 관리

프론트엔드 구조와 화면별 구현 상세는 각 feature 폴더의 문서와 코드 주석에서 관리합니다. 백엔드 API 계약이 바뀌면 이 README의 환경 변수, 실행 방법, 라우트/기능 설명도 함께 갱신합니다.
