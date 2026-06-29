# 16. 실사용 Nginx 설정 템플릿

- 작성 시각: 2026-03-18 00:54:24 +09:00
- 상태: 완료

## 이 문서의 목적

샘플 수준이 아니라, 운영 컴퓨터에서 실제 값만 채우면 바로 적용 방향을 잡을 수 있는 Nginx 템플릿을 제공한다.

## 중요한 전제

이 문서와 템플릿은 `실제 값 확정 전` 상태다.

즉, 지금 이 컴퓨터에서는 아래를 확정할 수 없다.

- 실제 도메인
- 실제 cloudflared가 붙는 로컬 포트
- 실제 Nginx 설치 경로
- 실제 TLS 종료 위치
- 실제 Spring Boot listen 포트

그래서 이번 템플릿은 `운영 컴퓨터에서 값만 채우면 되는 형태`로 만든다.

추가 전제:

- 2026-03-18 기준 현재 운영에는 Nginx가 없다.
- 따라서 이 템플릿은 현재 적용 문서가 아니라 `Nginx 도입 시 사용할 TODO 템플릿` 이다.
- 현재 실운영 구조는 [20_mac_mini_actual_state_2026_03_18.md](20_mac_mini_actual_state_2026_03_18.md) 를 기준으로 본다.

## 추가한 템플릿 파일

- [nginx-production-template.conf](nginx-production-template.conf)

## 이 템플릿의 의도

- Spring Boot는 외부 공개하지 않고 로컬 listen
- Nginx가 reverse proxy 담당
- 로그인/추천/검색/업로드에 앞단 rate limit
- body size, timeout, forwarding header를 명시

## 운영 컴퓨터에서 채워야 할 값

1. `server_name`
2. `upstream` 포트
3. 실제 listen 포트
4. 로그 경로
5. 필요 시 HTTPS / 인증서 처리 위치

## 적용 순서

1. 운영 컴퓨터에서 실제 값 확인
2. 템플릿 복사
3. placeholder 치환
4. `nginx -t`로 문법 검사
5. reload

## 참고 문서

- [13_cloudflare_nginx_architecture.md](13_cloudflare_nginx_architecture.md)
- [14_cloudflare_tunnel_and_nginx_practical_guide.md](14_cloudflare_tunnel_and_nginx_practical_guide.md)
- [11_nginx_rate_limit_example.md](11_nginx_rate_limit_example.md)
