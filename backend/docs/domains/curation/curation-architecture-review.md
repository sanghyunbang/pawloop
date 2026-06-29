# CURATION 모듈 아키텍처 리뷰

## 범위

이 문서는 아래 두 가지를 함께 평가한다.

1. `docs/domains/curation/curation-uml.md` 문서가 실제 코드 구조를 얼마나 정확하게 설명하는지
2. `curation` 모듈 자체가 OOP, SOLID, 클린 아키텍처 관점에서 얼마나 잘 설계되어 있는지

평가 기준은 다음과 같다.

- 객체화의 적절성: 현실 문제를 코드 객체로 잘 분해했는가
- OOP: 객체 책임이 응집되어 있고 의미가 분명한가
- SOLID: 변경 이유가 잘 분리되어 있고 의존 방향이 안정적인가
- 클린 아키텍처: 외부 기술, 입출력, 비즈니스 규칙이 적절히 분리되어 있는가
- 유지보수성: 신규 요구사항 추가 시 수정 범위가 예측 가능하고 좁은가

---

## 총평

현재 `curation` 모듈은 "추천 파이프라인을 빠르게 구현한 실용적 구조"로는 꽤 괜찮다.

- 외부 LLM 호출을 `RecommendationPort`로 분리한 점은 좋다.
- 추천 흐름 orchestration과 점수 계산이 최소한 서비스 단위로 나뉘어 있다.
- 장소 기본정보, feature, 평점, 감정 카테고리, CAT3 매핑을 분리한 데이터 모델링도 합리적이다.

하지만 이 구조를 엄밀한 OOP 혹은 클린 아키텍처 관점에서 보면 한계가 분명하다.

- 핵심 규칙이 서비스 클래스에 과도하게 몰려 있다.
- 도메인 객체보다 DTO와 절차형 계산 흐름이 중심이다.
- 컨트롤러, 서비스, 영속성, 표현용 enrichment가 일부 뒤섞여 있다.
- 엔티티 이름과 실제 역할이 어긋나는 부분이 있다.

결론적으로 현재 구조는 "레이어드 서비스 구조"로는 무난하지만, "풍부한 도메인 모델"이나 "클린 아키텍처"라고 부르기에는 부족하다.

---

## 우선 Findings

### High

1. `ScoringService`에 너무 많은 책임이 몰려 있다.

- 파일: `src/main/java/com/heattrip/heat_trip_backend/curation/service/ScoringService.java`
- 점수 계산, 데이터 조회, 사용자 상태 해석, 거리 계산, 카테고리 집계, 표시용 이름 주입까지 한 클래스가 담당한다.
- 이는 SRP 위반에 가깝고, 점수 규칙 변경과 조회 방식 변경이 같은 클래스 수정으로 이어진다.
- 특히 `rank()`와 `categories()`는 use case orchestration과 scoring rule을 동시에 수행한다.

2. `CurationRecommendService`가 입력 객체를 직접 변경한다.

- 파일: `src/main/java/com/heattrip/heat_trip_backend/curation/service/CurationRecommendService.java`
- `recommend()` 내부에서 `RankRequest`에 `setCat3Filter()`를 호출한다.
- 입력 객체를 mutate하면 호출자 입장에서 부작용이 생기고, 테스트 시 추적이 어려워진다.
- use case 내부에서 파생된 요청은 새 객체로 만드는 편이 안전하다.

3. `PlaceTrait`의 이름과 실제 역할이 다르다.

- 파일: `src/main/java/com/heattrip/heat_trip_backend/curation/entity/PlaceTrait.java`
- 코드상 핵심 역할은 장소 trait라기보다 `label ↔ cat3` 사전의 원천 데이터다.
- 그런데 `placeId` 필드는 실제 place id처럼 보이지만 `Cat3DictionaryService`에서는 사실상 CAT3 코드처럼 취급한다.
- 이는 유비쿼터스 언어를 흐리고, 객체화의 정확도를 떨어뜨린다.

### Medium

4. 컨트롤러가 기본 정책값을 직접 주입한다.

- 파일: `src/main/java/com/heattrip/heat_trip_backend/curation/controller/CurationController.java`
- `/rank`에서 `topK`, `maxDistanceKm`, `distanceWeight`를 컨트롤러가 직접 설정한다.
- 이 값들은 HTTP 계층 정책이 아니라 추천 use case 기본값에 가깝다.
- 현재 구조는 웹 계층이 비즈니스 규칙 일부를 알고 있는 상태다.

