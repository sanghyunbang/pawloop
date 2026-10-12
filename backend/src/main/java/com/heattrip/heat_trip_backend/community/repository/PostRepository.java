package com.heattrip.heat_trip_backend.community.repository;

import com.heattrip.heat_trip_backend.community.entity.Post;

import org.springframework.data.domain.Limit;
import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.LocalDateTime;
import java.util.Collection;
import java.util.List;

/**
 * 글 조회. 커서 페이지네이션은 {@code WalkRepository} 와 같은 모양이다 — 이슈 #170.
 *
 * <h2>{@code join fetch u} 가 이 쿼리의 요점이다</h2>
 * <p>{@code Post.user} 가 {@code LAZY} 라, 안 당겨 오면 응답을 만들 때 글마다 사용자 한 번씩
 * <b>N+1</b> 이 난다. {@code left join fetch} 인 것은 <b>탈퇴한 사람의 글도 목록에 나와야</b>
 * 하기 때문이다 — {@code user} 가 {@code null} 이면 inner join 이 그 행을 통째로 버린다.
 *
 * <h2>차단한 사람의 글은 쿼리가 뺀다 — 애플 지침 1.2</h2>
 * <p>{@code excludedAuthorIds} 는 <b>보는 사람이 차단한 사람들</b>이다. 1.2 가 "차단한 사람의 콘텐츠는
 * 피드에서 즉시 사라져야 한다" 고 요구한다. 예전에는 빼지 않고 {@code hiddenByBlock} 만 붙여 화면이
 * 접게 했다 — 그 이유였던 "가린 자리의 보기" 가 1.2 로 없어졌다.
 *
 * <p><b>응답을 만든 뒤에 거르지 않고 쿼리에서 뺀다.</b> 장을 읽은 뒤 자바에서 거르면 20건을 달라는
 * 장이 13건이나 0건으로 오고, 0건인데 {@code hasMore} 가 참인 장을 앱이 "글이 없다" 로 그린다.
 * 쿼리에서 빼면 장은 늘 꽉 차고, 커서는 돌려준 마지막 줄에서 이어지므로 경계도 그대로다.
 *
 * <p><b>비어 있어도 된다</b> — 게스트와 아무도 차단하지 않은 사람이 그렇다. Hibernate 6.6 은 빈 컬렉션의
 * {@code not in} 을 {@code 1=1} 로 그린다({@code AbstractSqlAstTranslator.visitInListPredicate}). 그래서
 * MySQL 이 문법 오류로 받는 {@code not in ()} 이 나가지 않는다. 아무도 안 걸리는 값을 채워 넣는 방법도
 * 있지만, 빈 집합을 그대로 넘겨 보니 커뮤니티 검사 61건이 그대로 초록이었다 — 그리고 모든 게스트 요청이
 * 이 길을 지나므로 그 동작이 바뀌는 날 그 검사들이 한꺼번에 빨개진다.
 *
 * <p>{@code u.id is null} 은 탈퇴한 사람의 글이다. 탈퇴하면 {@code post.user_id} 가 비워져
 * ({@code ON DELETE SET NULL}) 누구의 글이었는지 알 수 없으므로 거를 근거가 없다 — 예전
 * {@code hiddenByBlock} 도 같은 이유로 그 글에는 거짓이었다. 이 줄이 없으면 {@code not in} 이
 * {@code null} 에 대해 unknown 이라 탈퇴한 사람의 글이 <b>모든 사람의</b> 목록에서 사라진다.
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
               and (u.id is null or u.id not in :excludedAuthorIds)
             order by p.createdAt desc, p.id desc
            """)
    List<Post> findPage(@Param("board") String board,
                        @Param("sgg") String sgg,
                        @Param("dogId") Long dogId,
                        @Param("contentId") String contentId,
                        @Param("excludedAuthorIds") Collection<Long> excludedAuthorIds,
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
               and (u.id is null or u.id not in :excludedAuthorIds)
               and (p.createdAt < :cursorAt
                    or (p.createdAt = :cursorAt and p.id < :cursorId))
             order by p.createdAt desc, p.id desc
            """)
    List<Post> findPageAfter(@Param("board") String board,
                             @Param("sgg") String sgg,
                             @Param("dogId") Long dogId,
                             @Param("contentId") String contentId,
                             @Param("excludedAuthorIds") Collection<Long> excludedAuthorIds,
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

    /** 장소를 골라 쓴 글의 id 전부 — 머리의 "글 N · 사진 N"(#729). 사진은 이 id 들에 붙은 것을 센다. */
    @Query("select p.id from Post p where p.contentId = :contentId")
    List<Long> idsByPlace(@Param("contentId") String contentId);
}
