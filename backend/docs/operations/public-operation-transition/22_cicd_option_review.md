# 22. CI/CD 및 설정 관리 선택지 검토

- 작성 시각: 2026-03-19
- 상태: 완료
- 목적: 현재 운영 환경에 맞는 CI/CD 및 설정 관리 방식을 선택하기 위해, 가능한 선택지와 장단점, 현재 추천안을 정리한다.

## 현재 전제

현재 확인된 운영 전제는 아래와 같다.

- 운영 서버는 Mac mini 1대
- backend 와 recommender 는 별도 저장소다
- 실제 운영은 Docker Compose 중심이다
- backend 는 `cloudflared -> localhost:8080 -> backend container` 구조다
- recommender 는 현재 같은 운영 서버에서 함께 실행 중이다
- public 저장소 전환이 현재 최우선이다
- 비용이 가장 중요하다

관련 실측 문서:

- [20_mac_mini_actual_state_2026_03_18.md](20_mac_mini_actual_state_2026_03_18.md)

## 문제 정의

지금 구조의 핵심 문제는 이것이다.

- 코드 배포는 self-hosted runner 로 자동화할 수 있다
- 하지만 `.env` 와 `application-private.properties` 는 사람이 직접 서버에 들어가 수정해야 한다

즉, 현재는 `코드 배포 자동화` 는 가능하지만, `운영 설정 변경 자동화` 는 부족하다.

원하는 상태는 아래와 같다.

```text
노트북에서 push
 -> GitHub Actions 실행
 -> 운영 서버에서 설정 주입
 -> backend 또는 recommender 자동 재배포
```

## 선택지

### 1. GitHub Actions Secrets + self-hosted runner

방식:

- GitHub Secrets 또는 GitHub Environment Secrets 에 운영값 저장
- self-hosted runner 가 배포 시 `.env` 와 `application-private.properties` 파일 생성
- 이후 `docker compose up -d --build` 실행

장점:

- 현재 구조에서 가장 변경이 적다
- 추가 인프라 비용이 거의 없다
- `push -> 자동 배포` 를 빠르게 만들 수 있다
- backend 와 recommender 가 separate repo 여도 동일한 운영 패턴을 적용할 수 있다

단점:

- GitHub 가 사실상 secret 저장소 역할까지 하게 된다
- secret 개수가 많아지면 GitHub UI 관리가 번거로울 수 있다
- 런타임 동적 조회가 아니라 배포 시 파일 생성 방식이다

적합도:

- 현재 환경에 가장 적합

### 2. AWS SSM Parameter Store Standard

방식:

- AWS SSM Parameter Store 에 설정값 저장
- 배포 시 runner 가 SSM 에서 조회해 파일을 생성하거나
- 앱이 시작 시 SSM 값을 읽는다

장점:

- GitHub 보다 secret/config 저장소 역할에 더 자연스럽다
- 환경별 path 체계를 만들기 쉽다
- 나중에 서비스가 늘어나도 확장성이 좋다
- Standard tier 는 비용 부담이 매우 낮다

단점:

- AWS 인증 체계를 추가로 관리해야 한다
- 현재 Mac mini 운영에 AWS CLI 또는 SDK 연결 설계가 필요하다
- 지금 단계에서는 GitHub Secrets 보다 설정 난이도가 높다

적합도:

- 다음 단계 후보로 좋다

### 3. Spring Cloud Config Server

방식:

- 별도 Config Server 를 띄운다
- 앱이 시작 시 Config Server 에서 설정을 읽는다

장점:

- 중앙 설정 관리 모델이 명확하다
- Spring Boot 와의 결합이 자연스럽다
- 환경별 config 구조를 일관되게 관리하기 좋다

단점:

- Config Server 자체를 별도로 운영해야 한다
- 지금의 단일 Mac mini 환경에서는 운영 복잡도 대비 이득이 작다
- recommender(Python) 와는 별도 설계가 필요하다

적합도:

- 현재 환경에는 과한 편

### 4. Vault 또는 별도 secret server

방식:

- Vault 같은 전용 secret 시스템 운영
- 앱 또는 배포 스크립트가 secret 을 조회

장점:

- 보안/권한 모델이 가장 강력하다
- 확장성은 좋다

단점:

- 운영 난이도가 가장 높다
- 현재 규모에서는 비용보다 복잡도가 더 큰 문제다

적합도:

- 현재 환경에는 비추천

## 왜 지금은 GitHub Actions Secrets 를 우선 선택하는가

현재 구조에서는 `배포 기반은 이미 있고, 설정 주입 자동화만 비어 있다`.

실제 상태:

- self-hosted runner 가 이미 있다
- backend 배포 workflow 도 이미 있다
- Docker Compose 기반 운영도 이미 굴러가고 있다

즉, 가장 작은 변경으로 완성도를 높이려면:

1. GitHub Actions 에 운영 secret 저장
2. runner 가 배포 시 파일 생성
3. compose 재기동

이 3단계면 된다.

이 접근이 맞는 이유:

- 비용이 가장 낮다
- 지금 당장 구현이 쉽다
- public 저장소 전환 목표와 충돌하지 않는다
- backend 와 recommender 가 separate repo 여도 같은 배포 철학으로 갈 수 있다

## 왜 AWS SSM 을 당장 1순위로 선택하지 않았는가

SSM 은 좋은 선택지지만, 지금 당장은 아래 이유로 한 단계 뒤가 적절하다.

- 운영 규모가 아직 단일 서버 중심이다
- GitHub Secrets 만으로도 충분히 커버 가능하다
- AWS 인증/권한/조회 경로 설계를 추가하면 초기 복잡도가 커진다

즉:

- 장기 확장성만 보면 SSM 이 더 좋을 수 있다
- 현재 구현 속도와 단순성까지 보면 GitHub Secrets 가 더 적합하다

## 향후 확장성 관점

현재 추천안은 `영구 최종안` 이 아니라 `현재 최적안` 이다.

확장 신호가 생기면 SSM 으로 넘기는 것이 맞다.

예:

- prod 외에 staging 이 추가됨
- backend, recommender 외에 서비스가 더 생김
- GitHub Secrets 개수가 너무 많아짐
- secret rotation 이 자주 필요해짐
- 운영자가 GitHub UI 대신 별도 secret 저장소를 원함

## 추천 결론

지금은 아래 조합을 추천한다.

1. backend repo: GitHub Actions Secrets + self-hosted runner
2. recommender repo: GitHub Actions Secrets + 같은 self-hosted runner 재사용 가능
3. 운영 secret 은 배포 시 파일 생성 방식으로 주입
4. 나중에 필요해지면 AWS SSM Parameter Store Standard 로 이전

## 관련 문서

- [23_backend_and_recommender_cicd_design.md](23_backend_and_recommender_cicd_design.md)
- [21_secret_separation_and_recommender_hardening.md](21_secret_separation_and_recommender_hardening.md)
- [3_deployment_publicization.md](3_deployment_publicization.md)
