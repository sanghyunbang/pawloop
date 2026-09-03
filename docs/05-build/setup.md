# 개발환경 세팅 (setup)

> Pawloop(포루프) 프론트(Flutter)와 백엔드(Spring Boot)를 로컬에서 실행하기 위한 설치·환경변수·에뮬레이터·빌드 명령 정리. 실제 `pubspec.yaml` / `app/dart-define.example.json` / `application-*.properties` 구조를 그대로 반영한다.

---

## 1. 사전 준비물 (Prerequisites)

| 도구 | 버전 | 용도 |
| --- | --- | --- |
| Flutter SDK | **3.44.4** (Dart **3.12.2**, `sdk: ^3.8.1`) | 앱 빌드/실행 |
| Android Studio + Android SDK | **compileSdk 36**, minSdk 23 | 에뮬레이터/디바이스 빌드 |
| JDK | **17** (Android 빌드용) | Gradle/AGP |
| Android Gradle Plugin | **8.11.1** | 안드로이드 빌드 |
| Kotlin | **2.2.20** | 안드로이드 빌드 |
| Gradle Wrapper (app/android) | **8.13** | 안드로이드 빌드 |
| (백엔드) JDK | **21** | Spring Boot 실행 |
| (백엔드) MySQL | 8.x (공간형 POINT/LINESTRING) | 로컬 DB |

> Flutter/Dart 버전과 안드로이드 툴체인(AGP 8.11.1 / Kotlin 2.2.20 / Gradle 8.13 / compileSdk 36 / minSdk 23 / Java 17)은 프로젝트 설정에 고정되어 있으므로 임의 상향하지 말 것.

### Flutter 설치 확인

```bash
flutter --version          # Flutter 3.44.4 / Dart 3.12.2 확인
flutter doctor             # Android toolchain / 라이선스 상태 점검
flutter doctor --android-licenses
```

---

## 2. 프로젝트 클론 & 의존성 설치

```bash
git clone <repo-url> heattrip
cd heattrip/app          # ← Flutter 앱 루트는 heattrip/app
flutter pub get
```

주요 프론트 패키지(`app/pubspec.yaml`):

| 패키지 | 버전 | 역할 |
| --- | --- | --- |
| `flutter_naver_map` | ^1.3.1 (1.4.x 호환) | 지도 SDK |
| `fl_chart` | ^1.2.0 | 산책 통계 차트 |
| `lottie` | ^3.4.0 | 애니메이션 |
| `google_fonts` | ^8.1.0 | 폰트(Pretendard 로컬 에셋 병행) |
| `go_router` | ^16.1.0 | 라우팅(MainShell) |
| `provider` | ^6.1.5 | 상태/DI |
| `geolocator` | ^13.0.1 | 위치(도입됨, 화면은 아직 서울 고정) |
| `http` | ^1.4.0 | REST/공공데이터 호출 |
| `flutter_secure_storage` / `shared_preferences` | ^9.2.4 / ^2.5.3 | 토큰/설정 저장 |

