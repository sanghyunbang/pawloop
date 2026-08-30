package com.heattrip.heat_trip_backend.observability.error;

import com.heattrip.heat_trip_backend.observability.config.ObservabilityProperties;
import com.heattrip.heat_trip_backend.observability.logging.CorrelationIdFilter;
import com.heattrip.heat_trip_backend.observability.logging.SensitiveDataMasker;
import lombok.RequiredArgsConstructor;
import org.slf4j.MDC;
import org.springframework.stereotype.Component;
import org.springframework.web.context.request.RequestContextHolder;
import org.springframework.web.context.request.ServletRequestAttributes;

import java.time.Instant;
import java.util.Arrays;
import java.util.stream.Collectors;

@Component
@RequiredArgsConstructor
public class ErrorEventFactory {

    private final ObservabilityProperties props;
    private final SensitiveDataMasker masker;

    public ErrorEvent from(Throwable ex) {
        var attrs = (ServletRequestAttributes) RequestContextHolder.getRequestAttributes();
        var req = attrs != null ? attrs.getRequest() : null;

        String stack = Arrays.stream(ex.getStackTrace())
                .limit(props.getStacktraceLines())
                .map(StackTraceElement::toString)
                .collect(Collectors.joining("\n"));

        return ErrorEvent.builder()
                .occurredAt(Instant.now())
                .service(props.getServiceName())
                .correlationId(MDC.get(CorrelationIdFilter.MDC_KEY))
                .method(req != null ? req.getMethod() : "N/A")
                // 경로에도 비밀값이 실린다 — 초대코드(이슈 #75). 이 이벤트는 Slack 으로 나간다.
                .path(SensitiveDataMasker.maskUri(req != null ? req.getRequestURI() : "N/A"))
                .exceptionClass(ex.getClass().getName())
                .message(masker.mask(ex.getMessage()))
                .stackTraceSnippet(masker.mask(stack))
                .clientIp(req != null ? req.getRemoteAddr() : "N/A")
                .userAgent(req != null ? req.getHeader("User-Agent") : "N/A")
                .build();
    }
}
