# 3. 배포 workflow 공개용 정리

- 작성 시각: 2026-03-18 00:54:24 +09:00
- 상태: 완료

## 목적

기존 배포 workflow에 있던 self-hosted runner 절대경로와 과도한 운영 단서를 줄여서, public 저장소에 남길 수 있는 수준으로 정리한다.

## 변경 내용

- workflow 이름을 일반화
- 절대경로 checkout 제거
- `github.workspace` 기준 실행으로 변경
- `.env`, `config` 디렉터리 존재 여부를 사전 검사하도록 변경
- self-hosted label을 단순화
- 동시 배포 방지를 위해 concurrency 추가

## 실제 수정 파일

- [.github/workflows/deploy-backend.yml](/C:/Users/mm206/git_projects/heat_trip_backend/.github/workflows/deploy-backend.yml)

## 남은 판단 포인트

- 이 workflow 자체를 public 저장소에 계속 둘지
- 아니면 운영 전용 workflow만 별도 private 저장소로 분리할지

현재 상태에서는 절대경로 노출은 제거했지만, 운영 방식 자체를 더 숨기고 싶다면 private 분리가 더 안전하다.
