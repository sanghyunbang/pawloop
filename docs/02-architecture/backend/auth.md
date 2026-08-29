# 백엔드 구현 청사진 — Auth (인증)

> 대상 리소스: OpenAPI `/auth/**` (소셜로그인 시작·콜백·토큰갱신·me GET/DELETE·logout).
> 계약: [`docs/04-api/openapi.yaml`](../../04-api/openapi.yaml) · 데이터 모델: [`erd.md`](../../03-database/erd.md) / [`schema.md`](../../03-database/schema.md)
> ⚠️ 이 문서는 **구현 청사진(시그니처·필드·매핑·쿼리 개요)** 이다. 메서드 바디는 개발자가 직접 작성한다.

---

## 0. 지금 있는 것 vs 추가/수정할 것 (요약)

| 계약 엔드포인트 | 상태 | 비고 |
| --- | --- | --- |
| `GET /auth/oauth/{provider}` (로그인 시작 302) | **경로만 추가** | Spring 기본 진입점은 `GET /oauth2/authorization/{provider}` — 이미 동작. 계약 경로(`/auth/oauth/{provider}`)로 오면 302로 넘겨주는 얇은 리다이렉트만 추가. |
| (SuccessHandler → `heattrip://login-callback?token=`) | **있음(재사용)** | `OAuth2SuccessHandler` 그대로. 단 JWT subject 불일치(§6) 정리 필요. |
| `POST /auth/oauth/{provider}/callback` (code→token) | **신규 추가** | SPA/네이티브 대안 흐름. 현재 없음. 공급자 토큰 교환 + 사용자 upsert + JWT 발급. |
| `POST /auth/token/refresh` | **신규 추가(구조 변경)** | refresh token 저장소/엔티티 자체가 없음. §5·§6 참조. |
| `GET /auth/me` | **있음(수정)** | 현 `AuthController.me`가 `UserResponse` 반환. 계약 `User` 스키마(id/provider/nickname/isNew)로 응답 정합 맞추기. |
| `DELETE /auth/me` (회원탈퇴) | **있음(재사용)** | 현 `AuthController.deleteMe` 그대로. 204. |
| `POST /auth/logout` | **신규 추가** | refresh token 폐기. 현재 없음. 204. |

**재사용 가능한 기존 자산**
- `OAuth/jwt/JWTProvider` — `createAccessToken(userId, role)`, `getUserIdFromToken`, `validateToken`. (refresh 발급 메서드 없음 → 추가 필요)
- `OAuth/jwt/JWTAuthenticationFilter` — `Authorization: Bearer` 파싱 후 SecurityContext 설정. **인증 추출의 표준 규약.**
- `OAuth/service/CustomOAuth2UserService` — 소셜 응답 → `OAuth2UserInfo`(Google/Kakao/Naver) 변환 + `users` upsert.
- `OAuth/handler/OAuth2SuccessHandler` — JWT 발급 후 `heattrip://login-callback?token=` 딥링크 리다이렉트.
- `OAuth/user/OAuth2UserInfo`(+ Google/Kakao/NaverOAuth2User) — 공급자별 provider/providerId/email/name 추출.
- `user/service/UserService.emailFromAuth(authHeader)` — `Bearer` 헤더 → JWT subject 추출. me/삭제에서 사용 중.
- `user/repository/UserRepository` — `findByEmail`, `findByUsername`, `findByNickname`.
- `config/SecurityConfig` — `/auth/**`·`/oauth2/**`·`/login/**` permitAll, STATELESS, `oauth2Login(userService, successHandler)`.

---

## 1. 개요

- **책임**: 소셜(카카오/네이버/구글) 로그인 진입·콜백 처리, 앱 세션 토큰(access/refresh) 발급·갱신·폐기, 내 정보 조회/탈퇴.
- **관련 테이블**: `app_user`(스키마 문서) — **현재 코드 실체는 `users` 테이블 + `User` 엔티티**. 두 스키마가 다름(§6 정합성 함정 참조). refresh token 저장용 테이블은 **미존재 → 신설 필요**(§5).
- **인증 규약**: JWT Bearer, subject = 사용자 식별자. (계약/스키마는 `subject = email`을 명시. 현 코드는 소셜 흐름에서 `provider_providerId`를 subject로 쓰는 불일치 존재 → §6에서 통일.)

