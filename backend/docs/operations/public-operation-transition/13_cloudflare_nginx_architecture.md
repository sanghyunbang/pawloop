# 13. Cloudflare + Nginx + Mac mini + Spring Boot 구조 설명

- 작성 시각: 2026-03-18 00:54:24 +09:00
- 상태: 완료

## 이 문서의 목적

권장 아키텍처인 `Cloudflare + Mac mini + Nginx + Spring Boot` 구조를 이해할 수 있게 정리한다.

이 문서는 개념 설명과 목표 구조를 연결해 주는 문서다.

주의:

- 2026-03-18 기준 현재 실운영은 아직 이 구조가 아니다.
- 실제 운영 구조는 [20_mac_mini_actual_state_2026_03_18.md](20_mac_mini_actual_state_2026_03_18.md) 를 본다.

## 가장 먼저 결론

Cloudflare와 Nginx는 서로 대체재가 아니다.

둘은 계층이 다르다.

- Cloudflare: 인터넷 바깥쪽 앞단
- Nginx: Mac mini 내부에서 앱 앞단
- Spring Boot: 실제 백엔드 앱

즉, 목표 구조는 아래처럼 된다.

```text
사용자
  -> Cloudflare
  -> cloudflared tunnel 또는 Cloudflare proxy
  -> Mac mini
  -> Nginx
  -> Spring Boot (127.0.0.1:8080)
```

## 각 구성요소가 하는 일

### 1. Cloudflare

Cloudflare는 외부 인터넷 쪽 앞단 서비스다.

주요 역할:

- 도메인 연결
- HTTPS 인증서 처리
- 외부 트래픽 진입점
- DDoS 완화
- WAF
- 바깥쪽 rate limit

쉽게 말하면:

- 인터넷에서 들어오는 요청을 제일 먼저 받는 곳

### 2. cloudflared

`cloudflared`는 Mac mini에서 Cloudflare로 연결을 유지하는 에이전트다.

주요 역할:

- Mac mini를 공인 IP 없이 Cloudflare에 연결
- 외부 요청을 Cloudflare에서 받아 내부 서비스로 전달

쉽게 말하면:

- Cloudflare와 Mac mini를 이어주는 터널 프로그램

### 3. Nginx

Nginx는 Mac mini 안에서 Spring Boot 앞단에 두는 리버스 프록시다.

주요 역할:

- 경로별 reverse proxy
- rate limit
- 요청 크기 제한
- timeout 제어
- header 정리
- 여러 앱 포트 분기

쉽게 말하면:

- Mac mini 내부의 문지기

### 4. Spring Boot 앱

실제 비즈니스 로직을 처리하는 앱이다.

역할:

- 인증
- 추천
- 검색
- 일정/기록/업로드 처리

## 왜 이 구조가 좋은가

이 구조는 public 운영형에 잘 맞는다.

이유:

1. Cloudflare가 바깥에서 1차 보호
2. Nginx가 Mac mini 안에서 2차 제어
3. Spring Boot는 실제 로직만 담당

즉, 앱이 모든 걸 직접 받지 않아도 된다.

## public 저장소와의 관계

public 저장소가 된다고 해서 Cloudflare나 Nginx 설정 자체를 모두 공개해야 하는 것은 아니다.

구분:

- public 저장소에 남겨도 되는 것
  - 샘플 Nginx 설정
  - 구조 설명 문서
  - 예시 cloudflared 구성

- public 저장소에 두면 안 되는 것
  - 실제 tunnel id
  - 실제 domain
  - 실제 origin 경로
  - 실제 인증 토큰

즉, 구조는 공개해도 되지만 실제 값은 공개하면 안 된다.

## 추천 운영 흐름

1. Cloudflare에서 도메인 관리
2. cloudflared가 Mac mini와 연결
3. cloudflared는 Nginx로 전달
4. Nginx는 Spring Boot로 프록시
5. Spring Boot는 127.0.0.1:8080에서만 listening

이 방식의 장점:

- Spring Boot 포트를 직접 외부에 열지 않아도 된다
- 앞단에서 제어가 쉽다
- Nginx에서 route 정책을 정교하게 넣을 수 있다

## 가장 추천하는 최종 형태

```text
Internet
  -> Cloudflare
  -> cloudflared tunnel
  -> Nginx on Mac mini
  -> Spring Boot app
```

## 이 구조에서 보안적으로 중요한 점

- Spring Boot는 외부에 직접 노출하지 않는 편이 좋다
- Nginx와 Spring Boot는 Mac mini 내부 통신으로 둔다
- Cloudflare에서 바깥쪽 보호
- Nginx에서 경로별 제한
- 앱에서 마지막 보호선

## 요약

- Cloudflare는 바깥 경계
- Nginx는 Mac mini 안쪽 경계
- Spring Boot는 실제 서비스
- public 운영형의 목표 구조로는 이 3단계 구성이 실용적이다
