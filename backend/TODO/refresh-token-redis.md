# TODO: RefreshToken(MySQL 원장) + Redis(RT 검증캐시 · AT 블랙리스트)

> 직접 구현용 체크리스트. 코드는 내가 짠다 — 이 문서는 "무엇을, 어떤 순서로"만.
> 아키텍처: **MySQL = RT 원장(진실)** / **Redis = RT 검증 캐시 + AT 블랙리스트(jti·TTL)**.

## 0. 설계 결정 (확정한 것)
- [ ] RT = **opaque 랜덤 문자열**(UUID/SecureRandom) + MySQL 저장 (JWT 아님 — 폐기 가능해야 하므로)
- [ ] RT는 **해시로 저장** 권장(비번처럼). 행 단위 = 토큰 1개(멀티 디바이스 = 여러 행)
- [ ] **로테이션**: refresh 때 새 RT 발급 + 옛 RT 폐기. 폐기된 RT 재사용 감지 시 그 유저 RT 전부 폐기
- [ ] 만료: **AT 짧게(15~30분)** / RT 길게(2주). AT 짧아야 블랙리스트 TTL도 짧음
- [ ] Redis 다운 시: RT 검증은 **MySQL 폴백**, AT 블랙리스트는 **fail-open**(+짧은 AT 만료로 완화) ← 정책 확정 필요

## 1. 만들 것
| 대상 | 위치 | 내용 |
|---|---|---|
| `RefreshToken` 엔티티 | `user/entity/` | id, email, tokenHash, expiresAt, createdAt, (deviceId, revoked) |
| `RefreshTokenRepository` | `user/repository/` | findByToken(해시), deleteByEmail, deleteByToken |
| Redis 의존성 | build.gradle | spring-boot-starter-data-redis (로컬: `docker run -p 6379:6379 redis`) |
| `AtBlacklistPort` 인터페이스 | `OAuth/` 또는 `auth/port/` | `block(jti, ttl)` / `isBlocked(jti)` — 테스트에서 페이크로 교체 |
| `RtCachePort` 인터페이스 | 〃 | put/get/evict — RT 검증 캐시(선택. AT 블랙이 우선) |
| Redis 구현체 | `config/` 또는 `infra/` | StringRedisTemplate로 포트 구현. 키: `bl:at:{jti}`, `rt:{hash}` |
| `JWTProvider` 수정 | `OAuth/jwt/` | AT에 **jti 추가**(`.setId(UUID)`), jti·잔여수명 getter, `createRefreshToken`(opaque) |
| `JWTAuthenticationFilter` 수정 | 〃 | 서명/만료 검증 통과 후 → **jti 블랙리스트 조회 → 있으면 401** |
| `UserService.login` 수정 | user/service | AT+RT 발급, RT DB 저장, **둘 다 반환**(응답: openapi `AuthTokens` = accessToken/refreshToken/expiresIn) |
| `OAuth2SuccessHandler` 수정 | OAuth/handler | 소셜 로그인도 RT 발급·저장. 리다이렉트에 `&refresh=` 추가(프론트 파싱도 수정) |
| `POST /auth/token/refresh` | AuthController | RT 검증(캐시→MySQL 폴백) → 새 AT(+로테이션: 새 RT) |
| `UserService.logout` 채우기 | user/service | **AT jti 블랙리스트 추가(TTL=잔여) + RT 삭제(MySQL+캐시)** ← 지금 비어있는 메서드 |

## 2. TDD 순서 (한 사이클씩 🔴→🟢)
1. [ ] `RefreshToken` 엔티티/리포 — 저장·조회·삭제 테스트
2. [ ] `JWTProvider` — AT에 jti 들어가는지 / 잔여수명 계산 테스트
3. [ ] `AtBlacklistPort` 페이크 → **logout이 "블랙리스트 추가 + RT 삭제" 하는지** 서비스 테스트 (`verify`)
4. [ ] `refresh()` — 유효 RT→새 AT+새 RT/옛 RT 폐기, 만료·미존재 RT→예외, **폐기된 RT 재사용→전체 폐기**
5. [ ] 필터 — 블랙리스트된 jti 요청 401 (통합: Testcontainers Redis 권장)
6. [ ] login/소셜 — AT(jti)+RT 발급·저장 확인

## 3. 흐름 요약표
| 시점 | MySQL | Redis |
|---|---|---|
| 로그인/소셜 | RT 저장 | (선택) RT 캐시 |
| 매 인증요청 | — | AT 블랙리스트 조회 |
| refresh | 옛 RT 삭제+새 RT 저장 | 옛 RT 캐시 삭제 |
| logout | RT 삭제 | **AT 블랙(TTL=잔여)** + RT 캐시 삭제 |
| 재사용 감지 | 유저 RT 전부 삭제 | AT들 블랙 + 캐시 삭제 |

## 4. 잊지 말 것
- [ ] 폐기 순서: **MySQL 먼저(진실) → Redis 삭제** (동기)
- [ ] `AuthApiDoc`의 logout 설명을 실제 동작(블랙+RT폐기)으로 갱신
- [ ] 프론트: refresh 저장(`flutter_secure_storage` 권장) + 401 시 자동 재발급(dio 인터셉터) + 소셜 콜백 `&refresh=` 파싱
- [ ] 계약: `docs/04-api/openapi.yaml`의 `AuthTokens`/`/auth/token/refresh`와 응답 모양 일치시키기
- [ ] 만료 RT 정리 스케줄러(선택)
