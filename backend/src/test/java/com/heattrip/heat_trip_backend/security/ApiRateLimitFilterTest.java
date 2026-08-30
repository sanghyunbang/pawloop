package com.heattrip.heat_trip_backend.security;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.heattrip.heat_trip_backend.config.PublicSecurityProperties;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockFilterChain;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;

import java.util.List;
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
 *
 * <p><b>이 파일이 볼 수 없는 것:</b> 필터가 배포된 시큐리티 체인의 <b>어느 자리</b>에 있는지.
 * 여기서는 필터를 직접 태우므로 체인에서 앞선 필터가 요청을 끝내 버려도 알 수 없다. 실제로
 * {@code /oauth2/authorization/*} 는 그 이유로 운영에서 제한이 걸리지 않으면서 이 파일은
 * 초록이었다. 그 자리는 {@link ApiRateLimitFilterChainOrderIntegrationTest} 가 잠근다.
 */
class ApiRateLimitFilterTest {

    private static final ObjectMapper MAPPER = new ObjectMapper();

    /** nginx 가 앉는 자리. 기본 {@code trusted-proxies} 안이라 헤더가 해석된다. */
    private static final String BEHIND_PROXY = "127.0.0.1";

    /** 프록시 없이 직접 붙은 클라이언트. 신뢰 목록 밖이라 헤더가 무시된다. */
    private static final String DIRECT_PUBLIC = "203.0.113.9";

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

    /** login 버킷(이메일 로그인·회원가입)의 한도를 지정한 필터. */
    private static ApiRateLimitFilter filterWithLoginLimit(int loginLimit) {
        PublicSecurityProperties p = props(100);
        p.getRateLimit().setLoginMaxRequests(loginLimit);
        return new ApiRateLimitFilter(p, MAPPER);
    }

    /** 신뢰 프록시 뒤에서 {@code X-Real-IP} 하나만 실어 보내는, 운영과 같은 모양의 요청. */
    private static MockHttpServletResponse call(ApiRateLimitFilter filter,
                                                String method, String path, String realIp) throws Exception {
        return call(filter, method, path, BEHIND_PROXY, "X-Real-IP", realIp);
    }

    private static MockHttpServletResponse call(ApiRateLimitFilter filter,
                                                String method, String path,
                                                String remoteAddr,
                                                String headerName, String headerValue) throws Exception {
        MockHttpServletRequest request = new MockHttpServletRequest(method, path);
        request.setRequestURI(path);
        request.setRemoteAddr(remoteAddr);
        if (headerValue != null) {
            request.addHeader(headerName, headerValue);
        }
        MockHttpServletResponse response = new MockHttpServletResponse();
        filter.doFilter(request, response, new MockFilterChain());
        return response;
    }

    /** 한도까지 태우고, 한도+1 번째 응답을 돌려준다. */
    private static MockHttpServletResponse exhaust(ApiRateLimitFilter filter,
                                                   String method, String path, int limit) throws Exception {
        for (int i = 0; i < limit; i++) {
            MockHttpServletResponse ok = call(filter, method, path, "198.51.100.7");
            assertThat(ok.getStatus())
                    .as("한도 안(%d/%d)의 요청은 통과해야 한다", i + 1, limit)
                    .isEqualTo(200);
        }
        return call(filter, method, path, "198.51.100.7");
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
    @DisplayName("POST /auth/signup 도 login 버킷이다 — 한도+1 번째에서 429")
    void signupEndpoint_isRateLimited() throws Exception {
        // 이 분기가 없던 동안 회원가입은 **무제한**이었다. resolveRule 이 null 을 돌려주면
        // 필터가 그대로 통과시키기 때문이다 — 표에 없는 경로는 한도가 0 이 아니라 무한이다.
        // 계정 대량 생성은 이메일 열거와 스팸 계정의 입구다.
        // resolveRule 에서 이 분기를 지우면 여기가 빨간불이다.
        MockHttpServletResponse blocked = exhaust(filterWithLoginLimit(3), "POST", "/auth/signup", 3);

        assertThat(blocked.getStatus()).isEqualTo(429);
    }

    @Test
    @DisplayName("회원가입과 로그인은 같은 버킷을 나눠 쓴다 — 합쳐서 한도다")
    void signupAndLogin_shareTheSameBucket() throws Exception {
        // 버킷 이름이 같으므로 카운터도 같아야 한다. 따로 세면 한도가 사실상 두 배가 된다.
        ApiRateLimitFilter f = filterWithLoginLimit(2);

        assertThat(call(f, "POST", "/auth/login", "203.0.113.9").getStatus()).isNotEqualTo(429);
        assertThat(call(f, "POST", "/auth/signup", "203.0.113.9").getStatus()).isNotEqualTo(429);

        assertThat(call(f, "POST", "/auth/signup", "203.0.113.9").getStatus())
                .as("로그인 1 + 가입 1 로 한도 2 를 이미 썼으므로 세 번째는 막혀야 한다")
                .isEqualTo(429);
    }

    @Test
    @DisplayName("인증 경로가 아닌 곳은 인증 버킷에 걸리지 않는다")
    void unrelatedPath_isNotInTheAuthBucket() throws Exception {
        ApiRateLimitFilter filter = filter(1);
        // /auth/me 는 인증된 조회지 자격증명 경로가 아니다. 여기까지 묶으면 앱이 화면 전환마다 429 다.
        assertThat(call(filter, "GET", "/auth/me", "198.51.100.7").getStatus()).isEqualTo(200);
        assertThat(call(filter, "GET", "/auth/me", "198.51.100.7").getStatus()).isEqualTo(200);
        assertThat(call(filter, "GET", "/auth/me", "198.51.100.7").getStatus()).isEqualTo(200);
    }

    // ─────────────────── B. 카운터의 열쇠는 **위조할 수 없는** IP 다 ───────────────────
    //
    // 여기 있던 `X-Forwarded-For 가 다르면 카운터가 분리된다` 는 결함을 사양으로 고정하고
    // 있었다. 그 성질은 정확히 "헤더 한 줄로 한도를 없앨 수 있다" 와 같은 말이다.
    // 실측: 한도 5 에 매 요청 다른 XFF 로 1000건 → 429 **0건**.

    @Test
    @DisplayName("신뢰 프록시 뒤에서 X-Forwarded-For 를 위조해도 카운터가 갈라지지 않는다")
    void spoofedForwardedForHeader_doesNotSplitTheCounter() throws Exception {
        // 운영 nginx 는 X-Real-IP 를 $remote_addr 로 **덮어쓰고**, XFF 는
        // $proxy_add_x_forwarded_for 로 **덧붙인다**. 즉 XFF 앞부분은 클라이언트가 정한다.
        // 기본 ip-header 가 X-Real-IP 이므로 그 앞부분은 카운터에 아무 영향이 없어야 한다.
        ApiRateLimitFilter filter = filter(2);

        for (int i = 0; i < 2; i++) {
            MockHttpServletResponse ok = call(filter, "POST", "/auth/token/refresh",
                    BEHIND_PROXY, "X-Forwarded-For", "10.9.9." + i + ", 198.51.100.7");
            assertThat(ok.getStatus()).isEqualTo(200);
        }

        MockHttpServletResponse blocked = call(filter, "POST", "/auth/token/refresh",
                BEHIND_PROXY, "X-Forwarded-For", "10.9.9.99, 198.51.100.7");

        assertThat(blocked.getStatus())
                .as("XFF 를 매 요청 바꿔도 한도가 서야 한다 — 갈라지면 헤더 한 줄로 rate limit 이 사라진다")
                .isEqualTo(429);
    }

    @Test
    @DisplayName("신뢰 프록시 밖에서 온 연결의 IP 헤더는 아예 읽지 않는다")
    void ipHeaderFromUntrustedPeer_isIgnored() throws Exception {
        // 프록시 없이 노출된 배포. 헤더를 믿으면 아무나 자기 카운터를 새로 만들 수 있다.
        ApiRateLimitFilter filter = filter(2);

        for (int i = 0; i < 2; i++) {
            MockHttpServletResponse ok = call(filter, "POST", "/auth/token/refresh",
                    DIRECT_PUBLIC, "X-Real-IP", "10.1.1." + i);
            assertThat(ok.getStatus()).isEqualTo(200);
        }

        MockHttpServletResponse blocked = call(filter, "POST", "/auth/token/refresh",
                DIRECT_PUBLIC, "X-Real-IP", "10.1.1.99");

        assertThat(blocked.getStatus())
                .as("연결 반대편이 신뢰 프록시가 아니면 헤더는 그냥 요청자가 적은 문자열이다")
                .isEqualTo(429);
    }

    @Test
    @DisplayName("ip-header 를 X-Forwarded-For 로 두면 첫 원소가 아니라 마지막 홉을 쓴다")
    void forwardedForHeader_usesTheLastHopNotTheFirst() throws Exception {
        PublicSecurityProperties p = props(2);
        p.getRateLimit().setIpHeader("X-Forwarded-For");
        ApiRateLimitFilter filter = new ApiRateLimitFilter(p, MAPPER);

        // 신뢰 프록시가 1단일 때, 그 프록시가 실제로 본 주소는 **마지막** 원소다.
        for (int i = 0; i < 2; i++) {
            assertThat(call(filter, "POST", "/auth/token/refresh",
                    BEHIND_PROXY, "X-Forwarded-For", "1.2.3." + i + ", 198.51.100.7").getStatus())
                    .isEqualTo(200);
        }
        assertThat(call(filter, "POST", "/auth/token/refresh",
                BEHIND_PROXY, "X-Forwarded-For", "1.2.3.9, 198.51.100.7").getStatus())
                .as("앞 원소를 쓰면 여기서 200 이 나온다 — 그게 고치기 전의 동작이었다")
                .isEqualTo(429);

        // 마지막 홉이 다르면(= 실제로 다른 클라이언트) 여전히 카운터가 분리된다.
        assertThat(call(filter, "POST", "/auth/token/refresh",
                BEHIND_PROXY, "X-Forwarded-For", "1.2.3.9, 198.51.100.8").getStatus())
                .as("한 사람이 전체를 잠글 수 있으면 그것도 결함이다")
                .isEqualTo(200);
    }

    @Test
    @DisplayName("서로 다른 실제 클라이언트는 카운터가 분리된다")
    void realClients_stillHaveTheirOwnCounters() throws Exception {
        ApiRateLimitFilter filter = filter(1);

        assertThat(call(filter, "POST", "/auth/token/refresh", "198.51.100.1").getStatus()).isEqualTo(200);
        assertThat(call(filter, "POST", "/auth/token/refresh", "198.51.100.1").getStatus())
                .as("같은 IP 의 두 번째 요청은 한도(1)를 넘는다")
                .isEqualTo(429);

        assertThat(call(filter, "POST", "/auth/token/refresh", "198.51.100.2").getStatus())
                .as("다른 IP 의 첫 요청까지 막으면 한 사람이 전체를 잠글 수 있다")
                .isEqualTo(200);
    }

    @Test
    @DisplayName("신뢰 프록시 목록이 비면 헤더를 아무도 못 쓴다 — 열어 두는 쪽으로 실패하지 않는다")
    void emptyTrustedProxyList_meansNoHeaderIsTrusted() throws Exception {
        PublicSecurityProperties p = props(1);
        p.getRateLimit().setTrustedProxies(List.of());
        ApiRateLimitFilter filter = new ApiRateLimitFilter(p, MAPPER);

        assertThat(call(filter, "POST", "/auth/token/refresh",
                BEHIND_PROXY, "X-Real-IP", "198.51.100.1").getStatus()).isEqualTo(200);
        assertThat(call(filter, "POST", "/auth/token/refresh",
                BEHIND_PROXY, "X-Real-IP", "198.51.100.2").getStatus())
                .as("목록이 비었으면 헤더가 무시되고 둘 다 127.0.0.1 로 센다")
                .isEqualTo(429);
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
        // 이 단언은 예전에 `doesNotContain("bucket")` 하나뿐이었다. 그래서 본문을 옛 평면
        // 구조({"limit":1,"windowSeconds":3600,...})로 되돌려도 초록이었다 — 이름이
        // 약속한 "내부 한도 수치" 를 아무도 지키지 않고 있었다. 키 집합을 동등 비교한다.
        MockHttpServletResponse blocked = exhaust(filter(1), "POST", "/auth/oauth/kakao/callback", 1);

        @SuppressWarnings("unchecked")
        Map<String, Object> body = MAPPER.readValue(blocked.getContentAsString(), Map.class);
        assertThat(body.keySet()).containsExactly("error");

        @SuppressWarnings("unchecked")
        Map<String, Object> error = (Map<String, Object>) body.get("error");
        assertThat(error.keySet())
                .as("여기에 키가 하나라도 더 붙으면 그것이 곧 내부 분류의 유출이다")
                .containsExactlyInAnyOrder("code", "message", "traceId");

        String raw = blocked.getContentAsString();
        assertThat(raw)
                .as("버킷 이름·한도 수치·창 길이는 서버 내부 구현이다 — 응답에 실으면 그대로 새어 나간다")
                .doesNotContain("bucket")
                .doesNotContain("limit")
                .doesNotContain("windowSeconds")
                .doesNotContain("\"auth\"");
    }

    @Test
    @DisplayName("429 는 Retry-After 를 창 길이(초)로 붙인다")
    void tooManyRequests_carriesRetryAfter() throws Exception {
        MockHttpServletResponse blocked = exhaust(filter(1), "POST", "/auth/token/refresh", 1);

        assertThat(blocked.getHeader("Retry-After"))
                .as("앱은 이 값을 보고 기다린다. 없으면 즉시 재시도해 카운터를 더 태운다")
                .isEqualTo("3600");
    }

    // ─────────────────── D. 스위치가 실제로 끈다 ───────────────────

    @Test
    @DisplayName("rate-limit.enabled=false 면 한도를 넘겨도 통과한다")
    void disabledSwitch_turnsTheLimiterOff() throws Exception {
        PublicSecurityProperties p = props(1);
        p.getRateLimit().setEnabled(false);
        ApiRateLimitFilter filter = new ApiRateLimitFilter(p, MAPPER);

        assertThat(call(filter, "POST", "/auth/token/refresh", "198.51.100.7").getStatus()).isEqualTo(200);
        assertThat(call(filter, "POST", "/auth/token/refresh", "198.51.100.7").getStatus()).isEqualTo(200);
    }
}
