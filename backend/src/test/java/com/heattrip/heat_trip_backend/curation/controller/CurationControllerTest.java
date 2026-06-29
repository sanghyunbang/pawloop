package com.heattrip.heat_trip_backend.curation.controller;

import com.heattrip.heat_trip_backend.curation.dto.CategoryScoreDTO;
import com.heattrip.heat_trip_backend.curation.dto.PadDTO;
import com.heattrip.heat_trip_backend.curation.dto.PlaceScoreDTO;
import com.heattrip.heat_trip_backend.curation.dto.RankRequest;
import com.heattrip.heat_trip_backend.curation.dto.RecommendResultDto;
import com.heattrip.heat_trip_backend.curation.service.CurationRecommendService;
import com.heattrip.heat_trip_backend.curation.service.ScoringService;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class CurationControllerTest {

    @Mock
    private ScoringService scoring;

    @Mock
    private CurationRecommendService orchestration;

    @InjectMocks
    private CurationController controller;

    @Test
    @DisplayName("rank는 기본 topK, 거리 옵션을 주입한 뒤 scoring을 호출한다")
    void rank_setsDefaultOptionsBeforeScoring() {
        RankRequest request = baseRequest();
        List<PlaceScoreDTO> ranked = List.of(PlaceScoreDTO.builder().placeId(1L).name("calm place").build());
        when(scoring.rank(request)).thenReturn(ranked);

        List<PlaceScoreDTO> response = controller.rank(request);

        assertThat(request.getTopK()).isEqualTo(50);
        assertThat(request.getMaxDistanceKm()).isEqualTo(120.0);
        assertThat(request.getDistanceWeight()).isEqualTo(0.2);
        assertThat(response).isEqualTo(ranked);
        verify(scoring).rank(request);
    }

    @Test
    @DisplayName("categories는 scoring 결과를 그대로 반환한다")
    void categories_returnsScoringResult() {
        RankRequest request = baseRequest();
        List<CategoryScoreDTO> categories = List.of(
                CategoryScoreDTO.builder().categoryId(3).categoryName("healing").build()
        );
        when(scoring.categories(request)).thenReturn(categories);

        List<CategoryScoreDTO> response = controller.categories(request);

        assertThat(response).isEqualTo(categories);
        verify(scoring).categories(request);
    }

    @Test
    @DisplayName("recommend는 orchestration 결과를 그대로 반환한다")
    void recommend_returnsServiceResult() {
        RankRequest request = baseRequest();
        RecommendResultDto result = new RecommendResultDto(
                List.of(PlaceScoreDTO.builder().placeId(9L).name("quiet walk").build()),
                null,
                List.of("A01010100")
        );
        when(orchestration.recommend(request)).thenReturn(result);

        RecommendResultDto response = controller.recommend(request);

        assertThat(response).isEqualTo(result);
        verify(orchestration).recommend(request);
    }

    private RankRequest baseRequest() {
        RankRequest request = new RankRequest();
        request.setPad(new PadDTO(1, 0, 1));
        request.setEnergy(1);
        request.setSocialNeed(0.35);
        return request;
    }
}
