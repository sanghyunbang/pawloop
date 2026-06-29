# 11. Nginx Rate Limit 예시

- 작성 시각: 2026-03-18 00:54:24 +09:00
- 상태: 완료

## 이 문서의 목적

앱 레벨 rate limit 다음 단계로, Nginx 앞단에서 어떻게 1차 제한을 둘 수 있는지 예시를 남긴다.

이 문서는 실제 운영 서버에 바로 붙이는 확정본이 아니라,  
현재 API 구조에 맞춰 어떤 식으로 잡는지 이해할 수 있게 만든 샘플이다.

## 왜 Nginx 예시가 필요한가

앱 안에서 막는 것만으로는 부족하다.

이유:

- 앱까지 요청이 이미 들어온 뒤라 비용이 더 든다.
- 추천 API, 업로드 API는 앱이 받기 전에 먼저 막는 게 더 낫다.
- 로그인 공격은 앞단에서 먼저 걸러야 효과가 좋다.

즉, Nginx는 "앱 앞에서 1차 방어"를 하는 도구다.

## 이번에 추가한 샘플 파일

- [nginx-rate-limit-example.conf](nginx-rate-limit-example.conf)

## 샘플이 다루는 경로

- `/auth/login`
- `/api/curation/`
- `/api/explore/places/search`
- `/media`
- `/journeys/v2/entries/with-images`

## 핵심 개념

### `limit_req_zone`

IP별 카운터를 저장하는 메모리 영역을 만든다.

예:

- 로그인용 zone
- 추천용 zone
- 검색용 zone
- 업로드용 zone

### `limit_req`

실제 location에 제한을 건다.

예:

- 로그인은 더 엄격하게
- 검색은 조금 넉넉하게
- 업로드는 burst를 작게

## 현재 샘플의 의도

- 로그인은 가장 엄격
- 추천 API는 비용이 크므로 강하게 제한
- 검색은 상대적으로 넓게 허용
- 업로드는 크기 제한과 요청 수 제한을 함께 고려

## 실제 적용할 때 주의할 점

1. 지금 값은 샘플이다.
2. 모바일 앱 호출 패턴을 보고 조정해야 한다.
3. 프론트가 동시에 여러 요청을 보내면 너무 빡빡한 값은 오탐이 생긴다.
4. 프록시 뒤에 프록시가 또 있으면 real IP 설정이 맞아야 한다.

## 이 샘플을 바로 쓰기 전에 확인할 것

- 실제 도메인
- 실제 upstream 주소
- TLS 종료 위치
- `X-Forwarded-For` 전달 구조
- 프론트 호출 빈도

## 요약

- 앱 레벨 rate limit은 최소 보호선
- Nginx rate limit은 앞단 1차 보호선
- public 운영형 구조라면 가능한 빨리 앞단 rate limit을 붙이는 편이 좋다
