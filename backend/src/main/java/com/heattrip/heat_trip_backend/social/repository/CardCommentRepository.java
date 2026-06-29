package com.heattrip.heat_trip_backend.social.repository;

import com.heattrip.heat_trip_backend.social.entity.CardComment;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.List;

public interface CardCommentRepository extends JpaRepository<CardComment, Long> {

    /** 단일 카드의 댓글 목록(오래된 순). */
    List<CardComment> findByCardIdOrderByIdAsc(Long cardId);

    /** 단일 카드의 댓글 수. */
    long countByCardId(Long cardId);

    /**
     * 피드 한 페이지에 해당하는 카드들의 댓글 수를 한 번에 집계(N+1 방지).
     * 각 행은 [cardId(Long), count(Long)] 형태.
     */
    @Query("select c.cardId, count(c) from CardComment c where c.cardId in :ids group by c.cardId")
    List<Object[]> countByCardIdInGroupBy(@Param("ids") List<Long> ids);
}
