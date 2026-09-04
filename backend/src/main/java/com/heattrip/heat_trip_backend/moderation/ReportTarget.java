package com.heattrip.heat_trip_backend.moderation;

import java.util.Locale;

/**
 * 신고가 가리키는 것 하나 — 종류와 그 도메인 안의 id. 이슈 #166 · #254.
 *
 * <h2>좌표가 부모에서 자식으로 내려왔다 — 이슈 #254</h2>
 * <p>처음에는 {@code report} 부모가 이 값을 하나 들었다. 커뮤니티는 신고 한 건이 글 하나나
 * 댓글 하나를 가리키므로 그 모양이 맞았다.
 *
 * <p><b>채팅이 안 맞았다.</b> 채팅 신고는 한 건에 메시지가 <b>최대 셋</b>이다 — 부모가 좌표를
 * 하나만 들면 나머지 둘을 어디에도 못 적는다. ADR-0016 은 {@code target_type} 축이 있으면
 * 흡수가 {@code INSERT ... SELECT} 라고 적었는데, 실제로는 <b>부모↔자식 재배치</b>라 그
 * 산정이 성립하지 않았다.
 *
 * <p>그래서 좌표를 {@code report_snapshot} 으로 내렸다. 부모는 <b>"누가·누구를·왜·언제"</b>
 * 만 들고, <b>"무엇을"</b> 은 사본마다 붙는다. 커뮤니티 글 신고는 자식 한 줄, 댓글 신고는
 * 두 줄(대상 + 부모 글 맥락), 채팅 세 개 신고는 네 줄(대상 셋 + 방 좌표 맥락)이다.
 *
 * <h2>종류마다 대상 수의 상한이 다르다</h2>
 * <p>부모가 좌표를 들 때는 "정확히 하나" 가 구조로 보장됐다. 내리고 나면 그 보장이 사라지므로
 * {@link Type#maxTargets()} 이 종류별로 든다 — 커뮤니티는 1, 채팅 메시지는 3이다.
 *
 * <p>{@link Type#CHAT_ROOM} 은 <b>0 이다</b>. 방은 대상이 될 수 없고 좌표로만 쓰인다 —
 * {@code ChatReportService} 가 "가족방에서 방 전체를 신고하는 동작은 뜻이 불분명하다" 로
 * 그 모양을 명시적으로 배제했다. 그런데 방 id 없이는 {@code room_seq} 가 뜻을 못 가지므로,
 * 맥락 줄의 좌표로는 필요하다.
 */
public record ReportTarget(Type type, long id) {

    public enum Type {
        /** 커뮤니티 글. 신고 한 건에 하나. */
        COMMUNITY_POST(1),

        /** 커뮤니티 댓글. 신고 한 건에 하나. */
        COMMUNITY_COMMENT(1),

        /**
         * 채팅 메시지. <b>한 건에 셋까지.</b>
         *
         * <p>이 수는 {@code ChatLimits} 가 답하는 것과 같아야 한다 — 한쪽만 바꾸면 앱이
         * 셋을 보내는데 서버가 거절하거나, 넷을 보내는데 서버가 받는다.
         */
        CHAT_MESSAGE(3),

        /**
         * 채팅방. <b>대상이 될 수 없다(0).</b> 맥락 줄의 좌표로만 쓴다 — 방 id 가 없으면
         * {@code target_ordinal} 에 담긴 {@code room_seq} 가 어느 방의 번호인지 모른다.
         */
        CHAT_ROOM(0);

        private final int maxTargets;

        Type(int maxTargets) {
            this.maxTargets = maxTargets;
        }

        /** 신고 한 건에 이 종류가 대상으로 몇 개까지 올 수 있는가. {@code 0} 이면 못 온다. */
        public int maxTargets() {
            return maxTargets;
        }

        /** DB 에 쓰는 문자열. {@code report_snapshot.target_type} 의 CHECK 와 같은 어휘다. */
        public String wireValue() {
            return name().toLowerCase(Locale.ROOT);
        }
    }

    public static ReportTarget post(long postId) {
        return new ReportTarget(Type.COMMUNITY_POST, postId);
    }

    public static ReportTarget comment(long commentId) {
        return new ReportTarget(Type.COMMUNITY_COMMENT, commentId);
    }

    public static ReportTarget chatMessage(long messageId) {
        return new ReportTarget(Type.CHAT_MESSAGE, messageId);
    }

    public static ReportTarget chatRoom(long roomId) {
        return new ReportTarget(Type.CHAT_ROOM, roomId);
    }
}
