# PR #7 리뷰 로그

- PR 번호: `#7`
- PR 제목: `[refactor] Part of #2 migrate curation LLM DTOs to Kotlin`
- 이슈 연결: `Part of #2`
- 브랜치: `refactor/kotlin-curation-llm-dto`

## 문서 목적

이 문서는 PR `#7` 리뷰 과정에서 발견된 문제, 후속 수정 사항, 그리고 그 기술적 배경을 정리한 기록 문서다.

이번 리뷰에서 집중한 핵심 위험은 하나였다.

- Kotlin DTO 전환 과정에서 Jackson annotation 대상이 바뀌었다.
- LLM 응답 DTO는 외부 추천 서버 JSON을 역직렬화해서 사용한다.
- annotation target이 맞지 않으면 컴파일과 테스트는 통과해도 런타임에서 필드가 `null` 또는 기본값으로 들어갈 수 있다.

## 무엇을 리뷰했는가

PR `#7`은 원래 다음 작업을 수행했다.

- 추천 request/response DTO를 `curation/dto`로 이동
- 외부 추천 클라이언트 직접 의존을 `RecommendationPort`로 치환
- `OpenAiRecommendationAdapter` 도입
- `RecommendResultDTO.java`를 `RecommendResultDto.kt`로 전환
- `llm/RecommenderClient.java` 제거
- 테스트 및 JaCoCo 추가

이 과정에서 실제 런타임 호환성 위험 1건을 확인했다.

- `src/main/java/com/heattrip/heat_trip_backend/curation/dto/LlmRecommendResponse.kt`

## 발견된 문제

### 요약

`LlmRecommendResponse.kt`는 snake_case JSON 필드들에 대해 다음처럼 `@get:JsonProperty(...)`를 사용하고 있었다.

- `schema_version`
- `emotion_diagnosis`
- `theme_name`
- `theme_description`
- `category_groups`
- `comfort_letter`

그리고 nested DTO인 `CategoryGroup.groupName`도 같은 패턴이었다.

### 왜 위험했는가

이 DTO는 단순히 응답으로 직렬화되는 객체가 아니라, 외부 LLM 서버에서 받은 JSON을 역직렬화해서 내부에서 사용하는 객체다.

즉 실제 사용 지점은 다음과 같다.

- `WebClient.bodyToMono(LlmRecommendResponse::class.java)`

Kotlin data class는 primary constructor 기반으로 역직렬화되는 경우가 많다.

그런데 annotation이 getter에만 붙어 있으면:

- 직렬화는 문제 없어 보일 수 있지만
- constructor 기반 역직렬화에서는 JSON 필드명이 제대로 연결되지 않을 수 있다.

그 결과 다음이 생길 수 있다.

1. LLM 서버가 정상 JSON을 반환한다.
2. HTTP 호출 자체는 성공한다.
3. `LlmRecommendResponse` 객체가 생성되지만 중요한 필드가 비어 있다.
4. 이후 추천 로직이 잘못된 값으로 동작한다.

즉, 이건 컴파일 타임 문제라기보다 “런타임 계약 문제”다.

## 적용한 수정

### 1. `LlmRecommendResponse` annotation target 변경

기존:

- `@get:JsonProperty(...)`

변경:

- `@field:JsonProperty(...)`
- `@param:JsonProperty(...)`

적용 대상:

- `schemaVersion`
- `emotionDiagnosis`
- `themeName`
- `themeDescription`
- `categoryGroups`
- `comfortLetter`

### 2. nested `CategoryGroup`도 동일하게 수정

같은 수정이 다음 필드에도 적용되었다.

- `CategoryGroup.groupName`

이유:

- nested DTO 역시 역직렬화 체인 안에 있기 때문에 루트 DTO만 고치면 충분하지 않다.

### 3. 전용 회귀 테스트 추가

추가한 테스트:

- `src/test/java/com/heattrip/heat_trip_backend/curation/dto/LlmRecommendResponseJsonTest.java`

이 테스트가 검증하는 것:

- snake_case JSON이 Kotlin DTO에 제대로 매핑되는지
- `category_groups.group_name`이 올바르게 들어오는지
- `activities`, `keywords` 같은 리스트가 유지되는지
- 핵심 필드들이 모두 기대값대로 들어오는지

