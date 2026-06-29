# Heat Trip Backend 리팩토링 방향 정리

## 목적

현재 `heat_trip_backend`는 기능별 패키징은 어느 정도 되어 있지만, 단일 모듈 기반의 모놀리식 구조다.  
이 문서는 아래 3가지를 동시에 만족하는 방향으로 리팩토링 전략을 정리한다.

- Kotlin 관련 포트폴리오로 활용할 수 있을 것
- 코루틴을 무리 없이 도입할 수 있을 것
- 향후 MSA 전환을 고려한 modular monolith 구조를 먼저 만들 것

핵심 원칙은 다음이다.

- Kotlin 문법 전환보다 먼저 모듈 경계를 세운다
- 코루틴은 "전면 reactive 전환"이 아니라 외부 I/O와 애플리케이션 서비스부터 선택적으로 도입한다
- MSA는 바로 가지 않고, 먼저 모듈러 모놀리식으로 경계를 검증한다

---

## 현재 구조 진단

### 1. 현재 상태 요약

- `src/main/java` 아래에 모든 기능이 단일 모듈로 들어가 있다
- 패키지는 `user`, `explore`, `tour`, `curation`, `schedules`, `bookmark`, `feedback` 등으로 나뉘어 있다
- 하지만 웹, 서비스, 리포지토리, 외부 연동, 엔티티가 같은 빌드 모듈 안에 섞여 있다

즉, "기능별 패키징"은 되어 있지만 "아키텍처 경계"는 아직 약하다.

### 2. 긍정적인 부분

`explore` 쪽에는 이미 port-adapter 형태의 흔적이 있다.

- `explore.port.ExploreSearchPort`
- `explore.adapter.jpa.ExploreSearchJpaAdapter`
- `explore.service.ExploreService`

이 구조는 이후 전체 모듈 구조를 설계할 때 좋은 기준점이 된다.

### 3. 현재 문제점

#### 도메인 간 직접 결합

- `schedules`가 `user` 엔티티와 리포지토리를 직접 참조한다
- `tour`가 `curation` 엔티티와 리포지토리를 직접 참조한다
- `curation`이 외부 LLM 클라이언트를 직접 의존한다

이런 구조는 모듈 분리나 MSA 전환 시 결합도를 크게 높인다.

#### 블로킹 I/O와 혼합된 기술 스택

- `spring-boot-starter-web`와 `spring-boot-starter-webflux`가 함께 있다
- 외부 API 클라이언트는 `WebClient`를 사용하지만 실제로는 `.block()`으로 동작한다
- DB는 JPA 기반이라 전체 애플리케이션은 기본적으로 blocking MVC 구조다

즉, 지금은 "reactive 일부 사용"이지 "reactive architecture"는 아니다.

#### Kotlin 전환 준비 부족

- 현재 Gradle 설정은 Java 전용이다
- Kotlin plugin, Kotlin stdlib, Jackson Kotlin 모듈, Coroutines 관련 설정이 없다
- Lombok 의존도가 여전히 높다

---

## Kotlin 전환 전략

## 결론

Kotlin 전환은 한 번에 전체 코드를 바꾸기보다, 아래 순서로 점진 전환하는 것이 가장 안전하다.

1. 신규 코드부터 Kotlin으로 작성
2. DTO, command, query, use case 계층부터 Kotlin으로 전환
3. 외부 연동 서비스와 application service를 Kotlin으로 전환
4. 마지막에 JPA 엔티티 전환 여부를 판단

### 왜 엔티티는 마지막인가

JPA + Kotlin 조합은 주의할 점이 많다.

- 기본 생성자 문제
- `open` class 문제
- 프록시와 지연 로딩 문제
- equals/hashCode/data class 사용 위험

따라서 포트폴리오 목적이라도 엔티티를 먼저 Kotlin으로 옮기기보다, 아래 영역을 먼저 Kotlin화하는 편이 낫다.

- request/response DTO
- port interface
- application service
- external client
- mapper/utility

### 포트폴리오 관점에서 보여주기 좋은 Kotlin 요소

- `data class`
- `sealed interface` / `sealed class`
- null-safety 기반 API 설계
- 확장 함수
- `suspend` 함수
- Coroutines 기반 동시성 처리
- Java/Lombok 코드를 Kotlin스럽게 정리한 흔적

### 추천 전환 우선순위

#### 1순위

- `llm`
- `tour.service`
- `explore`의 port/usecase 계층
- 공통 DTO/응답 모델

#### 2순위

- `curation`
- `user` 서비스 계층
- `bookmark`

#### 3순위

- JPA entity
- Spring Security 관련 구성
- 레거시 컨트롤러

---

## 코루틴 도입 전략

## 결론

현재 구조에서는 "전면 코루틴 + 전면 non-blocking"보다 "선택적 코루틴 도입"이 맞다.

### 왜 전면 reactive 전환이 아닌가

현재 핵심 persistence는 JPA 기반이다.

- JPA는 blocking
- DB access가 blocking이면 전체 요청 흐름을 완전한 non-blocking으로 만들 수 없다
- 따라서 지금 단계에서 WebFlux + R2DBC까지 한 번에 가는 것은 비용이 크고 리스크가 높다

