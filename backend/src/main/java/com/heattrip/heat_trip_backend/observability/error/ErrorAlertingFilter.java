package com.heattrip.heat_trip_backend.observability.error;

import com.heattrip.heat_trip_backend.observability.alert.AlertOrchestrator;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.http.HttpStatusCode;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;

/**
 * 컨트롤러 예외를 <b>응답이 5xx 로 끝났을 때만</b> 경보로 보낸다 — 이슈 #657.
 *
 * <h2>왜 필터인가</h2>
 * <p>예외가 어느 상태 코드로 끝나는지는 던지는 순간에는 모른다. 그 표는 {@code error.GlobalExceptionHandler}
 * 에 있고({@code NoSuchElementException} → 404, {@code IllegalArgumentException} → 400, 그 밖은 500 …),
 * 그것을 경보 쪽으로 복사하면 같은 표가 두 벌이 돼 한쪽만 낡는다. 그래서 상태 코드를 <b>아는</b> 유일한
 * 자리에서 본다 — 응답이 다 쓰인 뒤다. {@link ErrorAlertingAspect} 가 예외를 이벤트로 만들어 요청에 붙여
 * 두고, 이 필터가 {@code response.getStatus()} 로 가른다.
 *
 * <h2>규칙은 하나다 — 5xx 만 경보</h2>
 * <p>4xx 는 "클라이언트에게 할 말이 있다" 이지 "서버가 아프다" 가 아니다. 가족이 없는 사람의
 * {@code GET /api/groups/me} 404 가 그랬다 — 새로 가입한 사람이 앱을 열 때마다 경보가 나갔고, 레이트
 * 리미터가 그것을 깎아내면서 진짜 오류도 함께 버릴 판이었다. 이 한 곳을 고치면 4xx 로 끝나는 다른
 * 경로(#657 의 셈으로 190곳 남짓)도 함께 조용해진다.
 *
 * <p>디스패처 밖으로 예외가 새어 나온 경우(어느 핸들러도 못 잡은 것)는 컨테이너가 500 을 만들므로 그것도
 * 경보다. 붙여 둔 이벤트가 없으면 그 자리에서 만든다 — 요청 컨텍스트는 이미 정리됐을 수 있어 경로가
 * {@code N/A} 일 수 있지만, 안 보내는 것보다 낫다.
 *
 * <p>순서: {@code @Component} 필터라 시큐리티 체인 <b>뒤</b>에서 돈다. 인증 필터가 끊은 401 은 컨트롤러에
 * 닿지 않으니 여기 올 이벤트도 없다.
 */
@Slf4j
@Component
@RequiredArgsConstructor
public class ErrorAlertingFilter extends OncePerRequestFilter {

    private final AlertOrchestrator alertOrchestrator;
    private final ErrorEventFactory eventFactory;

    @Override
    protected void doFilterInternal(HttpServletRequest request,
                                    HttpServletResponse response,
                                    FilterChain filterChain) throws ServletException, IOException {
        try {
            filterChain.doFilter(request, response);
        } catch (Throwable ex) {
            ErrorEvent pending = pendingEvent(request);
            alert(pending != null ? pending : eventFactory.from(ex));
            throw ex;
        }

        ErrorEvent pending = pendingEvent(request);
        if (pending == null) {
            return;
        }
        if (HttpStatusCode.valueOf(response.getStatus()).is5xxServerError()) {
            alert(pending);
        }
    }

    private static ErrorEvent pendingEvent(HttpServletRequest request) {
        Object value = request.getAttribute(ErrorAlertingAspect.PENDING_EVENT);
        return value instanceof ErrorEvent event ? event : null;
    }

    private void alert(ErrorEvent event) {
        alertOrchestrator.notifyError(event);
        log.error("[ALERT] error captured for {} {}", event.getMethod(), event.getPath());
    }
}
