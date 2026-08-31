package com.heattrip.heat_trip_backend.chat;

import org.springframework.http.HttpStatus;

/**
 * 앱이 코드로 갈라야 하는 채팅 오류들 — 이슈 #74(한도 넷) · #82(신고 다섯), 근거 ADR-0011 결정 10.
 *
 * <h2>왜 코드를 지금 정하나</h2>
 * <p>여기가 나중에 유료 유도 화면이 붙을 분기점이라, 앱이 <b>문구가 아니라 코드로</b>
 * 갈라야 한다. 문구로 갈리면 메시지를 다듬는 순간 앱이 깨진다.
 *
 * <h2>봉투를 새로 만들지 않는다</h2>
 * <p>응답 본문은 {@code GlobalExceptionHandler.ErrorResponse}
 * ({@code {error:{code,message,traceId}}}) 그대로다. 사본을 만들면 한쪽만 낡는다 —
 * {@code ApiRateLimitFilter} 가 이미 그 봉투를 그대로 재사용하는 선례다.
 *
 * <h2>왜 상태에서 코드를 파생하지 않는가</h2>
 * <p>{@code GlobalExceptionHandler.codeOf(HttpStatus)} 는 409 를 {@code CONFLICT} 로,
 * 410 을 {@code INTERNAL} 로 만든다. 그 표는 "던지는 쪽마다 문자열을 손으로 적으면 같은
 * 상태에 서로 다른 코드가 붙는다" 를 막으려고 있는 것이고 그 목적은 여전히 옳다.
 * 다만 여기 넷은 <b>같은 상태 안에서 서로 다른 뜻</b>이다 —
 * {@link #ROOM_MEMBER_LIMIT} 와 {@link #INVITE_USES_EXHAUSTED} 가 둘 다 409 인데
 * 앱이 보여줄 화면이 다르다. 그래서 코드를 상태에서 뽑지 않고 이 enum 이 들고 있는다.
 * 어휘의 출처가 한 곳이라는 성질은 그대로다 — 이 파일이 그 한 곳이다.
 */
public enum ChatErrorCode {

    /** 방 정원이 찼다. 정원은 {@link ChatLimits#maxMembersPerRoom(long)} 이 답한다. */
    ROOM_MEMBER_LIMIT(HttpStatus.CONFLICT, "방 정원이 찼습니다."),

    /** 초대코드의 유효기간이 지났다. 410 인 이유는 "있었는데 이제 없다" 이기 때문이다. */
    INVITE_EXPIRED(HttpStatus.GONE, "만료된 초대코드입니다."),

    /**
     * 방장이 이 코드를 회수했다({@code DELETE .../invites/{code}}).
     *
     * <p><b>재발급은 이전 코드를 회수하지 않는다.</b> 예전에는 이 자리에 "회수했거나
     * 재발급하면서 이전 코드가 폐기됐다" 고 적혀 있었는데 구현은 그렇게 하지 않는다 —
     * {@code ChatRoomService#issueInvite} 는 새 행을 저장할 뿐이다.
     */
    INVITE_REVOKED(HttpStatus.GONE, "회수된 초대코드입니다."),

    /** 사용 횟수 상한을 다 썼다. 코드 자체는 아직 유효하므로 410 이 아니라 409 다. */
    INVITE_USES_EXHAUSTED(HttpStatus.CONFLICT, "초대코드의 사용 횟수를 모두 썼습니다."),

    // ─────────────────────────── 신고 (이슈 #82) ───────────────────────────
    //
    // 아래 넷은 전부 400 이다. 상태가 같은데 코드를 나누는 이유는 위 javadoc 과 같다 —
    // 앱이 보여줄 화면이 다르다. "3개까지" 는 고른 것을 줄이라는 말이고,
    // "한 사람만" 은 선택을 나누라는 말이라 안내 문구도 다음 동작도 다르다.

    /** 아무것도 안 골랐다. */
    REPORT_EMPTY(HttpStatus.BAD_REQUEST, "신고할 메시지를 하나 이상 골라 주세요."),

    /**
     * 3개를 넘겼다. 카카오 일반채팅방과 같은 숫자다
     * (https://cs.kakao.com/helps_html/1073199392).
     */
    REPORT_MESSAGE_LIMIT(HttpStatus.BAD_REQUEST, "신고는 메시지를 세 개까지 고를 수 있습니다."),

    /**
     * 고른 메시지의 발신자가 여럿이다.
     *
     * <p>신고는 <b>사람</b>에 대한 것이라 대상이 하나여야 한다. 섞인 채로 받으면
     * {@code reported_user_id} 에 누구를 넣을지 서버가 임의로 고르게 된다.
     */
    REPORT_MIXED_SENDERS(HttpStatus.BAD_REQUEST, "한 번에 한 사람만 신고할 수 있습니다."),

    /** 자기 메시지를 골랐다. */
    REPORT_SELF(HttpStatus.BAD_REQUEST, "자기 메시지는 신고할 수 없습니다."),

    /**
     * 고른 번호가 그 방에 없다.
     *
     * <p>없는 방·남의 방은 여기 오기 전에 멤버십 검사에서 403 으로 끊긴다. 여기 오는 것은
     * <b>내 방인데 그 번호가 없는</b> 경우뿐이라 방 존재 여부가 새지 않는다.
     */
    REPORT_MESSAGE_NOT_FOUND(HttpStatus.BAD_REQUEST, "그 방에 없는 메시지입니다."),

    /**
     * 사유 분류가 계약의 목록에 없다.
     *
     * <p>모르는 값을 {@code OTHER} 로 눕히지 않는 이유는 {@code ChatReportReason} javadoc 에
     * 있다 — 앱의 오타가 조용히 통과하면 운영자가 세는 숫자가 소리 없이 틀어진다.
     */
    REPORT_REASON_UNKNOWN(HttpStatus.BAD_REQUEST, "신고 사유를 골라 주세요.");

    private final HttpStatus status;
    private final String message;

    ChatErrorCode(HttpStatus status, String message) {
        this.status = status;
        this.message = message;
    }

    public HttpStatus status() {
        return status;
    }

    /**
     * 사람이 읽는 문구.
     *
     * <p><b>식별자를 넣지 않는다.</b> 이 값은 그대로 응답 본문이 된다 — 방 id·초대코드·
     * 사용자 id 를 여기 섞으면 그 순간 유출 경로다(#6).
     */
    public String message() {
        return message;
    }
}