5. DTO 중복이 설계를 흐린다.

- 파일: `src/main/java/com/heattrip/heat_trip_backend/curation/dto/RecommendResultDTO.java`
- 파일: `src/main/java/com/heattrip/heat_trip_backend/curation/dto/RecommendResultDto.kt`
- 같은 의미의 결과 모델이 Java/Kotlin 두 버전으로 공존한다.
- 현재 서비스는 Kotlin `RecommendResultDto`를 사용하지만, Java DTO도 남아 있어 설계 중심 모델이 무엇인지 모호하다.

6. 현재 구조는 클린 아키텍처보다는 프레임워크 친화적 레이어드 구조다.

- 서비스가 JPA repository와 Spring 컴포넌트에 직접 기대고 있다.
- 도메인 규칙을 프레임워크로부터 분리한 순수 domain/application 계층이 없다.
- 따라서 비즈니스 규칙을 독립 실행하거나 대체 persistence로 검증하기가 다소 불편하다.

7. 확장성은 있으나 OCP에는 약하다.

- 예를 들어 추천 축이 6개에서 8개로 늘어나면 `PlaceFeatures`, `ScoringService.computeUserWeights()`, trait 계산 구문, 응답 모델까지 여러 곳을 수정해야 한다.
- 즉, 변경은 가능하지만 "기존 코드를 거의 건드리지 않고 확장"되도록 설계되지는 않았다.

### Low

8. 엔티티 관계가 모두 수동 조합이라 의미가 코드에 덜 드러난다.

- 현재는 읽기 최적화 관점에서는 실용적이다.
- 다만 `Place`와 `PlaceFeatures`, `PlaceStarRating`의 관계가 명시적 객체 연관이 아니라 서비스 조합에 숨어 있다.
- 도메인 이해에는 불리하지만, 분석형 read model로 보면 반드시 잘못은 아니다.

9. `curation-uml.md`의 일부 관계 표기는 "정확한 UML"보다는 "이해를 돕는 개념도"에 가깝다.

- 특히 객체 다이어그램은 실제 UML object diagram이라기보다 실행 흐름 개념도다.
- 엔티티 관계에서 `Place -> Cat3CategoryMapping`은 스키마 제약보다 해석 관계를 나타낸 것이다.
- 문서 용도상 허용 가능하지만, 엄밀성은 낮다.

---

## `curation-uml.md` 문서 평가

### 잘된 점

- 패키지 다이어그램은 실제 의존 방향을 대체로 잘 반영한다.
- `CurationRecommendService`가 orchestration, `ScoringService`가 scoring rule의 중심이라는 설명은 맞다.
- `Place`, `PlaceFeatures`, `PlaceStarRating`를 한 장소의 서로 다른 데이터 조각으로 본 해석도 적절하다.
- "현실의 THINGS를 어떤 객체로 치환했는가" 표는 이 모듈 이해에 실제로 도움이 된다.

### 이번 보정에 반영한 점

1. `객체 다이어그램` 제목을 `실행 시점 객체 흐름`으로 조정했다.

- 기존 표현보다 현재 Mermaid의 성격을 더 정확하게 설명한다.

2. `Place`와 `Cat3CategoryMapping` 관계를 직접 연관이 아닌 해석 관계로 명시했다.

- 다이어그램 표기를 `Place ..> Cat3CategoryMapping : interpreted by Place.cat3 = cat3Code`로 바꿨다.

3. `PlaceTrait`의 실제 역할을 더 강하게 경고하도록 문구를 보강했다.

- 현재 코드 기준으로는 일반 장소 trait보다 dictionary source에 가깝다는 점을 명시했다.

4. 문서 서두와 후반부에 현재 구조의 성격을 더 정확히 적었다.

- 즉, 이 모듈은 clean architecture 완성형이 아니라 service-centric layered design에 가깝다고 분명히 적었다.

### 여전히 남는 한계

1. Mermaid 자체 한계 때문에 엄밀한 UML object diagram을 그대로 표현한 것은 아니다.

- 이 점은 문서에서 명시했지만, 표기력의 한계는 남아 있다.

2. `PlaceTrait.placeId` 의미 혼선은 문서만으로 완전히 해결되지 않는다.

- 근본 해결은 코드의 이름 변경 또는 스키마 의미 정리다.

