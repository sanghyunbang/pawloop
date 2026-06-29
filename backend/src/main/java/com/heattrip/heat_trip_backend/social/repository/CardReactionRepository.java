package com.heattrip.heat_trip_backend.social.repository;

import com.heattrip.heat_trip_backend.social.entity.CardReaction;
import org.springframework.data.jpa.repository.JpaRepository;

import java.util.List;
import java.util.Optional;

public interface CardReactionRepository extends JpaRepository<CardReaction, Long> {

    /** 피드 한 페이지에 해당하는 카드들의 모든 리액션을 한 번에 로드(N+1 방지). */
    List<CardReaction> findByCardIdIn(List<Long> cardIds);

    /** 토글 시 (cardId, userId, type) 단건 조회. */
    Optional<CardReaction> findByCardIdAndUserIdAndReactionType(Long cardId, Long userId, String reactionType);

    /** 단일 카드의 모든 리액션(토글 후 카운트 재계산용). */
    List<CardReaction> findByCardId(Long cardId);
}
