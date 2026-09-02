package com.heattrip.heat_trip_backend.community.repository;

import com.heattrip.heat_trip_backend.community.entity.Comment;

import org.springframework.data.domain.Limit;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.LocalDateTime;
import java.util.List;

/** 댓글 조회. 이슈 #170. */
public interface CommentRepository extends JpaRepository<Comment, Long> {

    /**
     * 댓글 목록 첫 장. 글 목록과 <b>정렬 방향이 반대다</b> — 댓글은 오래된 것부터 읽는다.
     * 커서 비교도 그래서 {@code >} 다.
     */
    @Query("""
            select c from Comment c
              left join fetch c.user u
             where c.post.id = :postId
             order by c.createdAt asc, c.id asc
            """)
    List<Comment> findPage(@Param("postId") long postId, Limit limit);

    @Query("""
            select c from Comment c
              left join fetch c.user u
             where c.post.id = :postId
               and (c.createdAt > :cursorAt
                    or (c.createdAt = :cursorAt and c.id > :cursorId))
             order by c.createdAt asc, c.id asc
            """)
    List<Comment> findPageAfter(@Param("postId") long postId,
                                @Param("cursorAt") LocalDateTime cursorAt,
                                @Param("cursorId") long cursorId,
                                Limit limit);

    /**
     * 글 목록 한 장에 해당하는 글들의 댓글 수를 <b>한 번에</b> 집계한다(N+1 방지).
     *
     * <p>각 행은 {@code [postId(Long), count(Long)]} 이다. {@code SocialService} 의
     * {@code countByCardIdInGroupBy} 와 같은 모양이고, 거기서 이미 피해 둔 함정이다.
     */
    @Query("select c.post.id, count(c) from Comment c where c.post.id in :ids group by c.post.id")
    List<Object[]> countByPostIdInGroupBy(@Param("ids") List<Long> ids);
}
