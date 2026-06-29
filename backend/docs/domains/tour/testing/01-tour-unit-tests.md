# 1. Tour 단위 테스트

Tour 단위 테스트의 목적은 DB, Spring Context, 외부 API 없이 순수 Java 로직을 빠르게 검증하는 것이다.

여기서 확인할 대상은 다음과 같다.

- `PlaceMapper.toEntity()`
- `PlaceMapper.toDto()`
- `Sanitizers.truncate()`
- `Sanitizers.cleanTel()`
- `Place`의 저장 전 정제 로직
- Tour API JSON 응답을 `PlaceItemDto`로 변환하는 파싱 흐름

## 단위 테스트의 역할

단위 테스트는 동시성 문제를 찾기 위한 테스트가 아니다. 대신 import 파이프라인의 가장 작은 부품이 정확히 동작하는지 검증한다.

예를 들어 다음 문제는 단위 테스트로 잡을 수 있다.

- 전화번호에 이상한 문자가 들어와도 저장 전 제거되는가?
- `title`이 255자를 넘으면 잘리는가?
- `PlaceItemDto.contentid`가 `Place.contentid`로 매핑되는가?
- `createdtime`, `modifiedtime`이 누락되지 않는가?
- Tour API 응답 JSON에서 item 배열을 올바르게 꺼내는가?

반대로 다음 문제는 단위 테스트로 보기 어렵다.

- import 중 조회 API가 느려지는가?
- DB row lock이 발생하는가?
- transaction commit 전 데이터가 보이는가?
- snapshot 전체 update가 read latency를 올리는가?

이런 문제는 통합/부하 테스트에서 다룬다.

## 추천 패키지 구조

실제 테스트 코드를 작성한다면 아래처럼 둘 수 있다.

```text
src/test/java/com/heattrip/heat_trip_backend/tour/
  mapper/
    PlaceMapperTest.java
  util/
    SanitizersTest.java
  domain/
    PlaceSanitizeTest.java
  service/
    PlaceImportParsingTest.java
```

## 예시 1: Sanitizers 테스트

```java
package com.heattrip.heat_trip_backend.tour.util;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

class SanitizersTest {

    @Test
    @DisplayName("truncate는 maxLen을 초과한 문자열을 자른다")
    void truncateCutsLongString() {
        String value = "abcdef";

        String result = Sanitizers.truncate(value, 3);

        assertThat(result).isEqualTo("abc");
    }

    @Test
    @DisplayName("truncate는 null을 null로 유지한다")
    void truncateKeepsNull() {
        assertThat(Sanitizers.truncate(null, 10)).isNull();
    }

    @Test
    @DisplayName("cleanTel은 허용되지 않은 문자를 제거하고 길이를 제한한다")
    void cleanTelRemovesUnexpectedCharacters() {
        String value = "TEL: 02-123-4567 abc !!!";

        String result = Sanitizers.cleanTel(value, 20);

        assertThat(result).isEqualTo("02-123-4567");
    }
}
```

## 예시 2: PlaceMapper 테스트

```java
package com.heattrip.heat_trip_backend.tour.mapper;

import com.heattrip.heat_trip_backend.tour.domain.Place;
import com.heattrip.heat_trip_backend.tour.dto.PlaceItemDto;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.time.LocalDateTime;

import static org.assertj.core.api.Assertions.assertThat;

class PlaceMapperTest {

    @Test
    @DisplayName("Tour API DTO를 Place 엔티티로 변환한다")
    void toEntityMapsImportantFields() {
        LocalDateTime created = LocalDateTime.of(2026, 1, 1, 12, 0);

        PlaceItemDto dto = PlaceItemDto.builder()
                .contentid(100L)
                .title("테스트 장소")
                .addr1("서울시")
                .mapx(127.0)
                .mapy(37.5)
                .cat1("A01")
                .cat2("A0101")
                .cat3("A01010100")
                .areacode(1)
                .sigungucode(1)
                .tel("02-123-4567")
                .contenttypeid("12")
                .createdtime(created)
                .build();

        Place place = PlaceMapper.toEntity(dto);

        assertThat(place.getContentid()).isEqualTo(100L);
        assertThat(place.getTitle()).isEqualTo("테스트 장소");
        assertThat(place.getMapx()).isEqualTo(127.0);
        assertThat(place.getMapy()).isEqualTo(37.5);
        assertThat(place.getCat3()).isEqualTo("A01010100");
        assertThat(place.getCreatedtime()).isEqualTo(created);
    }
}
```

