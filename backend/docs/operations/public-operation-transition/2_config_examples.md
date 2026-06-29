# 2. 예시 설정 파일 추가

- 작성 시각: 2026-03-18 00:54:24 +09:00
- 상태: 완료

## 목적

public 저장소에서도 실행 구조를 이해할 수 있도록 예시 설정 파일을 제공하되, 실제 secret은 커밋하지 않는다.

## 추가한 파일

- [.env.example](/C:/Users/mm206/git_projects/heat_trip_backend/.env.example)
- [application-private.properties.example](/C:/Users/mm206/git_projects/heat_trip_backend/application-private.properties.example)

## 포함한 항목

- MySQL 환경변수
- JWT secret 예시
- Google/Kakao/Naver OAuth2 예시 키
- Kakao REST key 예시
- Tour API key 예시
- AWS / S3 예시 설정
- LLM recommender base URL 예시
- Slack / OpenAI 예시 설정
- 공개 운영용 에러/로그/CORS 기본 환경변수 예시

## 실제 수정 파일

- [src/main/resources/application.properties](/C:/Users/mm206/git_projects/heat_trip_backend/src/main/resources/application.properties)
- [.env.example](/C:/Users/mm206/git_projects/heat_trip_backend/.env.example)
- [application-private.properties.example](/C:/Users/mm206/git_projects/heat_trip_backend/application-private.properties.example)

## 전환 결과

- public 저장소 사용자도 필요한 설정 키 구조를 알 수 있다.
- 실제 값은 전부 외부 파일 또는 환경변수에서만 넣도록 강제하는 방향이 됐다.

## 2026-03-19 추가 반영

- `.env.example` 에 `LLM_RECOMMENDER_BASE_URL` 예시를 추가했다.
- recommender 기본 연결은 Docker 내부 주소 `http://recommender:8000` 를 우선으로 설명하도록 정리했다.
- 운영 hardening 절차는 [21_secret_separation_and_recommender_hardening.md](21_secret_separation_and_recommender_hardening.md) 에 따로 정리했다.