---

## 2. Controller — `AuthController` (`@RequestMapping("/auth")`)

> 기존 `user.controller.AuthController` 확장/정리. 컨벤션: `ResponseEntity<?>` 반환, 인증 필요 시 `HttpServletRequest`에서 `Authorization` 헤더 → JWT subject 추출(기존 필터/`emailFromAuth` 규약). 각 행은 openapi paths와 1:1.

| HTTP · 경로 | 메서드 시그니처(파라미터 타입) | 반환 DTO | 인증 |
| --- | --- | --- | --- |
| `GET /auth/oauth/{provider}` | `startOAuth(@PathVariable String provider, HttpServletRequest req, HttpServletResponse res)` | 302 (본문 없음) | ✕ |
| `POST /auth/oauth/{provider}/callback` | `oauthCallback(@PathVariable String provider, @RequestBody OAuthCallbackRequest body)` | `AuthTokensDto` | ✕ |
| `POST /auth/token/refresh` | `refresh(@RequestBody RefreshRequest body)` | `AuthTokensDto` | ✕ (refreshToken 본문 검증) |
| `GET /auth/me` | `me(HttpServletRequest req)` | `UserDto` | ○ |
| `DELETE /auth/me` | `deleteMe(HttpServletRequest req)` | 204 (`ResponseEntity<Void>`) | ○ |
| `POST /auth/logout` | `logout(@RequestBody(required=false) RefreshRequest body, HttpServletRequest req)` | 204 | ✕(선택) |

- `provider` 파라미터: `kakao|naver|google` 이외 값 → 400/error.
- 인증 필요 메서드는 `SocialController.requireUser(...)`와 동일한 패턴(헤더 → `validateToken` → subject → `UserService.findByEmail`)을 재사용/차용 권장.
- 오류 응답은 기존 `Error` 스키마 형태(`{ error: { code, message } }`) — §6.

---

## 3. DTO (Java `record`)

> 위치: `user.dto` 또는 신규 `auth.dto`(패키지 컨벤션상 `<resource>.dto`). 공통 `Error`/`Page`는 계약 참조만.

### 요청 (Request records)

| record | 필드 (이름:타입) | openapi 매핑 |
| --- | --- | --- |
| `OAuthCallbackRequest` | `code:String`(필수), `redirectUri:String`(nullable) | `POST /auth/oauth/{provider}/callback` requestBody |
| `RefreshRequest` | `refreshToken:String`(필수) | `POST /auth/token/refresh` · `POST /auth/logout` requestBody |

### 응답 (Response records)

| record | 필드 (이름:타입) | openapi 스키마 |
| --- | --- | --- |
| `AuthTokensDto` | `accessToken:String`, `refreshToken:String`, `expiresIn:int`(초), `user:UserDto` | `AuthTokens` |
| `UserDto` | `id:Long`, `provider:String`(kakao/naver/google), `nickname:String`, `isNew:boolean` | `User` |

> 주의: 계약 `User` 스키마는 4필드(id/provider/nickname/isNew)만. 기존 `UserResponse`(name/gender/age/email/travelType/imageUrl…)와 다르므로 **Auth 응답 전용으로 `UserDto`를 별도 정의**하고, 프로필 상세는 별도 리소스(User)로 분리한다. `isNew`는 콜백 시 신규 가입 여부(§4)에서 세팅, `me`에서는 통상 `false`.

---

## 4. Service — `AuthService` (`@Service`)

> 각 메서드 한 줄 책임(무엇을; 어떻게는 생략). 트랜잭션 경계는 §6.

| 메서드 시그니처 | 책임(무엇을) |
| --- | --- |
| `String buildAuthorizationRedirect(String provider)` | 계약 경로 → Spring 기본 진입점(`/oauth2/authorization/{provider}`)으로의 302 대상 URL 구성. |
| `AuthTokensDto exchangeCode(String provider, OAuthCallbackRequest req)` | 공급자 인가코드→access token 교환, 프로필 조회, 사용자 upsert, 앱 JWT(access+refresh) 발급·응답 조립(신규면 `isNew=true`). |
| `AppUser upsertSocialUser(OAuth2UserInfo info)` | provider+providerId 기준 사용자 조회/신규 생성(기존 `CustomOAuth2UserService` upsert 로직과 동일 규칙 공유). |
| `AuthTokensDto refresh(String refreshToken)` | refreshToken 유효성·폐기여부 검증 후 새 access(+회전 refresh) 발급. |
| `void logout(String refreshToken)` | 해당 refreshToken 폐기(저장소에서 삭제/무효화). |
| `UserDto me(String subject)` | JWT subject로 사용자 조회 후 계약 `User`(id/provider/nickname/isNew=false) 매핑. |
| `void deleteMe(String subject)` | 사용자 계정 삭제(+연관 refresh token 정리). 기존 `UserService.deleteMe` 위임 가능. |

