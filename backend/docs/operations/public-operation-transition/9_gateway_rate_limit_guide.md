# 9. Gateway / Nginx / Cloudflare Rate Limit 가이드

- 작성 시각: 2026-03-18 00:54:24 +09:00
- 상태: 작성 완료

## 먼저 큰 그림

rate limit은 한 군데에서만 하는 개념이 아니다.

보통 아래처럼 여러 층에서 할 수 있다.

1. Cloudflare 같은 엣지 레벨
2. Load Balancer / API Gateway / Nginx 레벨
3. 애플리케이션 레벨

지금 저장소에는 3번, 즉 앱 레벨 최소 보호선이 들어갔다.  
하지만 실운영에서는 1번 또는 2번이 더 중요하다.

## Cloudflare가 뭔가

Cloudflare는 인터넷과 내 서버 사이에 앞단으로 두는 서비스다.

쉽게 말하면:

- 사용자가 내 서버로 직접 오는 게 아니라
- 먼저 Cloudflare를 거친 뒤
- Cloudflare가 다시 내 서버로 요청을 전달하는 구조다.

Cloudflare가 해주는 대표 기능:

- CDN
- HTTPS 인증서 처리
- 캐싱
- DDoS 완화
- WAF
- Rate limiting

### 왜 좋은가

내 서버까지 요청이 오기 전에 Cloudflare에서 먼저 걸러낼 수 있다.

그래서:

- 트래픽 비용 절감
- 앱 부하 감소
- 악성 요청 차단

효과가 크다.

### public 운영에 왜 좋나

public 저장소가 되면 엔드포인트 구조를 더 빨리 분석당할 수 있다.  
그럴 때 Cloudflare 같은 앞단에서 먼저 막아주면 서버가 훨씬 편해진다.

## Nginx가 뭔가

Nginx는 아주 많이 쓰는 웹서버이자 리버스 프록시다.

리버스 프록시라는 건:

- 사용자는 Nginx에 요청을 보낸다.
- Nginx가 내부의 Spring Boot 앱으로 요청을 넘긴다.

즉, 앱 앞에 한 겹 더 두는 서버다.

Nginx가 흔히 맡는 역할:

- 도메인 연결
- HTTPS 종료
- 정적 파일 제공
- 프록시
- 로드밸런싱
- rate limit

### 왜 좋은가

Spring Boot 앱이 모든 걸 직접 다 받지 않아도 된다.

예를 들어:

- `/auth/login`은 분당 10회 이상 차단
- `/api/curation`은 너무 빠른 반복 호출 차단
- `/media`는 업로드 속도 제한

같은 걸 앱 바깥에서 미리 막을 수 있다.

## Gateway는 또 뭔가

gateway는 앱 앞단에서 요청을 모아서 처리하는 관문 역할이다.

Nginx도 넓게 보면 gateway처럼 쓸 수 있고, 더 큰 시스템에서는 아래를 쓴다.

- Spring Cloud Gateway
- Kong
- AWS API Gateway
- Traefik
- Nginx

즉, 개념적으로는:

- "앞단에서 요청을 통제하는 레이어"

라고 이해하면 된다.

## 왜 앱 안에도 rate limit을 넣었나

네 말대로 정석은 바깥에서 막는 것이다.

그런데 현재 상황은:

- public 운영 준비 단계
- 아직 gateway/WAF 구성이 문서화되지 않음
- 지금 당장 추천 API나 로그인 API는 노출될 수 있음

이라서, 앱 안에도 최소 보호선을 먼저 넣은 것이다.

즉, 이번 작업은:

- 최종 완성형 아키텍처가 아니라
- 비어 있는 상태를 그냥 두지 않기 위한 실용 조치

라고 보면 된다.

## 권장 구조

가장 추천하는 구조는 이렇다.

### 1차 방어

- Cloudflare 또는 WAF

역할:

- IP 차단
- 비정상 트래픽 차단
- DDoS 완화
- 요청 폭주 차단

### 2차 방어

- Nginx 또는 API Gateway

역할:

- 경로별 rate limit
- 업로드 크기 제한
- timeout 제어
- reverse proxy

### 3차 방어

- 애플리케이션 내부 rate limit

역할:

- 로그인
- 추천 API
- 업로드
- 특정 사용자 데이터 API

를 세밀하게 보호

## Nginx에서 보통 어떻게 하나

대표 개념은 두 개다.

### `limit_req_zone`

요청 제한용 메모리 영역을 만든다.

예를 들면:

- IP별 카운터를 유지한다

### `limit_req`

실제 location 또는 endpoint에 제한을 건다.

예를 들어 개념적으로는:

- 로그인은 초당 매우 낮게
- 검색은 좀 더 넓게
- 추천은 중간 정도

이런 식으로 다르게 줄 수 있다.

## Cloudflare에서는 보통 어떻게 하나

Cloudflare 대시보드에서 경로 단위 룰을 만든다.

예를 들어:

- `/auth/login`에 대해 1분당 10회 초과 시 차단
- `/api/curation/*`에 대해 짧은 시간 동안 과다 요청 차단
- 특정 국가, 특정 ASN, 특정 봇 패턴 차단

즉, UI 기반 또는 룰 기반으로 앞단에서 막는다.

## 지금 이 프로젝트에 맞는 현실적 추천

### 지금 당장

- 현재 추가한 앱 레벨 rate limit 유지

### 다음 단계

- Nginx를 앱 앞에 두고 로그인/추천/업로드 경로에 1차 제한

### 더 나중

- Cloudflare 또는 WAF까지 붙여서 외부 악성 트래픽을 더 앞단에서 차단

## 어떤 API부터 앞단 rate limit을 걸면 좋은가

우선순위:

1. `/auth/login`
2. `/api/curation/**`
3. `/media`
4. `/journeys/v2/entries/with-images`
5. `/api/explore/places/search`

이유:

- 로그인은 brute force 대상
- 추천은 비용이 큼
- 업로드는 저장소 비용과 트래픽 비용이 큼
- 검색은 호출량이 많아지기 쉬움

## 이번 문서의 결론

- 네 말대로 rate limit의 1순위는 gateway/Nginx/Cloudflare 같은 앞단이다.
- 이번 저장소에는 그 전에 쓸 수 있는 앱 레벨 최소 보호선을 먼저 넣었다.
- public 운영을 제대로 하려면 나중에 앞단 rate limit도 꼭 추가하는 게 좋다.
