# 백엔드 구현 청사진 — Auth (인증)

> 대상 리소스: OpenAPI `/auth/**` (소셜로그인 시작·콜백·토큰갱신·me GET/DELETE·logout).
> 계약: [`docs/04-api/openapi.yaml`](../../04-api/openapi.yaml) · 데이터 모델: [`erd.md`](../../03-database/erd.md) / [`schema.md`](../../03-database/schema.md)
> ⚠️ 이 문서는 **구현 청사진(시그니처·필드·매핑·쿼리 개요)** 이다. 메서드 바디는 개발자가 직접 작성한다.

---

## 0. 지금 있는 것 vs 추가/수정할 것 (요약)

| 계약 엔드포인트 | 상태 | 비고 |
| --- | --- | --- |
| `GET /auth/oauth/{provider}` (로그인 시작 302) | **있음(#10 완료)** | `AuthController.startOAuth` 가 `Location: /oauth2/authorization/{provider}` 로 302 한다. 화이트리스트(`kakao`·`google`·`apple`(#301)) 밖은 400 + `Error`(`VALIDATION`). `naver` 는 ADR-0010 이 보류로 확정하면서 계약 enum 과 함께 빠졌다 — 이 래퍼로는 400 이다(#15). 예전에는 핸들러가 **빈 200** 을 주면서 계약은 "미구현" 이라고 적고 있었다. |
| `POST /auth/signup` | **있음(#10 · #635 완료)** | `202` + `SignupStarted(mailSent)`. **계정을 안 만든다** — 인증 코드를 메일로 보내고, 계정은 `/auth/signup/verify` 에서 생긴다(#635). 이미 가입된 이메일도 **같은 202** 다 — 409 를 주면 이 경로가 가입 여부를 묻는 조회 수단이 된다. 2026-09 이전에는 `201` + `User` · 중복 `409` 였고, 그 전에는 `200` + 평문 `"회원가입 성공"` 이었다. |
| `POST /auth/signup/verify` | **있음(#635)** | `200` + `AuthTokensResponse`. **여기서 계정이 생기고** 바로 로그인된 상태가 된다(`isNew` 참). `401` 은 코드가 틀린 것, `410` 은 만료·시도초과·대기없음이다 — 뭉개면 앱이 "다시 보내기" 를 언제 권할지 모른다. |
| `POST /auth/signup/resend` | **있음(#635)** | `202` + `SignupStarted`. 대기 행이 없어도 같은 202 이고 메일은 안 나간다. |
| `POST /auth/login` | **있음(#10 완료)** | `200` + `AuthTokensResponse`(계약의 `AuthTokens`). #9 가 발급·저장하던 refresh 토큰이 드디어 응답에 실린다. 자격증명 실패는 **본문 없는 401**(예전에는 500). |
| (SuccessHandler → `heattrip://login-callback?code=&state=`) | **있음(#14 완료)** | `OAuth2SuccessHandler` 가 토큰 대신 60초짜리 1회용 코드를 내보낸다. 리다이렉트 대상은 `app.security.oauth.redirect-allowlist` 가 정한다. 예전에는 `?token=<AT>&refresh=<RT>` 였다. |
| `POST /auth/oauth/{provider}/callback` (code→token) | **있음(#14 완료)** | `AuthController.exchangeOAuthCode` → `OAuthCodeExchangeService`. 1회용 코드 → `AuthTokens`. **소셜 경로에서 토큰이 나가는 유일한 자리.** 공급자와의 인가코드 교환은 Spring Security 가 이미 끝냈으므로 여기서 다시 하지 않는다. |
| `POST /auth/token/refresh` | **있음(#9 완료)** | `AuthController.refresh` → `RefreshTokenService.rotate`. 회전 + 재사용 감지 + 만료. 실패는 본문 없는 401, 형식 오류는 400·415·405. §5·§6 참조. |
| `GET /auth/me` | **있음(#10 확인 완료)** | `AuthController.me` 가 `UserResponse` 를 반환하고, 그 필드 집합이 곧 계약의 `User` 다(11개: id·email·name·nickname·gender·age·travelType·imageUrl·provider·createdAt·updatedAt). 별도 `UserDto` 를 만들지 않았다 — 그러면 같은 스키마의 사본이 둘이 되고 한쪽만 낡는다. `isNew` 는 여기 없다(로그인 응답의 1회성 속성, #23). |
| `DELETE /auth/me` (회원탈퇴) | **있음(재사용)** | 현 `AuthController.deleteMe` 그대로. 204. |
| `POST /auth/logout` | **있음(#9 완료) / 부분 폐기** | `AuthController.logout` → `UserService.logout` → `RefreshTokenService.revokeAllByUserId`. **전 기기 로그아웃**이며 멱등(폐기할 것이 없어도 204). 다만 액세스 토큰은 여전히 만료(1시간)까지 유효하다 — `jti` 블록리스트가 없기 때문이고, 그 소유자는 M2 이후 Redis Epic(`backend/TODO/refresh-token-redis.md`)이다. |

**재사용 가능한 기존 자산**
- `OAuth/jwt/JWTProvider` — `createAccessToken(userId, role)`, `getUserIdFromToken`, `validateToken`, `getExpiresInSeconds`. **refresh 는 JWT 가 아니므로 여기서 만들지 않는다** — 폐기 가능해야 해서 `RefreshTokenService` 가 256bit 난수를 발급한다(#9).
- `OAuth/jwt/JWTAuthenticationFilter` — `Authorization: Bearer` 파싱 후 SecurityContext 설정. **인증 추출의 표준 규약.**
- `OAuth/service/CustomOAuth2UserService` — 소셜 응답 → `OAuth2UserInfo`(Google/Kakao/Naver) 변환 + `users` upsert.
- `OAuth/handler/OAuth2SuccessHandler` — 1회용 코드 발급 후 `heattrip://login-callback?code=&state=` 딥링크 리다이렉트(#14). 예전에는 여기서 JWT 를 만들어 URL 에 실었다.
- `OAuth/code/AuthCodeStore` — 1회용 코드의 발급소이자 유일한 소비처(#14). 인메모리이며 **수평 확장 시 깨진다** — 근거와 대응은 그 클래스의 javadoc 에 적혀 있다.
- `OAuth/state/OAuthAppStateFilter` — 앱이 만든 `state` 를 소셜 왕복 동안 세션에 붙든다(#14).
- `OAuth/user/OAuth2UserInfo`(+ Google/Kakao/AppleOAuth2User) — 공급자별 provider/providerId/email/name 추출. Apple 은 id_token 클레임(`sub`·`email`)이고 이름이 없다(#301).
- `OAuth/AppleOidcUserService` + `OAuth/apple/*` — OIDC 경로(Apple). `AppleClientSecret` 이 .p8 로 `client_secret` JWT 를 서명하고, `AppleTokenResponseClient` 가 토큰 교환 직전에 끼우며, `AppleSignInConfig` 가 발급자 검사를 더한다(#301).
- ~~`user/service/UserService` 의 `Bearer` 헤더 → subject 추출 헬퍼~~ — **#5 에서 삭제됐다.** 대체: `OAuth/principal/CurrentUserArgumentResolver` + `@CurrentUser`. 컨트롤러는 Authorization 헤더를 다시 읽지 않는다(§6-1).
- `user/repository/UserRepository` — `findByEmail`, `findByUsername`, `findByNickname`.
- `config/SecurityConfig` — **`/auth/**` 는 더 이상 permitAll 이 아니다(#23).** 공개는 `/auth/signup`·`/auth/signup/verify`·`/auth/signup/resend`·`/auth/login`·`/auth/oauth/**`·`/auth/token/refresh`·`/oauth2/**`·`/login/**` 등 열거된 경로뿐이고(가입 인증의 둘은 **낱개로** 연다 — `/auth/signup/**` 로 열면 그 아래 경로가 늘 때 인증 없이 딸려 들어간다, #635) 나머지는 `anyRequest().authenticated()` + `HttpStatusEntryPoint(401)`. STATELESS, `oauth2Login(userService, successHandler)`.

---

## 1. 개요

- **책임**: 소셜(카카오/구글) 로그인 진입·콜백 처리, 앱 세션 토큰(access/refresh) 발급·갱신·폐기, 내 정보 조회/탈퇴.
- **관련 테이블**: `users` (+ `User` 엔티티). 스키마 문서도 `users` 로 통일했다(#15) — 예전에는 문서만 `app_user` 라는 이름을 썼고 그 이름의 테이블은 만들어진 적이 없다. refresh token 원장은 **`refresh_token` 테이블로 존재한다**(#9). 운영 적용 SQL 은 `backend/mysql/post-start/05_refresh_token.sql`, 런북은 `backend/mysql/README.md`(§5-2).
- **인증 규약**: JWT Bearer, **subject = `users.id`**(#5 완료). 계약(`openapi.yaml`)은 이 값을 "파싱 금지의 불투명 사용자 키"로 선언한다 — 이메일도 `provider_providerId`도 아니다. 해석은 `JWTAuthenticationFilter` → `AuthenticatedUser` → `@CurrentUser` 한 줄기뿐이다(§6-1).

---

## 2. Controller — `AuthController` (`@RequestMapping("/auth")`)

> 기존 `user.controller.AuthController` 확장/정리. **인증이 필요한 핸들러는 `@CurrentUser User me` 파라미터를 받는다** — 컨트롤러가 `Authorization` 헤더를 다시 읽는 것은 #5 이후 금지이고 `AuthSubjectContractSpecTest` 가 소스 스캔으로 막는다. 각 행은 openapi paths와 1:1.

아래는 **shipped 시그니처**다(#9·#10 이후). 초안 청사진과 다른 곳은 각주로 남긴다.

| HTTP · 경로 | 메서드 시그니처(파라미터 타입) | 반환 DTO | 인증 |
| --- | --- | --- | --- |
| `POST /auth/signup` | `signup(@Valid @RequestBody SignupRequest request)` | 202 + `SignupStartedResponse` | ✕ |
| `POST /auth/signup/verify` | `verifySignup(@Valid @RequestBody VerifySignupRequest request)` | `AuthTokensResponse` | ✕ |
| `POST /auth/signup/resend` | `resendSignupCode(@Valid @RequestBody ResendSignupCodeRequest request)` | 202 + `SignupStartedResponse` | ✕ |
| `POST /auth/login` | `login(@RequestBody LoginRequest request)` | `AuthTokensResponse` | ✕ |
| `GET /auth/oauth/{provider}` | `startOAuth(@PathVariable String provider)` | 302 (본문 없음) | ✕ |
| `POST /auth/oauth/{provider}/callback` | (미구현 — #14) | `AuthTokensResponse` | ✕ |
| `POST /auth/token/refresh` | `refresh(@RequestBody RefreshTokenRequest body)` | `AuthTokensResponse` | ✕ (refreshToken 본문 검증) |
| `GET /auth/me` | `me(@CurrentUser User me)` | `UserResponse` | ○ |
| `PUT /auth/me` | `updateMe(@CurrentUser User me, @RequestBody UpdateProfileRequest req)` | `UserResponse` | ○ |
| `DELETE /auth/me` | `deleteMe(@CurrentUser User me)` | 204 (`ResponseEntity<Void>`) | ○ |
| `POST /auth/logout` | `logout(@CurrentUser User me)` | 204 | ○ |

> ⚠️ 초안 청사진과 다른 점. `logout` 은 **본문을 받지 않는다** — 로그아웃은 토큰 하나가 아니라
> 그 사용자의 살아 있는 RT 전량을 폐기하는 동작이라 주체만 있으면 되기 때문이다(#9).
> `startOAuth` 는 `HttpServletRequest`/`Response` 를 받지 않는다 — 302 를 `ResponseEntity` 로
> 만들면 서블릿 API 를 컨트롤러에 들일 이유가 없다(#10).

- `provider` 파라미터: `kakao|google|apple` 이외 값 → 400 + `Error`(`code: VALIDATION`). 네이버는 ADR-0010 의 보류 대상이라 이 목록에 없다. 대소문자·앞뒤 공백은 정규화한다. 사유 문구에 입력값을 되싣지 않는다 — 반사형 XSS 재료다.
- 인증 필요 메서드는 `@CurrentUser User me` 하나로 끝난다. 주입에 실패하는 모든 경우(인증 없음 · principal 타입 불일치 · 그 id 의 행 없음)는 **본문 없는 401** 이다. `SocialController.requireUser(...)` 같은 컨트롤러별 헬퍼는 #5 에서 전부 사라졌다.
- 오류 응답은 계약의 `Error` 형태(`{ error: { code, message, traceId } }`) 하나뿐이다(#10 완료) — §6-7.

---

## 3. DTO (Java `record`)

> 위치: `user.dto` 또는 신규 `auth.dto`(패키지 컨벤션상 `<resource>.dto`). 공통 `Error`/`Page`는 계약 참조만.

### 요청 (Request records)

| record | 필드 (이름:타입) | openapi 매핑 |
| --- | --- | --- |
| `OAuthCallbackRequest` | `code:String`(필수), `redirectUri:String`(nullable) | `POST /auth/oauth/{provider}/callback` requestBody |
| `RefreshRequest` | `refreshToken:String`(필수) | `POST /auth/token/refresh` · `POST /auth/logout` requestBody |

### 응답 (Response records)

| record / 클래스 | 필드 (이름:타입) | openapi 스키마 |
| --- | --- | --- |
| `AuthTokensResponse` | `accessToken:String`, `refreshToken:String`, `expiresIn:long`(초), `isNew:Boolean`, `user:UserResponse` | `AuthTokens` |
| `UserResponse` | `id:Long`, `email`, `name`, `nickname`, `gender`, `age:Integer`, `travelType`, `imageUrl`, `provider`, `createdAt`, `updatedAt` | `User` |

> **`UserDto` 를 따로 만들지 않았다.** 이 문서의 예전 판은 계약 `User` 가 4필드(id/provider/
> nickname/isNew)라고 적고 Auth 응답 전용 DTO 분리를 지시했는데, 그 서술은 #23 이 계약을
> 정리하기 전의 것이다. 지금 계약의 `User` 는 위 11필드이고 `isNew` 는 거기 **없다** —
> `isNew` 는 로그인 응답(`AuthTokens`)의 1회성 이벤트 속성이지 프로필의 영속 속성이 아니다.
> 즉 `UserResponse` 가 이미 계약의 `User` 다. 사본을 하나 더 만들면 한쪽만 낡는다. (#10)

> `AuthTokensResponse.isNew` 가 `boolean` 이 아니라 `Boolean` 인 것은 의도다. `null` 이면
> `@JsonInclude(NON_NULL)` 이 필드를 통째로 뺀다 — `POST /auth/token/refresh` 응답이 그 경우다.
> `false` 를 실으면 "이번 갱신으로 계정이 생기지 않았다" 는 **물어본 적 없는 질문의 답**이
> 매 갱신마다 앱의 온보딩 분기로 흘러든다. `user` 도 같은 이유로 `null` 이면 빠진다.

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

> ⚠️ **`AuthService` 는 아직 없다.** `refresh`·`logout`·`deleteMe` 의 refresh 토큰 부분은 #9 가
> `user/service/RefreshTokenService`(발급·회전·폐기·정리) + `user/service/UserService`(로그아웃·탈퇴 위임)로
> 구현했다. 특히 위 표의 `void logout(String refreshToken)` 은 **shipped 와 다르다** — 로그아웃은
> 토큰 단위가 아니라 `revokeAllByUserId(userId)` 로 전 기기를 끊는다.
>
> `UserDto me(String subject)` 도 shipped 와 다르다(#10): 주체 해석은 서비스가 아니라
> `CurrentUserArgumentResolver` 가 끝내고, 컨트롤러는 주입받은 엔티티를 `UserResponse.from` 으로
> 바꿀 뿐이다 — 서비스를 한 번 더 부르면 주체 해석 지점이 다시 둘로 갈라진다(#5).
> `buildAuthorizationRedirect(String provider)` 도 서비스에 두지 않았다: 그 메서드의 내용은
> 문자열 하나를 잇는 것뿐이라, 서비스를 하나 만드는 대신 `AuthController.startOAuth` 에 두었다.

> 소셜 토큰 교환(`exchangeCode`)은 `TourApiClient`/`WebClientConfig`의 WebClient 패턴을 그대로 사용(공급자 token endpoint + userinfo 호출). 공급자별 endpoint/파라미터 차이는 provider 분기로 처리.

---

## 5. Entity & Repository

### 5-1. 사용자 엔티티

- **현행**: `user.entity.User` → `@Table(name="users")`. `id`, `username`(=`provider_providerId`), `email`(unique), `name`, `nickname`, `gender`, `travelType`, 동의필드 등.
- **소셜 계정 모델은 #7 에서 실렸다.** 예전 이 자리에는 "스키마 문서(`app_user`) 대비 매핑" 표가 있었고 `provider`·`social_id` 를 **"없음 — 추가 권장"** 이라고 적고 있었다. 지금은 둘 다 컬럼으로 있다. 그 표를 그대로 읽은 다음 사람은 이미 있는 것을 또 만든다.

| 컬럼 | 현행 | 비고 |
| --- | --- | --- |
| `id BIGINT PK` | `id Long` | **JWT `sub` 가 이 값**(ADR-0010) |
| `provider VARCHAR(20)` | `provider` | `local`/`kakao`/`google`/`apple`(#301). `naver` 는 ADR-0010 에서 보류 |
| `social_id VARCHAR(191)` | `socialId` | 이메일 가입자는 NULL |
| `role VARCHAR(20) NOT NULL` | `role` | 기본 `ROLE_USER`. 토큰 발급이 쓴다 |
| `email VARCHAR(255) NULL UNIQUE` | `email` | 카카오 미동의 시 NULL |
| `username` | `username` | 레거시 식별자(`provider_socialId`). 백필용으로만 남는다 |

- 인덱스: `uk_users_provider_social_id(provider, social_id)` UNIQUE + `email` UNIQUE. 정본 DDL 은 `backend/mysql/init/01_schema.sql`, 문서 요약은 [테이블 스키마 §1](../../03-database/schema.md).

### 5-2. Refresh Token 엔티티 (**#9 에서 구현됨 — 아래는 shipped 사실이다**)

`user/entity/RefreshToken` → `@Table(name="refresh_token")`. 운영 적용 SQL 은
`backend/mysql/post-start/05_refresh_token.sql`(information_schema 가드 + PREPARE/EXECUTE 멱등,
사전 점검·사후 검증 포함), 런북은 `backend/mysql/README.md`.

| 엔티티 `RefreshToken` 필드 | 컬럼 | 비고 |
| --- | --- | --- |
| `id:Long` | `id BIGINT PK` | AUTO_INCREMENT |
| `userId:Long` | `user_id BIGINT NOT NULL` | INDEX. **FK 를 걸지 않았다**(아래 참조) |
| `tokenHash:String` | `token_hash VARCHAR(64) NOT NULL` | SHA-256 hex 는 정확히 64자다. 평문 저장 금지. UNIQUE |
| `expiresAt:LocalDateTime` | `expires_at DATETIME(6) NOT NULL` | 만료. INDEX(만료 정리 잡이 훑는다) |
| `revokedAt:LocalDateTime` | `revoked_at DATETIME(6)` NULL | 폐기/회전 시각. **NULL 인 행만 살아 있다** |
| `createdAt:LocalDateTime` | `created_at DATETIME(6) NOT NULL` | 생성 |

> ⚠️ **길이를 `VARCHAR(255)` 로 되돌리지 마라.** prod 는 `ddl-auto=validate` 라 엔티티와 컬럼
> 정의가 어긋나면 **부팅이 실패한다**. 반대로 `validate` 는 UNIQUE 제약을 검사하지 않으므로,
> UNIQUE 가 실제로 걸렸는지는 05 SQL 의 사후 검증이 유일한 확인 수단이다.

> ⚠️ **`user_id` 에 FK 를 걸지 않은 것은 의도다.** FK 가 있으면 회원 탈퇴 경로가 DB 의 삭제
> 순서에 묶인다. 대신 `UserService.deleteMe` 가 `deleteAllByUserId` 로 직접 정리하고,
> 그것이 실제로 남지 않는지는 `AuthTokenRefreshIntegrationTest` 가 매번 확인한다(완료 조건 7).

> ⚠️ **`device_id` 컬럼도 두지 않았다.** Epic #2 의 초기 설계에는 있었지만 빼기로 했습니다.
> 계약에 기기를 식별할 헤더가 없고 `POST /auth/logout` 은 계약상 **전 기기 폐기**라,
> 기기별 폐기를 소비할 코드가 하나도 없습니다. 소비자 없이 형식만 먼저 박지 않습니다 —
> `jti`·`prv` 에 대해 #5 가 세운 판단과 같습니다.
>
> **되돌리기 비싼 결정입니다.** 나중에 기기별 로그아웃을 넣으려면 원장 스키마
> 마이그레이션과 계약 변경(기기 식별 헤더)이 함께 옵니다. 이 문단이 없으면 Epic 본문의
> ERD 만 읽은 다음 사람이 컬럼이 있는 줄 알고 기기별 폐기 API 를 설계합니다. (#15)

> 공간 컬럼 없음(Auth 리소스는 비공간). SPATIAL INDEX 해당 없음.

### 5-3. Repository (Spring Data)

| Repository | 주요 메서드 시그니처 | 종류 |
| --- | --- | --- |
| `UserRepository`(기존) | `Optional<User> findByEmail(String email)` / `findByUsername(String)` | 파생 쿼리 |
| (추가 권장) | `Optional<User> findByProviderAndSocialId(String provider, String socialId)` | 파생 쿼리(provider/social_id 컬럼 추가 시) |
| `RefreshTokenRepository`(#9) | `Optional<RefreshToken> findByTokenHash(String tokenHash)` | 파생 쿼리. 회전의 시작점 |
| `RefreshTokenRepository` | `int revokeIfLive(Long id, LocalDateTime now)` | 회전 CAS. **영향 행 수가 곧 경합의 승패다** |
| `RefreshTokenRepository` | `int revokeAllByUserId(Long userId, LocalDateTime now)` | 전 기기 로그아웃 · 재사용 감지 |
| `RefreshTokenRepository` | `int deleteByUserId(Long userId)` | 탈퇴 시 정리(벌크 DELETE) |
| `RefreshTokenRepository` | `int deleteByExpiresAtBefore(LocalDateTime cutoff)` | 만료 정리 잡(벌크 DELETE) |

> ⚠️ **`deleteByTokenHash` 를 만들어 로그아웃 폐기를 '삭제' 로 바꾸지 마라.** 폐기는 행을
> 남긴 채 `revoked_at` 을 찍는다. 지우면 폐기된 RT 가 다시 왔을 때 "없는 토큰"과 구별되지
> 않아 **재사용 감지가 통째로 무력해진다**(완료 조건 4). 이 문서의 예전 판이 정확히 그
> `long deleteByTokenHash(String)` 를 지시하고 있었다.
>
> 폐기·삭제 네 건이 전부 `@Modifying @Query` 인 것도 의도다 — 파생 삭제는 대상 행을 전부
> SELECT 해 영속화한 뒤 행마다 DELETE 를 날린다.

> 공간/커스텀 native `@Query`는 Auth 범위에 없음.

---

## 6. 구현 노트 (함정 위주)

1. **JWT subject — 결정: `users.id` 로 통일(#5 완료).** 예전에는 `OAuth2SuccessHandler`가 `authentication.getName()`(= `provider_providerId`)을, `UserService.login`이 `email`을 subject로 넣어 한 토큰 형식에 두 규약이 공존했고, 소비처가 전부 email 을 가정해 **소셜 로그인 토큰으로는 me 조회가 깨졌다.** 이제 발급은 `createAccessToken(Long userId, String role)` 한 곳이고(타입이 email·소셜 ID 를 컴파일 단계에서 막는다), 해석은 `JWTAuthenticationFilter` → `AuthenticatedUser` → `@CurrentUser` 한 줄기다. 컨트롤러가 Authorization 헤더를 다시 읽지 않는다는 것은 `AuthSubjectContractSpecTest` 가 소스 스캔으로 잠근다.
1-1. **배포 영향 — 발급된 액세스 토큰이 전부 무효가 된다(강제 재로그인).** subject 규약이 바뀌므로, 배포 이전에 발급된 토큰(subject 가 이메일 또는 `kakao_1234567890`)은 `JWTAuthenticationFilter` 에서 401 로 떨어진다. 개발 단계이므로 마이그레이션 없이 **강제 재로그인**으로 처리한다(이슈 #5 3단계). 앱은 401 을 받으면 저장된 토큰을 지우고 로그인 화면으로 보내면 된다.

   앱이 함께 알아야 하는 계약 변화:

   | 무엇 | 이전 | 이후 |
   | --- | --- | --- |
   | 401 응답 본문 | 계약은 JSON `Error` 를 선언했다(서버는 준 적이 없다) | **본문 없음**(`Content-Type` 도 없음). `error.code` 로 분기하면 깨진다 |
   | 소셜 계정 토큰으로 `/auth/me`·`/bookmarks`·`/collections`·`/public/schedules` | 400 (`IllegalArgumentException` 이 400 으로 매핑) | **200** (본래 의도한 동작) |
   | 인증 실패한 `/api/social/**`·`/journeys/v2/**` | 500 | **401** |
   | `/journeys/v2/**` 의 "없음/권한없음" | 500 | **여전히 500** — 인증이 아니라 존재·소유 검증이라 이번 범위 밖이다. 소유자: #44 |
   | `media_object.owner_id` | JWT subject | `users.id` — 배포 이전 업로드분의 소유권이 끊긴다. 백필 결정은 `docs/03-database/migration.md` §3-1 |

1-2. **`prv`·`jti` 클레임은 넣지 않았다 — 이관처는 M2 이후 Redis Epic 이다(#9 아님).** 이슈 #5 완료 조건 6 은 `sub` 가 숫자 문자열인 것과 함께 "`prv` 가 `kakao`/`google`/`local` 중 하나"를 요구하고, 1단계 첫 체크박스는 `jti`(UUID)도 요구한다. 실제 발급 클레임은 `sub`·`role`·`iat`·`exp` 넷뿐이다. 이유: `jti` 는 블록리스트 저장소가 있어야 의미가 있고(#9 의 refresh 토큰 저장소와 같은 곳), `prv` 는 지금 어떤 소비처도 읽지 않는다 — 읽는 쪽 없이 클레임만 늘리면 토큰만 커지고 규약은 검증되지 않는다. **#9 도 `jti` 를 도입하지 않기로 결론냈다.** 계약이 그 판단과 새 소유자를 적어 두었다(`docs/04-api/openapi.yaml` 의 `bearerAuth` — "`jti` 는 이슈 #9 에서 도입하지 않기로 했습니다 … Redis 로 뒷받침되는 액세스 토큰 블록리스트는 M2 이후 별도 Epic 입니다"). MySQL 블록리스트는 모든 인증 요청마다 DB 조회를 1회 더하면서 고작 1시간짜리 창을 줄인다. `prv` 는 읽는 코드가 없고 가변 값을 불변 토큰에 복제하는 형태라 도입 계획 자체가 없다. **#5 를 닫을 때 완료 조건 6 의 `prv` 절과 1단계의 `jti` 는 이관으로 처리한다 — 이관처는 #9 가 아니라 Redis Epic(`backend/TODO/refresh-token-redis.md`)이다.**

1-3. **앱(#11·#12)에 반드시 전달해야 할 것 (#9·#10).** 백엔드 레인에서는 `app/**` 를 열 수 없으므로 여기 남긴다. **아래 세 번째·네 번째 줄은 지금 앱을 실제로 깨뜨린다** — `app/lib/features/auth/data/auth_repository_impl.dart` 가 로그인 응답 본문을 평문 토큰으로 읽고 있다.

   > **2026-08-30 (#14): 아래 첫 줄은 이력이다.** 딥링크에는 더 이상 토큰이 실리지 않는다 —
   > `heattrip://login-callback?code=<1회용 코드>&state=<앱이 만든 난수>` 이고, 토큰은
   > `POST /auth/oauth/{provider}/callback` 의 응답 본문으로만 온다. 앱은 그 교환을 이미
   > 구현했다(`auth_repository_impl.dart` 의 `exchangeOAuthCode`). 이 줄을 지우지 않는 이유는
   > "왜 그때 그렇게 넘겼는가" 가 다음 사람에게 필요한 맥락이기 때문이다.

   | 무엇 | 왜 | 안 하면 |
   | --- | --- | --- |
   | 딥링크는 `Uri.parse(url).queryParameters['token']` 로 파싱한다 (#14 로 대체됨 — 지금은 `['code']`·`['state']`) | 딥링크가 `heattrip://login-callback?token=<AT>&refresh=<RT>` 로 바뀌었다. 액세스 토큰이 더 이상 URL 의 꼬리가 아니다 | `token=` 뒤를 전부 잘라 쓰던 코드가 `<AT>&refresh=<RT>` 를 통째로 저장한다 → 모든 요청 401 |
   | 갱신 요청을 **single-flight** 로 직렬화하고 실패해도 재시도하지 않는다 | 서버는 유예 창을 두지 않는다. 같은 RT 로 동시에 두 번 보내면 진 쪽이 **재사용**으로 판정된다 | 만료된 AT 로 API 두 개가 동시에 401 → 각자 refresh → 한쪽이 재사용으로 판정되어 **전 기기 로그아웃**. 사용자에게는 서버 버그로 보인다 |
   | `POST /auth/login` 응답을 **JSON 으로 파싱**해 `accessToken` 을 꺼내고, `refreshToken` 을 함께 저장한다 | 응답이 JWT 평문 문자열에서 `AuthTokens` JSON 으로 바뀌었다(#10) | `response.body` 를 그대로 토큰으로 저장하면 JSON 전체가 `Authorization` 헤더에 실린다 → **모든 요청 401**. 그리고 refresh 토큰을 저장하지 않으면 1시간마다 재로그인이다 |
   | `POST /auth/signup` 의 성공을 **202** 로 받고, 계정의 `id` 는 `/auth/signup/verify` 응답의 `user.id` 에서 읽는다 | 가입이 두 걸음이 됐다(#635) — 이 응답에는 만들어진 것이 없다. 그전에는 201 + `User`(#10), 더 전에는 200 + 평문이었다 | 201 만 성공으로 보면 **정상 가입이 실패로 보인다**. 응답에서 `id` 를 읽으려 하면 빈 값이다 |
   | 중복 이메일을 **따로 다루지 않는다** | 이미 가입된 주소도 같은 202 다(#635). 409 를 주면 이 경로가 가입 여부를 묻는 조회 수단이 된다 | 409 분기를 남겨 두면 죽은 코드이고, 그 분기를 살리려고 서버에 409 를 되살리면 아무나 가입 여부를 셀 수 있다 |
   | 로그인 실패를 **401** 로 다룬다 | 자격증명 실패가 500 에서 401 로 바뀌었다(#10). 본문은 없다 | 500 만 서버 오류로 보던 코드가 "서버가 죽었다" 대신 아무 안내도 못 한다 |
   | 4xx·5xx 본문은 `{"error":{"code","message","traceId"}}` 하나뿐이다. **단 401 은 본문이 없다** | 전역 오류 포맷을 계약의 `Error` 로 통일했다(#10) | `{status,message,...}` 나 `{"error":"문자열"}` 을 기대하는 파싱은 전부 빈 값을 읽는다. 401 에서 `error.code` 를 읽으려 하면 파싱 예외가 난다 |

   두 번째 항목은 흔한 사고다(백그라운드 복귀·병렬 요청). 인터셉터에 뮤텍스를 두고, 진행 중인 갱신이 있으면 그 결과를 기다리게 하는 것이 표준 해법이다.

   세 번째 항목의 이행 순서: **서버가 먼저 바뀌었으므로 앱은 즉시 따라와야 한다.** 두 형태를 동시에 받는 관용 코드(문자열이면 그대로, JSON 이면 `accessToken`)를 잠시 두는 것은 괜찮지만, 그 관용은 앱이 배포된 뒤 지워야 한다 — 남겨 두면 다음 사람이 어느 쪽이 계약인지 알 수 없다.

2. **Access token 만료** — 해결됨. 수명은 `jwt.expiration`(기본 3600000ms = 1시간)이고 `JWTProvider.getExpiresInSeconds()` 가 그 값을 초로 돌려준다 — `POST /auth/token/refresh` 의 `expiresIn` 이 그것이다. RT 수명은 `jwt.refresh-expiration`(기본 14일)이며 두 값 모두 `.env.example` 에 등재돼 있다.
3. **Refresh token — #9 에서 구현됨.** 발급·저장(해시)·회전·재사용 감지·만료·폐기·탈퇴 정리·야간 만료 정리가 `user/service/RefreshTokenService` 한 곳에 있다. 남은 함정만 적는다.
   - **회전에 `@Transactional` 을 씌우지 마라.** 재사용 감지는 "전량 폐기를 커밋한 뒤 401 을 던진다" 인데, 하나의 트랜잭션이면 던지는 순간 그 폐기가 함께 롤백되어 완료 조건 4 가 조용히 거짓이 된다. 수정 쿼리 각각이 리포지토리에서 자기 트랜잭션을 갖는다.
   - **검사 순서가 곧 계약이다: ①없음 ②만료 ③재사용.** 만료를 먼저 봐야 "만료된 데다 폐기된" 토큰이 전량 폐기를 유발하지 않는다. 만료는 유출의 증거가 아니라 시간의 경과다(완료 조건 5).
   - **유예 창을 두지 않는다.** 그래서 같은 RT 로 동시에 두 번 보내면 진 쪽이 재사용으로 판정되어 **전 기기가 끊긴다**. 앱은 갱신 요청을 single-flight 로 직렬화해야 하고 실패해도 재시도하면 안 된다 — 재시도가 곧 재사용 판정이다. 계약이 이 요구를 명시한다(§6-1-3 인수인계 표).
   - **만료 정리 잡은 `@EnableScheduling`(`config/SchedulingConfig`) 없이는 완전히 무력하다.** 애너테이션은 붙어 있는데 잡이 영원히 등록되지 않는 상태에서도 앱은 멀쩡히 뜬다. `RefreshTokenOperationalWiringIntegrationTest` 가 살아 있는 컨텍스트의 등록된 잡 목록으로 잠근다.
   - **Hibernate 바인딩 로그를 TRACE 로 올리지 마라.** 올리면 `token_hash`(SHA-256)·이메일·BCrypt 해시·소셜 ID 가 전부 운영 로그로 나간다(#6). 기본값은 `application.properties` 에서 껐고 같은 테스트가 잠근다.
4. **로그인 시작 경로 이중화 — #10 에서 래퍼를 두었다.** 실제 Spring OAuth2 진입점은 `/oauth2/authorization/{provider}`(SecurityConfig `oauth2Login`). 계약 `GET /auth/oauth/{provider}` 는 그 진입점으로의 **302 리다이렉트 래퍼**뿐이다(성공 시 딥링크는 기존 SuccessHandler 가 처리). **별도 인증 로직 재구현 금지** — 그래서 `AuthController.startOAuth` 는 어떤 서비스도 부르지 않고, `AuthControllerTest` 가 그것을 `verifyNoMoreInteractions` 로 잠근다. 앱은 이 경로를 쓸 필요가 없다(진입점을 직접 열면 리다이렉트 한 번을 아낀다) — 계약을 보고 구현한 클라이언트가 막다른 길에 빠지지 않게 하는 호환 표면이다.
5. **콜백 대안 흐름(callback POST)의 토큰 교환** — `flutter_web_auth_2` 딥링크 흐름과 별개로, SPA/네이티브가 인가코드를 직접 넘기는 경우. 공급자 token endpoint 호출은 `WebClientConfig` 빈 + `TourApiClient` 스타일(WebClient, 타임아웃/에러 매핑)로. secret은 `@Value`로 주입, 로그에 노출 금지.
6. **provider 화이트리스트 — #10 에서 구현됨.** `AuthController.SUPPORTED_PROVIDERS` 가 `kakao|google` 만 허용하고, 그 외는 400 + `Error`(`code: VALIDATION`)다. 목록은 계약(`components/parameters/Provider`)의 enum 과 **같아야 한다** — 여기서만 넓히면 계약에 없는 값이 302 로 통과한다. 이제 글이 아니라 테스트가 지킨다: `OpenApiAuthContractTest.supportedProviders_matchTheContractEnum` 이 두 집합을 대조한다(#15). `naver` 는 ADR-0010 에 따라 양쪽에서 함께 빠졌다. 입력은 `trim().toLowerCase()` 로 정규화한다(`CustomOAuth2UserService` 의 `switch` 에 `"Kakao"` 대문자 중복 case 가 있던 것과 같은 함정을 여기서는 만들지 않는다).
7. **에러 포맷 통일 — #10 에서 완료.** 4xx/5xx 본문은 계약의 `Error`(`{ error: { code, message, traceId } }`) 하나뿐이고, 만드는 곳은 `GlobalExceptionHandler` 한 곳뿐이다. `code` 는 HTTP 상태에서 파생된다(`codeOf`) — 던지는 쪽이 문자열을 손으로 적지 않는다. 그 어휘는 계약의 `Error.code` enum 이 소유하며 `AuthContractSpecTest.errorSchema_declaresTheClosedCodeVocabulary` 가 둘을 대조한다.

   정리 전에는 세 갈래였다: 계약의 봉투, `GlobalExceptionHandler` 의 `{ status, error, message, path, timestamp }`, `SocialController` 의 `{ error: "msg" }`(문자열). `SocialController` 의 다섯 핸들러에 있던 `try/catch` 두 겹을 걷어냈다 — 그 `catch (Exception)` 은 예상하지 못한 예외를 스택트레이스도 남기지 않고 삼키고 있었다.

   **단 401 은 예외다:** 인증 실패는 원인과 무관하게 **본문 없는 401** 이고(#5·#6), 계약의 `components/responses/Unauthorized` 도 그렇게 선언한다. `handleDeclaredStatus` 도 401 만은 본문을 붙이지 않는다 — `ResponseStatusException(401)` 하나가 그 계약을 깨뜨리지 않게 하기 위해서다. 인증 실패를 만드는 곳은 `SecurityConfig` 의 `HttpStatusEntryPoint(401)` 와 `GlobalExceptionHandler.handleUnauthenticated`(주체 해석 실패·자격증명 실패·RT 회전 실패) 두 곳뿐이다.

   > ⚠️ **이슈 #10 본문은 401 에도 `{"error":{"code":"UNAUTHORIZED"}}` 본문을 요구했다. 따르지 않았다.** 그 요구는 #5 보다 먼저 쓰였고, #5 가 그 뒤에 '401 은 본문 없음' 으로 확정하면서 계약과 두 테스트(`AuthContractSpecTest.unauthorizedResponse_declaresNoBody`, `GeneratedOpenApiSpecTest.generatedSpec_401NeverDeclaresABody`)가 그것을 잠갔다. 본문을 되붙이면 그 둘이 빨간불이 된다. 계약이 코드보다 우선이라는 규약(#4)을 그대로 따른 결과다.
8. **트랜잭션** — `exchangeCode`(사용자 upsert + refresh 저장), `deleteMe`(사용자 + refresh 삭제)는 `@Transactional` 경계로 묶기. 외부 공급자 HTTP 호출은 트랜잭션 밖에서 수행 후, DB 쓰기만 트랜잭션 내부로(장시간 커넥션 점유 방지).
9. **좌표/공간 무관** — Auth 리소스는 EPSG:5174→WGS84·`ST_Distance_Sphere` 등 공간 처리와 무관(그쪽 함정은 Places/Walks 문서에서 다룸).
10. **테이블명 정합 — #15 에서 해소됐다.** 스키마 문서는 `app_user`, 코드 실체는 `users` 였다. `users` 로 수렴시켰고 `schema.md` §1 이 그 이름이 어디서 왔는지를 각주로 남긴다. `DocDriftTest` 가 `app_user` 가 정의로 되살아나면 빨간불을 낸다.
