package com.heattrip.heat_trip_backend.community.repository;

import com.heattrip.heat_trip_backend.community.entity.Reaction;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.LocalDateTime;
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

    /** 멱등 판정 — 이미 눌렀는지 본다. 응답의 {@code mine} 을 만드는 데 쓴다. */
    @Query("""
            select r from Reaction r
             where r.post.id = :postId and r.user.id = :userId and r.type = :type
            """)
    Optional<Reaction> findOne(@Param("postId") long postId,
                               @Param("userId") long userId,
                               @Param("type") String type);

    /**
     * <b>한 문장으로 끝나는 멱등 삽입.</b> 이미 있으면 아무것도 안 하고 0행을 돌려준다.
     *
     * <h2>왜 JPA {@code save} + 예외 삼키기가 아닌가</h2>
     * <p>#170 은 {@code saveAndFlush} 를 하고 {@code DataIntegrityViolationException} 을
     * 삼켰다. <b>그건 멱등이 아니다.</b> 제약 위반이 나는 순간 Hibernate 가 그 트랜잭션을
     * <b>rollback-only</b> 로 표시하고, 예외를 잡아도 그 표시는 안 지워진다. 이어지는 집계
     * 쿼리가 죽거나, 살아남아도 커밋에서 {@code UnexpectedRollbackException} 이 나서 결국
     * <b>500</b> 이다 — "이미 눌렀어도 200" 이라고 적어 둔 약속이 동시 요청에서만 거짓이 된다.
     *
     * <p>{@code ON DUPLICATE KEY UPDATE id = id} 는 아무 행도 안 바꾸는 no-op 이다.
     * {@code INSERT IGNORE} 를 안 쓴 이유는 그것이 FK 위반 같은 <b>다른</b> 오류까지 삼켜서,
     * 없는 글에 반응이 조용히 무시되기 때문이다. 여기서는 중복 키만 넘긴다.
     *
     * <p>선조회를 없애지는 않았다({@code findOne}). 있으면 쿼리 하나를 아끼는 흔한 경로가
     * 빨라지고, 없으면 이 문장이 마지막 방어선이다.
     */
    @Modifying
    @Query(value = """
            insert into reaction (post_id, user_id, type, created_at)
            values (:postId, :userId, :type, :createdAt)
            on duplicate key update id = id
            """, nativeQuery = true)
    int insertIfAbsent(@Param("postId") long postId,
                       @Param("userId") long userId,
                       @Param("type") String type,
                       @Param("createdAt") LocalDateTime createdAt);

    /**
     * <b>한 문장으로 끝나는 멱등 삭제.</b> 없으면 0행이고 그것도 성공이다.
     *
     * <p>#170 은 조회 후 엔티티를 {@code delete} 했다. 동시에 두 번 취소하면 진 쪽의
     * {@code DELETE ... WHERE id = ?} 가 0행이 되고, Hibernate 는 그것을
     * {@code StaleStateException} 으로 올린다 — 역시 <b>500</b> 이다.
     */
    @Modifying
    @Query("""
            delete from Reaction r
             where r.post.id = :postId and r.user.id = :userId and r.type = :type
            """)
    int deleteIfPresent(@Param("postId") long postId,
                        @Param("userId") long userId,
                        @Param("type") String type);
}
