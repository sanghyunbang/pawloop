package com.heattrip.heat_trip_backend.security;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.heattrip.heat_trip_backend.S3.media.error.GlobalExceptionHandler;
import com.heattrip.heat_trip_backend.config.PublicSecurityProperties;
import com.heattrip.heat_trip_backend.observability.logging.CorrelationIdFilter;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import lombok.RequiredArgsConstructor;
import org.slf4j.MDC;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

@Component
@RequiredArgsConstructor
public class ApiRateLimitFilter extends OncePerRequestFilter {

    private record CounterWindow(long startedAtEpochSecond, int count) {}
    private record Rule(String bucket, int limit) {}

    private final PublicSecurityProperties props;
    private final ObjectMapper objectMapper;
    private final Map<String, CounterWindow> counters = new ConcurrentHashMap<>();

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain filterChain)
            throws ServletException, IOException {
        var rule = resolveRule(request);
        if (!props.getRateLimit().isEnabled() || rule == null || rule.limit() <= 0) {
            filterChain.doFilter(request, response);
            return;
        }

        long now = Instant.now().getEpochSecond();
        long windowSeconds = Math.max(1, props.getRateLimit().getWindowSeconds());
        long currentWindow = now / windowSeconds;
        String key = resolveClientIp(request) + "|" + rule.bucket();

        CounterWindow result = counters.compute(key, (k, current) -> {
            if (current == null || current.startedAtEpochSecond() != currentWindow) {
                return new CounterWindow(currentWindow, 1);
            }
            return new CounterWindow(current.startedAtEpochSecond(), current.count() + 1);
        });

        if (result != null && result.count() > rule.limit()) {
            writeTooManyRequests(response, rule, windowSeconds);
            return;
        }

        cleanupStaleEntries(currentWindow);
        filterChain.doFilter(request, response);
    }

    private Rule resolveRule(HttpServletRequest request) {
        String method = request.getMethod();
        String path = request.getRequestURI();
        var rateLimit = props.getRateLimit();

        if ("POST".equals(method) && "/auth/login".equals(path)) {
            return new Rule("login", rateLimit.getLoginMaxRequests());
        }
        // ── 인증 버킷 (이슈 #14) ────────────────────────────────────────────────
        // 세 분기를 하나의 || 로 합치지 않는다. 합치면 "어느 경로가 언제 목록에서
        // 빠졌는지" 가 한 줄 안에 묻히고, 한 경로만 지웠을 때 어느 테스트가 빨간불이
        // 되는지도 흐려진다. 셋은 같은 버킷을 쓰되 서로 다른 문장이다.
        //
        // ⚠️ #9 는 refresh 경로가 rate limit 없이 열려 있다는 사실을 여기로 넘겼다.
        //    이 분기를 지우면 ApiRateLimitFilterTest.refreshEndpoint_isRateLimited 가 죽는다.
        if ("POST".equals(method) && "/auth/token/refresh".equals(path)) {
            return new Rule("auth", rateLimit.getAuthMaxRequests());
        }
        // 1회용 코드 교환. 자격증명을 만들어 내는 경로라 무제한이면 코드 추측이 공짜다.
        if ("POST".equals(method) && path.matches("^/auth/oauth/[^/]+/callback$")) {
            return new Rule("auth", rateLimit.getAuthMaxRequests());
        }
        // 소셜 진입. 여기는 토큰을 주지 않지만, 공급자로 나가는 302 를 무한히 뽑아낼 수 있으면
        // 우리 서버가 공급자에 대한 트래픽 증폭기가 된다.
        if (path.startsWith("/oauth2/authorization/")) {
            return new Rule("auth", rateLimit.getAuthMaxRequests());
        }
        if (path.startsWith("/api/curation/")) {
            return new Rule("curation", rateLimit.getCurationMaxRequests());
        }
        if ("GET".equals(method) && "/api/explore/places/search".equals(path)) {
            return new Rule("search", rateLimit.getSearchMaxRequests());
        }
        if ("POST".equals(method) && "/feedback".equals(path)) {
            return new Rule("feedback", rateLimit.getFeedbackMaxRequests());
        }
        if ("POST".equals(method) && path.matches("^/api/explore/places/\\d+/feedback$")) {
            return new Rule("feedback", rateLimit.getFeedbackMaxRequests());
        }
        if (path.startsWith("/media")) {
            return new Rule("upload", rateLimit.getUploadMaxRequests());
        }
        if (path.startsWith("/journeys/v2/entries/") && path.endsWith("/images")) {
            return new Rule("upload", rateLimit.getUploadMaxRequests());
        }
        if ("POST".equals(method) && "/journeys/v2/entries/with-images".equals(path)) {
            return new Rule("upload", rateLimit.getUploadMaxRequests());
        }
        return null;
    }

    private String resolveClientIp(HttpServletRequest request) {
        String headerName = props.getRateLimit().getIpHeader();
        String forwarded = request.getHeader(headerName);
        if (forwarded != null && !forwarded.isBlank()) {
            return forwarded.split(",")[0].trim();
        }
        return request.getRemoteAddr();
    }

    /**
     * 429 본문. <b>계약({@code openapi.yaml} 의 {@code Error})의 봉투 그대로다.</b> (이슈 #14)
     *
     * <p>예전에는 {@code {status, error(문자열), message, windowSeconds, limit}} 평면 구조였다.
     * 계약은 {@code {error:{code,message,traceId}}} 이고 앱은 {@code error.code} 로 분기한다 —
     * 평면 구조가 오면 그 분기가 그 자리에서 깨진다. 봉투 타입을 새로 만들지 않고
     * {@link GlobalExceptionHandler.ErrorResponse} 를 그대로 쓰는 이유가 그것이다.
     * 사본을 만들면 한쪽만 낡는다.
     *
     * <p><b>버킷 이름과 한도 수치를 싣지 않는다.</b> 그건 서버 내부의 경로 분류이고, 응답에
     * 실으면 어떤 경로가 어떤 버킷인지·한도가 얼마인지가 그대로 새어 나간다. 사용자가 알아야
     * 하는 것은 "잠시 후 다시" 하나뿐이고, 조사에 필요한 것은 {@code traceId} 다.
     */
    private void writeTooManyRequests(HttpServletResponse response, Rule rule, long windowSeconds) throws IOException {
        response.setStatus(HttpStatus.TOO_MANY_REQUESTS.value());
        response.setContentType(MediaType.APPLICATION_JSON_VALUE);
        response.setCharacterEncoding(StandardCharsets.UTF_8.name());
        // 초 단위 재시도 힌트. 표준 헤더라 클라이언트가 해석할 수 있고, 본문에 한도를 싣는 것과
        // 달리 내부 분류를 노출하지 않는다.
        response.setHeader("Retry-After", String.valueOf(windowSeconds));

        var body = new GlobalExceptionHandler.ErrorResponse(
                new GlobalExceptionHandler.ErrorResponse.ErrorBody(
                        "RATE_LIMITED",
                        "요청이 너무 잦습니다. 잠시 후 다시 시도해 주세요.",
                        MDC.get(CorrelationIdFilter.MDC_KEY)));

        objectMapper.writeValue(response.getWriter(), body);
    }

    private void cleanupStaleEntries(long currentWindow) {
        counters.entrySet().removeIf(entry -> entry.getValue().startedAtEpochSecond() + 2 < currentWindow);
    }
}