### 코루틴을 도입하기 좋은 지점

외부 I/O가 있는 부분부터 적용하는 것이 가장 효과적이다.

#### 우선 후보

- LLM 호출
- Tour API 호출
- Kakao API 호출
- S3 연동

이 부분은 현재 `WebClient`를 쓰면서도 `.block()`을 사용하고 있으므로, Kotlin 전환 시 `suspend` 기반으로 바꾸기 좋다.

### 권장 방향

- 서버는 우선 Spring MVC 유지
- 외부 연동 client는 Kotlin `suspend` 기반으로 전환
- application service에서 `coroutineScope`, `async` 등을 사용해 병렬화
- DB는 일단 JPA 유지

### 기대 효과

- 외부 API 여러 개를 동시에 호출하는 코드가 간결해진다
- callback/reactor 체인보다 읽기 쉬운 코드가 된다
- Kotlin 포트폴리오 관점에서 코루틴 활용 경험을 보여주기 좋다

### 주의점

- JPA를 사용하는 서비스 메서드를 무리하게 suspend로 바꾼다고 해서 자동으로 성능이 좋아지지는 않는다
- DB가 blocking이면 코루틴의 핵심 이점은 "동시성 구조화" 쪽에 있다
- 따라서 성능 개선보다 "읽기 좋은 비동기 orchestration"에 초점을 두는 것이 맞다

---

## Modular Monolith 전환 전략

## 결론

MSA를 바로 시작하지 말고, 먼저 modular monolith로 전환해야 한다.

이 단계의 목적은 다음이다.

- 도메인 경계를 코드와 빌드 레벨에서 강제
- 모듈 간 직접 참조 제거
- 향후 서비스 분리 시 충격 최소화

### 추천 모듈 구조

```text
root
├─ app
├─ common
├─ interfaces-api
├─ domain-user
├─ domain-schedule
├─ domain-explore
├─ domain-curation
├─ domain-tour
├─ infra-persistence
└─ infra-external
```

### 각 모듈 역할

#### `app`

- Spring Boot main application
- 모듈 조립
- security/config/bootstrapping

#### `common`

- 공통 예외
- 공통 응답
- 공통 유틸
- observability 공통 요소

#### `interfaces-api`

- controller
- request/response mapping
- API layer

#### `domain-*`

- use case
- domain service
- port interface
- domain model

주의할 점은 `domain-*` 모듈이 아래 기술을 직접 알지 않게 하는 것이다.

- JPA
- WebClient
- 외부 SDK
- Spring MVC

#### `infra-persistence`

- JPA entity
- Spring Data Repository
- QueryDSL/native query/JPA adapter
- port 구현체

#### `infra-external`

- LLM client
- Kakao client
- Tour API client
- S3 adapter

---

## MSA 전환까지 고려한 도메인 경계

향후 분리 가능성이 높은 bounded context는 다음과 같다.

### 1. User/Auth

- 회원
- 인증/인가
- OAuth
- JWT

### 2. Schedule

- 일정
- 여정

### 3. Explore / Place Catalog

- 장소 조회
- 검색
- 태그/특성 조회

### 4. Recommendation / Curation

- 감정 기반 추천
- 점수 계산
- LLM orchestration

### 5. Media

- 이미지 업로드
- S3
- 미디어 메타데이터

### 6. Integration / Sync

- Tour API 수집
- Kakao backfill
- 배치/동기화 작업

### 먼저 분리하기 좋은 영역

- `media`
- `recommendation`
- `tour import / sync`

이유는 다음과 같다.

- 외부 의존성이 명확하다
- 독립 실행이나 배치 분리가 비교적 쉽다
- 다른 핵심 도메인에 비해 트랜잭션 결합이 약하다

### 나중에 분리해야 하는 영역

- `schedule`
- `user`

이유는 현재 엔티티와 인증 흐름이 많이 얽혀 있어 먼저 내부 경계 정리가 필요하기 때문이다.

---

## 현재 코드 기준으로 우선 정리해야 할 결합

### 1. `schedules -> user` 직접 의존 제거

현재 일정 도메인이 사용자 엔티티와 리포지토리를 직접 참조한다.  
이 구조는 `domain-schedule`을 독립 모듈로 만들 때 바로 걸림돌이 된다.

개선 방향:

- `UserReaderPort`
- `AuthenticatedUserPort`
- `ScheduleOwnerResolver`

같은 형태로 추상화하고, 구현은 infra 쪽으로 내린다.

### 2. `tour -> curation` 직접 의존 제거

현재 `tour`가 `curation` 엔티티와 리포지토리를 직접 사용하고 있다.  
이는 데이터 소유권이 불명확하다는 신호다.

개선 방향:

- `PlaceTrait`의 소유 모듈을 명확히 결정
- 다른 모듈은 직접 엔티티 접근 대신 port로 조회
- snapshot 생성 로직은 orchestration 계층으로 이동 검토

### 3. `curation -> llm client` 직접 의존 제거

