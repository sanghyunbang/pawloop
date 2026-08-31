# Pawloop(포루프) REST API 명세

> [!IMPORTANT]
> **API 계약의 단일 출처(SSOT)는 [`openapi.yaml`](openapi.yaml) 이다.**
> 이 문서는 사람이 읽기 위한 요약이며, 값이 충돌하면 **언제나 `openapi.yaml` 이 우선한다.**
> 계약을 바꿀 때는 `openapi.yaml` 을 먼저 고치고, 이 문서를 뒤따라 맞춘다.

> 산책·동반장소·커뮤니티 앱 **Pawloop(포루프)**의 REST API 명세. 현재 구현된 부분과 **계획(Planned)** 을 함께 정리한다. 지금 앱은 장소 데이터를 관광공사 KTO API로 **직접 호출**하고 있으며, 백엔드는 이 문서의 프록시·저장 API로 점진 이전한다.

관련 문서: [ERD](../03-database/erd.md) · [아키텍처](../02-architecture/)

---

## 0. 개요

| 항목 | 값 |
|---|---|
| 백엔드 | Spring Boot (Java/Kotlin 혼용) + MySQL(공간형 POINT/LINESTRING) |
| Base URL(운영) | `https://api.heattrip.link` (도메인 유지, 서비스명만 Pawloop로 피벗) |
| Base URL(로컬) | `http://10.0.2.2:8080` (안드로이드 에뮬레이터 → 호스트 localhost) |
| 프론트 진입점 | `app/lib/core/config/env.dart` → `Env.apiBase` (`--dart-define=API_BASE` > `--dart-define=API_BASE_URL` > `Env.localEmulator`) |
| 인증 | JWT Bearer 토큰 (`Authorization: Bearer <token>`) |
| Content-Type | `application/json; charset=utf-8` |
| 시간 | ISO-8601 (`2026-06-30T08:12:00+09:00`), 서버는 KST 기준 |
| 좌표 | WGS84 위도(`lat`)/경도(`lng`). KTO 응답의 `mapx`=경도, `mapy`=위도 |

### 구현 상태 범례

| 표기 | 의미 |
|---|---|
| ✅ 구현 | 레거시 백엔드에 유사 엔드포인트 존재(감정앱). Pawloop 맥락으로 재사용/개편 |
| 🟡 계획 | Pawloop MVP 대상. 아직 미구현(설계 확정) |
| 🔵 프록시 계획 | 현재 앱이 외부 API 직접 호출. 백엔드 프록시+캐싱으로 이전 예정 |
| ⚪ post-MVP | 확장 범위. 스텁만 |

> 레거시 백엔드(`backend/`)에는 감정앱 시절의 `/auth`(signup/login/me), `/api/social`(cards/comments/reactions), tour import 컨트롤러가 있다. 아래 명세는 이 구조와 JWT 규약을 **그대로 계승**하되, 리소스명을 반려(강아지) 도메인으로 바꾼 것이다.

---

## 1. 공통 규약

### 1.1 인증 헤더

```http
Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9...
```

