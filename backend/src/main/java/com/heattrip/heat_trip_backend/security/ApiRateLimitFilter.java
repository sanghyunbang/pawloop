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
import java.util.concurrent.atomic.AtomicLong;

@Component
@RequiredArgsConstructor
public class ApiRateLimitFilter extends OncePerRequestFilter {

    private record CounterWindow(long startedAtEpochSecond, int count) {}
    private record Rule(String bucket, int limit) {}

    private final PublicSecurityProperties props;
    private final ObjectMapper objectMapper;
    private final Map<String, CounterWindow> counters = new ConcurrentHashMap<>();

    /** 마지막으로 스테일 항목을 훑은 창. 같은 창에서 두 번 훑지 않기 위한 것뿐이다. */
    private final AtomicLong lastSweptWindow = new AtomicLong(Long.MIN_VALUE);

    /** {@link #trustedProxies()} 가 채운다. 기동 뒤 바뀌지 않는 값이라 한 번만 파싱한다. */
    private volatile TrustedProxies trustedProxies;

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
            writeTooManyRequests(response, windowSeconds);
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

    /**
     * 카운터의 열쇠가 될 클라이언트 주소. <b>신뢰 경계를 명시한다.</b> (이슈 #14)
     *
     * <h2>무엇이 문제였나</h2>
     * 예전 구현은 {@code X-Forwarded-For} 의 <b>첫 원소</b>를 무조건 취했다. 그런데 이
     * 저장소의 nginx 템플릿({@code nginx-production-template.conf:34},
     * {@code nginx-rate-limit-example.conf:27})은 {@code $proxy_add_x_forwarded_for} 라서
     * <b>클라이언트가 보낸 값 뒤에</b> 실제 IP 를 덧붙인다. 즉 첫 원소는 배포된 환경에서도
     * 공격자가 정하는 문자열이었고, 요청마다 다른 값을 적으면 카운터가 갈라져 한도가
     * 통째로 사라졌다 — 한도 5 에 1000 요청, 429 <b>0건</b>.
     *
     * <h2>두 개의 벽</h2>
     * <ol>
     *   <li><b>연결 반대편이 신뢰 프록시가 아니면 헤더를 아예 읽지 않는다.</b> 헤더가 의미를
     *       갖는 조건은 "우리가 통제하는 프록시가 붙였다" 하나뿐이고, 그것을 확인할 수 있는
     *       값은 {@code getRemoteAddr()} 뿐이다. 프록시 없이 노출된 배포에서는 헤더가
     *       그냥 무시된다 — 위조가 통하지 않는다.</li>
     *   <li><b>목록형 헤더는 마지막 원소를 취한다.</b> 신뢰 프록시가 1단일 때 그 자리가
     *       프록시가 실제로 본 주소다. 앞쪽은 전부 클라이언트가 적은 값이다.
     *       ({@code X-Real-IP} 는 단일 값이라 마지막 = 전체다.)</li>
     * </ol>
     *
     * <p>둘 중 하나만 두면 부족하다. 1번만 두면 신뢰 프록시 뒤에서 첫 원소 위조가 그대로
     * 살아 있고, 2번만 두면 프록시 없는 배포에서 아무나 헤더를 붙일 수 있다.
     */
    private String resolveClientIp(HttpServletRequest request) {
        String remoteAddr = request.getRemoteAddr();
        String connectionPeer = (remoteAddr == null || remoteAddr.isBlank()) ? "unknown" : remoteAddr;

        if (!trustedProxies().contains(connectionPeer)) {
            return connectionPeer;
        }

        String headerName = props.getRateLimit().getIpHeader();
        String forwarded = headerName == null ? null : request.getHeader(headerName);
        if (forwarded == null || forwarded.isBlank()) {
            return connectionPeer;
        }

        String[] hops = forwarded.split(",");
        String nearest = hops[hops.length - 1].trim();
        return nearest.isEmpty() ? connectionPeer : nearest;
    }

    /**
     * 신뢰 프록시 목록은 기동 뒤 바뀌지 않는다. 요청마다 CIDR 을 다시 파싱하지 않도록
     * 한 번만 만들어 둔다.
     */
    private TrustedProxies trustedProxies() {
        TrustedProxies cached = this.trustedProxies;
        if (cached == null) {
            cached = TrustedProxies.parse(props.getRateLimit().getTrustedProxies());
            this.trustedProxies = cached;
        }
        return cached;
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
    private void writeTooManyRequests(HttpServletResponse response, long windowSeconds) throws IOException {
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

    /**
     * 지난 창의 항목을 치운다. <b>창이 바뀔 때만</b> 훑는다. (이슈 #14)
     *
     * <p>예전에는 차단되지 않은 <b>모든 요청</b>이 맵 전체를 순회했다. 그 상태에서 카운터
     * 열쇠를 공격자가 정할 수 있었으므로(위 {@code resolveClientIp} 참조) 맵을 부풀린 만큼
     * 요청당 CPU 가 함께 올라갔다 — 실측으로 맵 크기가 2배가 되자 요청당 비용이 3.7배가 됐다.
     * 인증 없이 보낼 수 있는 요청으로 서버 CPU 를 증폭시킬 수 있다는 뜻이다.
     *
     * <p>열쇠 위조를 막은 것이 근본 수정이고, 이 게이트는 그 위의 두 번째 벽이다.
     * 창 하나에 순회 한 번이면 정리 주기는 그대로이고 요청당 비용은 O(1) 이 된다.
     */
    private void cleanupStaleEntries(long currentWindow) {
        long previous = lastSweptWindow.get();
        if (previous == currentWindow) {
            return;
        }
        // 진 쪽은 그냥 건너뛴다. 청소는 다음 요청이 해도 되는 일이라 재시도할 이유가 없다.
        if (!lastSweptWindow.compareAndSet(previous, currentWindow)) {
            return;
        }
        counters.entrySet().removeIf(entry -> entry.getValue().startedAtEpochSecond() + 2 < currentWindow);
    }
}
