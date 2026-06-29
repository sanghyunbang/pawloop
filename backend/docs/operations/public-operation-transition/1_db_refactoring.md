# 1. DB 리팩토링

- 작성 시각: 2026-03-18 00:54:24 +09:00
- 상태: 완료

## 목적

`docker-compose.yml`에 있던 평문 DB 비밀번호를 제거하고, public 저장소에 올릴 수 있는 형태로 바꾼다.

## 변경 내용

- `MYSQL_ROOT_PASSWORD` 평문 제거
- `MYSQL_PASSWORD` 평문 제거
- MySQL 관련 값은 `.env` 기반으로 주입되도록 변경
- healthcheck도 고정 비밀번호 대신 컨테이너 환경변수를 사용하도록 변경

## 실제 수정 파일

- [docker-compose.yml](/C:/Users/mm206/git_projects/heat_trip_backend/docker-compose.yml)
- [.env.example](/C:/Users/mm206/git_projects/heat_trip_backend/.env.example)
- [.gitignore](/C:/Users/mm206/git_projects/heat_trip_backend/.gitignore)
- [.dockerignore](/C:/Users/mm206/git_projects/heat_trip_backend/.dockerignore)

## 전환 결과

- 저장소에는 더 이상 DB 평문 비밀번호가 남지 않는다.
- 실제 실행은 `.env` 파일 또는 셸 환경변수 주입이 필요하다.

## 주의사항

- 배포 서버에는 반드시 `.env`를 따로 둬야 한다.
- `.env`는 저장소에 커밋하지 않는다.