> 참고: `.env` 는 더 이상 쓰지 않는다. 에셋으로 번들링하면 APK 안에 원본 그대로 실려 나가기 때문에 `flutter_dotenv` 째로 걷어냈다(이슈 #29). 환경값은 3절의 `--dart-define` 으로 넣는다. 폰트 Pretendard는 `assets/fonts/`의 로컬 OTF를 사용한다.
>
> **`.env` 가 없어도 `flutter pub get` / `analyze` / `test` / `build` 가 전부 통과한다.** 새로 클론한 직후 바로 돌려도 된다.

---

## 3. 프론트 환경변수 — `--dart-define` (`.env` 아님)

앱의 환경값은 **컴파일 타임 `--dart-define`** 으로만 들어온다. 읽는 곳은 `lib/core/config/env.dart`의 `Env` 하나뿐이고, 런타임 파일 로드는 없다.

> **왜 `.env`를 버렸나.** `pubspec.yaml`의 `assets`에 올린 파일은 APK/IPA 안에 **원본 그대로** 들어간다. `unzip -p app-release.apk assets/flutter_assets/.env` 한 줄이면 값이 그대로 보였다. → [이슈 #29](https://github.com/sanghyunbang/heattrip/issues/29)

### 3.1 값 넣는 법

전부 기본값이 있어서 **아무것도 주지 않아도 빌드·실행은 된다**(지도/공공데이터만 비활성). 실제 키를 쓰려면 둘 중 하나.

**(a) 한두 개만 잠깐** — 커맨드라인에 직접

```bash
flutter run --dart-define=API_BASE=http://10.0.2.2:8080
```

**(b) 매번 쓰는 값 묶음** — 템플릿을 복사해 파일로 넘긴다. `app/dart-define.json`은 `.gitignore` 대상이다.

```bash
cd heattrip/app
cp dart-define.example.json dart-define.json   # 값을 채운다
flutter run --dart-define-from-file=dart-define.json
```

```jsonc
// app/dart-define.json  (추적되지 않음 / 추적되는 건 값이 빈 dart-define.example.json)
{
  "API_BASE_URL": "https://api.heattrip.link",
  "NAVER_MAP_CLIENT_ID": "<네이버 클라우드 Client ID>"
}
```

### 3.2 키별 설명

| 키 | 읽는 위치 | 기본값 | 의미 / 주의 |
| --- | --- | --- | --- |
| `API_BASE` | `Env.apiBase` | (없음) | 로컬/스테이징 전환용 override. `API_BASE_URL`보다 **우선**한다. |
| `API_BASE_URL` | `Env.apiBase` | (없음) | 백엔드 베이스 URL. 운영은 `https://api.heattrip.link`. |
| `NAVER_MAP_CLIENT_ID` | `Env.naverMapClientId` | `''` | 네이버 지도 SDK 초기화(`FlutterNaverMap().init`). 비어 있으면 지도 탭이 비활성(안내문)만 표시된다. |
| `UPLOAD_LOCATION` | `LocationUploadPolicy` | `false` | **좌표를 서버로 보낼지.** 기본이 안전한 쪽이다 — 켜려면 명시해야 한다. 위치기반서비스사업 신고 전에는 켜면 안 된다([#235](https://github.com/sanghyunbang/heattrip/issues/235)). |

> `Env.apiBase` 우선순위: **(1)** `--dart-define=API_BASE=...` → **(2)** `--dart-define=API_BASE_URL=...` → **(3)** `http://10.0.2.2:8080`.

> [!WARNING]
> **관광공사 서비스키는 이제 앱에 없다**([#40](https://github.com/sanghyunbang/heattrip/issues/40)). 호출 자체를 백엔드로 옮겼고, 키는 서버 환경변수 `TOUR_API_SECRET` 으로만 존재한다.
>
> `--dart-define` 은 완화였을 뿐이다 — 값이 컴파일 타임에 코드로 박히고 문자열은 바이너리에 남아 `strings` 한 번이면 나온다. **여기에 그 키를 다시 넣지 말 것.**

### 3.3 신고 전 배포본 — 좌표를 안 보내는 빌드

위치기반서비스사업 신고(위치정보법 제9조)는 사업자등록이 있어야 할 수 있다. 그것이 없는 동안 배포하는 빌드는 **좌표가 단말을 떠나지 않아야 한다**([#235](https://github.com/sanghyunbang/heattrip/issues/235) · `docs/00-product/legal-lbs-compliance.md`).

그 빌드는 **아무것도 더 하지 않는 것**으로 만들어진다 — 기본값이 이미 안전한 쪽이다.

```bash
# 좌표를 안 보내는 빌드. UPLOAD_LOCATION 과 NAVER_MAP_CLIENT_ID 를 **주지 않는다.**
flutter build apk --release --dart-define=API_BASE_URL=https://api.heattrip.link
```

| 무엇이 | 왜 |
| --- | --- |
| `UPLOAD_LOCATION` 을 안 준다 | `LocationUploadPolicy` 가 산책 경로·주변 장소 조회·커뮤니티 장소를 전부 죽인다 |
| `NAVER_MAP_CLIENT_ID` 를 안 준다 | 지도 SDK 에 카메라 중심(= 사용자 좌표)이 안 넘어간다. `Env.hasNaverMap` 이 false 라 세 지도 화면이 `MapUnavailable` 로 떨어진다 |

**확인은 테스트가 한다.** `app/test/v2/data/location_upload_policy_test.dart` 가 소스를 훑어 정책을 안 지나는 전송 경로가 있는지 세고, 진짜 저장소에 목을 꽂아 값이 실제로 죽는지 본다.

신고를 마친 뒤에는 `--dart-define=UPLOAD_LOCATION=true` 를 붙이면 된다. **코드를 되돌릴 필요가 없다** — 그 하나를 위해 정책 객체를 둔 것이다.
>
> ⚠️ **아직 남은 일**: 이미 배포된 빌드에는 그 키가 들어 있으므로 **유출된 것으로 보고 폐기·재발급**해야 한다. 순서는 프록시 배포 → 앱 업데이트 배포 → 구 키 폐기다.

### 네이버 지도 콘솔 등록 (지도 인증 실패 방지)

- 네이버 클라우드 플랫폼 콘솔에서 Mobile Dynamic Map 애플리케이션을 만들고 **Client ID**를 발급.
- Android 패키지명 **`com.cetacealab.heattrip`** 을 허용목록에 등록해야 인증이 통과한다(`onAuthFailed` 로그로 확인 가능).

---

## 4. 에뮬레이터 / 디바이스 실행

### 에뮬레이터 준비

```bash
flutter devices           # 연결된 에뮬레이터/디바이스 목록
flutter emulators         # 등록된 AVD 목록
flutter emulators --launch <avd_id>
```

### 앱 실행

```bash
cd heattrip/app

# (아무 값 없이) Env.apiBase 가 http://10.0.2.2:8080 으로 폴백. 지도/공공데이터는 비활성.
flutter run

# (평소) 값 묶음을 파일로 주기 — 3.1 (b)
flutter run --dart-define-from-file=dart-define.json

# (로컬 백엔드로 붙기) 파일의 API_BASE_URL 을 그때만 덮어쓴다
flutter run --dart-define-from-file=dart-define.json \
            --dart-define=API_BASE=http://10.0.2.2:8080
```

> 에뮬레이터에서 `localhost`는 에뮬레이터 자신을 가리키므로, 호스트 PC의 로컬 백엔드는 반드시 **`10.0.2.2`** 로 접근한다(`Env.localEmulator`).

---

## 5. 로컬 백엔드 실행 (선택)

백엔드 루트: `heattrip/backend` (Spring Boot 3.5.4, **Java 21**, MySQL). 앱을 로컬 백엔드에 붙이지 않고 운영 원격(`api.heattrip.link`)만 쓸 거면 이 절은 건너뛰어도 된다.

### 5.1 사전 조건

- **JDK 21** 설치.
- 로컬 **MySQL**에 DB 생성(기본값 `heat_trip_db`).

```sql
CREATE DATABASE heat_trip_db CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
```

### 5.2 백엔드 환경변수 (`backend/.env` 또는 셸 env)

`application-dev.properties`가 `spring.config.import=optional:file:./.env[.properties]`로 로컬 `.env`를 자동 로드한다. 모든 값에 개발용 기본값이 있어 최소 세팅으로도 뜨지만, 실제 DB/외부연동은 아래를 채운다.

| 항목 | 키(env) | 기본값 | 비고 |
| --- | --- | --- | --- |
| 서버 포트 | `SERVER_PORT` | `8080` | 앱 폴백 `10.0.2.2:8080`과 일치 |
| DB URL | `SPRING_DATASOURCE_URL` | `jdbc:mysql://localhost:3306/heat_trip_db?...` | 공간형 스키마 |
| DB 계정 | `SPRING_DATASOURCE_USERNAME` / `SPRING_DATASOURCE_PASSWORD` | `root` / (빈값) | 로컬 MySQL 계정 |
| DDL | `SPRING_JPA_HIBERNATE_DDL_AUTO` | `update` | 개발용 자동 반영 |
| JWT 시크릿 | `JWT_SECRET` | dev 기본값 | 운영은 반드시 교체 |
| 관광 API 시크릿 | `TOUR_API_SECRET` | `dev-tour-api-secret` | 백엔드 프록시 경로용 |
| OpenAI(추천) | `OPENAI_API_KEY` | `disabled-local-placeholder` | 레거시 추천 파이프라인. 반려 맥락 재검토 대상, 미설정 시 비활성 |
| CORS 허용 | `APP_SECURITY_ALLOWED_ORIGINS` | `http://localhost:8080,http://10.0.2.2:8080` | 에뮬레이터 접근 허용됨 |

> OAuth(구글/카카오/네이버)·AWS S3·Kakao Local API 키는 전부 dev 기본값(placeholder)이 들어가 있어 로컬 부팅은 되지만, 소셜 로그인/이미지 업로드/장소 백필을 실제로 쓰려면 해당 키를 env로 주입해야 한다.

### 5.3 백엔드 실행

```bash
cd heattrip/backend

# dev 프로파일로 실행 (로컬 .env 자동 로드)
./gradlew bootRun --args='--spring.profiles.active=dev'

# 또는 빌드 후 jar 실행
./gradlew clean build
java -jar -Dspring.profiles.active=dev build/libs/*.jar
```

- 기동 확인: `http://localhost:8080/actuator/health`
- 백엔드 Gradle Wrapper는 8.14.3(앱 안드로이드 Wrapper 8.13과 별개).

### 5.4 소셜 로그인(구글) 로컬 테스트

> 이 절의 존재 이유: **구글은 사설 IP의 http redirect URI를 등록해주지 않는다.** 카카오는 `http://10.0.2.2:8080`을 그대로 받아주기 때문에 지금까지 이 차이가 드러나지 않았다. (이슈 #3)

#### 왜 `10.0.2.2` 로는 안 되는가

백엔드의 `APP_BASE_URL` 이 그대로 구글 redirect URI 가 된다.

```
APP_BASE_URL=http://10.0.2.2:8080
  → redirect URI = http://10.0.2.2:8080/login/oauth2/code/google   ← 구글 콘솔이 거부
```

구글이 받아주는 형태는 **https** 이거나 **`http://localhost`** 둘뿐이다.

#### 구글 클라우드 콘솔 — 승인된 리디렉션 URI

OAuth 클라이언트는 이미 만들어져 있다(`backend/.env` 에 `GOOGLE_CLIENT_ID`/`GOOGLE_CLIENT_SECRET` 존재). 아래 두 개가 목록에 있는지만 확인하고, 없으면 추가한다.

| 환경 | 등록할 redirect URI |
| --- | --- |
| 운영/스테이징 | `https://api.heattrip.link/login/oauth2/code/google` |
| 로컬 개발 | `http://localhost:8080/login/oauth2/code/google` |

#### 로컬 왕복 절차 (안드로이드 에뮬레이터)

에뮬레이터에서 `localhost` 는 에뮬레이터 자신을 가리키므로, 호스트 PC 의 8080 을 에뮬레이터의 8080 으로 되돌려 꽂는다.

```bash
# 1) 에뮬레이터의 localhost:8080 → 호스트 PC 의 8080 으로 포워딩
adb reverse tcp:8080 tcp:8080

# 2) 백엔드를 localhost 기준으로 띄운다 (redirect URI 가 localhost 로 만들어진다)
cd heattrip/backend
APP_BASE_URL=http://localhost:8080 ./gradlew bootRun --args='--spring.profiles.active=dev'

# 3) 앱도 같은 주소를 보게 한다. API_BASE 가 API_BASE_URL 보다 우선하므로
#    dart-define.json(운영 주소가 든 값 묶음)은 건드릴 필요가 없다.
cd heattrip/app
flutter run --dart-define-from-file=dart-define.json \
            --dart-define=API_BASE=http://localhost:8080
```

- `adb reverse` 는 **안드로이드 전용**이다. iOS 시뮬레이터는 호스트와 `localhost` 를 공유하므로 그냥 `http://localhost:8080` 을 쓰면 된다.
- 터널(ngrok 등)로 공개 https 주소를 붙여도 되지만, 실행할 때마다 URL 이 바뀌면 콘솔에 매번 재등록해야 한다.

#### 딥링크 복귀 설정 (이게 없으면 로그인이 끝나도 앱으로 못 돌아온다)

`flutter_web_auth_2` 는 로그인 후 `heattrip://login-callback?code=...&state=...` 로 앱에 돌아온다(#14 이전에는 `?token=...` 이었다). 양 플랫폼 모두 OS 에 스킴이 등록돼 있어야 한다.

| 플랫폼 | 파일 | 내용 |
| --- | --- | --- |
| iOS | `app/ios/Runner/Info.plist` | `CFBundleURLTypes` → `CFBundleURLName=com.cetacealab.heattrip`, `CFBundleURLSchemes=[heattrip]` |
| Android | `app/android/app/src/main/AndroidManifest.xml` | `com.linusu.flutter_web_auth_2.CallbackActivity` + `scheme=heattrip`, `host=login-callback` |

> [!WARNING]
> 안드로이드 intent-filter 는 **`MainActivity` 가 아니라 플러그인의 `CallbackActivity`** 에 달아야 한다. 플러그인은 `CallbackActivity.onCreate` 에서만 대기 중인 결과를 완료시키기 때문에, `MainActivity` 로 받으면 앱은 앞으로 나오지만 `authenticate()` 의 Future 가 영원히 끝나지 않는다.
>
> `android:autoVerify="true"` 는 App Links(https) 전용 속성이라 커스텀 스킴에는 의미가 없다. 붙이지 않는다.

이 설정값들은 `app/test/platform_config_test.dart` 가 지키고 있다. 지우면 `flutter test` 가 빨간불이 된다.

---

## 5.1 안 될 때 — 실제로 겪은 것 둘

### `/api/places/nearby` 가 어느 좌표를 넣어도 `[]` 를 준다

HTTP 는 **200** 이고 본문만 빈 배열이라 오류처럼 안 보입니다. 원인은 둘 중 하나입니다.

**1) 서비스 키가 관광공사에 등록돼 있지 않다.** 백엔드 로그에 이 줄이 있으면 그것입니다.

```
WARN  c.h.h.place.service.KtoApiClient
      KTO 게이트웨이가 거절했다 — op=nearby returnReasonCode=30 msg=등록되지 않은 서비스키
```

키를 직접 던져 보면 갈립니다. `<키>` 자리에 `backend/.env` 의 `TOUR_API_SECRET` 을 넣습니다.

```bash
curl -s "https://apis.data.go.kr/B551011/KorPetTourService2/locationBasedList2?serviceKey=<키>&MobileOS=ETC&MobileApp=t&_type=json&numOfRows=1&pageNo=1&mapX=126.99&mapY=37.57&radius=2000"
```

`resultCode: "0000"` 이면 키는 정상입니다. **403 이면 그 키가 문제**입니다 — 2026-09-02 에 실제로
`backend/.env` 와 `app/.env` 의 키가 서로 달랐고, 동작하는 쪽이 앱에 남아 있었습니다(#182).
앱은 #40 이후 그 키를 안 쓰므로 **서버 쪽만 맞으면 됩니다.**

**2) 그날의 호출 예산이 닫혀 있다.** KTO 가 한 번이라도 `resultCode=22`(한도) 나 `30`(키)을 주면
`KtoCallBudget.closeForToday` 가 **DB 에** `used = cap` 을 박습니다. 재시작해도 안 풀립니다.

```sql
SELECT `day`, pool, used FROM kto_call_budget ORDER BY `day` DESC;
-- 오늘 행의 used 가 cap(기본 300)이면 닫힌 것입니다.
UPDATE kto_call_budget SET used = 0 WHERE `day` = CURDATE() AND pool = 'nearby';
```

키를 고쳐도 이 행을 안 풀면 **여전히 빈 배열**입니다. 둘을 함께 봐야 합니다.

### 지도 자리에 "지도를 불러올 수 없어요" 가 뜬다

`NAVER_MAP_CLIENT_ID` 없이 빌드한 것입니다. 3절의 `--dart-define` 을 빠뜨리면 이렇게 됩니다.

예전에는 이 경우 **빨간 assertion** 이 그대로 보였습니다. 지금은 세 화면(`explore` ·
`walk_tracking` · `emotion_map`)이 `Env.hasNaverMap` 을 보고 안내문으로 대신합니다(#182).

---

## 6. 빌드 명령 정리

### 프론트 (app/)

```bash
# 코드 정적 분석 / 테스트
flutter analyze
flutter test

# 디버그 실행
flutter run
flutter run --dart-define=API_BASE=http://10.0.2.2:8080   # 로컬 백엔드 연동

# 릴리스 APK / AAB — 실제 키는 여기서 주입한다(에셋에 들어 있지 않다)
flutter build apk --release --dart-define-from-file=dart-define.json
flutter build appbundle --release --dart-define-from-file=dart-define.json

# 번들에 .env 가 남아 있지 않은지 확인 (아무것도 안 나와야 정상)
unzip -l build/app/outputs/flutter-apk/app-release.apk | grep -F 'flutter_assets/.env'

# 클린
flutter clean && flutter pub get
```

> **릴리스 서명**: `android/app/build.gradle.kts`는 릴리스 태스크(`assembleRelease`/`bundleRelease`)일 때만 `android/key.properties`를 요구한다. 파일이 없으면 릴리스 빌드가 의도적으로 실패하고, 디버그 빌드는 키 없이 항상 동작한다. 스토어 제출 전 `android/key.properties`(keystore) 준비 필요.

### 앱 아이콘 재생성 (선택)

```bash
dart run flutter_launcher_icons
```

---

## 7. 빠른 체크리스트

- [ ] `flutter --version` → 3.44.4 / Dart 3.12.2
- [ ] `flutter pub get` 성공 (`.env` 없이 그냥 된다)
- [ ] `cp app/dart-define.example.json app/dart-define.json` 후 2개 키(`API_BASE_URL`, `NAVER_MAP_CLIENT_ID`) 채움 — 이 파일은 커밋되지 않는다. **관광공사 키는 여기 없다**(#40)
- [ ] 네이버 콘솔에 패키지명 `com.cetacealab.heattrip` 등록
- [ ] 에뮬레이터 부팅 후 `flutter run --dart-define-from-file=dart-define.json` — 지도 탭에 KTO 실데이터(서울) 표시되면 키 정상
- [ ] (로컬 백엔드 쓸 때) MySQL `heat_trip_db` 생성 + `./gradlew bootRun` + 앱에 `--dart-define=API_BASE=http://10.0.2.2:8080` 추가
- [ ] (구글 로그인 테스트할 때) `adb reverse tcp:8080 tcp:8080` + 백엔드 `APP_BASE_URL=http://localhost:8080` + 앱 `--dart-define=API_BASE=http://localhost:8080` → [5.4](#54-소셜-로그인구글-로컬-테스트)

---

## 관련 문서

- [ERD](../03-database/erd.md) — 데이터 모델(MySQL 공간형)
