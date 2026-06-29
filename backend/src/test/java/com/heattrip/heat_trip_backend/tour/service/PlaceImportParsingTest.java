package com.heattrip.heat_trip_backend.tour.service;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.heattrip.heat_trip_backend.tour.dto.PlaceItemDto;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

public class PlaceImportParsingTest {

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
                .path("response")
                .path("body")
                .path("items")
                .path("item");

        PlaceItemDto dto = objectMapper.treeToValue(items.get(0), PlaceItemDto.class);

        assertThat(items).hasSize(1);
        assertThat(dto.getContentid()).isEqualTo(100L);
        assertThat(dto.getTitle()).isEqualTo("테스트 장소");
    }

}
