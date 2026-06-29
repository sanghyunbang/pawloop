package com.heattrip.heat_trip_backend.tour.mapper;

import com.heattrip.heat_trip_backend.tour.domain.Place;
import com.heattrip.heat_trip_backend.tour.dto.PlaceItemDto;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.time.LocalDateTime;

import static org.assertj.core.api.Assertions.assertThat;

public class PlaceMapperTest {

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
