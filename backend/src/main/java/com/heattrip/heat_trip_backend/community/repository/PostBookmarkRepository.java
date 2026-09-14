package com.heattrip.heat_trip_backend.community.repository;

import com.heattrip.heat_trip_backend.community.entity.PostBookmark;

import org.springframework.data.domain.Limit;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.LocalDateTime;
import java.util.List;
import java.util.Set;

/** 글 저장 조회·저장 — 이슈 #451 4번. 모양은 {@link ReactionRepository} 와 같다. */
public interface PostBookmarkRepository extends JpaRepository<PostBookmark, Long> {

    /**
     * 목록 한 장의 글 중 <b>내가 저장한 것</b>의 글 id. 한 번에 묻는다(N+1 방지) — 글마다
     * 물으면 20건 조회에 쿼리가 21개다.
     */
    @Query("""
            select b.post.id from PostBookmark b
             where b.user.id = :userId and b.post.id in :ids
            """)
    Set<Long> findPostIdsIn(@Param("userId") long userId, @Param("ids") List<Long> ids);

    /**
     * <b>한 문장으로 끝나는 멱등 삽입.</b> 이미 있으면 아무것도 안 하고 0행이다.
     * {@code saveAndFlush} + 예외 삼키기가 왜 안 되는지는 {@link ReactionRepository#insertIfAbsent}.
     */
    @Modifying
    @Query(value = """
            insert into post_bookmark (post_id, user_id, created_at)
            values (:postId, :userId, :createdAt)
            on duplicate key update id = id
            """, nativeQuery = true)
    int insertIfAbsent(@Param("postId") long postId,
                       @Param("userId") long userId,
                       @Param("createdAt") LocalDateTime createdAt);

    /** <b>한 문장으로 끝나는 멱등 삭제.</b> 없으면 0행이고 그것도 성공이다. */
    @Modifying
    @Query("""
            delete from PostBookmark b
             where b.post.id = :postId and b.user.id = :userId
            """)
    int deleteIfPresent(@Param("postId") long postId, @Param("userId") long userId);

    /**
     * 저장한 글 첫 장. 정렬은 <b>저장한 시각</b> {@code (createdAt, id)} 내림차순이다 — 글이
     * 쓰인 순이 아니다. 글과 글쓴이를 함께 당긴다(목록과 같은 이유, 탈퇴한 글쓴이의 글도
     * 살아남게 {@code left join}).
     */
    @Query("""
            select b from PostBookmark b
              join fetch b.post p
              left join fetch p.user u
             where b.user.id = :userId
             order by b.createdAt desc, b.id desc
            """)
    List<PostBookmark> findPage(@Param("userId") long userId, Limit limit);

    /** 다음 장. 커서보다 엄격히 뒤인 것만 — {@link PostRepository#findPageAfter} 와 같은 규칙. */
    @Query("""
            select b from PostBookmark b
              join fetch b.post p
              left join fetch p.user u
             where b.user.id = :userId
               and (b.createdAt < :cursorAt
                    or (b.createdAt = :cursorAt and b.id < :cursorId))
             order by b.createdAt desc, b.id desc
            """)
    List<PostBookmark> findPageAfter(@Param("userId") long userId,
                                     @Param("cursorAt") LocalDateTime cursorAt,
                                     @Param("cursorId") long cursorId,
                                     Limit limit);
}
