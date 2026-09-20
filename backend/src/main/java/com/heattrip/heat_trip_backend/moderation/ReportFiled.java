package com.heattrip.heat_trip_backend.moderation;

import java.time.Instant;
import java.util.List;

/**
 * 신고가 접수됐다 — {@link Reports#file} 이 저장 트랜잭션 안에서 발행한다. 이슈 #707.
 *
 * <h2>왜 사건인가 — 이 모듈은 아무도 못 부른다</h2>
 * <p>{@code package-info} 가 {@code allowedDependencies = {}} 다. 여기서 슬랙을 직접 부르면
 * 나가는 참조가 생기고, 그 위반은 {@code ModularityBaselineTest} 의 정규식이 못 읽는 모양으로
 * 나와서 고치는 사람이 <b>"정규식을 고쳐라"</b> 로 오진한다. 그래서 화살표를 뒤집는다 —
 * 이 모듈은 "접수됐다" 고 말하기만 하고, 누가 듣는지 모른다. {@code chat/ChatMessagePosted} ·
 * {@code user/UserSessionsRevoked} · {@code group/FamilyGroupCreated} 와 같은 모양이다.
 *
 * <p>듣는 쪽은 {@code @TransactionalEventListener(AFTER_COMMIT)} 로 받아야 한다 — 커밋 전에
 * 받으면 롤백된 신고의 알림이 나간다.
 *
 * <h2>값이 전부 평평하다</h2>
 * <p>듣는 쪽은 다른 모듈이라 {@code moderation.entity.*} 를 못 만진다(하위 패키지는 공개
 * 표면이 아니다). 그래서 운영자에게 필요한 것을 <b>값으로</b> 다 들고 나간다.
 *
 * <h2>무엇을 안 싣나 — 이 record 의 결론</h2>
 * <p>여기 실린 것은 곧 알림 채널에 실릴 수 있는 것이다. 그래서 <b>싣지 않는 것</b>을 여기서
 * 정한다.
 * <ul>
 *   <li><b>메모 본문</b>은 없다. {@link #hasMemo} 뿐이다 — 신고자가 자기 연락처나 제3자
 *       정보를 적는 자리다({@link Reports#MAX_MEMO_LENGTH}). 있음/없음이면 판단에 충분하다.</li>
 *   <li><b>신고자 닉네임</b>은 없다. id 뿐이다 — 이름까지 실으면 알림 채널이 보복의 재료가 된다.</li>
 *   <li>채팅이면 <b>본문도 작성자 이름도 없다.</b> 사적 대화다. {@link Target#body} 와
 *       {@link Target#authorName} 이 {@code null} 로 온다. 공개 글과 사적 대화를 같은 규칙으로
 *       다루지 않는다.</li>
 *   <li>커뮤니티 본문은 <b>앞 {@value #BODY_PREVIEW_LENGTH}자까지</b>다.</li>
 * </ul>
 *
 * @param reportId       {@code report.id}. 운영자가 DB 를 열 때의 좌표다
 * @param reason         {@code ReportReason} 의 wire 값(소문자)
 * @param reporterUserId 신고한 사람의 id. 이름은 없다
 * @param reportedUserId 신고당한 사람의 id. 탈퇴했으면 {@code null}
 * @param hasMemo        메모가 있었는가. 본문은 싣지 않는다
 * @param filedAt        접수 시각(UTC). 표시할 때 KST 로 바꾼다
 * @param targets        대상 줄들 — 커뮤니티는 하나, 채팅은 최대 셋. 맥락 줄은 없다
 */
public record ReportFiled(
        long reportId,
        String reason,
        long reporterUserId,
        Long reportedUserId,
        boolean hasMemo,
        Instant filedAt,
        List<Target> targets) {

    /** 커뮤니티 본문을 알림에 실을 때의 상한. 상수로 두고 검사가 못 박는다. */
    public static final int BODY_PREVIEW_LENGTH = 80;

    /**
     * 대상 하나.
     *
     * @param targetType   {@code community_post} · {@code community_comment} · {@code chat_message}
     * @param targetId     그 도메인 안의 id
     * @param authorUserId 쓴 사람. 탈퇴했으면 {@code null}
     * @param authorName   쓴 사람의 표시 이름. <b>채팅이면 {@code null}</b>
     * @param bodyPreview  본문 앞부분. <b>채팅이면 {@code null}</b>, 커뮤니티는 {@value #BODY_PREVIEW_LENGTH}자까지
     */
    public record Target(
            String targetType,
            long targetId,
            Long authorUserId,
            String authorName,
            String bodyPreview) {

        /** 채팅 메시지인가 — 본문과 이름을 싣지 않는 갈래다. */
        public boolean isChat() {
            return "chat_message".equals(targetType);
        }
    }

    public ReportFiled {
        targets = List.copyOf(targets);
    }

    /** 커뮤니티 본문을 상한까지 자른다. 채팅에는 부르지 않는다 — 부르는 쪽이 {@code null} 을 넣는다. */
    public static String preview(String body) {
        if (body == null) {
            return null;
        }
        String flat = body.strip().replace('\n', ' ');
        return flat.length() <= BODY_PREVIEW_LENGTH ? flat : flat.substring(0, BODY_PREVIEW_LENGTH) + "…";
    }
}
