package com.heattrip.heat_trip_backend.chat.repository;

import com.heattrip.heat_trip_backend.chat.entity.ChatMessageReaction;

import org.springframework.data.jpa.repository.JpaRepository;
import org.springframework.data.jpa.repository.Modifying;
import org.springframework.data.jpa.repository.Query;
import org.springframework.data.repository.query.Param;

import java.time.LocalDateTime;
import java.util.Collection;
import java.util.List;

/**
 * 반응 저장·조회 — #452, ADR-0023(#500) 셋째 줄.
 *
 * <h2>켜기·끄기는 <b>한 문장으로</b> 끝난다</h2>
 * <p>커뮤니티 {@code ReactionRepository} 가 실측으로 배운 것을 그대로 쓴다. {@code saveAndFlush}
 * 하고 {@code DataIntegrityViolationException} 을 삼키는 판은 <b>멱등이 아니다</b> — 제약 위반이
 * 나는 순간 Hibernate 가 그 트랜잭션을 rollback-only 로 표시하고, 예외를 잡아도 표시는 안 지워져
 * 커밋에서 {@code UnexpectedRollbackException} 이 난다. "두 번 눌러도 200" 이라는 약속이
 * <b>동시 요청에서만</b> 거짓이 된다.
 *
 * <p>지우는 쪽도 같다. 엔티티를 읽어 {@code delete} 하면 동시에 두 번 취소했을 때 진 쪽의
 * {@code DELETE ... WHERE id = ?} 가 0행이 되고 Hibernate 가 {@code StaleStateException} 을 올린다.
 */
public interface ChatMessageReactionRepository extends JpaRepository<ChatMessageReaction, Long> {

    /**
     * 이 말들에 붙은 <b>모든</b> 반응 — 한 장에 한 번. 집계와 "내가 누른 것" 을 <b>같은 결과</b>에서
     * 만든다: 따로 물으면 쿼리가 둘이 되고 그 사이에 값이 바뀌면 카운트와 {@code mine} 이 어긋난다.
     *
     * <p>{@code uq_chat_reaction} 의 왼쪽 접두가 {@code message_id} 라 이 조회가 그 인덱스를 쓴다 —
     * 집계 전용 인덱스를 따로 두지 않는 이유다.
     *
     * <p>{@code message} 를 당기지 않는다({@code select r} 이지만 {@code LAZY} 라 프록시다) —
     * 필요한 것은 {@code message.id} 뿐이고 그건 FK 컬럼이라 프록시만으로 읽힌다.
     */
    @Query("select r from ChatMessageReaction r where r.message.id in :messageIds")
    List<ChatMessageReaction> findByMessageIdIn(@Param("messageIds") Collection<Long> messageIds);

    /**
     * <b>한 문장으로 끝나는 멱등 삽입.</b> 이미 눌러 뒀으면 아무것도 안 하고 0행을 돌려준다.
     *
     * <p>{@code ON DUPLICATE KEY UPDATE id = id} 는 아무 행도 안 바꾸는 no-op 이다.
     * {@code INSERT IGNORE} 를 안 쓴 이유는 그것이 FK 위반 같은 <b>다른</b> 오류까지 삼켜서
     * 없는 말에 누른 반응이 조용히 무시되기 때문이다 — 여기서는 중복 키만 넘긴다.
     *
     * @return 1 이면 새로 눌렀고, 0 이면 이미 눌러 둔 것이다
     */
    @Modifying
    @Query(value = """
            insert into chat_message_reaction (message_id, user_id, kind, created_at)
            values (:messageId, :userId, :kind, :createdAt)
            on duplicate key update id = id
            """, nativeQuery = true)
    int insertIfAbsent(@Param("messageId") long messageId,
                       @Param("userId") long userId,
                       @Param("kind") String kind,
                       @Param("createdAt") LocalDateTime createdAt);

    /**
     * <b>한 문장으로 끝나는 멱등 삭제.</b> 안 눌렀던 것을 취소해도 0행이고 그것도 성공이다.
     *
     * @return 1 이면 실제로 지웠고, 0 이면 없던 것이다
     */
    @Modifying
    @Query("""
            delete from ChatMessageReaction r
             where r.message.id = :messageId and r.userId = :userId and r.kind = :kind
            """)
    int deleteIfPresent(@Param("messageId") long messageId,
                        @Param("userId") long userId,
                        @Param("kind") String kind);

    /**
     * 이 말의 반응을 전부 지운다 — 소프트 삭제가 부른다.
     *
     * <p>FK 의 {@code CASCADE} 는 행을 하드 삭제할 때만 도는데, 우리 삭제는 톰스톤이라 행이 남는다
     * ({@code ChatRoomService#deleteMessage}). 지운 말 밑에 반응이 남으면 지운 사람에게는 지워지지
     * 않은 것이나 같다.
     */
    @Modifying
    @Query("delete from ChatMessageReaction r where r.message.id = :messageId")
    int deleteByMessageId(@Param("messageId") long messageId);
}
