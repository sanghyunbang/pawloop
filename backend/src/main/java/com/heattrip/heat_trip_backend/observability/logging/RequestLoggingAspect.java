package com.heattrip.heat_trip_backend.observability.logging;

import com.heattrip.heat_trip_backend.observability.config.ObservabilityProperties;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.aspectj.lang.ProceedingJoinPoint;
import org.aspectj.lang.annotation.Around;
import org.aspectj.lang.annotation.Aspect;
import org.springframework.stereotype.Component;
import org.springframework.web.context.request.RequestContextHolder;
import org.springframework.web.context.request.ServletRequestAttributes;

@Slf4j
@Aspect
@Component
@RequiredArgsConstructor
public class RequestLoggingAspect {

    private final ObservabilityProperties props;

    @Around("within(@org.springframework.web.bind.annotation.RestController *)")
    public Object logRestController(ProceedingJoinPoint pjp) throws Throwable {
        if (!props.isEnabled() || !props.isRequestLogEnabled()) {
            return pjp.proceed();
        }

        long start = System.currentTimeMillis();
        var attrs = (ServletRequestAttributes) RequestContextHolder.getRequestAttributes();
        var req = attrs != null ? attrs.getRequest() : null;

        String method = req != null ? req.getMethod() : "N/A";
        String path = req != null ? req.getRequestURI() : pjp.getSignature().toShortString();

        try {
            Object result = pjp.proceed();
            long took = System.currentTimeMillis() - start;
            log.info("[REQ] {} {} completed in {}ms", method, path, took);
            return result;
        } catch (Throwable ex) {
            long took = System.currentTimeMillis() - start;
            log.warn("[REQ] {} {} failed in {}ms: {}", method, path, took, ex.toString());
            throw ex;
        }
    }
}
