// service/ExploreEmotionService.java
package com.heattrip.heat_trip_backend.explore.service;

import com.heattrip.heat_trip_backend.explore.dto.*;
import com.heattrip.heat_trip_backend.explore.entity.*;
import com.heattrip.heat_trip_backend.explore.mapper.EmotionMapper;
import com.heattrip.heat_trip_backend.explore.repository.*;
import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;

import static java.util.stream.Collectors.toList;

@Service
@RequiredArgsConstructor
@Transactional(readOnly = true)
public class ExploreEmotionService {

  private final PlaceFeaturesRepository featuresRepo;
  private final EmotionReviewRepository reviewRepo;
  private final EmotionFeedbackRepository feedbackRepo;

  public PlaceFeaturesDto getFeatures(Long contentId) {
    PlaceFeaturesEntity e = featuresRepo.findById(contentId) // link_id = contentId (①)
        .orElse(null);
    return EmotionMapper.toDto(e);
  }

  public List<EmotionalReviewDto> getReviews(Long contentId) {
    return reviewRepo.findByContentIdOrderByReviewDateDesc(contentId)
        .stream().map(EmotionMapper::toDto).collect(toList());
  }

  @Transactional
  public FeedbackResponseDto submitFeedback(Long contentId, FeedbackRequestDto req) {
    EmotionFeedbackEntity saved = feedbackRepo.save(EmotionMapper.toEntity(contentId, req));
    return FeedbackResponseDto.builder().id(saved.getId()).build();
  }
}