---

## 객체화 평가

### 잘 객체화된 부분

1. "장소"를 단일 객체로 뭉개지 않고 여러 관점으로 분해한 점은 좋다.

- `Place`: 식별/표시/좌표
- `PlaceFeatures`: 추천 feature
- `PlaceStarRating`: 대중적 평가
- `Cat3CategoryMapping`: 분류 체계 연결

이 분해는 현실 문제를 데이터 출처와 계산 목적에 맞게 잘 나눈 것이다.

2. 사용자 상태를 추상 감정과 추천 의도로 분리한 점도 좋다.

- `PadDTO`는 정서 상태
- `goals`, `purposeKeywords`, `notes`는 추천 의도

즉, "지금 어떤 감정인가"와 "무엇을 원하나"를 구분하고 있다.

### 객체화가 약한 부분

1. 핵심 도메인 개념이 객체보다 계산 절차로 존재한다.

- 예를 들어 `UserIntent`, `PlaceProfile`, `Popularity`, `DistancePolicy`, `RecommendationCandidate` 같은 도메인 객체가 없다.
- 대신 서비스 메서드 안에서 원시값과 DTO가 직접 계산된다.

2. 점수 계산 규칙이 값 객체로 추출되지 않았다.

- 현재는 `Weights`, `Agg` 정도만 내부 보조 구조다.
- 추천 시스템의 중요한 개념인 `TraitMatch`, `PopularityScore`, `FinalScore`가 독립 객체가 아니므로 의미가 코드에 덜 남는다.

3. 분류 사전의 개념이 엔티티 명칭에 반영되지 않았다.

- `PlaceTrait`는 현재 역할과 이름이 불일치한다.
- 이 지점이 객체화 관점에서 가장 어색하다.

---

## OOP 관점 평가

### 장점

- 큰 흐름이 서비스 단위로 나뉘어 있어 읽기 쉽다.
- 외부 연동은 포트로 캡슐화되어 있다.
- JPA 엔티티를 계산 로직과 분리하려는 방향은 보인다.

### 약점

1. 객체가 책임을 갖기보다 서비스가 절차를 수행한다.

- 엔티티는 대부분 데이터 컨테이너다.
- 추천 로직의 의미는 객체 메시지 교환보다 서비스 메서드 내부 절차에 있다.

2. 원시 타입과 null 허용이 많다.

- `Double`, `Integer`, `String`을 직접 조합하며 null 체크가 곳곳에 필요하다.
- 값 객체가 부족해 도메인 invariant를 타입 차원에서 보장하지 못한다.

3. 응집도가 낮은 클래스가 있다.

- 대표적으로 `ScoringService`는 OOP적 응집보다 procedural aggregation에 가깝다.

평가:

- OOP 성숙도는 중간 이하
- 데이터 중심 서비스 구조로는 충분히 실용적
- 풍부한 도메인 모델 관점에서는 약함

---

## SOLID 관점 평가

### S: Single Responsibility Principle

부분적으로 위반된다.

- `ScoringService`는 책임이 많다.
- `CurationController`도 일부 기본 정책값을 안다.
- `Cat3DictionaryService`는 사전 구축, 정규화, 표시명 제공을 함께 담당한다.

### O: Open/Closed Principle

부분적으로만 만족한다.

- LLM adapter 교체는 포트 덕분에 비교적 쉽다.
- 하지만 scoring axis 추가, popularity 공식 변경, 사용자 상태 모델 변경은 서비스 내부 수정이 크게 필요하다.

### L: Liskov Substitution Principle

특별한 상속 계층이 거의 없어 큰 이슈는 없다.

### I: Interface Segregation Principle

대체로 무난하다.

- `RecommendationPort`는 작고 명확하다.
- 다만 repository는 직접 서비스에 노출되어 application-facing port로 추상화되지는 않았다.

### D: Dependency Inversion Principle

부분적으로 잘 되어 있다.

- 외부 LLM 의존은 `RecommendationPort`에 역전되어 있다.
- 그러나 persistence는 여전히 JPA repository에 직접 의존한다.
- 핵심 use case가 저장소 인터페이스를 별도 application port로 바라보지는 않는다.

총평:

- SOLID는 일부만 적용되어 있다.
- 가장 잘된 부분은 DIP at LLM boundary
- 가장 약한 부분은 SRP at scoring layer

---

## 클린 아키텍처 관점 평가

