package com.heattrip.heat_trip_backend.community;

import java.time.Instant;
import java.util.Optional;

/**
 * 운영자가 신고된 글·댓글을 지운다 — 이슈 #718. {@code moderationweb} 의 운영자 경로만 부른다.
 *
 * <h2>작성자 삭제와 같은 길을 탄다</h2>
 * <p>지우는 일 자체는 작성자가 자기 글을 지울 때와 <b>같은 코드</b>다 — 붙은 사진·영상을 떼고(행은 트랜잭션 안에서,
 * 저장소의 파일은 커밋 뒤에) 글을 지우면 댓글·반응·저장이 DB 의 {@code ON DELETE CASCADE} 로 함께 사라진다.
 * 다른 것은 <b>작성자 확인을 건너뛴다</b>는 것 하나다. 그래서 탈퇴한 사람의 글(작성자가 비어 아무도 못 지우던 글)도
 * 지울 수 있다.
 *
 * <h2>지우기 직전의 사본을 돌려준다</h2>
 * <p>신고의 사본은 <b>신고한 때</b>의 글이고, 글은 그 뒤에 고쳐질 수 있다. 무엇을 지웠는지는 지우는 순간의 글로
 * 남겨야 하므로, 지우기 전에 읽은 그대로를 {@link Removed} 로 돌려준다. 남기는 일은 부르는 쪽(조치 기록)이 한다.
 *
 * <p>없는 글·댓글이면 빈 값이다 — 이미 지워졌다는 뜻이고, 오류가 아니다.
 */
public interface CommunityTakedown {

    /** 글을 지운다. 이미 없으면 빈 값. */
    Optional<Removed> removePost(long postId);

    /** 댓글을 지운다. 이미 없으면 빈 값. */
    Optional<Removed> removeComment(long commentId);

    /**
     * 지우기 직전의 글·댓글.
     *
     * @param targetType   {@code community_post} · {@code community_comment} — 신고 사본과 같은 낱말
     * @param targetId     글·댓글 id
     * @param authorUserId 쓴 사람(탈퇴했으면 {@code null})
     * @param authorName   그때의 닉네임(탈퇴했으면 {@code null})
     * @param title        글 제목(댓글이면 {@code null})
     * @param body         본문
     * @param occurredAt   원본이 쓰인 시각(UTC)
     */
    record Removed(String targetType, long targetId, Long authorUserId, String authorName,
                   String title, String body, Instant occurredAt) {
    }
}
