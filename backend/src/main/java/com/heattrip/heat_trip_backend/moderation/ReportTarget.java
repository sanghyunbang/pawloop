package com.heattrip.heat_trip_backend.moderation;

/**
 * 무엇을 신고했나 — {@code report.target_type} 과 {@code target_id}.
 *
 * <p>이 축이 있어야 채팅 신고를 합치는 것이 재설계가 아니라 {@code INSERT ... SELECT} 다
 * (ADR-0016). 지금 값 둘은 커뮤니티 것이고, 감정 카드와 채팅 메시지가 뒤따른다.
 *
 * <p>{@code targetId} 로 FK 를 걸지 않는다 — <b>원본이 지워져도 신고는 남아야 한다.</b>
 * 그래서 스냅샷이 본문까지 벤다.
 */
public record ReportTarget(Type type, long id) {

    public enum Type {
        COMMUNITY_POST,
        COMMUNITY_COMMENT;

        /** DB 와 계약에 쓰는 문자열. */
        public String wireValue() {
            return name().toLowerCase(java.util.Locale.ROOT);
        }
    }

    public static ReportTarget post(long postId) {
        return new ReportTarget(Type.COMMUNITY_POST, postId);
    }

    public static ReportTarget comment(long commentId) {
        return new ReportTarget(Type.COMMUNITY_COMMENT, commentId);
    }
}
