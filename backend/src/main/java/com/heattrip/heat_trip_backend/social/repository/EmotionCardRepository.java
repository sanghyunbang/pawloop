package com.heattrip.heat_trip_backend.social.repository;

import com.heattrip.heat_trip_backend.social.entity.EmotionCard;
import org.springframework.data.domain.Pageable;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;

public interface EmotionCardRepository extends JpaRepository<EmotionCard, Long> {

    /** 최신순 카드 페이지 조회. */
    List<EmotionCard> findAllByOrderByIdDesc(Pageable pageable);
}
