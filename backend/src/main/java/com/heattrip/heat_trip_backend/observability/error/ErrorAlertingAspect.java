package com.heattrip.heat_trip_backend.observability.error;

import lombok.RequiredArgsConstructor;
import org.aspectj.lang.ProceedingJoinPoint;
import org.aspectj.lang.annotation.Around;
import org.aspectj.lang.annotation.Aspect;
import org.springframework.stereotype.Component;
import org.springframework.web.context.request.RequestContextHolder;
import org.springframework.web.context.request.ServletRequestAttributes;

/**
 * 컨트롤러가 던진 예외를 <b>요청에 붙여 둔다.</b> 경보는 여기서 보내지 않는다 — 이슈 #657.
 *
 * <p>2026-09-19 까지 이 애스펙트는 예외를 잡는 순간 종류를 가리지 않고 경보를 보냈다. 그런데
 * 가족이 아직 없는 사람의 {@code GET /api/groups/me} 는 {@code NoSuchElementException} 을 던지고
 * {@code GlobalExceptionHandler} 가 그것을 <b>404</b> 로 옮긴다 — 응답은 맞는데, "찾는 것이 없다" 와
 * "서버가 고장났다" 를 같은 것으로 취급해 새로 가입한 사람이 앱을 열 때마다 경보가 나갔다.
 *
 * <p><b>여기서는 상태 코드를 모른다.</b> 예외가 어느 코드로 끝나는지는 {@code GlobalExceptionHandler} 가
 * 이 뒤에 정하고, 그 표를 여기로 복사하면 표가 두 벌이 된다. 그래서 이 애스펙트는 요청 컨텍스트가
 * 살아 있는 지금 이벤트(경로 · 메서드 · 상관관계 ID · 스택)만 만들어 요청에 붙여 두고, 응답이 다 쓰인
 * 뒤에 {@link ErrorAlertingFilter} 가 상태 코드를 보고 5xx 일 때만 경보로 보낸다.
 */
@Aspect
@Component
@RequiredArgsConstructor
public class ErrorAlertingAspect {

    /**
     * 붙여 두는 자리의 이름. 값은 {@link ErrorEvent} 다.
     *
     * <p>요청 속성인 이유: 스레드 로컬은 비동기 디스패치와 스레드 풀에서 새고, 응답이 끝난 뒤 그것을
     * 읽는 필터가 같은 요청 객체를 들고 있다.
     */
    public static final String PENDING_EVENT = ErrorAlertingAspect.class.getName() + ".pendingEvent";

    private final ErrorEventFactory eventFactory;

    @Around("within(@org.springframework.web.bind.annotation.RestController *)")
    public Object captureError(ProceedingJoinPoint pjp) throws Throwable {
        try {
            return pjp.proceed();
        } catch (Throwable ex) {
            var attrs = (ServletRequestAttributes) RequestContextHolder.getRequestAttributes();
            if (attrs != null) {
                // 이벤트는 지금 만든다 — 필터가 도는 시점에는 요청 컨텍스트와 MDC 가 이미 정리돼
                // 경로도 상관관계 ID 도 못 읽는다. 판정(5xx 인가)만 필터에 맡긴다.
                attrs.getRequest().setAttribute(PENDING_EVENT, eventFactory.from(ex));
            }
            throw ex;
        }
    }
}
