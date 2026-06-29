# 2026-04-19 PR #7 Code Scanning 후속 대응

## 개요

- 날짜: `2026-04-19`
- 대상 PR: `#7`
- PR 제목: `[refactor] Part of #2 migrate curation LLM DTOs to Kotlin`
- 관련 브랜치: `refactor/kotlin-curation-llm-dto`

이 문서는 PR `#7`에서 GitHub Code Scanning과 `github-advanced-security[bot]`가 남긴 코멘트에 대응한 기록이다.

이번 대응의 목적은 다음과 같다.

- Code Scanning이 실제로 어떤 경고를 남겼는지 기록한다.
- 그 경고가 왜 발생했는지 기술적으로 설명한다.
- 어떤 수정으로 대응했는지 남긴다.
- 이후 같은 유형의 경고를 봤을 때 팀원이 빠르게 이해할 수 있게 한다.

## 배경

Qodana에 SARIF 업로드를 추가한 이후, PR `#7`에 `github-advanced-security[bot]`이 별도의 Code Scanning 코멘트를 남겼다.

이 봇은 “Code Scanning이 설정되었다”는 안내 메시지와 함께 실제 코드 라인에 대한 리뷰 코멘트도 남긴다.

이번 PR에서 남은 실제 경고는 모두 같은 유형이었다.

- `QDJVMC / Nullability and data flow problems`
- `Method invocation 'stream' may produce 'NullPointerException'`

대상 파일:

- `src/main/java/com/heattrip/heat_trip_backend/curation/service/CurationRecommendService.java`

대상 위치:

- category 라벨을 펼치는 `stream()` 호출 부근
- activity 리스트를 `stream()`으로 변환하는 부근

## 무엇이 문제였는가

표면적으로는 코드가 이미 null-safe해 보였다.

예를 들어 이전 코드는 다음과 같은 방식이었다.

- `Objects.requireNonNullElse(res.getCategoryGroups(), List.of())`
- `Objects.requireNonNullElse(group.getCategories(), List.of())`
- `Objects.requireNonNullElse(res.getActivities(), List.of()).stream()`

런타임 관점에서는 이 코드가 충분히 안전해 보일 수 있다.

하지만 정적 분석기 입장에서는 다음 문제가 있었다.

1. `var`와 제네릭 타입 추론이 섞여 있다.
2. `Objects.requireNonNullElse(...)`가 비-null을 보장한다고 하더라도, 분석기가 그 흐름을 완전히 좁히지 못할 수 있다.
3. nested getter 호출과 즉시 `stream()` 호출이 이어지면, 분석기가 “혹시 null일 수도 있다”고 보수적으로 판단할 수 있다.

즉, 실제 런타임 버그라기보다는:

- “정적 분석기가 null 아님을 확신하기 어려운 코드 형태”

가 문제였다.

## 왜 이런 경고를 무시하지 않았는가

이런 경고는 항상 실제 버그는 아니다.

하지만 무시하지 않은 이유는 다음과 같다.

- Code Scanning이 지적한 코드가 핵심 추천 흐름 안에 있다.
- null 관련 경고는 작은 오해가 나중에 실제 예외로 이어질 수 있다.
- 조금 더 명시적인 코드로 바꾸면 사람도 읽기 쉬워지고 정적 분석기도 이해하기 쉬워진다.

즉, “실행은 되지만 애매한 코드”를 “의도가 분명한 코드”로 바꾸는 것이 목적이었다.

## 적용한 수정

### 1. categoryGroups를 명시적 비-null 리스트로 정규화

이전:

```java
var categoryGroups = Objects.requireNonNullElse(
        res.getCategoryGroups(),
        List.<LlmRecommendResponse.CategoryGroup>of()
);
```

수정 후:

```java
List<LlmRecommendResponse.CategoryGroup> categoryGroups =
        res.getCategoryGroups() == null ? List.of() : res.getCategoryGroups();
```

의미:

- 이후 `categoryGroups.stream()`은 정적 분석기 기준으로도 비-null 리스트에 대해 호출됨이 더 명확해진다.

### 2. nested categories 처리에서 `Stream.empty()` 사용

이전:

```java
.flatMap(group -> {
    var categories = Objects.requireNonNullElse(group.getCategories(), List.<String>of());
    return categories.stream();
})
```

수정 후:

```java
.flatMap(group -> group.getCategories() == null
        ? Stream.<String>empty()
        : group.getCategories().stream())
```

의미:

- `categories`가 null이면 빈 stream
- 아니면 실제 categories stream

이렇게 쓰면 null 분기가 훨씬 직접적으로 드러난다.

### 3. activities도 명시적 비-null 리스트로 정규화

이전:

```java
Objects.requireNonNullElse(
        res.getActivities(),
        List.<LlmRecommendResponse.Activity>of()
).stream()
```

수정 후:

```java
List<LlmRecommendResponse.Activity> activities =
        res.getActivities() == null ? List.of() : res.getActivities();

activities.stream()
```

의미:

- `stream()` 호출 대상이 명시적 비-null 리스트가 되므로 Code Scanning 경고를 줄일 수 있다.

## 이번 수정의 성격

이 수정은 기능 변경이 아니라 다음 목적의 코드 명확화다.

- nullability 의도 명시
- 정적 분석 친화적 형태로 재작성
- 추천 로직 의미는 유지
- 잠재적 오해 제거

즉, 추천 결과 자체를 바꾸는 수정이 아니라:

- “정적 분석기와 사람 모두가 읽기 쉬운 형태로 바꾸는 수정”

이라고 보면 된다.

## 왜 reply와 코드 수정이 같이 필요한가

PR에 남은 bot 코멘트는 리뷰 히스토리로 남는다.

그래서 대응은 보통 두 단계가 필요하다.

1. 실제 코드 수정
2. 해당 리뷰 코멘트에 “무엇을 고쳤는지” 답글 남기기

이렇게 해야:

- 나중에 PR 기록만 봐도 왜 수정했는지 남고
- reviewer나 팀원이 대응 여부를 빠르게 이해할 수 있다.

## 이번 후속 대응에서 남긴 메시지 기준

답글에서는 다음을 짧게 남겼다.

- nullable 컬렉션을 명시적으로 비-null 리스트로 정규화했다
- nested category/activity stream 호출도 null-safe한 형태로 바꿨다
- 기능 변화가 아니라 nullability 경고 해소 목적이다

## 검증

이 수정 후에는 최소한 다음을 확인해야 한다.

- 기존 테스트가 깨지지 않는지
- recommendation 흐름이 그대로 동작하는지

실행:

- `./gradlew.bat test`

결과:

- 테스트 통과

## 관련 파일

- `src/main/java/com/heattrip/heat_trip_backend/curation/service/CurationRecommendService.java`
- `docs/logs/ci/2026-04-19-pr-7-code-scanning-후속대응.md`

## 요약

이번 Code Scanning 후속 대응의 핵심은 다음과 같다.

1. GitHub Advanced Security bot이 nullability 경고 3건을 남겼다.
2. 문제의 본질은 즉시 런타임 버그라기보다, 정적 분석기가 null 아님을 확신하기 어려운 코드 형태였다.
3. nullable 컬렉션을 명시적 비-null 리스트로 정규화하고, nested stream 호출도 더 직접적인 null-safe 형태로 변경했다.
4. 기능 의미는 유지하면서 정적 분석 친화성과 코드 가독성을 높였다.
