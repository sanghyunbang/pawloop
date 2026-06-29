# 14. Cloudflare Tunnel + Nginx 실전 가이드

- 작성 시각: 2026-03-18 00:54:24 +09:00
- 상태: 완료

## 목적

Mac mini에서 Cloudflare Tunnel과 Nginx를 함께 쓰는 실전적인 흐름을 정리한다.

이 문서는 "이해용"이 아니라 "구성 순서"에 더 가깝다.

주의:

- 2026-03-18 기준 현재 실운영은 아직 이 구조가 아니다.
- 현재는 `cloudflared -> localhost:8080 -> backend container` 구조다.
- 이 문서는 Nginx 도입 시 사용할 후속 가이드다.

관련 실측 문서:

- [20_mac_mini_actual_state_2026_03_18.md](20_mac_mini_actual_state_2026_03_18.md)

## 목표 구조

```text
사용자
  -> api.example.com
  -> Cloudflare
  -> cloudflared tunnel
  -> Nginx (Mac mini)
  -> Spring Boot :8080
```

## 왜 이 구조를 추천하나

- Spring Boot를 직접 외부에 노출하지 않아도 된다
- public 운영에 필요한 rate limit, header, body size 제한을 Nginx에서 처리할 수 있다
- 나중에 앱이 여러 개가 되어도 Nginx에서 분기하기 쉽다

## 운영 시 각 포트의 역할

예시:

- Spring Boot: `127.0.0.1:8080`
- Nginx: `127.0.0.1:80` 또는 `127.0.0.1:8081`
- cloudflared: Cloudflare와 터널 연결, 로컬 Nginx로 전달

핵심:

- Spring Boot는 되도록 외부 공개 포트가 아니라 로컬 바인딩
- Cloudflare -> cloudflared -> Nginx -> Spring Boot 흐름 유지

## 권장 순서

### 1. Spring Boot를 로컬 포트에서만 띄움

예:

- `127.0.0.1:8080`

의미:

- 외부 인터넷이 직접 Spring Boot로 들어오지 않게 함

### 2. Nginx를 Spring Boot 앞에 둠

Nginx 역할:

- reverse proxy
- rate limit
- upload size 제한
- timeout 제어

### 3. cloudflared는 Nginx로 연결

즉, cloudflared가 직접 Spring Boot를 보지 않고, Nginx를 보게 한다.

이유:

- 앞단 제어를 Nginx에 모을 수 있다
- 나중에 앱이 늘어도 구조가 덜 흔들린다

## 실제 구성에서 필요한 파일 종류

보통 아래가 필요하다.

1. Nginx 설정 파일
2. cloudflared 설정 파일
3. 앱 `.env`
4. `application-private.properties`

## 지금 저장소에 추가한 샘플

- Nginx 샘플: [nginx-rate-limit-example.conf](nginx-rate-limit-example.conf)
- cloudflared 샘플: [cloudflared-config-example.yml](cloudflared-config-example.yml)

## 실전 구성 순서

### 1. 앱이 먼저 정상 동작하는지 확인

- Mac mini에서 앱 단독 실행
- `127.0.0.1:8080` 기준 health check

### 2. Nginx를 붙여서 프록시 확인

- `http://127.0.0.1/` 또는 지정한 로컬 Nginx 포트로 호출
- Nginx가 Spring Boot로 잘 넘기는지 확인

### 3. cloudflared를 붙임

- Cloudflare Tunnel이 Nginx를 origin으로 바라보게 설정
- 외부 도메인으로 들어오는 요청이 Nginx까지 오는지 확인

### 4. rate limit 점검

- 로그인
- 추천
- 업로드
- 검색

순으로 너무 빡빡하지 않은지 확인

## 운영에서 특히 중요한 포인트

### 1. real IP 처리

Cloudflare 뒤에 있으면 앱이 보는 IP와 실제 사용자 IP가 달라질 수 있다.

그래서:

- Cloudflare -> cloudflared -> Nginx
- `X-Forwarded-For`

전달 구조를 맞춰야 한다.

지금 앱 rate limit은 기본적으로 `X-Forwarded-For`를 보게 해두었다.

### 2. 업로드 크기 제한

업로드 API가 있으므로 Nginx `client_max_body_size`를 적절히 잡아야 한다.

### 3. timeout

추천 API나 외부 연동 API가 늦을 수 있으므로 Nginx timeout도 너무 짧으면 안 된다.

### 4. Swagger 공개 여부

운영에서는 기본 비공개가 안전하다.

지금 앱은 `APP_SECURITY_DOCS_PUBLIC=false` 기본값이다.

## 추천 운영 원칙

- Spring Boot 직접 공개 금지
- Nginx 앞단 사용
- Cloudflare Tunnel은 Nginx를 origin으로 사용
- 실제 domain, tunnel id, token은 public 저장소에 두지 않음

## 요약

- Cloudflare Tunnel과 Nginx는 같이 쓸 수 있다
- 실전에서는 cloudflared -> Nginx -> Spring Boot 구조가 관리하기 좋다
- 지금 public 운영형 방향과도 잘 맞는다