현재 추천 서비스가 외부 LLM 클라이언트를 직접 호출한다.

개선 방향:

- `RecommendationPort`
- `EmotionInferencePort`

형태로 추상화

이렇게 하면 나중에 다음 변경이 쉬워진다.

- FastAPI -> 다른 서비스 교체
- 외부 API -> 내부 추천 서비스 전환
- 동기 호출 -> 비동기 메시징 전환

---

## 실제 리팩토링 순서 제안

## Phase 1. 멀티모듈 골격 만들기

목표:

- 빌드 단위 분리
- 의존성 방향 정리

작업:

- `settings.gradle`에 모듈 추가
- root gradle 공통 설정 추출
- `app`, `common`, `interfaces-api`, `domain-*`, `infra-*` 생성

이 단계에서는 기능 이동을 많이 하지 말고, 구조만 만든다.

## Phase 2. `explore`를 샘플 모듈로 정리

목표:

- port-adapter 패턴을 실제 기준 모듈로 완성

작업:

- `ExploreService`를 use case 중심으로 정리
- `ExploreSearchPort` 유지
- JPA adapter는 `infra-persistence`로 이동
- controller는 `interfaces-api`로 이동

이 단계가 성공하면 나머지 도메인에 같은 패턴을 반복하기 쉬워진다.

## Phase 3. 외부 클라이언트 Kotlin + Coroutine 전환

목표:

- 포트폴리오 포인트 확보
- 외부 I/O 구조 개선

우선 대상:

- `RecommenderClient`
- `TourApiClient`
- 필요 시 `KakaoLocalClient`

작업:

- Kotlin 파일로 전환
- `suspend` 함수화
- `.block()` 제거
- timeout/retry 정책 정리

## Phase 4. 추천/수집 계층의 orchestration 정리

목표:

- 비즈니스 규칙과 외부 연동 분리

작업:

- `curation`에 `RecommendationPort` 도입
- `tour import`와 `trait snapshot`을 별도 application service로 정리
- 외부 의존성은 infra로 이동

## Phase 5. `schedule`, `user` 경계 정리

목표:

- 강한 결합 제거
- 추후 서비스 분리 기반 확보

작업:

- `schedule`에서 `user repository` 직접 접근 제거
- 인증 사용자 조회 책임 분리
- 엔티티 직접 참조 대신 식별자 또는 port 기반 조회로 전환

## Phase 6. DTO / UseCase 계층 Kotlin 확대

목표:

- Kotlin 비중 확대
- Lombok 축소

작업:

- request/response DTO를 Kotlin data class로 전환
- 공통 응답/예외 모델 Kotlin화
- use case/application service Kotlin화

## Phase 7. JPA 엔티티 전환 여부 최종 판단

목표:

- 비용 대비 효과 검토

판단 기준:

- 엔티티를 Kotlin으로 바꿨을 때 유지보수 이점이 큰가
- JPA 프록시/지연 로딩 문제를 관리할 수 있는가
- 포트폴리오 관점에서 필요한가

개인적으로는 엔티티는 반드시 Kotlin으로 바꾸지 않아도 된다.  
오히려 application/service/client 계층이 Kotlin스럽게 잘 설계되어 있으면 더 설득력 있다.

---

## 포트폴리오 관점에서 강조할 만한 메시지

이 프로젝트를 Kotlin 포트폴리오로 가져갈 때는 단순히 "Java를 Kotlin으로 바꿨다"보다 아래 메시지가 더 강하다.

### 추천 메시지

- Java Spring monolith를 Kotlin 기반 modular monolith로 재구성
- JPA 중심 구조를 유지하면서 외부 I/O 영역에 coroutine을 선택적으로 적용
- port-adapter 구조를 도입해 향후 MSA 분리 가능한 경계를 선제적으로 설계
- 도메인 간 직접 참조를 줄이고 애플리케이션 계층 중심으로 orchestration 재정리

### 면접/포트폴리오에서 어필 포인트

- 왜 전면 reactive 전환이 아니라 선택적 coroutine 전략을 택했는가
- 왜 modular monolith를 먼저 만든 뒤 MSA를 고려했는가
- 어떤 의존성 방향을 기준으로 모듈을 설계했는가
- 어떤 모듈이 먼저 분리 가능한지, 왜 그런지 설명할 수 있는가

---

## 최종 제안

현재 프로젝트에 가장 적합한 방향은 다음 한 줄로 정리할 수 있다.

> 먼저 modular monolith로 경계를 세우고, 그 위에서 외부 연동과 application 계층부터 Kotlin + Coroutine으로 점진 전환한다.

즉, 추천 순서는 아래와 같다.

1. 멀티모듈 구조 생성
2. `explore`를 기준 샘플로 port-adapter 정리
3. `llm`, `tour api`를 Kotlin + Coroutine으로 전환
4. `curation`, `schedule`, `user` 경계 분리
5. DTO/service 중심으로 Kotlin 비중 확대
6. 필요 시 마지막에 엔티티 전환 검토

이 순서가 가장 현실적이고, 포트폴리오 관점에서도 설계 의도를 설명하기 쉽다.
