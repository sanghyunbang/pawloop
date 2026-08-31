package com.heattrip.heat_trip_backend.security;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.heattrip.heat_trip_backend.S3.media.error.GlobalExceptionHandler;
import com.heattrip.heat_trip_backend.observability.logging.CorrelationIdFilter;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import org.slf4j.MDC;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;

/**
 * 필터가 직접 쓰는 오류 응답 하나. (이슈 #80 에서 429 용으로 만들고 #129 에서 일반화)
 *
 * <h2>왜 필터가 직접 써야 하는가</h2>
 * <p>{@code GlobalExceptionHandler} 는 <b>MVC 안</b>에서만 돈다. 필터가 요청을 끊으면 그 핸들러가
 * 돌 기회가 없으므로 본문을 여기서 만들어야 한다.
 *
 * <p><b>그래서 계약이 두 벌이 될 위험이 있다.</b> 이 클래스가 그것을 막는다 — 모양은 한 곳에서만
 * 만들고, 필터들은 상태와 코드만 정한다. 지금 두 곳이 쓴다(429 · 400).
 *
 * <h2>본문에 무엇을 싣지 않는가</h2>
 * <p>한도 값이나 실제 크기를 싣지 않는다. 사용자가 할 수 있는 것은 "줄여서 다시" 하나뿐이고,
 * 조사에 필요한 것은 {@code traceId} 다. 숫자를 실으면 내부 분류를 알려 주는 것이다.
 *
 * <p>스프링 빈이 아니다. 필터가 주입받은 {@code ObjectMapper} 로 직접 만든다 — 상태가 없어서
 * 공유할 이유가 없다.
 */
class ErrorBodyWriter {

    private final ObjectMapper objectMapper;

    ErrorBodyWriter(ObjectMapper objectMapper) {
        this.objectMapper = objectMapper;
    }

    /**
     * 429 하나. {@code Retry-After} 는 표준 헤더라 클라이언트가 해석할 수 있다.
     *
     * @param windowSeconds 다시 시도해도 되는 시각까지의 초
     */
    void tooManyRequests(HttpServletResponse response, long windowSeconds) throws IOException {
        response.setHeader("Retry-After", String.valueOf(windowSeconds));
        write(response, HttpStatus.TOO_MANY_REQUESTS, "RATE_LIMITED",
                "요청이 너무 잦습니다. 잠시 후 다시 시도해 주세요.");
    }

    /**
     * 400 하나.
     *
     * <p><b>413 이 아닌 이유</b>(#129): 같은 경로에서 본문 길이를 거절하는 자리가 이미 있고
     * ({@code ChatRoomService.validBody}) 그쪽이 400 이다. 여기만 413 으로 두면 <b>같은 이유의
     * 거절이 크기에 따라 다른 코드</b>가 되어 앱이 두 가지를 다뤄야 한다. 계약
     * ({@code openapi.yaml})을 바꾸지 않는 것이 이 이슈의 범위다.
     */
    void badRequest(HttpServletResponse response, String code, String message) throws IOException {
        write(response, HttpStatus.BAD_REQUEST, code, message);
    }

    private void write(HttpServletResponse response, HttpStatus status, String code, String message)
            throws IOException {
        response.setStatus(status.value());
        response.setContentType(MediaType.APPLICATION_JSON_VALUE);
        response.setCharacterEncoding(StandardCharsets.UTF_8.name());

        var body = new GlobalExceptionHandler.ErrorResponse(
                new GlobalExceptionHandler.ErrorResponse.ErrorBody(
                        code, message, MDC.get(CorrelationIdFilter.MDC_KEY)));

        objectMapper.writeValue(response.getWriter(), body);
    }
}
