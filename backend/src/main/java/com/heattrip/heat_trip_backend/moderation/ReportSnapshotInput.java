package com.heattrip.heat_trip_backend.moderation;

import java.time.Instant;
import java.util.Locale;

/**
 * 신고 시점의 사본 한 줄 — 부르는 쪽이 만들어서 넘긴다.
 *
 * <h2>왜 부르는 쪽이 만드나</h2>
 * <p>이 모듈은 어떤 도메인도 안 부른다(package-info). 글이 무엇이고 누가 썼는지는
 * {@code community} 가 아는 것이라, 그쪽이 값으로 넘긴다.
 *
 * <h2>왜 본문까지 베나</h2>
 * <p><b>원본이 지워진 뒤에 읽는 기록이기 때문이다.</b> 참조만 남기면 작성자가 글을 지우는
 * 순간 운영자가 무엇을 판단해야 하는지 알 수 없다. 채팅 신고가 같은 이유로 본문 사본을
 * 남긴다.
 *
 * @param role         {@code TARGET} 이면 신고 대상, {@code CONTEXT} 면 맥락. 댓글을 신고하면
 *                     <b>부모 글을 {@code CONTEXT} 로 함께</b> 넘긴다 — 댓글 한 줄만 남으면
 *                     무슨 글에 달린 말인지 모르고, 글을 지우면 댓글이 CASCADE 로 함께
 *                     사라져 되짚을 수도 없다
 * @param authorUserId 그 글·댓글을 쓴 사람. 탈퇴했으면 {@code null}
 * @param authorName   신고 시점 표시 이름. 폭은 {@code users.nickname} 과 같은 255 다 —
 *                     좁히면 긴 닉네임을 가진 사람이 쓴 글을 <b>아무도 신고할 수 없다</b>
 * @param title        글이면 제목, 댓글이면 {@code null}. 제목에 욕설·광고가 실린 신고가
 *                     정확히 그 자리라 본문만 베면 기록에 안 남는다
 * @param body         신고 시점 본문
 * @param occurredAt   그 글·댓글이 쓰인 시각
 */
public record ReportSnapshotInput(
        Role role,
        Long authorUserId,
        String authorName,
        String title,
        String body,
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

    public static ReportSnapshotInput target(
            Long authorUserId, String authorName, String title, String body, Instant occurredAt) {
        return new ReportSnapshotInput(
                Role.TARGET, authorUserId, authorName, title, body, occurredAt);
    }

    public static ReportSnapshotInput context(
            Long authorUserId, String authorName, String title, String body, Instant occurredAt) {
        return new ReportSnapshotInput(
                Role.CONTEXT, authorUserId, authorName, title, body, occurredAt);
    }
}