### 잘된 점

- 외부 시스템 호출을 포트/어댑터로 분리한 점
- 컨트롤러와 계산 서비스를 구분한 점

### 부족한 점

1. application layer와 domain layer가 사실상 분리되어 있지 않다.

- `ScoringService`가 use case orchestration, domain rule, repository coordination을 같이 가진다.

2. domain model이 framework-independent하지 않다.

- 핵심 규칙이 Spring 서비스와 repository 호출 안에 있다.

3. 경계가 명확하지 않다.

- 어떤 것은 정책인지, 어떤 것은 표현용 enrichment인지, 어떤 것은 persistence concern인지 한 클래스 안에 섞여 있다.

판정:

- "클린 아키텍처 일부 요소를 차용한 레이어드 구조"
- 엄밀한 클린 아키텍처로 보긴 어려움

---

## 유지보수성 평가

### 현재 장점

- 작은 팀이 빠르게 읽고 수정하기 쉬운 구조다.
- 추천 파이프라인 흐름이 비교적 직선적이다.
- 디버깅 포인트가 명확하다.

### 현재 리스크

- 점수 공식을 고치면 `ScoringService` 수정이 커질 가능성이 높다.
- `PlaceTrait` 의미 오해로 인한 버그 위험이 있다.
- DTO 중복으로 직렬화/응답 계약 혼선이 생길 수 있다.
- 정책값이 여러 계층으로 흩어질 수 있다.

---

## 개선 우선순위

### 1순위

1. `ScoringService` 분해

권장 분리 예:

- `UserPreferenceMapper`
- `TraitMatchCalculator`
- `PopularityCalculator`
- `DistanceScoreCalculator`
- `PlaceRankingUseCase`
- `CategoryAggregationUseCase`

2. `RankRequest` 불변 취급

- 파생된 `cat3Filter`는 새 command/query 객체로 만든다.

3. `PlaceTrait` 명칭과 의미 정리

- 실제 역할이 CAT3 dictionary라면 이름과 필드명을 바꾸는 것이 좋다.
- 예: `Cat3LabelEntry`, `label`, `cat3Code`

### 2순위

4. 컨트롤러 기본값 정책 이동

- 기본 `topK`, `distanceWeight`, `maxDistanceKm`는 application service나 request normalizer로 이동

5. 결과 DTO 중복 제거

- `RecommendResultDTO.java`와 `RecommendResultDto.kt` 중 하나로 통일

6. 표시용 enrichment 분리

- `cat3Name`, `firstImageUrl` 같은 표시 필드 조합을 별도 assembler/view mapper로 분리

### 3순위

7. 도메인 값 객체 도입

- `PadState`
- `UserIntent`
- `PlaceProfile`
- `PopularityScore`
- `DistancePolicy`
- `RecommendationCandidate`

8. persistence 경계 명확화

- JPA repository를 직접 서비스에서 쓰기보다 application port를 둘지 검토

---

## 추천 결론

현재 구조는 "실용적인 추천 서비스 구현"이라는 목표에는 부합한다.
다만 아래처럼 보는 것이 정확하다.

- OOP: 제한적으로 사용
- SOLID: 일부 적용
- 클린 아키텍처: 부분 요소만 존재
- 객체화: 데이터 분해는 괜찮지만, 도메인 의미가 객체보다 서비스 절차에 더 많이 존재

즉, 지금 상태를 부정적으로 볼 필요는 없지만, 문서나 설명에서 "클린 아키텍처로 잘 되어 있다" 또는 "객체지향적으로 풍부하다"라고 표현하면 과장이다.

더 정확한 표현은 아래에 가깝다.

> `curation` 모듈은 포트/어댑터를 일부 적용한 레이어드 추천 서비스이며, 데이터 모델링은 괜찮지만 핵심 규칙은 서비스 중심으로 구현되어 있다.

---

## `curation-uml.md`에 대해 바로 적용할 권장 보정

1. `객체 다이어그램` 제목을 `실행 시점 객체 흐름`으로 변경
2. `PlaceTrait`는 일반 place trait가 아니라 dictionary source라는 경고 문구 강화
3. `Place -> Cat3CategoryMapping`은 직접 연관이 아니라 `cat3 code 기반 해석 관계`라고 더 명시
4. 문서 어디엔가 "현재 구조는 clean architecture 완성형이 아니라 service-centric layered design"이라는 문장 추가
