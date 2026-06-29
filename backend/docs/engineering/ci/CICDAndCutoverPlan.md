챙# CI/CD 및 무중단 이전 계획

## 목적

새 저장소를 더 안전한 비밀값 관리와 최소 다운타임 방식으로 운영 환경에 배포한다.

## 현재 방식의 한계

현재 `.github/workflows/deploy-backend.yml`은 기존 컨테이너를 먼저 중지하고 삭제한 뒤 다시 올리는 구조이므로, 배포 시 다운타임이 발생한다.

## 목표 구조

권장 방향:

- GitHub Actions 기반 CI
- 컨테이너 이미지 빌드 및 레지스트리 푸시
- 리버스 프록시 뒤에서 애플리케이션 배포
- blue-green 또는 rolling 방식 전환

## CI 파이프라인

Pull Request 시:

1. checkout
2. build
3. test 실행
4. secret scan 실행
5. dependency scan 실행

`main` 머지 시:

1. 이미지 빌드
2. 커밋 SHA 기준 태그 부여
3. 레지스트리 푸시
4. 배포 트리거

## secret scan

다음 중 하나를 사용한다.

- `gitleaks`
- `trufflehog`
- `git-secrets`

이 검사는 모든 PR과 보호 브랜치에서 실행하는 것이 좋다.

## 이미지 레지스트리

다음 중 하나를 사용할 수 있다.

- GitHub Container Registry
- Amazon ECR
- Docker Hub

권장 태그 전략:

- `latest`
- 전체 commit SHA
- 필요하면 `prod` 같은 환경 태그

## 배포 구성

권장 구성 요소:

- 리버스 프록시: `nginx`, `traefik`, 또는 클라우드 로드밸런서
- 앱 컨테이너: `blue`, `green`
- 데이터베이스: 별도 호스트 또는 관리형 DB
- 저장소 밖에서 주입되는 config 파일 또는 secret

## Blue-Green 전환 절차

1. 현재 운영 트래픽은 `blue`가 처리한다.
2. 새 버전은 다른 포트 또는 다른 컨테이너 이름으로 `green`에 띄운다.
3. `green`에 대해 health check를 수행한다.
4. 리버스 프록시 upstream을 `blue`에서 `green`으로 바꾼다.
5. 로그와 메트릭을 관찰한다.
6. 안정화가 끝난 뒤에만 이전 `blue`를 내린다.

장점:

- 거의 무중단에 가깝다.
- 롤백이 빠르다.
- 실제 운영 검증이 더 안전하다.

## 데이터베이스 마이그레이션 전략

같은 DB를 계속 사용할 경우:

- 스키마 변경은 가능한 한 하위 호환되게 만든다.
- 구버전과 신버전이 잠시 함께 돌아가도 버티는 형태로 변경한다.
- 전환 시점에 파괴적 마이그레이션은 피한다.

새 DB로 옮길 경우:

- 원본 데이터를 스냅샷 또는 복제한다.
- 마이그레이션 스크립트를 실행한다.
- row 수와 핵심 비즈니스 흐름을 검증한다.
- 데이터 검증 완료 후 트래픽을 전환한다.

## 런타임 비밀값 처리

`docker-compose.yml`에 비밀값을 직접 넣지 않는다.

대신 다음 중 하나를 사용한다.

- 호스트 환경변수
- 마운트된 private properties 파일
- Docker secrets
- 시작 시점에 SSM 또는 secret manager에서 조회

## 저장소 분리 권장안

Public 저장소:

- 애플리케이션 소스
- 문서
- 예시 설정 파일

Private 운영 저장소:

- 배포 workflow
- 인프라 매니페스트
- 환경별 compose 파일
- 운영 런북

## 최소 실행 순서

1. 현재 비밀값을 전부 회전한다.
2. 새 private 마이그레이션 저장소를 만든다.
3. 모듈 경계를 정리해 모듈러 모놀리식 구조를 만든다.
4. build/test 중심 CI를 붙인다.
5. 이미지 빌드와 레지스트리 푸시를 추가한다.
6. 리버스 프록시와 두 번째 앱 슬롯을 준비한다.
7. 새 버전을 병행 배포한다.
8. 트래픽을 새 환경으로 전환한다.
9. 모니터링 후 필요 시 즉시 롤백한다.
10. 운영 안정화 후 비밀값이 제거된 public 저장소를 공개한다.

## 지금 바로 해야 할 일

- compose에서 평문 DB 비밀번호를 제거한다.
- `.env.example` 또는 예시 private 설정 파일을 추가한다.
- CI에 secret scan을 붙인다.
- 배포 workflow를 stop-first 방식에서 병행 배포 방식으로 바꾼다.