## 예시 3: Place 저장 전 정제 테스트

`@PrePersist`, `@PreUpdate` 메서드는 private이므로 단위 테스트에서 직접 호출하기 애매하다. 선택지는 두 가지다.

1. JPA 저장을 통해 lifecycle callback을 검증한다.
2. 정제 로직을 별도 package-private 메서드나 helper로 분리한 뒤 단위 테스트한다.

현재 코드를 건드리지 않고 학습용으로 보면 JPA 저장 기반 테스트가 더 자연스럽다. 하지만 이것은 순수 단위 테스트가 아니라 JPA slice 테스트에 가깝다.

예시:

```java
package com.heattrip.heat_trip_backend.tour.domain;

import com.heattrip.heat_trip_backend.tour.repository.PlaceRepository;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;

import static org.assertj.core.api.Assertions.assertThat;

@DataJpaTest
class PlaceSanitizeJpaTest {

    @Autowired
    PlaceRepository placeRepository;

    @Test
    @DisplayName("Place 저장 시 title과 tel을 정제한다")
    void sanitizeBeforePersist() {
        String longTitle = "가".repeat(300);

        Place place = Place.builder()
                .contentid(1L)
                .title(longTitle)
                .tel("전화: 02-123-4567 abc")
                .cat1("A01")
                .cat2("A0101")
                .cat3("A01010100")
                .build();

        placeRepository.saveAndFlush(place);

        Place saved = placeRepository.findById(1L).orElseThrow();
        assertThat(saved.getTitle()).hasSizeLessThanOrEqualTo(Place.TITLE_MAX_LEN);
        assertThat(saved.getTel()).isEqualTo("02-123-4567");
        assertThat(saved.getSearchText()).contains("A01010100");
    }
}
```

주의: `@DataJpaTest`는 기본적으로 embedded DB를 쓰려고 한다. MySQL 고유 동작을 보려면 2번 문서의 Testcontainers 구성을 사용한다.

## 예시 4: JSON 파싱 테스트

외부 Tour API를 직접 호출하지 않고 sample JSON 문자열을 사용한다.

```java
package com.heattrip.heat_trip_backend.tour.service;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.heattrip.heat_trip_backend.tour.dto.PlaceItemDto;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

class PlaceImportParsingTest {

    private final ObjectMapper objectMapper = new ObjectMapper();

    @Test
    @DisplayName("Tour API 응답에서 item 배열을 PlaceItemDto로 변환한다")
    void parseTourApiItems() throws Exception {
        String json = """
            {
              "response": {
                "body": {
                  "items": {
                    "item": [
                      {
                        "contentid": 100,
                        "title": "테스트 장소",
                        "addr1": "서울",
                        "mapx": 127.0,
                        "mapy": 37.5,
                        "cat1": "A01",
                        "cat2": "A0101",
                        "cat3": "A01010100"
                      }
                    ]
                  }
                }
              }
            }
            """;

        JsonNode items = objectMapper.readTree(json)
                .path("response").path("body").path("items").path("item");

        PlaceItemDto dto = objectMapper.treeToValue(items.get(0), PlaceItemDto.class);

        assertThat(items).hasSize(1);
        assertThat(dto.getContentid()).isEqualTo(100L);
        assertThat(dto.getTitle()).isEqualTo("테스트 장소");
    }
}
```

## 단위 테스트 결과를 어떻게 보여줄까

단위 테스트 결과는 동시성 수치보다 품질 보증 자료에 가깝다.

예시:

| 테스트 대상 | 케이스 수 | 결과 |
|---|---:|---|
| `Sanitizers` | 6 | 통과 |
| `PlaceMapper` | 3 | 통과 |
| Tour JSON 파싱 | 4 | 통과 |
| `Place` 저장 전 정제 | 3 | 통과 |

이 단계에서 보여줄 메시지는 다음이다.

> 외부 API 응답이 길이 초과, null, 형식 차이를 포함해도 내부 저장 모델로 변환되기 전 기본 방어 로직을 검증했다.