- JWT 의 `sub` 는 서버가 발급한 **불투명 사용자 키**다. 이메일이라고 가정하거나 파싱하지 말 것 — 소셜 로그인 경로에서는 이메일이 아니다. 사용자 정보가 필요하면 `GET /auth/me` 로 조회한다.
- 현재 발급되는 클레임은 `sub`·`role`·`iat`·`exp` 뿐이다. `jti` 가 없어 로그아웃해도 액세스 토큰은 만료까지 유효하다. #9 는 `jti` 를 도입하지 않기로 했다 — 블록리스트 저장소라는 소비자가 있어야 의미가 있고, 그건 M2 이후 별도 Epic 이다. 로그아웃은 대신 **서버측 refresh 토큰을 전부 폐기**한다(#9).
- 소셜 로그인 계정과 이메일 가입 계정은 **같은 경로로 동작한다.** 어느 쪽 토큰으로든 `GET /auth/me`·`PUT /auth/me`·`DELETE /auth/me`·`POST /auth/logout` 이 200/204 다. (2026-08 이전에는 소셜 계정에서 400 이었다. #5 에서 해소되었다.)
- 토큰 없음/만료/무효 → `401 Unauthorized`. **본문이 없다** — 상태 코드만 돌아오고 `Content-Type` 도 없다.
  토큰 없음·서명 위조·만료·옛 형식 subject·탈퇴 계정의 살아 있는 토큰이 전부 같은 모양이다(실패 원인을 알려 주지 않는 것이 의도다 — #6).
  클라이언트는 `error.code` 를 읽어 분기하지 말고 상태 코드 401 만 보고 재로그인으로 보낸다. (#5)
- MVP 단계에서는 로그인 없이도 홈/지도/산책이 동작하도록 **비인증 읽기**를 일부 허용(장소 조회 등). 쓰기(산책 저장·글 작성)는 인증 필요.

### 1.2 페이지네이션

목록 API는 커서 기반을 기본으로 한다.

| 파라미터 | 타입 | 기본 | 설명 |
|---|---|---|---|
| `limit` | int | 20 | 페이지 크기(최대 100) |
| `cursor` | string | - | 이전 응답의 `nextCursor` |

```json
{
  "items": [ /* ... */ ],
  "nextCursor": "eyJpZCI6MTIzfQ==",
  "hasMore": true
}
```

### 1.3 에러 포맷

4xx·5xx 본문은 **이 봉투 하나뿐이다**(#10). 만드는 곳도 `GlobalExceptionHandler` 한 곳이다.

```json
{
  "error": {
    "code": "NOT_FOUND",
    "message": "해당 장소를 찾을 수 없습니다.",
    "traceId": "b3f1..."
  }
}
```

`code` 는 **HTTP 상태 하나당 하나로 고정**된다 — 던지는 쪽이 문자열을 손으로 적지 않는다.
`traceId` 는 응답 헤더 `X-Correlation-Id` 와 같은 값이며, 서버 로그에서 그 요청을 집는 열쇠다.

| HTTP | code | 상황 |
|---|---|---|
| 400 | `VALIDATION` | 요청 바디/쿼리 검증 실패, 읽을 수 없는 JSON |
| 401 | (본문 없음) | 토큰 없음/무효, 자격증명 실패 — 이 표에서 유일하게 **본문을 주지 않는** 상태다(위 1.1 참조) |
| 403 | `FORBIDDEN` | 타인 리소스 수정 시도 |
| 404 | `NOT_FOUND` | 리소스 없음, 알 수 없는 경로 |
| 405 | `METHOD_NOT_ALLOWED` | 그 경로가 지원하지 않는 HTTP 메서드 |
| 409 | `CONFLICT` | 중복(예: 이미 가입된 이메일) |
| 415 | `UNSUPPORTED_MEDIA_TYPE` | `Content-Type` 이 `application/json` 이 아님 |
| 429 | `RATE_LIMITED` | 외부 데이터(예: KTO 1000콜/일) 한도, 또는 서버의 요청 빈도 제한. 인증 경로(`POST /auth/login`·`POST /auth/token/refresh`·`POST /auth/oauth/{provider}/callback`·`GET /oauth2/authorization/*`)가 여기 걸린다(#14). `Retry-After` 헤더에 창 길이(초)가 실린다. 버킷 이름·한도 수치는 본문에 싣지 않는다 |
| 500 | `INTERNAL` | 서버 오류. `message` 는 고정 문구다 — 예외 메시지에는 SQL 조각·경로·이메일·토큰이 섞인다(#6) |

> 2026-08 이전에는 실제 응답이 세 갈래였다: 이 봉투(계약), 전역 처리기의
> `{ status, error, message, path, timestamp }`, `SocialController` 의 `{ "error": "문자열" }`.
> #10 이 하나로 합쳤다. `VALIDATION_ERROR`·`INTERNAL_ERROR` 표기도 이때 사라졌다.

---

## 2. 인증 (Auth)

카카오·구글 OAuth 중심(레거시 `kakao/`, `OAuth/` 패키지 계승). 네이버는 **보류**다 — [ADR-0010](../99-decisions/decision-log.md#adr-0010--소셜-로그인-공급자와-앱-세션-토큰-전략) 이 확정했고 계약 enum 과 `AuthController.SUPPORTED_PROVIDERS` 에서 함께 뺐다. 다만 클라이언트 등록과 `NaverOAuth2User` 매핑은 아직 남아 있어 `/oauth2/authorization/naver` 는 열려 있다 — 그 구멍은 #13 소유다. 프론트는 `flutter_web_auth_2`로 소셜 로그인 콜백을 받는다.

> JWT 의 `sub` 는 서버가 발급한 **불투명 사용자 키**다. 이메일이라고 가정하거나 파싱하지 말 것. 사용자 정보는 `GET /auth/me` 로 조회한다.

**인가 경계** — 비인증 허용은 `/auth/signup`, `/auth/login`, `/auth/oauth/**`, `/auth/token/refresh`, `/oauth2/**`, `/login/oauth2/**` 뿐이다. `/auth/me`(GET·PUT·DELETE)와 `/auth/logout` 은 반드시 토큰 검증을 거친다.

### 2.1 소셜 로그인 시작 — ✅ 구현

`GET /oauth2/authorization/{provider}` — `provider ∈ {kakao, google}` (naver 보류)

앱(`flutter_web_auth_2`)이 실제로 여는 URL. 소셜 인증 화면으로 302 리다이렉트되고, 성공 시 백엔드가 앱 딥링크 `heattrip://login-callback?code=<1회용 코드>&state=<앱이 만든 난수>` 로 되돌린다(#14).

**딥링크에는 토큰이 없다.** 쿼리 파라미터는 정확히 `code` 와 `state` 둘뿐이고, 토큰은 §2.2 의 교환 응답 본문으로만 온다.

> ⚠️ `state` 는 앱이 만들어 앱이 대조한다. 인증을 시작할 때 `?state=<난수>` 로 보내면 서버가 왕복 동안 붙들었다가 딥링크에 그대로 실어 돌려준다. **돌아온 값이 보낸 값과 다르면 로그인 실패로 처리하라** — 응답 바꿔치기를 막는 장치가 그것뿐이다. 허용 문자는 `[A-Za-z0-9_-]{1,128}`.
> `state` 없이 시작하면 딥링크의 `state` 가 빈 값이 되고, **그 코드는 §2.2 교환 단계에서 401 이다**(#14). 서버쪽 대조의 존재 여부를 왕복을 시작한 쪽이 정하지 못하게 하기 위한 것이다 — 항상 보내라.
> 예전에는 이 딥링크가 `?token=<JWT>&refresh=<refreshToken>` 이었다(#9). 커스텀 스킴은 어느 앱이든 등록할 수 있고 URL 은 302 의 `Location` 헤더·브라우저 히스토리에 남는다 — 그 채널로 1시간짜리 AT 와 14일짜리 RT 가 함께 나가고 있었다. #14 가 60초짜리 1회용 코드로 바꿨다.

> 계약에 있는 `GET /auth/oauth/{provider}` 는 이 경로로의 **302 래퍼**다(#10 에서 구현).
> 앱은 그걸 쓸 필요가 없다 — 위 경로를 직접 열면 리다이렉트 한 번을 아낀다.
> 예전에는 계약이 "미구현" 이라고 적었는데 실제로는 핸들러가 있었고 **빈 200** 을 줬다.
> `state` 는 그 래퍼를 통과해 전달된다(#14): `GET /auth/oauth/kakao?state=S` → `Location: /oauth2/authorization/kakao?state=S`. 화이트리스트(`[A-Za-z0-9_-]{1,128}`)를 통과하지 못한 값은 붙지 않는다 — 이 값은 `Location` 헤더에 그대로 들어가므로 검증 없이 이어 붙이면 헤더 주입이 된다. **2026-08 초에는 래퍼가 쿼리를 옮기지 않아** 이 경로로 시작한 로그인이 빈 `state` 를 받아 대조에서 항상 실패했다.
> 딥링크 스킴은 `heattrip://` 다 — 코드(`social_login_service.dart`, `OAuth2SuccessHandler.java`)가 그렇게 동작한다. 이 문서가 예전에 예시로 들던 `pawloop` 스킴은 오기였고, 그대로 구현하면 콜백을 받지 못한다.

### 2.2 소셜 로그인 콜백 → 토큰 교환 — ✅ 구현(#14)

`POST /auth/oauth/{provider}/callback`

소셜 로그인의 **마지막 단계**다. 딥링크로 받은 1회용 코드를 토큰으로 바꾼다. 인증이 필요 없다 — 주체는 코드 자체가 증명한다.

```json
// Request
{ "code": "딥링크로 받은 1회용 코드(패딩 없는 Base64URL 43자)", "state": "인증 시작 때 앱이 만든 난수" }
```

> `code` 는 **공급자가 준 인가코드가 아니다.** 공급자와의 코드 교환은 백엔드(Spring Security)가 이미 끝냈다. 그래서 이 흐름에는 PKCE 가 없다 — 앱이 공급자와 직접 말하게 바꾸는 날 필수가 된다. 그 판단의 근거와 트리거는 [ADR-0009](../99-decisions/decision-log.md#adr-0009--소셜-로그인에-pkce-를-도입하지-않는다) 에 있다.
> `redirectUri` 를 함께 보내도 **리다이렉트 대상으로 쓰이지 않는다.** 이 시점에는 리다이렉트가 이미 끝났고, 대상은 서버 설정(`app.security.oauth.redirect-allowlist`)이 정한다.

```json
// 200 OK
{
  "accessToken": "eyJhbGci...",
  "refreshToken": "9qQ1t...(패딩 없는 Base64URL 43자, JWT 아님)",
  "expiresIn": 3600,
  "isNew": false,
  "user": {
    "id": 42,
    "email": "bori@example.com",
    "nickname": "보리아빠"
  }
}
```

- `isNew` 는 **로그인 응답의 1회성 이벤트 속성**이라 `user` 블록 밖(`AuthTokens` 최상위)에 있다. `true` 면 프론트는 온보딩(강아지 프로필 등록)으로 유도.
- `refreshToken` 이 이 응답에 함께 실린다(#14). 소셜 로그인에서 refresh 토큰이 앱에 도달하는 **유일한 경로**다 — #14 이전에는 딥링크의 `refresh` 파라미터였다.
- 실패는 원인과 무관하게 **본문 없는 401** 이다 — 코드 재사용·만료(60초)·공급자 불일치·`state` 불일치가 전부 같은 모양이다. 구분해 주면 그 차이가 "그 코드가 존재하긴 했는가" 를 알려 주는 오라클이 된다. **실패한 교환도 코드를 죽인다** — 코드 하나에 시도 한 번이다.
- 한도에 걸리면 **429** 이고 본문은 §1.3 의 공통 `Error`(`error.code = RATE_LIMITED`)다.

### 2.3 토큰 갱신 — ✅ 구현(#9)

`POST /auth/token/refresh` — 인증 불필요. 주체는 본문의 refresh 토큰 자체가 증명한다.

```json
// Request
{ "refreshToken": "9qQ1t...(패딩 없는 Base64URL 43자, JWT 아님)" }
// 200 OK — 회전된다. 새 refreshToken 으로 반드시 교체 저장할 것
{ "accessToken": "eyJhbGci...", "refreshToken": "새 값", "expiresIn": 3600 }
```

- **회전**: 성공하면 옛 refresh 토큰은 그 자리에서 폐기된다. 다시 쓰면 401 이다.
- **재사용 감지**: 이미 폐기된 refresh 토큰이 다시 오면 유출로 간주해 **그 사용자의 모든 세션**을 폐기하고 401 이다. 즉 옛 토큰으로 한 번 재시도하면 방금 받았던 새 토큰도 함께 죽는다.
- 만료·미존재는 그냥 401 이며 다른 세션을 끊지 않는다. **형식이 맞는 요청**의 실패는 원인과 무관하게 전부 **본문 없는 401** 이다(빈 문자열·`{}` 포함).
- ⚠️ **형식 자체가 깨진 요청은 401 이 아니다.** 읽을 수 없는 JSON·배열 본문·타입 불일치는 **400**, `Content-Type` 이 `application/json` 이 아니면 **415**, `POST` 가 아니면 **405** 다(#9). 세 응답의 본문은 §1.3 의 공통 `Error` 봉투이고 예외 메시지를 싣지 않는다 — 파서 메시지에 요청 본문(= refresh 토큰 원문) 조각이 섞이기 때문이다(#6). **앱은 이 셋을 401 처럼 다루면 안 된다** — 재로그인 사유가 아니라 요청이 잘못됐다는 신호이고, 재시도해도 결과가 같다.
- ⚠️ 클라이언트는 갱신 요청을 **직렬화(single-flight)** 해야 한다. 같은 값으로 동시에 두 번 보내면 한쪽이 재사용으로 처리되어 전 기기가 끊긴다. 서버는 유예 창을 두지 않는다.
- 수명 14일(`jwt.refresh-expiration`). 서버에는 SHA-256 해시만 저장된다.

### 2.4 내 정보 조회 — ✅ 구현(재사용)

`GET /auth/me` — 헤더 `Authorization: Bearer <token>` 필요.

```json
// 200 OK
{
  "id": 42,
  "email": "bori@example.com",
  "name": "방상현",
  "nickname": "보리아빠",
  "gender": "MALE",
  "age": 32,
  "travelType": "healing",
  "imageUrl": "https://.../me.png",
  "provider": "local",
  "createdAt": "2026-05-01T10:00:00+09:00",
  "updatedAt": "2026-08-01T10:00:00+09:00"
}
```

> `provider` 는 내려온다 — `users.provider` 컬럼은 #7 에서 생겼고 `UserResponse` 가 매핑한다. 값은 `local`(이메일 가입)·`kakao`·`google` 중 하나다(`naver` 는 ADR-0010 에서 보류. 백필 전 옛 행은 `null` 일 수 있다). (이 문서는 오래도록 "컬럼이 없어 아직 내려오지 않는다"고 적고 있었다.) 필드명은 `profileImage` 가 아니라 **`imageUrl`** 이다.
> `isNew` 는 여기에 없다 — 로그인 응답(`AuthTokens`)의 1회성 이벤트 속성이지 프로필의 영속 속성이 아니다(#23).

### 2.5 이메일 회원가입 — ✅ 구현(#10)

`POST /auth/signup` — 비인증. `201 Created` + `User` JSON. 중복 이메일은 `409` + §1.3 의 `Error`(`code: CONFLICT`).

```json
// 201 Created — 2.4 와 같은 User 형태
{ "id": 42, "email": "bori@example.com", "nickname": "보리아빠", "provider": "local", "...": "..." }
```

> ⚠️ **예전에는 `200 OK` + 본문 `"회원가입 성공"`(평문)이었고 중복은 400 이었다.** 200 만 성공으로 보는 클라이언트는 201 도 성공으로 받아야 한다.
> **이 응답에는 토큰이 없다.** 가입 직후 로그인 상태로 만들려면 `POST /auth/login` 을 한 번 더 부른다.

### 2.6 이메일 로그인 — ✅ 구현(#10)

`POST /auth/login` — 비인증. `200 OK` + `AuthTokens` JSON.

```json
// 200 OK
{
  "accessToken": "eyJhbGci...",
  "refreshToken": "9qQ1t...(43자)",
  "expiresIn": 3600,
  "isNew": false,
  "user": { "id": 42, "email": "bori@example.com", "provider": "local", "...": "..." }
}
```

> ⚠️ **예전에는 JSON 이 아니라 JWT 원문 문자열을 본문에 그대로 담았다.** `response.body` 를 토큰으로 저장하던 코드는 이제 `accessToken` 을 읽어야 한다 — 안 고치면 JSON 전체가 토큰으로 저장되어 모든 요청이 401 이 된다.
> `refreshToken` 이 드디어 실린다. 서버는 #9 부터 발급·저장하고 있었지만 응답에 자리가 없어 아무에게도 전달되지 않았다. `isNew` 는 이 경로에서 항상 `false` 다.
> 자격증명 실패는 **본문 없는 401** 이다(가입되지 않은 이메일과 비밀번호 오류를 구분하지 않는다 — 구분해 주면 그 자체가 가입 여부 조회 수단이다). 예전에는 두 경우 모두 **500** 이었다.

### 2.7 내 정보 수정 — ✅ 구현

`PUT /auth/me` — 부분 수정(보낸 필드만 반영). `200 OK` + `User`.

> 시맨틱이 부분 수정이므로 장기적으로는 `PATCH` 가 옳다. 전환은 별도 정리 이슈.

### 2.8 로그아웃 — ✅ 구현(#9)

`POST /auth/logout` — 인증된 주체를 받아 `204 No Content`(멱등) / `401`. 어느 쪽 토큰(소셜·이메일 가입)으로 불러도 204 다.

> **전 기기 로그아웃이다.** 그 사용자의 서버측 refresh 토큰을 전부 폐기한다. 요청 본문은 없다 — 기기 하나만 끊는 경로는 정의하지 않는다.
> **다만 이미 발급된 액세스 토큰은 만료(≤1시간)까지 유효하다.** `jti` 블록리스트가 없기 때문이고, 그건 M2 이후 별도 Epic 이다. 따라서 클라이언트가 저장한 토큰을 반드시 스스로 지워야 한다.

### 2.9 회원 탈퇴 — ✅ 구현(재사용)

`DELETE /auth/me` — `204 No Content` / `401`. (레거시 `AuthController.deleteMe()` 계승)

---

## 3. 강아지 프로필 (Dogs)

프론트 도메인: `app/lib/v2/domain/pet.dart` → `DogProfile { name, breed, size(소형/중형/대형), ageMonths, neutered, avatarAsset }`.
현재 앱은 전역 `ValueNotifier<DogProfile> kMyDog`로 로컬 보관(백엔드 미연동).

### 3.1 내 강아지 목록 — 🟡 계획

`GET /api/dogs` — 인증 필요. 한 사용자가 다견 가정 가능.

```json
// 200 OK
[
  {
    "id": 7,
    "name": "보리",
    "breed": "믹스견",
    "size": "small",          // small | medium | large
    "birth": "2024-01-15",
    "ageMonths": 30,
    "neutered": true,
    "avatarUrl": "https://.../dogs/7.png"
  }
]
```

> `size` enum은 프론트 `DogSize{small,medium,large}`와 1:1. `ageMonths`는 `birth` 기준 서버 계산값(응답 편의 필드).

### 3.2 강아지 등록 — 🟡 계획

`POST /api/dogs`

```json
// Request
{
  "name": "보리",
  "breed": "믹스견",
  "size": "small",
  "birth": "2024-01-15",
  "neutered": true
}
// 201 Created → 3.1 항목 1건 반환
```

검증: `name` 1~20자, `size` ∈ enum, `birth` ≤ 오늘.

### 3.3 강아지 상세 — 🟡 계획

`GET /api/dogs/{dogId}` → 3.1 항목 1건.

### 3.4 강아지 수정(부분) — 🟡 계획

`PATCH /api/dogs/{dogId}` — 본인 소유만(아니면 `403`). 변경 필드만 전송.

```json
// Request
{ "name": "보리", "neutered": true, "size": "medium" }
```

### 3.5 강아지 삭제 — 🟡 계획

`DELETE /api/dogs/{dogId}` — `204 No Content`.

### 3.6 아바타 업로드 — ⚪ post-MVP

`POST /api/dogs/{dogId}/avatar` (multipart/form-data, `file`) — 레거시 `S3/MediaController` 재사용 예정.

---

## 4. 장소 (Places)

**현재 상태:** 앱이 관광공사 KTO(`KorPetTourService2`)를 **직접 호출**한다.
구현 위치: `app/lib/v2/data/pet_places_repository.dart` → `PetPlacesRepository.fetchNearby()`.

### 4.1 (현행) KTO 직접 호출 — 🔵 프록시 계획

```http
GET https://apis.data.go.kr/B551011/KorPetTourService2/locationBasedList2
  ?serviceKey={ENCODED_KEY}
  &MobileOS=ETC&MobileApp=heattrip&_type=json
  &numOfRows=80&pageNo=1
  &mapX={lng}&mapY={lat}&radius=8000&arrange=E
  &contentTypeId={optional}
```

- `serviceKey`: `--dart-define=YOUR_DECODING_SERVICE_KEY` 로 들어오는 값(`Env.tourServiceKey`). 명칭과 달리 이미 **인코딩된** 키라 프론트에서 그대로 붙인다. 예전에는 `.env` 를 에셋으로 번들해 읽었는데, 그러면 APK 안에 원본이 그대로 실려 나간다 — #29 가 걷어냈다. dart-define 도 완화일 뿐이라 이 키를 앱에서 진짜로 없애려면 백엔드 프록시로 옮겨야 한다(#29 (B)).
- `arrange=E`: 거리순. `radius` 기본 8000m.
- 응답 파싱(프론트): `response.body.items.item[]` → `contentid, title, contenttypeid, addr1, firstimage, tel, mapx(경도), mapy(위도), dist(m)`.
- `contenttypeid`: `12`관광지 `14`문화 `28`레포츠 `32`숙박 `38`쇼핑 `39`음식점.

**한계:** KTO 1000콜/일 제한, 키 노출, 캐싱 부재 → 아래 백엔드 프록시로 이전.

### 4.2 주변 장소 조회 (백엔드 프록시) — 🔵 프록시 계획

`GET /api/places/nearby`

| 쿼리 | 타입 | 기본 | 설명 |
|---|---|---|---|
| `lat` | double | 필수 | 위도(WGS84) |
| `lng` | double | 필수 | 경도 |
| `radius` | int | 8000 | 반경(m) |
| `category` | string | - | 필터. `12/14/28/32/38/39`(KTO) 또는 `vet/shop/trail`(공공데이터 레이어) |
| `limit` | int | 80 | 최대 100 |

동작: 백엔드가 KTO/LOCALDATA/두루누비를 호출·정규화하고 `place` 테이블에 캐시(공간 인덱스), 이후 `ST_Distance_Sphere`로 거리순 반환.

```json
// 200 OK
{
  "items": [
    {
      "id": "kto:126508",              // source:contentId
      "source": "kto_pet",             // kto_pet | localdata_vet | localdata_shop | durunubi_trail
      "category": "39",                // KTO contenttypeid 또는 vet/shop/trail
      "name": "성수동 반려카페",
      "addr": "서울 성동구 ...",
      "tel": "02-000-0000",
      "image": "http://tong.visitkorea.or.kr/...jpg",
      "lat": 37.5445,
      "lng": 127.0557,
      "distanceM": 320,
      "petAllowed": true
    }
  ],
  "count": 45,
  "cachedAt": "2026-06-30T08:00:00+09:00"
}
```

> 카테고리 SSOT: `app/lib/v2/domain/pet.dart` `kPetCategories`. `vet/shop/trail`은 별도 공공데이터 레이어(현재 앱 더미).

### 4.3 장소 상세 — 🔵 프록시 계획

`GET /api/places/{placeId}` — `placeId` = `source:contentId`(예: `kto:126508`).

```json
// 200 OK
{
  "id": "kto:126508",
  "source": "kto_pet",
  "category": "39",
  "name": "성수동 반려카페",
  "addr": "서울 성동구 성수이로 ...",
  "tel": "02-000-0000",
  "images": ["http://.../1.jpg", "http://.../2.jpg"],
  "lat": 37.5445,
  "lng": 127.0557,
  "petInfo": {                         // KTO detailPetTour2 정규화
    "acmpyTypeCd": "가능",
    "acmpyPsblCpam": "실내 동반 가능, 소형견 위주",
    "petFacility": "물그릇 제공"
  },
  "homepage": "https://...",
  "openHours": "10:00~21:00",
  "updatedAt": "2026-06-30T08:00:00+09:00"
}
```

원본 KTO 오퍼레이션: `detailCommon2` + `detailPetTour2`(반려 동반 상세).

### 4.4 산책로 코스 — ⚪ post-MVP

`GET /api/trails/nearby?lat&lng&radius` → 두루누비(걷기여행길) 코스. `path`는 인코딩 폴리라인/GPX 좌표열. 현재 앱은 더미 폴리라인.

---

## 5. 산책 (Walks)

실시간 GPS 트래킹 결과를 저장/조회. 프론트 도메인: `WalkLog { date, place, km, minutes, memo, pace }`, 통계용 `kWeekKm`.
현재 앱은 시뮬 이동 + 로컬 샘플(`kWalks`). 백엔드 미연동.

경로 저장 규약: GPS 경로는 `walk.path` **한 컬럼**(LINESTRING / 인코딩 폴리라인). 개별 포인트 테이블 없음.

### 5.1 산책 생성 — 🟡 계획

`POST /api/walks` — 인증 필요. 트래킹 종료 시 1회 전송.

```json
// Request
{
  "dogId": 7,
  "startedAt": "2026-06-30T07:10:00+09:00",
  "endedAt":   "2026-06-30T07:48:00+09:00",
  "distanceM": 2400,
  "durationS": 2280,
  "path": "y`psFhguhW...",             // 인코딩 폴리라인(권장) 또는 좌표배열
  "placeId": "kto:126508",             // nullable — 시작 근처 장소
  "placeName": "서울숲",
  "memo": "아침 공기가 좋아 한 바퀴 더.",
  "weather": "맑음"
}
```

```json
// 201 Created
{
  "id": 1012,
  "dogId": 7,
  "startedAt": "2026-06-30T07:10:00+09:00",
  "endedAt": "2026-06-30T07:48:00+09:00",
  "distanceM": 2400,
  "durationS": 2280,
  "paceSecPerKm": 950,                 // 서버 계산 (durationS / km)
  "placeName": "서울숲",
  "memo": "아침 공기가 좋아 한 바퀴 더.",
  "weather": "맑음"
}
```

검증: `endedAt` > `startedAt`, `distanceM ≥ 0`, `dogId`는 본인 소유.

### 5.2 산책 목록 — 🟡 계획

`GET /api/walks?dogId={id}&from=2026-06-01&to=2026-06-30&limit=20&cursor=...`

```json
// 200 OK
{
  "items": [
    {
      "id": 1012,
      "date": "2026-06-30",
      "placeName": "서울숲",
      "distanceM": 2400,
      "durationS": 2280,
      "paceSecPerKm": 950,
      "memo": "아침 공기가 좋아 한 바퀴 더."
    }
  ],
  "nextCursor": null,
  "hasMore": false
}
```

### 5.3 산책 상세 — 🟡 계획

`GET /api/walks/{walkId}` — 5.1 응답 + `path`(경로 폴리라인) 포함. 지도에서 경로 리플레이용.

### 5.4 산책 삭제 — 🟡 계획

`DELETE /api/walks/{walkId}` — 본인 소유만. `204 No Content`.

### 5.5 산책 통계 — 🟡 계획

`GET /api/walks/stats?dogId={id}&period=week` — `period ∈ {week, month}`. 통계 차트(`fl_chart`)용 집계.

```json
// 200 OK
{
  "period": "week",
  "range": { "from": "2026-06-24", "to": "2026-06-30" },
  "daily": [                            // 프론트 kWeekKm / kWeekDayLabels 대응
    { "day": "월", "date": "2026-06-24", "distanceKm": 2.1, "count": 1 },
    { "day": "화", "date": "2026-06-25", "distanceKm": 2.9, "count": 1 },
    { "day": "수", "date": "2026-06-26", "distanceKm": 1.2, "count": 1 },
    { "day": "목", "date": "2026-06-27", "distanceKm": 0.0, "count": 0 },
    { "day": "금", "date": "2026-06-28", "distanceKm": 1.8, "count": 1 },
    { "day": "토", "date": "2026-06-29", "distanceKm": 3.1, "count": 1 },
    { "day": "일", "date": "2026-06-30", "distanceKm": 2.4, "count": 1 }
  ],
  "summary": {
    "totalKm": 13.5,
    "totalWalks": 6,
    "avgPaceSecPerKm": 980,
    "topPlaces": ["서울숲", "남산 둘레길", "한강공원(뚝섬)"]
  }
}
```

---

## 6. 커뮤니티 (Community)

레거시 `/api/social`(cards/comments/reactions) 구조를 반려 게시판으로 개편.
프론트 도메인: `PetPost { nick, board, loc, date, title, body, commentCount, reactions[3] }`.
게시판 `kPetBoards = [전체, 산책로 후기, 동반장소, 건강·병원, 자유, 자랑]`, 반응 `kPetReactions = [도움돼요, 귀여워요, 공감]`.

board 코드 매핑:

| 코드 | 라벨 |
|---|---|
| `walk_review` | 산책로 후기 |
| `pet_place` | 동반장소 |
| `health` | 건강·병원 |
| `free` | 자유 |
| `brag` | 자랑 |

reaction 코드: `help`(도움돼요) · `cute`(귀여워요) · `empathy`(공감). (ERD `reaction.type[help/cute/empathy]`와 동일)

### 6.1 글 목록 — ✅ 구현(개편)

`GET /api/posts?board={code}&placeId={id}&limit=20&cursor=...`

- `board` 미지정 = 전체. `placeId` 지정 시 특정 장소 관련 글만.

```json
// 200 OK
{
  "items": [
    {
      "id": 331,
      "board": "walk_review",
      "author": { "id": 42, "nickname": "보리아빠", "avatarUrl": "https://.../42.png" },
      "placeName": "서울숲",
      "placeId": "kto:126508",
      "title": "서울숲 아침 산책 코스 추천",
      "bodyPreview": "이른 아침엔 사람이 적어서 대형견도 편해요...",
      "commentCount": 4,
      "reactions": { "help": 7, "cute": 3, "empathy": 2 },
      "createdAt": "2026-06-30T09:00:00+09:00"
    }
  ],
  "nextCursor": "eyJpZCI6MzMwfQ==",
  "hasMore": true
}
```

### 6.2 글 상세 — 🟡 계획

`GET /api/posts/{postId}` → 6.1 항목 + `body`(전문) + `myReaction`(내가 누른 반응 코드/null).

### 6.3 글 작성 — ✅ 구현(개편)

`POST /api/posts` — 인증 필요. (레거시 `SocialController.shareCard()` 계승)

```json
// Request
{
  "board": "walk_review",
  "title": "서울숲 아침 산책 코스 추천",
  "body": "이른 아침엔 사람이 적어서 대형견도 편해요. 잔디마당은 목줄 필수!",
  "placeId": "kto:126508",            // nullable
  "placeName": "서울숲"                // nullable
}
// 201 Created → 6.2 상세 반환
```

검증: `title` 1~100자, `body` 1~5000자, `board` ∈ enum.

### 6.4 글 수정 — 🟡 계획

`PATCH /api/posts/{postId}` — 작성자만(아니면 `403`). 변경 필드만.

### 6.5 글 삭제 — 🟡 계획

`DELETE /api/posts/{postId}` — 작성자만. `204 No Content`.

### 6.6 댓글 목록 — ✅ 구현(개편)

`GET /api/posts/{postId}/comments?limit=50&cursor=...` — 오래된 순.

```json
// 200 OK
{
  "items": [
    {
      "id": 900,
      "author": { "id": 51, "nickname": "초코맘", "avatarUrl": "https://.../51.png" },
      "body": "저도 아침에 자주 가요! 배변봉투통 위치 공유 감사합니다.",
      "createdAt": "2026-06-30T09:20:00+09:00"
    }
  ],
  "nextCursor": null,
  "hasMore": false
}
```

### 6.7 댓글 작성 — ✅ 구현(개편)

`POST /api/posts/{postId}/comments` — 인증 필요. (레거시 `addComment()` 계승)

```json
// Request
{ "body": "저도 아침에 자주 가요!" }
// 201 Created → 6.6 항목 1건
```

### 6.8 댓글 삭제 — 🟡 계획

`DELETE /api/comments/{commentId}` — 작성자만. `204 No Content`.

### 6.9 반응 토글 — ✅ 구현(개편)

`POST /api/posts/{postId}/reactions` — 인증 필요. 같은 타입 재요청 시 취소(토글). (레거시 `toggleReaction()` 계승)

```json
// Request
{ "type": "cute" }                     // help | cute | empathy
```

```json
// 200 OK
{
  "postId": 331,
  "myReaction": "cute",                // 취소된 경우 null
  "reactions": { "help": 7, "cute": 4, "empathy": 2 }
}
```

---

## 7. 채팅 (Chat) — 🟡 계획

**가족 그룹 전용이 아니다.** 방은 `chat_room` 이고, 가족 그룹은 `origin_kind`/`origin_ref` 로 방과 이어진 여러 출처 중 하나다. 앱이 이미 방을 둘 들고 있고(`pet.dart` 의 `kChatRooms` — `우리 가족`·`서울숲 산책 크루`), 방별 화면은 이미 범용이다. 근거는 [ADR-0011](../99-decisions/decision-log.md#adr-0011--채팅은-가족-그룹-종속이-아니라-범용-다중-방이다).

**순서·델타·미읽음은 전부 방별 `roomSeq` 하나로 푼다.** `id`(AUTO_INCREMENT)를 커서로 쓰지 않는다 — 배정 시점과 가시성 시점이 달라 `afterId` 폴링이 메시지를 영구히 건너뛴다. 그래서 이 장의 목록 응답은 §1.2 의 공용 페이지네이션(`nextCursor`)을 쓰지 않고 `{ items, lastSeq, hasMore }` 를 직접 돌려준다. 미읽음은 `room.lastSeq − member.lastReadSeq` **뺄셈**이라 읽음 표를 두지 않는다.

MVP 는 **폴링**(`afterSeq`)이다. 소켓은 실측 트리거가 걸릴 때만 연다(M2.9).

데이터 모델: `chat_room(origin_kind, origin_ref, title, last_seq)` · `chat_room_member(room_id, user_id, role, last_read_seq, removed_at, rejoin_blocked)` · `chat_room_invite(room_id, code, expires_at, max_uses, used_count, revoked_at)` · `chat_message(room_id, room_seq, sender_user_id, sender_name, content_type, body, client_msg_id, deleted_at)`. **chat 경계 밖으로 나가는 FK 는 0개다.** `client_msg_id` 에는 `UNIQUE (room_id, client_msg_id)` 가 걸려 있어 같은 키로 두 번 보낸 재전송이 두 줄이 되지 않는다(#78).

| 메서드 | 경로 | 설명 | 마일스톤 |
|---|---|---|---|
| `GET` | `/api/chat/rooms` | 내 방 목록. 방마다 `unread`·`lastMessage`·`memberCount`·`tag`·`isDefault` | M2.6 |
| `GET` | `/api/chat/rooms/{roomId}` | 방 상세(멤버 목록·내 `lastReadSeq`·역할) | M2.6 |
| `GET` | `/api/chat/rooms/{roomId}/messages?afterSeq\|beforeSeq&limit` | 폴링/스크롤 겸용. 응답은 `{ items, lastSeq, hasMore }` | M2.6 |
| `POST` | `/api/chat/rooms/{roomId}/messages` | 전송 `{ "body": "...", "clientMsgId": "..." }`. 멱등키로 재시도 중복을 막고 201 에 배정된 `roomSeq` 를 싣는다 | M2.6 |
| `POST` | `/api/chat/rooms/{roomId}/read` | `lastReadSeq` 올리기. **단조 증가만** | M2.6 |
| `POST` | `/api/chat/rooms/{roomId}/invites` | 초대코드 발급(방장만. 7일·무제한 고정 — **본문을 받지 않는다**) | M2.5 ✅ |
| `DELETE` | `/api/chat/rooms/{roomId}/invites/{code}` | 초대코드 폐기. **행을 지우지 않는다**(회수된 코드와 없던 코드를 구별해야 한다). 기존 멤버는 남는다 | M2.5 ✅ |
| `POST` | `/api/chat/invites/{code}/join` | 코드로 입장. 없음 `404` → 만료 `410` → 회수 `410` → **이미 멤버면 `200`** → 소진 `409` → 정원 `409`. 재입장 금지 대상이면 `403` | M2.5 ✅ |
| `DELETE` | `/api/chat/rooms/{roomId}/members/me` | 나가기 | M2.6 |
| `DELETE` | `/api/chat/rooms/{roomId}/members/{userId}` | 강퇴(방장). `removed_at` + `rejoin_blocked` | M2.7 |
| `DELETE` | `/api/chat/messages/{messageId}` | 삭제 — **소프트**(`deleted_at`). 빈틈이 나면 델타가 깨진다 | M2.6 |
| `POST` | `/api/chat/messages/{messageId}/reports` | 신고(사유 코드 + 메모). 서버가 본문 스냅샷을 남긴다 | M2.7 |
| `POST`·`DELETE` | `/api/chat/blocks` · `/api/chat/blocks/{userId}` | 차단·해제. 차단은 **가리기**이지 삭제가 아니다 | M2.7 |

- **✅ 표시는 구현됐다는 뜻이다**(이슈 #75). 나머지는 아직 계획이다.
- 방 멤버가 아닌 사용자의 접근 → `403 FORBIDDEN`. 확인은 서비스 경계 한 곳이다 — 지금 발급·회수는 `ChatRoomService.requireOwner(roomId, userId)` 다. **404 가 아니라 403 인 것은 의도다**: 404 로 답하면 남의 방 id 를 훑어 있는 방과 없는 방을 가려낼 수 있다.
- **초대·참여 경로에 rate limit 이 아직 없다.** `ApiRateLimitFilter.resolveRule` 의 표에 없는 경로는 한도가 0 이 아니라 **무한**이다. 이슈 #75 의 NOTE 가 참여 경로 버킷을 M2.6 으로 미뤘고, 지금 코드 추측을 견디는 것은 초대코드의 길이(50비트)뿐이다.
- 한도·상태 위반은 봉투를 새로 만들지 않고 공통 `Error` 의 `error.code` 로 갈린다 — `ROOM_MEMBER_LIMIT`(409) · `INVITE_EXPIRED`(410) · `INVITE_REVOKED`(410) · `INVITE_USES_EXHAUSTED`(409).
- 만 14세 미만(`users.age_group = 'UNDER14'`)은 방 생성과 초대코드로 새 방 참여를 막고 **가족방만 예외로 허용**한다(M2.7).

---

## 8. 북마크 (Bookmarks) — ⚪ post-MVP

레거시 `bookmark/` 패키지 재사용. 장소 즐겨찾기.

| 메서드 | 경로 | 설명 |
|---|---|---|
| `GET` | `/api/bookmarks` | 내 북마크 장소 목록 |
| `POST` | `/api/bookmarks` | `{ "placeId": "kto:126508" }` 추가 |
| `DELETE` | `/api/bookmarks/{placeId}` | 해제 |

---

## 9. 가족 케어 (Groups) — 🟢 구현됨

반려는 혼자가 아니라 **가족이 함께** 돌본다. 가족 그룹으로 오늘의 케어(물/밥/산책)를 공유해 이중 급여(밥 두 번)·산책 누락을 막는다. **채팅은 여기 없다** — 방은 가족 그룹에 종속되지 않는 범용 리소스라 7장으로 나갔다([ADR-0011](../99-decisions/decision-log.md#adr-0011--채팅은-가족-그룹-종속이-아니라-범용-다중-방이다)).

프론트: 홈의 "오늘의 케어" 카드(`app/lib/v2/widgets/today_care_card.dart`)와 `family_screen` 의 멤버·케어·주의사항이 **서버 응답으로 그려진다**(이슈 #76). 아직 더미인 것은 초대코드(`kFamilyInviteCode` — 발급은 7장의 방 경로다)와 거리 공유(`FamilyMember.todayKm`)뿐이다.
데이터 모델: `family_group(id,name,created_at)` — **초대코드도 멤버십도 여기 없다.** 초대는 `chat_room_invite`, 멤버십은 `chat_room_member` 가 가지고(7장), 방이 `origin_kind`/`origin_ref` 로 이 그룹을 불투명하게 가리킨다. 나머지는 `walk_note(id,group_id,body,updated_by,updated_at)` — **그룹당 한 장**이고 `UNIQUE(group_id)` 가 그것을 지킨다 — 과 `care_log(id,dog_id,group_id,type,done_by,occurred_at,memo,created_at)` 이다. `type` 은 `water|meal|walk|med|vet` **소문자**이고 계약·DB CHECK·앱 enum 이 같은 문자열을 쓴다. **`dog_id` 에는 FK 가 없다** — `dog` 표가 정본 스키마에 아직 없어서다([schema.md §17](../03-database/schema.md)).

| 메서드 | 경로 | 설명 |
|---|---|---|
| `POST` | `/api/groups` | 그룹 생성 — **같은 트랜잭션에서 방과 `OWNER` 멤버십이 함께 생긴다.** 초대코드는 여기서 발급하지 않는다(응답의 `roomId` 로 7장의 발급 경로를 부른다) |
| `GET` | `/api/groups/me` | 내 그룹 + 멤버 목록(없으면 `404`). 멤버 목록의 출처는 `chat_room_member` 다 |
| `GET` | `/api/groups/{groupId}/care-logs?date&type` | 오늘의 케어 조회 — 누가·언제 물/밥/산책을 했는지. `date` 생략 시 오늘 |
| `POST` | `/api/groups/{groupId}/care-logs` | 케어 기록 `{ "type": "meal", "memo": "" }`. **`done_by`·`occurredAt` 은 서버가 정한다** |
| `GET` | `/api/groups/{groupId}/walk-notes` | 산책 시 주의사항 한 장. 아직 없으면 404 가 아니라 `body: ""` |
| `PUT` | `/api/groups/{groupId}/walk-notes` | 주의사항 전체 교체 `{ "body": "..." }` |

- **여섯 경로 모두 구현됐다** — `POST /api/groups`·`GET /api/groups/me` 는 이슈 #75, 케어 넷은 이슈 #76.
- 그룹 멤버가 아닌 사용자의 접근 → `403 FORBIDDEN`. **없는 `groupId` 도 404 가 아니라 403 이다** — 404 로 답하면 id 를 훑어 "있는 가족/없는 가족" 을 가려낼 수 있다. 초대코드로 들어오는 경로는 7장(`POST /api/chat/invites/{code}/join`)이다.
- 멤버십 판정의 원본은 **`chat_room_member` 하나**다. `care` 패키지는 `ChatRoomService` 의 공개 표면(`findRoom`·`isLiveMember`)으로만 묻는다 — chat 밖에서 `chat.repository` 를 부르는 것은 `ChatBoundaryArchitectureTest §E` 가 막는다.
- **인가와 조회 필터는 서로 다른 방어다.** 인가는 요청을 통째로 막고, `care_log.group_id = :groupId` 필터는 통과한 요청이 어느 행을 보는지를 정한다. 한 사람이 여러 방에 속하는 것은 정상이라(초대코드로 들어오면 그렇게 된다) 인가만 있으면 가족 A 의 멤버가 가족 B 의 기록을 함께 본다.
- **같은 종류를 하루에 두 번 찍어도 서버는 막지 않는다.** 둘 다 남고, 확인 문구는 앱이 `GET` 응답을 보고 만든다 — 그 목록에 답이 이미 들어 있는데 응답에 "이미 있음" 필드를 더하면 같은 사실의 출처가 둘이 된다.
- **쓰기 둘(`POST care-logs`·`PUT walk-notes`)은 `group-write` 버킷**(rate limit)이다. 읽기 둘은 표 밖이라 **한도가 무한**이다 — 미룬 것이고 M2.6 에서 앱의 폴링 주기와 함께 정한다.
- **`POST /api/groups/join` 은 없다.** 예전 계약에 있던 그 경로는 초대코드가 `family_group.invite_code` 컬럼이던 시절의 것이고, [ADR-0011](../99-decisions/decision-log.md#adr-0011--채팅은-가족-그룹-종속이-아니라-범용-다중-방이다) 이후로는 7장의 참여 경로 하나다. 이슈 #75 가 계약에서 걷어냈다.
- **post-MVP:** 친구 추가(가족 외), 케어 알림/리마인더, 케어 히스토리 통계.

---

## 10. 확장 로그 (Care Logs) — ⚪ post-MVP

건강·식사·병원·접종 기록. ERD `care_log(type[meal/health/vet/med], occurred_at, title, value, memo, photo)`. (9장의 가족 케어 공유가 MVP로 앞당겨지며 `type`·`group_id`·`done_by`가 확장됨 — 9장 참조.)

| 메서드 | 경로 | 설명 |
|---|---|---|
| `GET` | `/api/dogs/{dogId}/care-logs?type=vet&from&to` | 로그 목록 |
| `POST` | `/api/dogs/{dogId}/care-logs` | `{ "type":"vet", "occurredAt":"...", "title":"", "value":"", "memo":"" }` |
| `PATCH` | `/api/care-logs/{id}` | 수정 |
| `DELETE` | `/api/care-logs/{id}` | 삭제 |

---

## 11. 프론트↔API 매핑 요약

| 화면(lib/v2) | 현재 데이터 소스 | 목표 API |
|---|---|---|
| 홈 (강아지 히어로/오늘 산책) | `kMyDog`, `WalkToday` (로컬) | `GET /auth/me`, `GET /api/dogs`, `GET /api/walks/stats` |
| 지도 (KTO 45곳 + 병원/펫샵/산책로 더미) | KTO 직접호출(`PetPlacesRepository`) | `GET /api/places/nearby`, `GET /api/places/{id}` |
| 실시간 산책 (시뮬) | 로컬 | `POST /api/walks` |
| 산책 통계 (fl_chart) | `kWeekKm`(로컬) | `GET /api/walks/stats` |
| 커뮤니티 (더미) | `kPetPosts`(로컬) | `GET/POST /api/posts`, `/comments`, `/reactions` |
| 강아지 프로필/편집 | `kMyDog`(로컬) | `GET/POST/PATCH /api/dogs` |
| 홈 오늘의 케어 카드 · family_screen (멤버·케어·주의사항) | ~~`kCareToday`, `kFamilyMembers`, `kWalkNotes`~~ → **서버 연동 완료**(#76). 남은 더미는 `kFamilyInviteCode`·`FamilyMember.todayKm` | `GET /api/groups/me`, `GET/POST /api/groups/{id}/care-logs`, `GET/PUT /api/groups/{id}/walk-notes` |
| chat_list_screen (방 목록·미읽음) | `kChatRooms`(로컬) | `GET /api/chat/rooms` |
| family_chat_screen (방 안 대화) | `kChatMessages`(로컬) | `GET/POST /api/chat/rooms/{id}/messages`, `POST /api/chat/rooms/{id}/read` |

---

## 12. 이관 로드맵 (직접호출 → 백엔드)

1. **Phase 1 — 장소 프록시:** `GET /api/places/nearby|{id}`로 KTO 호출을 백엔드 이전. `place` 캐시 테이블 + 공간 인덱스 + KTO 1000콜/일 완화(캐싱·TTL). 프론트 `Env.apiBase` 스위치만으로 전환.
2. **Phase 2 — 계정·프로필:** 카카오/구글 OAuth + `/auth/me` + `/api/dogs`. 로컬 `kMyDog` → 서버 동기화.
3. **Phase 3 — 산책 저장:** `POST /api/walks` + `stats` 집계. GPS 경로 `walk.path` LINESTRING 저장.
4. **Phase 4 — 커뮤니티 실연동:** `/api/posts` 계열로 `kPetPosts` 대체. 레거시 `/api/social` 로직 재사용.
5. **Phase 5 — 공공데이터 레이어:** LOCALDATA(동물병원 ~9,445건, EPSG:5174→WGS84) · 두루누비 산책로 실데이터. `vet/shop/trail` 레이어 더미 제거.
6. **post-MVP:** 북마크, 케어 로그, 매칭/산책 크루.

---

_본 문서는 SSOT. 엔드포인트 변경 시 [ERD](../03-database/erd.md) 및 프론트 `app/lib/v2/data`·`app/lib/v2/domain`과 동기화할 것._
