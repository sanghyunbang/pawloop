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
| `POST /auth/token/refresh` | **있음(#9 완료)** | `AuthController.refresh` → `RefreshTokenService.rotate`. 회전 + 재사용 감지 + 만료. 실패는 본문 없는 401, 형식 오류는 400·415·405. §5·§6 참조. |
| `GET /auth/me` | **있음(수정)** | 현 `AuthController.me`가 `UserResponse` 반환. 계약 `User` 스키마(id/provider/nickname/isNew)로 응답 정합 맞추기. |
| `DELETE /auth/me` (회원탈퇴) | **있음(재사용)** | 현 `AuthController.deleteMe` 그대로. 204. |
| `POST /auth/logout` | **있음(#9 완료) / 부분 폐기** | `AuthController.logout` → `UserService.logout` → `RefreshTokenService.revokeAllByUserId`. **전 기기 로그아웃**이며 멱등(폐기할 것이 없어도 204). 다만 액세스 토큰은 여전히 만료(1시간)까지 유효하다 — `jti` 블록리스트가 없기 때문이고, 그 소유자는 M2 이후 Redis Epic(`backend/TODO/refresh-token-redis.md`)이다. |

**재사용 가능한 기존 자산**
- `OAuth/jwt/JWTProvider` — `createAccessToken(userId, role)`, `getUserIdFromToken`, `validateToken`, `getExpiresInSeconds`. **refresh 는 JWT 가 아니므로 여기서 만들지 않는다** — 폐기 가능해야 해서 `RefreshTokenService` 가 256bit 난수를 발급한다(#9).
- `OAuth/jwt/JWTAuthenticationFilter` — `Authorization: Bearer` 파싱 후 SecurityContext 설정. **인증 추출의 표준 규약.**
- `OAuth/service/CustomOAuth2UserService` — 소셜 응답 → `OAuth2UserInfo`(Google/Kakao/Naver) 변환 + `users` upsert.
- `OAuth/handler/OAuth2SuccessHandler` — JWT 발급 후 `heattrip://login-callback?token=` 딥링크 리다이렉트.
- `OAuth/user/OAuth2UserInfo`(+ Google/Kakao/NaverOAuth2User) — 공급자별 provider/providerId/email/name 추출.
- ~~`user/service/UserService` 의 `Bearer` 헤더 → subject 추출 헬퍼~~ — **#5 에서 삭제됐다.** 대체: `OAuth/principal/CurrentUserArgumentResolver` + `@CurrentUser`. 컨트롤러는 Authorization 헤더를 다시 읽지 않는다(§6-1).
- `user/repository/UserRepository` — `findByEmail`, `findByUsername`, `findByNickname`.
- `config/SecurityConfig` — **`/auth/**` 는 더 이상 permitAll 이 아니다(#23).** 공개는 `/auth/signup`·`/auth/login`·`/auth/oauth/**`·`/auth/token/refresh`·`/oauth2/**`·`/login/**` 등 열거된 경로뿐이고 나머지는 `anyRequest().authenticated()` + `HttpStatusEntryPoint(401)`. STATELESS, `oauth2Login(userService, successHandler)`.

---

## 1. 개요

- **책임**: 소셜(카카오/네이버/구글) 로그인 진입·콜백 처리, 앱 세션 토큰(access/refresh) 발급·갱신·폐기, 내 정보 조회/탈퇴.
- **관련 테이블**: `app_user`(스키마 문서) — **현재 코드 실체는 `users` 테이블 + `User` 엔티티**. 두 스키마가 다름(§6 정합성 함정 참조). refresh token 원장은 **`refresh_token` 테이블로 존재한다**(#9). 운영 적용 SQL 은 `backend/mysql/post-start/05_refresh_token.sql`, 런북은 `backend/mysql/README.md`(§5-2).
- **인증 규약**: JWT Bearer, **subject = `users.id`**(#5 완료). 계약(`openapi.yaml`)은 이 값을 "파싱 금지의 불투명 사용자 키"로 선언한다 — 이메일도 `provider_providerId`도 아니다. 해석은 `JWTAuthenticationFilter` → `AuthenticatedUser` → `@CurrentUser` 한 줄기뿐이다(§6-1).

---

## 2. Controller — `AuthController` (`@RequestMapping("/auth")`)

> 기존 `user.controller.AuthController` 확장/정리. **인증이 필요한 핸들러는 `@CurrentUser User me` 파라미터를 받는다** — 컨트롤러가 `Authorization` 헤더를 다시 읽는 것은 #5 이후 금지이고 `AuthSubjectContractSpecTest` 가 소스 스캔으로 막는다. 각 행은 openapi paths와 1:1.

| HTTP · 경로 | 메서드 시그니처(파라미터 타입) | 반환 DTO | 인증 |
| --- | --- | --- | --- |
| `GET /auth/oauth/{provider}` | `startOAuth(@PathVariable String provider, HttpServletRequest req, HttpServletResponse res)` | 302 (본문 없음) | ✕ |
| `POST /auth/oauth/{provider}/callback` | `oauthCallback(@PathVariable String provider, @RequestBody OAuthCallbackRequest body)` | `AuthTokensDto` | ✕ |
| `POST /auth/token/refresh` | `refresh(@RequestBody RefreshRequest body)` | `AuthTokensDto` | ✕ (refreshToken 본문 검증) |
| `GET /auth/me` | `me(HttpServletRequest req)` | `UserDto` | ○ |
| `DELETE /auth/me` | `deleteMe(HttpServletRequest req)` | 204 (`ResponseEntity<Void>`) | ○ |
| `POST /auth/logout` | `logout(@RequestBody(required=false) RefreshRequest body, HttpServletRequest req)` | 204 | ✕(선택) |

> ⚠️ 위 표는 **설계 시점의 청사진**이다. `/auth/token/refresh`·`/auth/logout` 의 shipped 시그니처는 다르다(#9):
> `refresh(@RequestBody RefreshTokenRequest body)` 는 `AuthTokensResponse` 를 돌려주고,
> `logout(@CurrentUser User me)` 는 **본문을 받지 않는다** — 로그아웃은 토큰 하나가 아니라
> 그 사용자의 살아 있는 RT 전량을 폐기하는 동작이라 주체만 있으면 되기 때문이다.

- `provider` 파라미터: `kakao|naver|google` 이외 값 → 400/error.
- 인증 필요 메서드는 `@CurrentUser User me` 하나로 끝난다. 주입에 실패하는 모든 경우(인증 없음 · principal 타입 불일치 · 그 id 의 행 없음)는 **본문 없는 401** 이다. `SocialController.requireUser(...)` 같은 컨트롤러별 헬퍼는 #5 에서 전부 사라졌다.
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

> ⚠️ **`AuthService` 는 아직 없다.** `refresh`·`logout`·`deleteMe` 의 refresh 토큰 부분은 #9 가
> `user/service/RefreshTokenService`(발급·회전·폐기·정리) + `user/service/UserService`(로그아웃·탈퇴 위임)로
> 구현했다. 특히 위 표의 `void logout(String refreshToken)` 은 **shipped 와 다르다** — 로그아웃은
> 토큰 단위가 아니라 `revokeAllByUserId(userId)` 로 전 기기를 끊는다.

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

1-3. **앱(#11·#12)에 반드시 전달해야 할 두 가지 (#9).** 백엔드 레인에서는 `app/**` 를 열 수 없으므로 여기 남긴다.

   | 무엇 | 왜 | 안 하면 |
   | --- | --- | --- |
   | 딥링크는 `Uri.parse(url).queryParameters['token']` 로 파싱한다 | 딥링크가 `heattrip://login-callback?token=<AT>&refresh=<RT>` 로 바뀌었다. 액세스 토큰이 더 이상 URL 의 꼬리가 아니다 | `token=` 뒤를 전부 잘라 쓰던 코드가 `<AT>&refresh=<RT>` 를 통째로 저장한다 → 모든 요청 401 |
   | 갱신 요청을 **single-flight** 로 직렬화하고 실패해도 재시도하지 않는다 | 서버는 유예 창을 두지 않는다. 같은 RT 로 동시에 두 번 보내면 진 쪽이 **재사용**으로 판정된다 | 만료된 AT 로 API 두 개가 동시에 401 → 각자 refresh → 한쪽이 재사용으로 판정되어 **전 기기 로그아웃**. 사용자에게는 서버 버그로 보인다 |

   두 번째 항목은 흔한 사고다(백그라운드 복귀·병렬 요청). 인터셉터에 뮤텍스를 두고, 진행 중인 갱신이 있으면 그 결과를 기다리게 하는 것이 표준 해법이다.

2. **Access token 만료** — 해결됨. 수명은 `jwt.expiration`(기본 3600000ms = 1시간)이고 `JWTProvider.getExpiresInSeconds()` 가 그 값을 초로 돌려준다 — `POST /auth/token/refresh` 의 `expiresIn` 이 그것이다. RT 수명은 `jwt.refresh-expiration`(기본 14일)이며 두 값 모두 `.env.example` 에 등재돼 있다.
3. **Refresh token — #9 에서 구현됨.** 발급·저장(해시)·회전·재사용 감지·만료·폐기·탈퇴 정리·야간 만료 정리가 `user/service/RefreshTokenService` 한 곳에 있다. 남은 함정만 적는다.
   - **회전에 `@Transactional` 을 씌우지 마라.** 재사용 감지는 "전량 폐기를 커밋한 뒤 401 을 던진다" 인데, 하나의 트랜잭션이면 던지는 순간 그 폐기가 함께 롤백되어 완료 조건 4 가 조용히 거짓이 된다. 수정 쿼리 각각이 리포지토리에서 자기 트랜잭션을 갖는다.
   - **검사 순서가 곧 계약이다: ①없음 ②만료 ③재사용.** 만료를 먼저 봐야 "만료된 데다 폐기된" 토큰이 전량 폐기를 유발하지 않는다. 만료는 유출의 증거가 아니라 시간의 경과다(완료 조건 5).
   - **유예 창을 두지 않는다.** 그래서 같은 RT 로 동시에 두 번 보내면 진 쪽이 재사용으로 판정되어 **전 기기가 끊긴다**. 앱은 갱신 요청을 single-flight 로 직렬화해야 하고 실패해도 재시도하면 안 된다 — 재시도가 곧 재사용 판정이다. 계약이 이 요구를 명시한다(§6-1-3 인수인계 표).
   - **만료 정리 잡은 `@EnableScheduling`(`config/SchedulingConfig`) 없이는 완전히 무력하다.** 애너테이션은 붙어 있는데 잡이 영원히 등록되지 않는 상태에서도 앱은 멀쩡히 뜬다. `RefreshTokenOperationalWiringIntegrationTest` 가 살아 있는 컨텍스트의 등록된 잡 목록으로 잠근다.
   - **Hibernate 바인딩 로그를 TRACE 로 올리지 마라.** 올리면 `token_hash`(SHA-256)·이메일·BCrypt 해시·소셜 ID 가 전부 운영 로그로 나간다(#6). 기본값은 `application.properties` 에서 껐고 같은 테스트가 잠근다.
4. **로그인 시작 경로 이중화** — 실제 Spring OAuth2 진입점은 `/oauth2/authorization/{provider}`(SecurityConfig `oauth2Login`). 계약 `GET /auth/oauth/{provider}`는 이 진입점으로의 **302 리다이렉트 래퍼**만 두면 됨(성공 시 딥링크는 기존 SuccessHandler가 처리). 별도 인증 로직 재구현 금지.
5. **콜백 대안 흐름(callback POST)의 토큰 교환** — `flutter_web_auth_2` 딥링크 흐름과 별개로, SPA/네이티브가 인가코드를 직접 넘기는 경우. 공급자 token endpoint 호출은 `WebClientConfig` 빈 + `TourApiClient` 스타일(WebClient, 타임아웃/에러 매핑)로. secret은 `@Value`로 주입, 로그에 노출 금지.
6. **provider 화이트리스트** — `{provider}`는 `kakao|naver|google`만 허용. 그 외는 400 + `Error`(`code: VALIDATION`류). `CustomOAuth2UserService`의 `switch`에 `"Kakao"`(대문자) 중복 case가 있으니 정규화(소문자) 후 분기 통일 권장.
7. **에러 포맷 통일** — 계약은 4xx/5xx 본문으로 `{ error: { code, message, traceId? } }` 를 선언한다. 반면 `SocialController`는 `{ error: "msg" }`(문자열), `GlobalExceptionHandler`는 `{ status, error, message, path, timestamp }` 로 서로 다르다 → 정리는 #10. **단 401 은 예외다:** 인증 실패는 원인과 무관하게 **본문 없는 401** 이고(#5·#6), 계약의 `components/responses/Unauthorized` 도 그렇게 선언한다. 인증 실패를 컨트롤러가 만들지 않는다는 점도 함께 바뀌었다 — `SecurityConfig` 의 `HttpStatusEntryPoint(401)` 와 `CurrentUserArgumentResolver` 두 곳뿐이다.
8. **트랜잭션** — `exchangeCode`(사용자 upsert + refresh 저장), `deleteMe`(사용자 + refresh 삭제)는 `@Transactional` 경계로 묶기. 외부 공급자 HTTP 호출은 트랜잭션 밖에서 수행 후, DB 쓰기만 트랜잭션 내부로(장시간 커넥션 점유 방지).
9. **좌표/공간 무관** — Auth 리소스는 EPSG:5174→WGS84·`ST_Distance_Sphere` 등 공간 처리와 무관(그쪽 함정은 Places/Walks 문서에서 다룸).
10. **테이블명 정합** — 스키마 문서는 `app_user`, 코드 실체는 `users`. 문서·코드 중 한쪽으로 명칭을 수렴시키거나, 문서에 "실 테이블=`users`" 주석을 남길 것(마이그레이션 혼선 방지).

완료: C:/Users/mm206/git_projects/heattrip/docs/02-architecture/backend/auth.md
