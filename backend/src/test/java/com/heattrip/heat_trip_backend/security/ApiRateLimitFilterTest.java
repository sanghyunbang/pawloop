package com.heattrip.heat_trip_backend.security;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.heattrip.heat_trip_backend.config.PublicSecurityProperties;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockFilterChain;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;

import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * {@link ApiRateLimitFilter} 의 첫 테스트. (이슈 #14)
 *
 * <p>이 필터에는 테스트가 <b>0건</b>이었다. 그동안 이 필터가 어떤 경로를 어떤 버킷으로
 * 묶는지는 코드를 읽는 사람의 기억에만 있었고, 그래서 {@code POST /auth/token/refresh} 와
 * 소셜 진입점이 목록에서 빠져 있다는 사실도 아무 신호를 내지 않았다.
 *
 * <p>스프링 컨텍스트를 띄우지 않는다. 필터 하나에 {@code MockHttpServletRequest} 를 직접
 * 태운다 — 카운터가 인스턴스 필드({@code ApiRateLimitFilter.counters})이므로
 * <b>테스트마다 필터를 새로 만들어</b> 격리한다. 공유하면 앞 테스트가 소진한 카운터가
 * 뒤 테스트의 판정을 바꾼다.
 */
class ApiRateLimitFilterTest {

    private static final ObjectMapper MAPPER = new ObjectMapper();

    /** 창을 넉넉히 잡는다 — 이 테스트가 재는 것은 시간 경과가 아니라 한도 초과다. */
    private static PublicSecurityProperties props(int authLimit) {
        PublicSecurityProperties p = new PublicSecurityProperties();
        p.getRateLimit().setEnabled(true);
        p.getRateLimit().setWindowSeconds(3600);
        p.getRateLimit().setAuthMaxRequests(authLimit);
        return p;
    }

    private static ApiRateLimitFilter filter(int authLimit) {
        return new ApiRateLimitFilter(props(authLimit), MAPPER);
    }

    private static MockHttpServletResponse call(ApiRateLimitFilter filter,
                                                String method, String path, String ip) throws Exception {
        MockHttpServletRequest request = new MockHttpServletRequest(method, path);
        request.setRequestURI(path);
        if (ip != null) {
            request.addHeader("X-Forwarded-For", ip);
        }
        MockHttpServletResponse response = new MockHttpServletResponse();
        filter.doFilter(request, response, new MockFilterChain());
        return response;
    }

    /** 한도까지 태우고, 한도+1 번째 응답을 돌려준다. */
    private static MockHttpServletResponse exhaust(ApiRateLimitFilter filter,
                                                   String method, String path, int limit) throws Exception {
        for (int i = 0; i < limit; i++) {
            MockHttpServletResponse ok = call(filter, method, path, "203.0.113.9");
            assertThat(ok.getStatus())
                    .as("한도 안(%d/%d)의 요청은 통과해야 한다", i + 1, limit)
                    .isEqualTo(200);
        }
        return call(filter, method, path, "203.0.113.9");
    }

    // ─────────────────── A. 인증 경로가 버킷에 매핑된다 (완료 조건 6·11) ───────────────────

    @Test
    @DisplayName("POST /auth/token/refresh 는 인증 버킷이다 — 한도+1 번째에서 429")
    void refreshEndpoint_isRateLimited() throws Exception {
        // #9 는 이 경로가 rate limit 없이 열려 있다는 사실을 #14 로 넘겼다. 여기서 닫는다.
        // 이 분기를 resolveRule 에서 지우면 이 테스트가 빨간불이다 (완료 조건 11).
        MockHttpServletResponse blocked = exhaust(filter(3), "POST", "/auth/token/refresh", 3);

        assertThat(blocked.getStatus()).isEqualTo(429);
    }

    @Test
    @DisplayName("POST /auth/oauth/{provider}/callback 은 인증 버킷이다 — 한도+1 번째에서 429")
    void oauthCallbackEndpoint_isRateLimited() throws Exception {
        // 1회용 코드 교환은 자격증명을 만들어 내는 경로다. 무제한이면 코드 추측이 공짜가 된다.
        MockHttpServletResponse blocked = exhaust(filter(2), "POST", "/auth/oauth/kakao/callback", 2);

        assertThat(blocked.getStatus()).isEqualTo(429);
    }

    @Test
    @DisplayName("GET /oauth2/authorization/kakao 진입도 인증 버킷이다 — 한도+1 번째에서 429")
    void socialEntryPoint_isRateLimited() throws Exception {
        MockHttpServletResponse blocked = exhaust(filter(2), "GET", "/oauth2/authorization/kakao", 2);

        assertThat(blocked.getStatus()).isEqualTo(429);
    }

    @Test
    @DisplayName("인증 경로가 아닌 곳은 인증 버킷에 걸리지 않는다")
    void unrelatedPath_isNotInTheAuthBucket() throws Exception {
        ApiRateLimitFilter filter = filter(1);
        // /auth/me 는 인증된 조회지 자격증명 경로가 아니다. 여기까지 묶으면 앱이 화면 전환마다 429 다.
        assertThat(call(filter, "GET", "/auth/me", "203.0.113.9").getStatus()).isEqualTo(200);
        assertThat(call(filter, "GET", "/auth/me", "203.0.113.9").getStatus()).isEqualTo(200);
        assertThat(call(filter, "GET", "/auth/me", "203.0.113.9").getStatus()).isEqualTo(200);
    }

    // ─────────────────── B. 카운터의 열쇠는 IP 다 ───────────────────

    @Test
    @DisplayName("X-Forwarded-For 가 다르면 카운터가 분리된다")
    void countersAreSeparatedByClientIp() throws Exception {
        ApiRateLimitFilter filter = filter(1);

        assertThat(call(filter, "POST", "/auth/token/refresh", "198.51.100.1").getStatus()).isEqualTo(200);
        assertThat(call(filter, "POST", "/auth/token/refresh", "198.51.100.1").getStatus())
                .as("같은 IP 의 두 번째 요청은 한도(1)를 넘는다")
                .isEqualTo(429);

        assertThat(call(filter, "POST", "/auth/token/refresh", "198.51.100.2").getStatus())
                .as("다른 IP 의 첫 요청까지 막으면 한 사람이 전체를 잠글 수 있다")
                .isEqualTo(200);
    }

    // ─────────────────── C. 429 본문이 계약의 Error 다 (완료 조건 11) ───────────────────

    @Test
    @DisplayName("429 본문이 계약의 Error 스키마와 같은 모양이다 — 최상위 키는 error 하나뿐")
    void tooManyRequestsBody_matchesTheContractErrorEnvelope() throws Exception {
        // 예전 본문은 {status, error(문자열), message, windowSeconds, limit} 평면 구조였다.
        // 계약(openapi.yaml 의 Error)은 {error:{code,message,traceId}} 다. 평면으로 되돌리면
        // 이 테스트가 빨간불이다 (완료 조건 11).
        MockHttpServletResponse blocked = exhaust(filter(1), "POST", "/auth/token/refresh", 1);

        assertThat(blocked.getStatus()).isEqualTo(429);
        assertThat(blocked.getContentType()).contains("application/json");

        @SuppressWarnings("unchecked")
        Map<String, Object> body = MAPPER.readValue(blocked.getContentAsString(), Map.class);

        assertThat(body.keySet())
                .as("최상위에 필드를 펼치면 앱의 error.code 분기가 그 자리에서 깨진다")
                .containsExactly("error");

        Object errorNode = body.get("error");
        assertThat(errorNode)
                .as("error 가 문자열이면 그건 계약이 아니라 예전 평면 구조다")
                .isInstanceOf(Map.class);

        @SuppressWarnings("unchecked")
        Map<String, Object> error = (Map<String, Object>) errorNode;
        assertThat(error).containsKeys("code", "message", "traceId");
        assertThat(error.get("code"))
                .as("GlobalExceptionHandler.codeOf(TOO_MANY_REQUESTS) 와 같은 어휘여야 한다")
                .isEqualTo("RATE_LIMITED");
        assertThat(String.valueOf(error.get("message"))).isNotBlank();
    }

    @Test
    @DisplayName("429 본문이 버킷 이름이나 내부 한도 수치를 노출하지 않는다")
    void tooManyRequestsBody_doesNotLeakInternals() throws Exception {
        MockHttpServletResponse blocked = exhaust(filter(1), "POST", "/auth/oauth/kakao/callback", 1);

        String raw = blocked.getContentAsString();
        assertThat(raw)
                .as("버킷 이름은 서버 내부 구현이다 — 응답에 실으면 경로 분류가 그대로 새어 나간다")
                .doesNotContain("bucket");
    }

    // ─────────────────── D. 스위치가 실제로 끈다 ───────────────────

    @Test
    @DisplayName("rate-limit.enabled=false 면 한도를 넘겨도 통과한다")
    void disabledSwitch_turnsTheLimiterOff() throws Exception {
        PublicSecurityProperties p = props(1);
        p.getRateLimit().setEnabled(false);
        ApiRateLimitFilter filter = new ApiRateLimitFilter(p, MAPPER);

        assertThat(call(filter, "POST", "/auth/token/refresh", "203.0.113.9").getStatus()).isEqualTo(200);
        assertThat(call(filter, "POST", "/auth/token/refresh", "203.0.113.9").getStatus()).isEqualTo(200);
    }
}
