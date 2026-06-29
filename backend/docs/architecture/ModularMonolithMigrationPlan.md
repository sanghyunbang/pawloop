# 모듈러 모놀리식 전환 계획

## 목적

현재 백엔드를 새 저장소로 옮기면서, 처음부터 마이크로서비스로 분리하지 않고 모듈러 모놀리식 구조로 정리한다.

## 왜 먼저 모듈러 모놀리식인가

- 현재 코드가 이미 기능별 패키지로 어느 정도 나뉘어 있다.
- 배포와 디버깅이 단순하다.
- 분산 시스템 복잡도 없이 경계를 먼저 안정화할 수 있다.
- CI/CD를 훨씬 쉽게 정착시킬 수 있다.

## 추천 모듈 경계

우선 비즈니스 모듈을 다음처럼 잡는다.

- `auth`
- `user`
- `tour`
- `explore`
- `schedule`
- `bookmark`
- `curation`
- `media`
- `observability`

보조 모듈:

- `bootstrap`
- `common`
- `config`

## 디렉터리 방향

예시 패키지 구조:

```text
com.heattrip
  app
  common
  auth
  user
  tour
  explore
  schedule
  bookmark
  curation
  media
  observability
```

## 경계 규칙

- 한 모듈이 다른 모듈의 repository를 직접 호출하지 않는다.
- 모듈 간 접근은 service interface, facade, port를 통해서만 한다.
- 공통 코드는 최소화한다.
- 서로 무관한 모듈끼리 DTO를 직접 공유하지 않는다.
- controller는 얇게 두고, 핵심 비즈니스 규칙은 각 모듈 service에 둔다.

## 실제 이전 순서

1. 현재 코드베이스를 새 private 저장소로 복사한다.
2. 패키지 이동 전에 우선 실행 가능 상태를 유지한다.
3. 목표 모듈 경계를 문서로 정의한다.
4. 패키지를 단계적으로 이동한다.
5. 모듈 간 직접 repository 접근을 모듈 API 호출로 바꾼다.
6. 모듈 경계 지점에 통합 테스트를 추가한다.
7. 경계가 안정화된 뒤에만 필요하면 서비스 분리를 검토한다.

## 먼저 손대기 좋은 영역

비교적 낮은 위험:

- `observability`
- `media`
- `bookmark`

결합도가 높은 영역은 나중:

- `user`, `auth`
- `tour`, `explore`, `curation`
- `schedule`

## 초기에 반드시 둘 가드레일

- 패키지 네이밍 규칙
- 의존 방향 문서
- 모듈 공개 API 테스트
- 필요하면 아키텍처 테스트

## 새 저장소의 산출물

- 정리된 모듈 구조
- 로컬 실행 방법이 적힌 `README`
- `.env.example` 또는 예시 private 설정 파일
- build/test가 도는 CI 파이프라인
- 소스와 운영을 분리한 배포 파이프라인
