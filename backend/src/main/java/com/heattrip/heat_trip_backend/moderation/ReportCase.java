package com.heattrip.heat_trip_backend.moderation;

import java.time.Instant;
import java.util.List;

/**
 * 신고 한 건을 운영자가 판단할 수 있는 모양으로 — 이슈 #718.
 *
 * <p>운영자는 슬랙 알림에서 신고 번호 하나를 받는다({@code ReportAlertListener}). 알림에는 본문이 80자까지만
 * 있고 채팅은 아예 없으므로, 판단하려면 신고 시점의 사본 전부가 필요하다. {@link Reports#caseOf} 가 그것을
 * 모아 이 모양으로 준다 — 운영자 경로({@code GET /internal/moderation/reports/{id}})만 쓴다.
 *
 * <p>{@link #targets} 와 {@link #context} 를 <b>나눠서</b> 준다. 사본 표를 읽는 쿼리는 role 의 글자순으로
 * 정렬해 {@code context} 가 {@code target} 보다 먼저 온다 — 순서에 기대면 맥락 줄을 신고 대상으로 읽는다.
 *
 * @param reportId       {@code report.id}
 * @param reason         신고 사유 코드
 * @param memo           신고자가 남긴 메모(없으면 {@code null})
 * @param reporterUserId 신고한 사람
 * @param reportedUserId 신고당한 사람(탈퇴했거나 모르면 {@code null})
 * @param filedAt        신고 시각(UTC)
 * @param targets        신고 대상 줄(사본)
 * @param context        앞뒤 맥락 줄(채팅의 앞뒤 메시지 등)
 */
public record ReportCase(long reportId,
                         String reason,
                         String memo,
                         long reporterUserId,
                         Long reportedUserId,
                         Instant filedAt,
                         List<Line> targets,
                         List<Line> context) {

    /**
     * 사본 한 줄 — 신고 시점의 글·댓글·메시지. 원본이 그 뒤에 고쳐지거나 지워져도 이 줄은 그대로다.
     *
     * @param targetType    {@code community_post} · {@code community_comment} · {@code chat_message} · {@code chat_room}
     * @param targetId      대상 id
     * @param targetOrdinal 채팅 메시지의 방 안 순번(그 밖에는 {@code null})
     * @param authorUserId  쓴 사람(탈퇴했으면 {@code null})
     * @param authorName    그때의 닉네임
     * @param title         글 제목(글만)
     * @param body          본문
     * @param contentType   메시지 종류(채팅만)
     * @param occurredAt    원본이 쓰인 시각(UTC)
     */
    public record Line(String targetType,
                       long targetId,
                       Long targetOrdinal,
                       Long authorUserId,
                       String authorName,
                       String title,
                       String body,
                       String contentType,
                       Instant occurredAt) {
    }
}
