# TODO: Redis(RT 검증캐시 · AT 블랙리스트)

> ✅ **MySQL 절반은 이슈 #9 에서 끝났다.** 여기 남은 것은 **Redis 캐시 + 액세스 토큰
> 블록리스트(jti)** 뿐이다. 아래 "이미 끝난 것" 을 다시 만들지 마라 — shipped 보증을 깬다.
>
> 아키텍처: **MySQL = RT 원장(진실)** / **Redis = RT 검증 캐시 + AT 블랙리스트(jti·TTL)**.
> 코드는 내가 짠다 — 이 문서는 "무엇을, 어떤 순서로"만.

## 0. 설계 결정

- [x] RT = **opaque 랜덤 문자열** + MySQL 저장 (JWT 아님 — 폐기 가능해야 하므로). shipped: `SecureRandom` 32바이트를 패딩 없는 Base64URL 로 적은 43자
- [x] RT 는 **SHA-256 해시로 저장**. 행 단위 = 토큰 1개(멀티 디바이스 = 여러 행)
- [x] **로테이션**: refresh 때 새 RT 발급 + 옛 RT 폐기. 폐기된 RT 재사용 감지 시 그 유저 RT 전부 폐기
- [x] 만료: AT 1시간(`jwt.expiration`) / RT 14일(`jwt.refresh-expiration`)
- [ ] Redis 다운 시: RT 검증은 **MySQL 폴백**, AT 블랙리스트는 **fail-open**(+짧은 AT 만료로 완화) ← 정책 확정 필요

## 1. 이미 끝난 것 (#9) — 다시 만들지 말 것