> 소셜 토큰 교환(`exchangeCode`)은 `TourApiClient`/`WebClientConfig`의 WebClient 패턴을 그대로 사용(공급자 token endpoint + userinfo 호출). 공급자별 endpoint/파라미터 차이는 provider 분기로 처리.

---

## 5. Entity & Repository

### 5-1. 사용자 엔티티

- **현행**: `user.entity.User` → `@Table(name="users")`. `id`, `username`(=`provider_providerId`), `email`(unique), `name`, `nickname`, `gender`, `travelType`, 동의필드 등.
- **스키마 문서(`app_user`) 대비 매핑**:

| `app_user`(문서) 컬럼 | 현행 `users` 필드 | 처리 |
| --- | --- | --- |
| `id BIGINT PK` | `id Long` | 동일 |
| `provider VARCHAR(20)` | (없음 — `username` 접두어에 내포) | **추가 권장**: `provider` 컬럼 신설 or `username` 파싱. |
| `social_id VARCHAR(191)` | (없음 — `username` 접미어에 내포) | **추가 권장**: `social_id` 컬럼 신설. `UNIQUE(provider, social_id)` 목표. |
| `nickname VARCHAR(50)` | `nickname` | 동일 |
| `created_at DATETIME` | `createdAt` | 동일 |

> MVP에선 기존 `users`/`User`를 그대로 재사용해도 됨. 다만 계약 `User.provider` 응답을 위해 provider 값을 어디서든 복원할 수 있어야 함(컬럼 추가 또는 `username` prefix 파싱).

- 인덱스: `email` UNIQUE(현행). 목표 `UNIQUE(provider, social_id)`.

### 5-2. Refresh Token 엔티티 (**신규 필요**)

계약의 `/auth/token/refresh`·`/auth/logout`을 성립시키려면 폐기 가능한 저장소가 필요(현 JWT는 stateless·무기한에 가까움 §6).

| 엔티티 `RefreshToken` 필드 | 컬럼 | 비고 |
| --- | --- | --- |
| `id:Long` | `id BIGINT PK` | AUTO_INCREMENT |
| `userId:Long` | `user_id BIGINT` | FK→`users.id`, INDEX |
| `tokenHash:String` | `token_hash VARCHAR(255)` | 평문 저장 금지(해시). UNIQUE |
| `expiresAt:LocalDateTime` | `expires_at DATETIME` | 만료 |
| `revokedAt:LocalDateTime` | `revoked_at DATETIME` NULL | 폐기/회전 시각 |
| `createdAt:LocalDateTime` | `created_at DATETIME` | 생성 |

> 공간 컬럼 없음(Auth 리소스는 비공간). SPATIAL INDEX 해당 없음.

### 5-3. Repository (Spring Data)

| Repository | 주요 메서드 시그니처 | 종류 |
| --- | --- | --- |
| `UserRepository`(기존) | `Optional<User> findByEmail(String email)` / `findByUsername(String)` | 파생 쿼리 |
| (추가 권장) | `Optional<User> findByProviderAndSocialId(String provider, String socialId)` | 파생 쿼리(provider/social_id 컬럼 추가 시) |
| `RefreshTokenRepository`(신규) | `Optional<RefreshToken> findByTokenHash(String tokenHash)` | 파생 쿼리 |
| `RefreshTokenRepository` | `void deleteByUserId(Long userId)` | 탈퇴 시 정리 |
| `RefreshTokenRepository` | `long deleteByTokenHash(String tokenHash)` | 로그아웃 폐기 |

> 공간/커스텀 native `@Query`는 Auth 범위에 없음.

---

## 6. 구현 노트 (함정 위주)

