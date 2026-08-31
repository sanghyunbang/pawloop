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
 * 429 응답 하나를 쓴다. (이슈 #80 에서 {@code ApiRateLimitFilter} 에서 꺼냈다)
 *
 * <p><b>왜 꺼냈나.</b> #80 이 채팅용 두 번째 rate limit 필터를 요구하는데, 그쪽도 같은 본문을
 * 써야 한다. 복사하면 <b>본문 계약이 두 벌</b>이 되고 한쪽만 고치는 날이 온다. 계약은
 * {@code openapi.yaml} 이 정하는 것이라 두 벌이면 안 된다.
 *
 * <p><b>한도 값을 본문에 싣지 않는다.</b> 사용자가 할 수 있는 것은 "잠시 후 다시" 하나뿐이고,
 * 조사에 필요한 것은 {@code traceId} 다. 한도를 싣는 것은 내부 분류를 알려 주는 것이다.
 *
 * <p>{@code Retry-After} 는 표준 헤더라 클라이언트가 해석할 수 있다.
 *
 * <p>스프링 빈이 아니다. 필터가 주입받은 {@code ObjectMapper} 로 직접 만든다 — 상태가 없어서
 * 공유할 이유가 없고, 필터 생성자 시그니처를 그대로 두면 기존 테스트 21건이 안 바뀐다.
 */
class TooManyRequestsWriter {

    private final ObjectMapper objectMapper;

    TooManyRequestsWriter(ObjectMapper objectMapper) {
        this.objectMapper = objectMapper;
    }

    void write(HttpServletResponse response, long windowSeconds) throws IOException {
        response.setStatus(HttpStatus.TOO_MANY_REQUESTS.value());
        response.setContentType(MediaType.APPLICATION_JSON_VALUE);
        response.setCharacterEncoding(StandardCharsets.UTF_8.name());
        response.setHeader("Retry-After", String.valueOf(windowSeconds));

        var body = new GlobalExceptionHandler.ErrorResponse(
                new GlobalExceptionHandler.ErrorResponse.ErrorBody(
                        "RATE_LIMITED",
                        "요청이 너무 잦습니다. 잠시 후 다시 시도해 주세요.",
                        MDC.get(CorrelationIdFilter.MDC_KEY)));

        objectMapper.writeValue(response.getWriter(), body);
    }
}
