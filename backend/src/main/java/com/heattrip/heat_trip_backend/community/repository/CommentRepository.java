package com.heattrip.heat_trip_backend.community.repository;

import com.heattrip.heat_trip_backend.community.entity.Comment;

import org.springframework.data.domain.Limit;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.LocalDateTime;
import java.util.Collection;
import java.util.List;

/**
 * 댓글 조회. 이슈 #170.
 *
 * <h2>차단한 사람의 댓글은 쿼리가 뺀다 — 애플 지침 1.2</h2>
 * <p>{@link PostRepository} 의 글 목록과 같은 규칙이다. {@code excludedAuthorIds} 는 보는 사람이 차단한
 * 사람들이고, 비어 있어도 된다({@link PostRepository} javadoc). 댓글 수도 같은 사람을
 * 빼고 센다 — 목록에서는 뺐는데 수에는 남기면 "댓글 3" 을 보고 들어가 둘만 보게 된다.
 */
public interface CommentRepository extends JpaRepository<Comment, Long> {

    /**
     * 댓글 목록 첫 장. 글 목록과 <b>정렬 방향이 반대다</b> — 댓글은 오래된 것부터 읽는다.
     * 커서 비교도 그래서 {@code >} 다.
     */
    @Query("""
            select c from Comment c
              left join fetch c.user u
             where c.post.id = :postId
               and (u.id is null or u.id not in :excludedAuthorIds)
             order by c.createdAt asc, c.id asc
            """)
    List<Comment> findPage(@Param("postId") long postId,
                           @Param("excludedAuthorIds") Collection<Long> excludedAuthorIds,
                           Limit limit);

    @Query("""
            select c from Comment c
              left join fetch c.user u
             where c.post.id = :postId
               and (u.id is null or u.id not in :excludedAuthorIds)
               and (c.createdAt > :cursorAt
                    or (c.createdAt = :cursorAt and c.id > :cursorId))
             order by c.createdAt asc, c.id asc
            """)
    List<Comment> findPageAfter(@Param("postId") long postId,
                                @Param("excludedAuthorIds") Collection<Long> excludedAuthorIds,
                                @Param("cursorAt") LocalDateTime cursorAt,
                                @Param("cursorId") long cursorId,
                                Limit limit);

    /**
     * 글 목록 한 장에 해당하는 글들의 댓글 수를 <b>한 번에</b> 집계한다(N+1 방지).
     *
     * <p>각 행은 {@code [postId(Long), count(Long)]} 이다. {@code SocialService} 의
     * {@code countByCardIdInGroupBy} 와 같은 모양이고, 거기서 이미 피해 둔 함정이다.
     */
    @Query("""
            select c.post.id, count(c) from Comment c
             where c.post.id in :ids
               and (c.user is null or c.user.id not in :excludedAuthorIds)
             group by c.post.id
            """)
    List<Object[]> countByPostIdInGroupBy(@Param("ids") List<Long> ids,
                                          @Param("excludedAuthorIds") Collection<Long> excludedAuthorIds);
}
