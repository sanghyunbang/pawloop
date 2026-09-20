package com.heattrip.heat_trip_backend.community.repository;

import com.heattrip.heat_trip_backend.community.entity.Post;

import org.springframework.data.domain.Limit;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.LocalDateTime;
import java.util.List;

/**
 * 글 조회. 커서 페이지네이션은 {@code WalkRepository} 와 같은 모양이다 — 이슈 #170.
 *
 * <h2>{@code join fetch u} 가 이 쿼리의 요점이다</h2>
 * <p>{@code Post.user} 가 {@code LAZY} 라, 안 당겨 오면 응답을 만들 때 글마다 사용자 한 번씩
 * <b>N+1</b> 이 난다. {@code left join fetch} 인 것은 <b>탈퇴한 사람의 글도 목록에 나와야</b>
 * 하기 때문이다 — {@code user} 가 {@code null} 이면 inner join 이 그 행을 통째로 버린다.
 */
public interface PostRepository extends JpaRepository<Post, Long> {

    /**
     * 목록 첫 장. 정렬은 {@code (createdAt, id)} 내림차순이다 — 커서가 그 두 축으로 비교한다.
     *
     * <p>{@code board} 가 {@code null} 이면 전체다. 선택 필터를
     * {@code (:param is null or 컬럼 = :param)} 로 쓰는 것이 이 저장소의 모양이다.
     *
     * <p>{@code sgg} 는 <b>시군구 앞 다섯 자리</b>다 — "우리 동네"(#342). {@code null} 이면
     * 전국이다. 앞자리 {@code like} 라 {@code idx_users_neighborhood} 의 범위를 탄다.
     * <b>동네를 안 고른 사람의 글은 안 나온다</b>({@code is not null}) — 그게 없으면
     * {@code like} 가 {@code null} 에 대해 unknown 이라 결과가 조용히 비거나 섞인다.
     */
    @Query("""
            select p from Post p
              left join fetch p.user u
              left join fetch p.dog d
             where (:board is null or p.board = :board)
               and (:sgg is null
                    or (u.neighborhoodCode is not null
                        and u.neighborhoodCode like concat(:sgg, '%')))
               and (:dogId is null or d.id = :dogId)
               and (:contentId is null or p.contentId = :contentId)
             order by p.createdAt desc, p.id desc
            """)
    List<Post> findPage(@Param("board") String board,
                        @Param("sgg") String sgg,
                        @Param("dogId") Long dogId,
                        @Param("contentId") String contentId,
                        Limit limit);

    /**
     * 다음 장. <b>커서보다 엄격히 뒤인 것만</b> 준다.
     *
     * <p>{@code createdAt} 이 같은 두 행이 있을 수 있어서 {@code id} 로 한 번 더 가른다.
     * 그게 없으면 같은 시각의 행들이 장 경계에서 중복되거나 건너뛰어진다.
     */
    @Query("""
            select p from Post p
              left join fetch p.user u
              left join fetch p.dog d
             where (:board is null or p.board = :board)
               and (:sgg is null
                    or (u.neighborhoodCode is not null
                        and u.neighborhoodCode like concat(:sgg, '%')))
               and (:dogId is null or d.id = :dogId)
               and (:contentId is null or p.contentId = :contentId)
               and (p.createdAt < :cursorAt
                    or (p.createdAt = :cursorAt and p.id < :cursorId))
             order by p.createdAt desc, p.id desc
            """)
    List<Post> findPageAfter(@Param("board") String board,
                             @Param("sgg") String sgg,
                             @Param("dogId") Long dogId,
                             @Param("contentId") String contentId,
                             @Param("cursorAt") LocalDateTime cursorAt,
                             @Param("cursorId") long cursorId,
                             Limit limit);

    /** 상세. 목록과 같은 이유로 사용자를 함께 당긴다. */
    @Query("""
            select p from Post p
              left join fetch p.user u
              left join fetch p.dog d
             where p.id = :id
            """)
    java.util.Optional<Post> findDetail(@Param("id") long id);
}
