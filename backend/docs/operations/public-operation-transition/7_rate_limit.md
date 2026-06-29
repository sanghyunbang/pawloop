# 7. Rate Limit 추가

- 작성 시각: 2026-03-18 00:54:24 +09:00
- 상태: 완료

## 이게 뭔가

rate limit은 일정 시간 안에 같은 사용자 또는 같은 IP가 너무 많은 요청을 보내면 요청을 막는 보호 장치다.

쉽게 말하면:

- 로그인 무차별 대입 공격 방지
- 추천 API 과다 호출 방지
- 파일 업로드 남용 방지
- 검색 API 폭주 방지

## 보통 어디에서 하나

네가 말한 것처럼 보통은 아래 계층이 1순위다.

- API Gateway
- Nginx
- Load Balancer
- WAF
- Cloudflare 같은 엣지 계층

왜냐하면 앱까지 요청이 도착하기 전에 막는 게 더 싸고 효율적이기 때문이다.

## 그런데 왜 앱에도 넣었나

현재 구조는 gateway가 명확히 분리된 상태가 아니고, public 운영을 준비하는 단계다.

그래서 이번에는 `최소 보호선`으로 앱 안에도 rate limit을 넣었다.

이걸 앱 레벨 fallback이라고 보면 된다.

즉, 정석은:

1. gateway/load balancer에서 1차 차단
2. 앱에서 민감 API만 2차 보호

지금은 2차 보호막을 먼저 만든 셈이다.

## 이번에 어떤 방식으로 넣었나

IP 기반 in-memory rate limit filter를 추가했다.

추가 파일:

- [PublicSecurityProperties.java](/C:/Users/mm206/git_projects/heat_trip_backend/src/main/java/com/heattrip/heat_trip_backend/config/PublicSecurityProperties.java)
- [PublicSecurityConfig.java](/C:/Users/mm206/git_projects/heat_trip_backend/src/main/java/com/heattrip/heat_trip_backend/config/PublicSecurityConfig.java)
- [ApiRateLimitFilter.java](/C:/Users/mm206/git_projects/heat_trip_backend/src/main/java/com/heattrip/heat_trip_backend/security/ApiRateLimitFilter.java)

연결 파일:

- [SecurityConfig.java](/C:/Users/mm206/git_projects/heat_trip_backend/src/main/java/com/heattrip/heat_trip_backend/config/SecurityConfig.java)
- [application.properties](/C:/Users/mm206/git_projects/heat_trip_backend/src/main/resources/application.properties)
- [.env.example](/C:/Users/mm206/git_projects/heat_trip_backend/.env.example)

## 어떤 요청을 제한하나

이번에는 비용과 위험이 큰 경로만 좁게 잡았다.

- `POST /auth/login`
- `/api/curation/**`
- `GET /api/explore/places/search`
- `POST /feedback`
- `POST /api/explore/places/{contentId}/feedback`
- `/media`
- 여행 이미지 업로드 관련 경로

## 현재 기본 제한값

기본 윈도우:

- 60초

기본 제한:

- 로그인: 10회
- 추천: 30회
- 업로드: 20회
- 피드백: 30회
- 검색: 120회

이 값들은 `.env` 환경변수로 조정할 수 있다.

## 응답은 어떻게 되나

제한을 넘기면 서버는 `429 Too Many Requests`를 반환한다.

응답 바디에는 아래 정보가 들어간다.

- 상태 코드
- 에러 이름
- 어떤 bucket에서 막혔는지
- 윈도우 시간
- 제한 수치

## 이 방식의 한계

이건 어디까지나 `앱 내부 최소 보호선`이다.

한계:

- 서버 재시작 시 카운터 초기화
- 여러 대 서버로 늘어나면 인스턴스 간 공유 안 됨
- Redis 같은 중앙 저장소 기반보다 단순함
- 진짜 대규모 방어는 gateway/WAF가 더 적합

즉, 지금은 public 운영 준비용 1차 방어다.

## 앞으로 더 좋은 구조

나중에는 아래 순서가 더 좋다.

1. Cloudflare / WAF / Nginx / Gateway에서 1차 rate limit
2. 로그인, 추천, 업로드만 앱 레벨 세부 제한
3. 필요하면 Redis 기반 분산 rate limit

## 이번 작업의 의미

이번 rate limit은 "완성형 보안"이 아니라, public 저장소 기반 운영에서 바로 비어 보이는 구멍을 막는 작업이다.

즉, 지금 목적에는 충분히 실용적이다.