1. **JWT subject — 결정: `users.id` 로 통일(#5 완료).** 예전에는 `OAuth2SuccessHandler`가 `authentication.getName()`(= `provider_providerId`)을, `UserService.login`이 `email`을 subject로 넣어 한 토큰 형식에 두 규약이 공존했고, 소비처가 전부 email 을 가정해 **소셜 로그인 토큰으로는 me 조회가 깨졌다.** 이제 발급은 `createAccessToken(Long userId, String role)` 한 곳이고(타입이 email·소셜 ID 를 컴파일 단계에서 막는다), 해석은 `JWTAuthenticationFilter` → `AuthenticatedUser` → `@CurrentUser` 한 줄기다. 컨트롤러가 Authorization 헤더를 다시 읽지 않는다는 것은 `AuthSubjectContractSpecTest` 가 소스 스캔으로 잠근다.
2. **Access token 만료** — `JWTProvider.TOKEN_VALID_TIME = 1000L*60*60*10000`(주석은 "1시간"이나 실제 ~416일)로 사실상 무기한. 계약 `expiresIn`(예 3600)과 어긋남. access는 짧게(예 1h) 재설정하고, 실제 만료초를 `expiresIn`으로 정확히 반환할 것.
3. **Refresh token 부재** — 발급/저장/검증/회전/폐기 로직이 전무. `JWTProvider`에 `createRefreshToken`(또는 불투명 랜덤 토큰) 추가 + `RefreshToken` 저장소(§5-2)로 폐기 가능하게. 로그아웃/탈퇴는 반드시 저장된 refresh를 무효화.
4. **로그인 시작 경로 이중화** — 실제 Spring OAuth2 진입점은 `/oauth2/authorization/{provider}`(SecurityConfig `oauth2Login`). 계약 `GET /auth/oauth/{provider}`는 이 진입점으로의 **302 리다이렉트 래퍼**만 두면 됨(성공 시 딥링크는 기존 SuccessHandler가 처리). 별도 인증 로직 재구현 금지.
5. **콜백 대안 흐름(callback POST)의 토큰 교환** — `flutter_web_auth_2` 딥링크 흐름과 별개로, SPA/네이티브가 인가코드를 직접 넘기는 경우. 공급자 token endpoint 호출은 `WebClientConfig` 빈 + `TourApiClient` 스타일(WebClient, 타임아웃/에러 매핑)로. secret은 `@Value`로 주입, 로그에 노출 금지.
6. **provider 화이트리스트** — `{provider}`는 `kakao|naver|google`만 허용. 그 외는 400 + `Error`(`code: VALIDATION`류). `CustomOAuth2UserService`의 `switch`에 `"Kakao"`(대문자) 중복 case가 있으니 정규화(소문자) 후 분기 통일 권장.
7. **에러 포맷 통일** — 계약은 `{ error: { code, message, traceId? } }`. 반면 `SocialController`는 `{ error: "msg" }`(문자열)로 반환 중. Auth는 **계약의 중첩 객체 포맷**을 따르도록 공통 에러 바디/핸들러 정비(401=UNAUTHORIZED). `SecurityConfig`에서 `/auth/**`는 permitAll이므로 인증 실패는 컨트롤러/서비스 레벨에서 명시적으로 401을 던져야 함(`ResponseStatusException` 패턴).
8. **트랜잭션** — `exchangeCode`(사용자 upsert + refresh 저장), `deleteMe`(사용자 + refresh 삭제)는 `@Transactional` 경계로 묶기. 외부 공급자 HTTP 호출은 트랜잭션 밖에서 수행 후, DB 쓰기만 트랜잭션 내부로(장시간 커넥션 점유 방지).
9. **좌표/공간 무관** — Auth 리소스는 EPSG:5174→WGS84·`ST_Distance_Sphere` 등 공간 처리와 무관(그쪽 함정은 Places/Walks 문서에서 다룸).
10. **테이블명 정합** — 스키마 문서는 `app_user`, 코드 실체는 `users`. 문서·코드 중 한쪽으로 명칭을 수렴시키거나, 문서에 "실 테이블=`users`" 주석을 남길 것(마이그레이션 혼선 방지).

완료: C:/Users/mm206/git_projects/heattrip/docs/02-architecture/backend/auth.md