이 테스트는 단순 서비스 테스트로는 놓칠 수 있는 “JSON 계약”을 고정한다는 점에서 의미가 크다.

## 기술 개념 정리

### 1. Kotlin의 `@get:` / `@field:` / `@param:`

Kotlin 프로퍼티는 JVM 레벨에서 여러 요소로 나뉠 수 있다.

- constructor parameter
- backing field
- getter method
- setter method

그래서 annotation을 쓸 때는 어느 대상에 붙일 것인지 명시해야 하는 경우가 있다.

대표적인 use-site target:

- `@get:`: getter에 붙임
- `@field:`: backing field에 붙임
- `@param:`: constructor parameter에 붙임

### 2. Jackson은 왜 이 구분에 민감한가

Jackson은 객체를 만들 때 다음 방식들을 사용할 수 있다.

- getter/setter 기반 바인딩
- field 기반 바인딩
- constructor 기반 바인딩

Kotlin data class는 constructor 기반 바인딩과 잘 연결된다.

그래서 JSON 이름을 Kotlin 프로퍼티 이름과 다르게 쓰는 경우, constructor parameter 또는 field 쪽 annotation이 중요해진다.

즉, Kotlin DTO에서 snake_case JSON을 안전하게 역직렬화하려면 `@get:`만으로는 부족할 수 있다.

### 3. 왜 컴파일은 되는데 런타임에서 깨질 수 있는가

컴파일러는:

- 문법
- 타입

까지만 본다.

하지만 다음은 확인하지 못한다.

- 외부 JSON 계약과 annotation이 실제로 맞는지
- Jackson이 getter를 쓸지, field를 쓸지, constructor parameter를 쓸지
- 값이 비었을 때 기본값으로 조용히 대체되는지

그래서 이런 유형은 컴파일 에러가 아니라 런타임 계약 버그로 분류하는 것이 맞다.

### 4. 왜 서비스 테스트만으로는 부족한가

서비스 테스트는 보통 다음을 검증한다.

- orchestration 로직이 맞는지
- 의존성을 올바르게 호출하는지
- 최종 응답 조립이 맞는지

하지만 테스트 코드 안에서 DTO를 직접 new 해서 쓰면 JSON 역직렬화 문제는 검증하지 못한다.

그래서 이 경우에는 별도의 JSON 역직렬화 테스트가 꼭 필요했다.

## 수동 테스트와의 관계

Postman으로 API를 직접 호출하는 테스트는 여전히 유효하다.

확인할 수 있는 것:

- 엔드포인트 접근 가능 여부
- 인증 흐름
- happy path 동작

하지만 이 케이스에서는 다음 한계가 있다.

- 응답은 `200 OK`인데 일부 필드만 잘못 들어올 수 있다.
- 문제 원인이 비즈니스 로직인지 DTO 역직렬화인지 구분이 어려울 수 있다.

그래서 이번 회귀 테스트가 그 빈틈을 메우는 역할을 한다.

## 후속 적용 결과

후속 수정 이후 PR `#7`에는 다음이 포함되었다.

- Kotlin 역직렬화를 고려한 Jackson annotation target 보강
- nested DTO mapping 보정
- LLM 응답 JSON 계약을 고정하는 자동화 테스트

## 이후 권장 기준

앞으로 이 저장소에서 Kotlin DTO 전환 작업을 할 때는 다음 기준을 기본으로 삼는 것이 안전하다.

- 외부 JSON 계약 DTO에는 `@field:JsonProperty` 또는 `@param:JsonProperty`를 우선 고려한다.
- 중요한 외부 계약에는 최소 1개의 JSON 역직렬화 테스트를 둔다.
- 테스트를 다음 세 종류로 나눠 생각한다.
  - 서비스 로직 테스트
  - 컨트롤러 테스트
  - 직렬화/역직렬화 계약 테스트

## 관련 파일

- `src/main/java/com/heattrip/heat_trip_backend/curation/dto/LlmRecommendResponse.kt`
- `src/test/java/com/heattrip/heat_trip_backend/curation/dto/LlmRecommendResponseJsonTest.java`

## 상태

- PR 리뷰 완료
- 리뷰 코멘트 작성 완료
- 후속 수정 반영 완료
- 회귀 테스트 추가 완료
