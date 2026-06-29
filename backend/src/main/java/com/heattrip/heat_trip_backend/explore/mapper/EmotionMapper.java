// mapper/EmotionMapper.java
package com.heattrip.heat_trip_backend.explore.mapper;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.heattrip.heat_trip_backend.explore.dto.*;
import com.heattrip.heat_trip_backend.explore.entity.*;

import java.util.Collections;
import java.util.List;

public class EmotionMapper {

  private static final ObjectMapper om = new ObjectMapper();

  // place_features 엔티티 → DTO (snake_case 맞춰서 세팅)
  public static PlaceFeaturesDto toDto(PlaceFeaturesEntity e) {
    if (e == null) return null;
    return PlaceFeaturesDto.builder()
        .sociality(e.getSociality())
        .spirituality(e.getSpirituality())
        .adventure(e.getAdventure())
        .culture(e.getCulture())
        .nature_healing(e.getNatureHealing())
        .quiet(e.getQuiet())
        .n_reviews(e.getNReviews())
        .n_blogs(e.getNBlogs())
        .conf_sociality(e.getConfSociality())
        .conf_spirituality(e.getConfSpirituality())
        .conf_adventure(e.getConfAdventure())
        .conf_culture(e.getConfCulture())
        .conf_nature_healing(e.getConfNatureHealing())
        .conf_quiet(e.getConfQuiet())
        .method_ver(e.getMethodVer())
        .updated_at(e.getUpdatedAt())
        .build();
  }

  // emotion_reviews 엔티티 → DTO
  public static EmotionalReviewDto toDto(EmotionReviewEntity e) {
    if (e == null) return null;
    List<String> images;
    try {
      images = e.getImagesJson() == null ? Collections.emptyList()
          : om.readValue(e.getImagesJson(), new TypeReference<List<String>>() {});
    } catch (Exception ex) {
      images = Collections.emptyList();
    }

    return EmotionalReviewDto.builder()
        .id(String.valueOf(e.getId()))
        .author(e.getAuthor())
        .date(e.getReviewDate())
        .beforeEmotion(e.getBeforeEmotion())
        .afterEmotion(e.getAfterEmotion())
        .emotionalChange(EmotionalChangeDto.builder()
            .valence(e.getDeltaValence())
            .arousal(e.getDeltaArousal())
            .dominance(e.getDeltaDominance())
            .build())
        .content(e.getContent())
        .helpfulCount(e.getHelpfulCount())
        .images(images)
        .build();
  }

  // FeedbackRequestDto → EmotionFeedbackEntity (JSON 직렬화 포함)
  public static EmotionFeedbackEntity toEntity(Long contentId, FeedbackRequestDto req) {
    EmotionFeedbackEntity en = new EmotionFeedbackEntity();
    en.setContentId(contentId);
    en.setBeforeEmotion(req.getBeforeEmotion());
    en.setAfterEmotion(req.getAfterEmotion());
    try {
      en.setFeatureRatingsJson(om.writeValueAsString(req.getFeatureRatings()));
    } catch (Exception ex) {
      en.setFeatureRatingsJson("{}");
    }
    en.setContent(req.getContent());
    en.setClientTimestamp(req.getTimestamp());
    return en;
  }
}
