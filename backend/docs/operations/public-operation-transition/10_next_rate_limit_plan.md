# 10. 다음 단계 Rate Limit 계획

- 작성 시각: 2026-03-18 00:54:24 +09:00
- 상태: 계획

## 목적

앱 레벨 rate limit 다음 단계로, 앞단 rate limit까지 포함한 운영형 구조를 정리한다.

## 현재 상태

- 앱 내부 rate limit 있음
- gateway / Nginx / Cloudflare 레벨 rate limit 없음

## 추천 순서

1. 현재 앱 레벨 rate limit 유지
2. 운영 환경 앞단에 Nginx가 있다면 로그인/추천/업로드에 1차 제한 추가
3. 도메인과 엣지 계층을 정리할 때 Cloudflare rate limit 검토
4. 서버가 여러 대로 늘어나면 Redis 기반 분산 rate limit 고려

## 지금 당장 하지 않은 이유

- 현재 저장소에는 Nginx 설정 파일이나 Cloudflare 인프라 코드가 없다.
- 그래서 이번 단계에서는 앱 레벨 보호선과 문서화까지를 먼저 완료했다.

## 관련 문서

- [7_rate_limit.md](7_rate_limit.md)
- [9_gateway_rate_limit_guide.md](9_gateway_rate_limit_guide.md)
