package com.heattrip.heat_trip_backend.curation.dto;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.module.kotlin.KotlinModule;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

class LlmRecommendResponseJsonTest {

    private final ObjectMapper objectMapper = new ObjectMapper()
            .registerModule(new KotlinModule.Builder().build());

    @Test
    @DisplayName("snake_case LLM 응답을 Kotlin DTO로 역직렬화한다")
    void deserializesSnakeCaseResponseIntoKotlinDto() throws Exception {
        String json = """
                {
                  "schema_version": 1,
                  "emotion_diagnosis": "tired but stable",
                  "theme_name": "quiet healing",
                  "theme_description": "rest and walk",
                  "category_groups": [
                    {
                      "group_name": "core",
                      "categories": ["healing", "quiet"]
                    }
                  ],
                  "activities": [
                    {
                      "title": "walk",
                      "description": "slow walk"
                    }
                  ],
                  "keywords": ["healing", "quiet"],
                  "comfort_letter": "take it easy"
                }
                """;

        LlmRecommendResponse response = objectMapper.readValue(json, LlmRecommendResponse.class);

        assertThat(response.getSchemaVersion()).isEqualTo(1);
        assertThat(response.getEmotionDiagnosis()).isEqualTo("tired but stable");
        assertThat(response.getThemeName()).isEqualTo("quiet healing");
        assertThat(response.getThemeDescription()).isEqualTo("rest and walk");
        assertThat(response.getCategoryGroups()).hasSize(1);
        assertThat(response.getCategoryGroups().get(0).getGroupName()).isEqualTo("core");
        assertThat(response.getCategoryGroups().get(0).getCategories())
                .containsExactly("healing", "quiet");
        assertThat(response.getActivities()).hasSize(1);
        assertThat(response.getActivities().get(0).getTitle()).isEqualTo("walk");
        assertThat(response.getActivities().get(0).getDescription()).isEqualTo("slow walk");
        assertThat(response.getKeywords()).containsExactly("healing", "quiet");
        assertThat(response.getComfortLetter()).isEqualTo("take it easy");
    }
}
