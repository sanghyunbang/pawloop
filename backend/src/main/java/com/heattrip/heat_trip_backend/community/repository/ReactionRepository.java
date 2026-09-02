package com.heattrip.heat_trip_backend.community.repository;

import com.heattrip.heat_trip_backend.community.entity.Reaction;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.util.List;
import java.util.Optional;

/** 반응 조회·저장. 이슈 #170, ADR-0016 결정 2. */
public interface ReactionRepository extends JpaRepository<Reaction, Long> {

    /**
     * 글 목록 한 장에 해당하는 글들의 <b>모든 반응</b>을 한 번에 로드한다(N+1 방지).
     *
     * <p>집계와 "내가 누른 것" 을 <b>같은 결과에서</b> 만든다 — 따로 물으면 쿼리가 둘이 되고,
     * 그 사이에 값이 바뀌면 카운트와 {@code mine} 이 어긋난다.
     *
     * <p>{@code user} 를 당기지 않는다 — 필요한 것이 {@code user.id} 뿐이고 그건 FK 컬럼이라
     * 프록시만으로 읽힌다.
     */
    @Query("select r from Reaction r where r.post.id in :ids")
    List<Reaction> findByPostIdIn(@Param("ids") List<Long> ids);

    /** 상세 한 건의 반응. 목록과 같은 조립을 한 글에 대해 한다. */
    @Query("select r from Reaction r where r.post.id = :postId")
    List<Reaction> findByPostId(@Param("postId") long postId);

    /** 멱등 판정 — 이미 눌렀는지 본다. */
    @Query("""
            select r from Reaction r
             where r.post.id = :postId and r.user.id = :userId and r.type = :type
            """)
    Optional<Reaction> findOne(@Param("postId") long postId,
                               @Param("userId") long userId,
                               @Param("type") String type);
}
