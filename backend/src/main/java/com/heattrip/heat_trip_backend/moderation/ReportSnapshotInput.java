package com.heattrip.heat_trip_backend.moderation;

import java.time.Instant;
import java.util.Locale;

/**
 * 신고 시점의 사본 한 줄 — 부르는 쪽이 만들어서 넘긴다.
 *
 * <h2>왜 부르는 쪽이 만드나</h2>
 * <p>이 모듈은 어떤 도메인도 안 부른다(package-info). 글이 무엇이고 누가 썼는지는
 * {@code community} 가 아는 것이라, 그쪽이 값으로 넘긴다. 채팅도 같다 —
 * {@code chatweb} 이 {@code chat} 에서 받은 초안을 이 모양으로 옮긴다.
 *
 * <h2>왜 본문까지 베나</h2>
 * <p><b>원본이 지워진 뒤에 읽는 기록이기 때문이다.</b> 참조만 남기면 작성자가 글을 지우는
 * 순간 운영자가 무엇을 판단해야 하는지 알 수 없다.
 *
 * <h2>좌표가 여기 있다 — 이슈 #254</h2>
 * <p>{@link #target} 은 <b>이 줄이 가리키는 것</b>이다. 예전에는 {@code report} 부모가
 * 하나 들었는데, 채팅 신고가 한 건에 메시지 셋까지라 부모로는 담기지 않았다({@link ReportTarget}).
 *
 * @param role         {@code TARGET} 이면 신고 대상, {@code CONTEXT} 면 맥락. 댓글을 신고하면
 *                     <b>부모 글을 {@code CONTEXT} 로 함께</b> 넘긴다 — 댓글 한 줄만 남으면
 *                     무슨 글에 달린 말인지 모르고, 글을 지우면 댓글이 CASCADE 로 함께
 *                     사라져 되짚을 수도 없다
 * @param target       이 줄이 가리키는 것. 맥락 줄도 좌표를 든다 — 좌표 없는 사본은
 *                     "어느 글의 무엇이었나" 를 못 말한다
 * @param targetOrdinal 그 도메인 안의 순번. 채팅은 {@code room_seq}, 커뮤니티는 {@code null} 이다.
 *                     <b>맥락 범위를 이 값으로 다시 세운다</b> — 채팅의
 *                     {@code context_from/to_seq} 는 대상들의 {@code room_seq} 와 반경
 *                     상수에서 완전히 유도되는 파생값이라 따로 안 담는다
 * @param authorUserId 그 글·댓글·메시지를 쓴 사람. 탈퇴했으면 {@code null}. 맥락 좌표 줄이면
 *                     {@code null} 이다(방에는 작성자가 없다)
 * @param authorName   신고 시점 표시 이름. 폭은 {@code users.nickname} 과 같은 255 다 —
 *                     좁히면 긴 닉네임을 가진 사람이 쓴 글을 <b>아무도 신고할 수 없다</b>
 * @param title        글이면 제목, 댓글·메시지면 {@code null}. 제목에 욕설·광고가 실린 신고가
 *                     정확히 그 자리라 본문만 베면 기록에 안 남는다
 * @param body         신고 시점 본문. <b>대상 줄은 반드시 있어야 한다</b> — 좌표만 남은
 *                     대상은 원본이 지워지면 아무것도 못 말한다. 좌표만 담는 맥락 줄
 *                     (채팅의 방)은 {@code null} 이다
 * @param contentType  본문의 종류. 채팅만 채운다({@code text} 등) — 이미지 신고와 글 신고가
 *                     구분되지 않으면 운영자가 무엇을 봐야 하는지 모른다. 커뮤니티는 {@code null}
 * @param occurredAt   그 글·댓글·메시지가 쓰인 시각. 좌표만 담는 맥락 줄은 신고 시각을 쓴다
 */
public record ReportSnapshotInput(
        Role role,
        ReportTarget target,
        Long targetOrdinal,
        Long authorUserId,
        String authorName,
        String title,
        String body,
        String contentType,
        Instant occurredAt) {

    /** 이 사본이 신고 대상인가, 그것을 읽기 위한 맥락인가. */
    public enum Role {
        TARGET,
        CONTEXT;

        /** DB 에 쓰는 문자열. */
        public String wireValue() {
            return name().toLowerCase(Locale.ROOT);
        }
    }

    /** 커뮤니티 글·댓글 한 줄. 순번도 종류도 없다. */
    public static ReportSnapshotInput target(ReportTarget target, Long authorUserId,
                                             String authorName, String title, String body,
                                             Instant occurredAt) {
        return new ReportSnapshotInput(Role.TARGET, target, null,
                authorUserId, authorName, title, body, null, occurredAt);
    }

    /** 커뮤니티 맥락 한 줄 — 댓글 신고에 딸려 오는 부모 글이다. */
    public static ReportSnapshotInput context(ReportTarget target, Long authorUserId,
                                              String authorName, String title, String body,
                                              Instant occurredAt) {
        return new ReportSnapshotInput(Role.CONTEXT, target, null,
                authorUserId, authorName, title, body, null, occurredAt);
    }

    /** 채팅 메시지 한 줄. {@code roomSeq} 가 순번이고 {@code contentType} 이 종류다. */
    public static ReportSnapshotInput chatMessage(long messageId, long roomSeq,
                                                  Long senderUserId, String senderName,
                                                  String body, String contentType,
                                                  Instant sentAt) {
        return new ReportSnapshotInput(Role.TARGET, ReportTarget.chatMessage(messageId), roomSeq,
                senderUserId, senderName, null, body, contentType, sentAt);
    }

    /**
     * 채팅방 좌표 한 줄 — <b>사본이 아니다.</b>
     *
     * <p>본문 칸이 전부 비어 있다. 신고당하지 않은 사람의 말은 한 줄도 안 베면서
     * {@code room_seq} 가 어느 방의 번호인지만 남긴다. 방이 지워져도 이 줄은 남으므로
     * "어느 방에서 있었던 일인가" 를 계속 말할 수 있다.
     */
    public static ReportSnapshotInput chatRoom(long roomId, Instant reportedAt) {
        return new ReportSnapshotInput(Role.CONTEXT, ReportTarget.chatRoom(roomId), null,
                null, null, null, null, null, reportedAt);
    }
}
