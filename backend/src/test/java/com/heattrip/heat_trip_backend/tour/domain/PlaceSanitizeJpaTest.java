package com.heattrip.heat_trip_backend.tour.domain;

import com.heattrip.heat_trip_backend.support.AbstractMySqlIntegrationTest;
import com.heattrip.heat_trip_backend.tour.repository.PlaceRepository;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.jdbc.AutoConfigureTestDatabase;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;

import static org.assertj.core.api.Assertions.assertThat;

// 데이터소스·dialect·ddl-auto 는 AbstractMySqlIntegrationTest 가 실 MySQL 로 넣는다.
// replace = NONE 이 없으면 @DataJpaTest 가 그걸 임베디드 DB 로 갈아치운다. (#49)
@DataJpaTest
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
public class PlaceSanitizeJpaTest extends AbstractMySqlIntegrationTest {

    @Autowired
    PlaceRepository placeRepository;

    @Test
    @DisplayName("Place 저장 시 title과 tel을 정제한다")
    void sanitizeBeforePersist() {
        String longTitle = "가".repeat(300);

        Place place = Place.builder()
                .contentid(1L)
                .title(longTitle)
                .tel("전화: 123-456-7890 abc")
                .cat1("A01")
                .cat2("A0101")
                .cat3("A01010100")
                .build();

        placeRepository.saveAndFlush(place);

        Place saved = placeRepository.findById(1L).orElseThrow();
        assertThat(saved.getTitle()).hasSizeLessThanOrEqualTo(Place.TITLE_MAX_LEN);
        assertThat(saved.getTel()).isEqualTo("123-456-7890");
        assertThat(saved.getSearchText()).contains("A01010100");
    }
}