| 대상 | 위치 | shipped 사실 |
|---|---|---|
| `RefreshToken` 엔티티 | `user/entity/` | `id, userId, tokenHash, expiresAt, revokedAt, createdAt`. **email 로 키잉하지 않는다** — 인증 주체는 `users.id` 하나다(#5). |
| `RefreshTokenRepository` | `user/repository/` | `findByTokenHash`, `revokeIfLive`(회전 CAS), `revokeAllByUserId`, `deleteByUserId`, `deleteByExpiresAtBefore`. **`deleteByEmail`·`deleteByToken` 은 만들지 않는다** — 이 문서의 예전 판에 남아 있던 초안이다. |
| `RefreshTokenService` | `user/service/` | 발급·해싱·회전·재사용 감지·폐기·만료 정리의 유일한 출입구. Redis 를 끼운다면 **이 경계**가 이음새다. |
| `POST /auth/token/refresh` | `AuthController` | 회전 + 재사용 감지. 실패는 본문 없는 401, 형식 오류는 400·415·405. |
| `UserService.logout` | `user/service/` | `revokeAllByUserId` 로 **전 기기 로그아웃**. 멱등. |
| `OAuth2SuccessHandler` | `OAuth/handler/` | 소셜 로그인도 RT 발급·저장. 딥링크에 `&refresh=` 추가됨. |
| 만료 RT 정리 스케줄러 | `user/service/RefreshTokenPurgeScheduler` | 야간 cron(`auth.refresh-token.purge-cron`, Asia/Seoul). `config/SchedulingConfig` 의 `@EnableScheduling` 이 켠다. |
| 계약 갱신 | `docs/04-api/openapi.yaml`·`api-spec.md`·`docs/02-architecture/backend/auth.md` | 회전·재사용 감지·single-flight 요구·`AuthApiDoc` 의 logout 설명까지 갱신됨. |
| 운영 SQL | `backend/mysql/post-start/05_refresh_token.sql` | 멱등 + 사전 점검 + 사후 검증. 런북은 `backend/mysql/README.md`. |

> ⚠️ **폐기는 삭제가 아니다.** 로그아웃·회전·재사용 감지는 행을 남긴 채 `revoked_at` 을
> 찍는다. 지우면 폐기된 RT 가 다시 왔을 때 "없는 토큰" 과 구별되지 않아 **재사용 감지가
> 무력해진다.** 행을 실제로 지우는 것은 탈퇴 정리와 만료 정리 둘뿐이다.

## 2. 남은 것 — 만들 것

| 대상 | 위치 | 내용 |
|---|---|---|
| Redis 의존성 | build.gradle | spring-boot-starter-data-redis (로컬: `docker run -p 6379:6379 redis`) |
| `AtBlacklistPort` 인터페이스 | `OAuth/` 또는 `auth/port/` | `block(jti, ttl)` / `isBlocked(jti)` — 테스트에서 페이크로 교체 |
| `RtCachePort` 인터페이스 | 〃 | put/get/evict — RT 검증 캐시(선택. AT 블랙이 우선) |
| Redis 구현체 | `config/` 또는 `infra/` | StringRedisTemplate 로 포트 구현. 키: `bl:at:{jti}`, `rt:{hash}` |
| `JWTProvider` 수정 | `OAuth/jwt/` | AT 에 **jti 추가**(`.setId(UUID)`), jti·잔여수명 getter |
| `JWTAuthenticationFilter` 수정 | 〃 | 서명/만료 검증 통과 후 → **jti 블랙리스트 조회 → 있으면 401** |
| `UserService.logout` 보강 | user/service | 지금은 RT 전량 폐기만 한다. 여기에 **AT jti 블랙리스트 추가(TTL=잔여)** 를 더한다 |

> `jti` 를 지금 넣지 않은 이유는 계약(`openapi.yaml` 의 `bearerAuth`)에 적혀 있다 —
> 소비자(블록리스트 저장소) 없이 형식만 먼저 박으면 토큰만 커지고 규약은 검증되지 않는다.
> **이 문서가 그 소비자를 만드는 작업이다.** 넣는 순간
> `AuthContractSpecTest.bearerAuth_documentsActualClaims` 가 빨간불이 된다 — 실제 발급
> 토큰과 문서의 클레임 표를 대조하기 때문이다. 문서를 함께 고치라는 뜻이다.

## 3. TDD 순서 (한 사이클씩 🔴→🟢)

1. [ ] `JWTProvider` — AT 에 jti 들어가는지 / 잔여수명 계산 테스트 (+ 계약의 클레임 표 갱신)
2. [ ] `AtBlacklistPort` 페이크 → logout 이 "블랙리스트 추가 + RT 전량 폐기" 하는지 서비스 테스트
3. [ ] 필터 — 블랙리스트된 jti 요청 401 (통합: Testcontainers Redis)
4. [ ] Redis 다운 시 폴백/fail-open 동작

## 4. 흐름 요약표 (shipped + 계획)

| 시점 | MySQL (shipped) | Redis (계획) |
|---|---|---|
| 로그인/소셜 | RT 저장 | (선택) RT 캐시 |
| 매 인증요청 | — | AT 블랙리스트 조회 |
| refresh | 옛 RT `revoked_at` 마킹 + 새 RT 저장 | 옛 RT 캐시 삭제 |
| logout | 그 유저의 살아 있는 RT 전량 `revoked_at` 마킹 | **AT 블랙(TTL=잔여)** + RT 캐시 삭제 |
| 재사용 감지 | 그 유저의 살아 있는 RT 전량 마킹 | AT 들 블랙 + 캐시 삭제 |
| 탈퇴 | 그 유저의 RT 행 **삭제** | 캐시 삭제 |
| 야간 정리 | 만료된 행 **삭제** | — |

## 5. 잊지 말 것

- [ ] 폐기 순서: **MySQL 먼저(진실) → Redis 삭제** (동기)
- [ ] 프론트(#11·#12): refresh 저장(`flutter_secure_storage`) + 401 시 자동 재발급(dio 인터셉터, **single-flight 필수**) + 소셜 콜백 `&refresh=` 파싱. 상세는 `docs/02-architecture/backend/auth.md` §6-1-3
- [ ] `POST /auth/login`·`/auth/signup` 응답을 계약의 `AuthTokens` JSON 으로 옮기는 것은 **#10** 이다. 그때 `UserService.login` 이 이미 발급하고 있는 RT 를 응답에 실어라 — 지금은 발급만 하고 아무도 받지 않는다
- [ ] `POST /auth/token/refresh` 의 rate limit 은 **#14**. 현재 이 경로는 비인증 + 무제한이다
