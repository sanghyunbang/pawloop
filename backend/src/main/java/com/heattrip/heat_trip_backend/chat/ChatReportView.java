package com.heattrip.heat_trip_backend.chat;

import java.time.LocalDateTime;
import java.util.List;

/**
 * 신고 한 건을 {@code chat} 밖으로 내보내는 모양 — 이슈 #82.
 *
 * <h2>신고자가 없다</h2>
 * <p>{@code reporterUserId} 를 <b>일부러 넣지 않았다.</b> 저장은 하지만 밖으로 내보내는
 * 모양에는 넣지 않는다 — 이 record 에 필드가 없으면 어떤 응답도 그것을 실을 수 없다.
 * 문서로 "싣지 마세요" 라고 적는 것과 <b>실을 수 없게 만드는 것</b>은 다르다
 * (#82 완료 조건 2).
 *
 * <p>왓츠앱·카카오·라인·디스코드 넷이 전부 신고자 익명을 문서에 명시한다.
 *
 * @param contextFromSeq 고른 메시지 앞 5개까지 내려간 {@code room_seq}. 그 구간의 메시지를
 *                       베끼지는 않는다 — 원본이 지워지면 맥락은 실제로 못 읽고 "어디를
 *                       봐야 하는가" 만 남는다({@code ChatReport} javadoc)
 * @param reason         분류. {@code ChatReportReason} 의 값이고 소문자 문자열이다 —
 *                       enum 자체를 안 내보내는 것은 이게 그대로 계약의 wire 값이라서다
 * @param memo           신고자가 덧붙인 말. 없으면 {@code null}
 */
public record ChatReportView(
        long id,
        long reportedUserId,
        long roomId,
        long contextFromSeq,
        long contextToSeq,
        String reason,
        String memo,
        LocalDateTime createdAt,
        List<ChatReportedMessageView> messages) {
}
