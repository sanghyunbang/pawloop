package com.heattrip.heat_trip_backend.observability.error;

import com.heattrip.heat_trip_backend.observability.alert.AlertOrchestrator;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.aspectj.lang.ProceedingJoinPoint;
import org.aspectj.lang.annotation.Around;
import org.aspectj.lang.annotation.Aspect;
import org.springframework.stereotype.Component;

@Slf4j
@Aspect
@Component
@RequiredArgsConstructor
public class ErrorAlertingAspect {

    private final ErrorEventFactory eventFactory;
    private final AlertOrchestrator alertOrchestrator;

    @Around("within(@org.springframework.web.bind.annotation.RestController *)")
    public Object alertOnError(ProceedingJoinPoint pjp) throws Throwable {
        try {
            return pjp.proceed();
        } catch (Throwable ex) {
            ErrorEvent event = eventFactory.from(ex);
            alertOrchestrator.notifyError(event);
            log.error("[ALERT] error captured for {} {}", event.getMethod(), event.getPath());
            throw ex;
        }
    }
}
