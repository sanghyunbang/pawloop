package com.heattrip.heat_trip_backend.chat;

/**
 * 한도·초대 상태 위반. {@link ChatErrorCode} 가 상태 코드와 문구를 함께 든다 — 이슈 #74.
 *
 * <p>{@code ResponseStatusException} 을 쓰지 않는 이유: 그쪽은 코드가 상태에서 파생돼
 * {@code CONFLICT} 하나로 뭉개진다({@link ChatErrorCode} javadoc 참조). 앱이 갈라야 하는
 * 것은 상태가 아니라 코드다.
 *
 * <p>응답으로 바꾸는 것은 {@code GlobalExceptionHandler} 다. <b>그 클래스 안에 있어야
 * 한다</b> — 별도 {@code @ControllerAdvice} 로 빼면 예외 구체성이 아니라 advice 빈 순서로
 * 승자가 정해져서 catch-all 이 먼저 잡고 500 이 나간다(#44 에서 실측).
 */
public class ChatLimitViolationException extends RuntimeException {

    private final transient ChatErrorCode errorCode;

    public ChatLimitViolationException(ChatErrorCode errorCode) {
        super(errorCode.message());
        this.errorCode = errorCode;
    }

    public ChatErrorCode errorCode() {
        return errorCode;
    }
}
