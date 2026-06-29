package com.heattrip.heat_trip_backend.curation.service;

import com.heattrip.heat_trip_backend.curation.dto.LlmRecommendRequest;
import com.heattrip.heat_trip_backend.curation.dto.LlmRecommendResponse;
import com.heattrip.heat_trip_backend.curation.dto.PadDTO;
import com.heattrip.heat_trip_backend.curation.dto.PlaceScoreDTO;
import com.heattrip.heat_trip_backend.curation.dto.RankRequest;
import com.heattrip.heat_trip_backend.curation.dto.RecommendResultDto;
import com.heattrip.heat_trip_backend.curation.port.RecommendationPort;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.util.List;
import java.util.Set;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class CurationRecommendServiceTest {

    @Mock
    private RecommendationPort recommender;

    @Mock
    private Cat3DictionaryService cat3Dict;

    @Mock
    private ScoringService scoring;

    @InjectMocks
    private CurationRecommendService service;

    @Test
    @DisplayName("cat3Filter가 있으면 LLM을 호출하지 않고 바로 랭킹한다")
    void recommend_skipsLlmWhenCat3FilterExists() {
        RankRequest req = baseRequest();
        req.setCat3Filter(List.of("A01010100", "A01010200"));
        List<PlaceScoreDTO> ranked = List.of(PlaceScoreDTO.builder().placeId(1L).name("quiet walk").build());

        when(scoring.rank(req)).thenReturn(ranked);

        RecommendResultDto result = service.recommend(req);

        verify(recommender, never()).getRecommendation(any());
        verify(scoring).rank(req);
        assertThat(result.getPlaces()).isEqualTo(ranked);
        assertThat(result.getLlm()).isNull();
        assertThat(result.getCat3FromLlm()).isNull();
    }

    @Test
    @DisplayName("cat3Filter가 없으면 LLM 결과를 cat3로 변환한 뒤 랭킹한다")
    void recommend_callsLlmAndUsesResolvedCat3Codes() {
        RankRequest req = baseRequest();
        List<PlaceScoreDTO> ranked = List.of(PlaceScoreDTO.builder().placeId(7L).name("healing trail").build());
        LlmRecommendResponse llmResponse = new LlmRecommendResponse(
                1,
                "tired but stable",
                "quiet healing",
                "rest and walk",
                List.of(new LlmRecommendResponse.CategoryGroup("core", List.of("healing", "quiet"))),
                List.of(new LlmRecommendResponse.Activity("walk", "slow walk")),
                List.of("healing", "quiet"),
                "take it easy"
        );

        when(recommender.getRecommendation(any(LlmRecommendRequest.class))).thenReturn(llmResponse);
        when(cat3Dict.resolveCat3Codes(List.of("healing", "quiet")))
                .thenReturn(Set.of("A01010100", "A01010200"));
        when(scoring.rank(req)).thenReturn(ranked);

        RecommendResultDto result = service.recommend(req);
        ArgumentCaptor<LlmRecommendRequest> captor = ArgumentCaptor.forClass(LlmRecommendRequest.class);

        verify(recommender).getRecommendation(captor.capture());
        verify(scoring).rank(req);

        LlmRecommendRequest llmRequest = captor.getValue();
        assertThat(llmRequest.getPleasure()).isEqualTo(1.0);
        assertThat(llmRequest.getArousal()).isEqualTo(0.0);
        assertThat(llmRequest.getDominance()).isEqualTo(1.0);
        assertThat(llmRequest.getEnergy()).isEqualTo(1.0);
        assertThat(llmRequest.getSocial()).isEqualTo(0.35);
        assertThat(llmRequest.getMoodKey()).isEqualTo("tired");
        assertThat(llmRequest.getPurposeKeywords()).containsExactly("healing", "quiet", "walk");
        assertThat(llmRequest.getNotes()).isEqualTo("조용히 걷고 쉬고 싶음");

        assertThat(req.getCat3Filter()).containsExactlyInAnyOrder("A01010100", "A01010200");
        assertThat(result.getPlaces()).isEqualTo(ranked);
        assertThat(result.getCat3FromLlm()).containsExactlyInAnyOrder("A01010100", "A01010200");
        assertThat(result.getLlm()).isNotNull();
        assertThat(result.getLlm().getThemeName()).isEqualTo("quiet healing");
        assertThat(result.getLlm().getCategoryGroups()).hasSize(1);
    }

    @Test
    @DisplayName("LLM 응답이 null이면 예외를 던진다")
    void recommend_throwsWhenLlmResponseIsNull() {
        RankRequest req = baseRequest();
        when(recommender.getRecommendation(any(LlmRecommendRequest.class))).thenReturn(null);

        assertThatThrownBy(() -> service.recommend(req))
                .isInstanceOf(NullPointerException.class)
                .hasMessage("Recommendation response must not be null");
    }

    private RankRequest baseRequest() {
        RankRequest req = new RankRequest();
        req.setPad(new PadDTO(1, 0, 1));
        req.setEnergy(1);
        req.setSocialNeed(0.35);
        req.setPurposeKeywords(List.of("healing", "quiet", "walk"));
        req.setMoodKey("tired");
        req.setNotes("조용히 걷고 쉬고 싶음");
        return req;
    }
}
