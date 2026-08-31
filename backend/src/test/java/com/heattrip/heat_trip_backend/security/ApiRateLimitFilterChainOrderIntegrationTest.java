package com.heattrip.heat_trip_backend.security;

import com.heattrip.heat_trip_backend.OAuth.state.OAuthAppStateFilter;
import com.heattrip.heat_trip_backend.support.AbstractMySqlIntegrationTest;

import jakarta.servlet.Filter;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.security.oauth2.client.web.OAuth2AuthorizationRequestRedirectFilter;
import org.springframework.security.web.FilterChainProxy;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;

import java.util.ArrayList;
import java.util.List;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;

/**
 * rate limit 필터가 <b>배포되는 체인의 어느 자리</b>에 있는지를 잠근다. (이슈 #14)
 *
 * <h2>왜 단위 테스트로는 안 되는가</h2>
 * {@link ApiRateLimitFilterTest} 는 필터를 직접 태운다. 그래서 {@code resolveRule} 이
 * {@code /oauth2/authorization/*} 를 인증 버킷으로 묶는다는 것까지는 증명하지만,
 * <b>그 요청이 필터까지 오는지</b>는 정의상 볼 수 없다.
 *
 * <p>실제로 그것이 오지 않았다. 필터가
 * {@code addFilterBefore(apiRateLimitFilter, JWTAuthenticationFilter.class)} 로 등록돼
 * {@link OAuth2AuthorizationRequestRedirectFilter} <b>뒤</b>에 있었고, 그 리다이렉트 필터는
 * 진입점 요청에 302 를 쓰고 {@code chain.doFilter} 를 부르지 않은 채 끝낸다. 한도 2 로
 * 진입점을 6번 쳐도 전부 302 였고, 곧이어 같은 버킷의 {@code POST /auth/token/refresh} 가
 * 401,401,429 를 냈다 — 앞선 6건이 카운터에 한 건도 들어가지 않았다는 뜻이다.
 * 코드도 있고 테스트도 초록인데 운영에서는 아무 일도 하지 않는, 회귀보다 나쁜 상태였다.
 *
 * <p>카운터의 열쇠가 IP 이므로 <b>테스트마다 다른 {@code X-Real-IP} 를 쓴다</b>.
 * 필터는 컨텍스트의 싱글턴이라 카운터가 메서드 사이에 공유되고, 같은 IP 를 쓰면 앞
 * 테스트가 소진한 카운터가 뒤 테스트의 판정을 바꾼다.
 * (MockMvc 의 {@code remoteAddr} 는 {@code 127.0.0.1} 이라 기본 신뢰 프록시 목록 안이고,
 * 그래서 이 헤더가 해석된다 — 운영의 nginx 뒤와 같은 조건이다.)
 */
@SpringBootTest
@AutoConfigureMockMvc
@TestPropertySource(properties = {
        "app.security.rate-limit.enabled=true",
        "app.security.rate-limit.auth-max-requests=2",
        // 창이 짧으면 테스트 도중 창이 넘어가 카운터가 초기화될 수 있다. 여기서 재는 것은
        // 시간 경과가 아니라 "한도가 실제로 서는가" 다.
        "app.security.rate-limit.window-seconds=3600"
})
class ApiRateLimitFilterChainOrderIntegrationTest extends AbstractMySqlIntegrationTest {

    private static final String ENTRY_POINT = "/oauth2/authorization/kakao";

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private FilterChainProxy filterChainProxy;

    @Autowired
    private RateLimitProperties rateLimitProperties;

    @Test
    @DisplayName("배포되는 설정의 IP 헤더는 nginx 가 덮어쓰는 X-Real-IP 이고 신뢰 프록시 목록이 비어 있지 않다")
    void shippedConfiguration_trustsOnlyTheOverwrittenHeader() {
        var rateLimit = rateLimitProperties;

        assertThat(rateLimit.getIpHeader())
                .as("""
                    nginx 템플릿은 X-Forwarded-For 를 $proxy_add_x_forwarded_for 로 **덧붙이고**
                    X-Real-IP 를 $remote_addr 로 **덮어쓴다**. 덧붙이는 헤더로 되돌리면 그 값의
                    앞부분은 다시 공격자가 정한다. 이 단언은 POJO 기본값이 아니라
                    application.properties 가 실제로 바인딩된 값을 본다""")
                .isEqualTo("X-Real-IP");

        assertThat(rateLimit.getTrustedProxies())
                .as("목록이 비면 헤더가 통째로 무시되어 프록시 뒤 전 사용자가 한 카운터를 나눠 쓴다")
                .isNotEmpty()
                .contains("127.0.0.1/32");
    }

    @Test
    @DisplayName("ApiRateLimitFilter 가 소셜 진입점 리다이렉트 필터보다 앞에 등록돼 있다")
    void rateLimitFilter_isRegisteredBeforeTheAuthorizationRedirectFilter() {
        List<Class<?>> order = new ArrayList<>();
        for (var chain : filterChainProxy.getFilterChains()) {
            for (Filter filter : chain.getFilters()) {
                order.add(filter.getClass());
            }
        }

        int rateLimit = order.indexOf(ApiRateLimitFilter.class);
        int redirect = order.indexOf(OAuth2AuthorizationRequestRedirectFilter.class);
        int stateCapture = order.indexOf(OAuthAppStateFilter.class);

        assertThat(rateLimit).as("필터가 체인에 아예 없다").isGreaterThanOrEqualTo(0);
        assertThat(redirect).as("소셜 진입점 리다이렉트 필터가 체인에 없다").isGreaterThanOrEqualTo(0);
        assertThat(rateLimit)
                .as("뒤에 있으면 진입점 요청이 302 로 끝난 뒤라 필터까지 오지 않는다. 실제 체인 순서: %s",
                        order.stream().map(Class::getSimpleName).toList())
                .isLessThan(redirect);
        assertThat(rateLimit)
                .as("state 캡처보다도 앞이어야 한도를 넘긴 요청이 세션조차 만들지 않는다")
                .isLessThan(stateCapture);
    }

    @Test
    @DisplayName("실제 체인에서 GET /oauth2/authorization/{provider} 가 한도+1 번째에 429 다")
    void socialEntryPoint_isRateLimitedOnTheDeployedChain() throws Exception {
        String clientIp = "198.51.100.21";

        // 한도(2) 안에서는 여전히 공급자로 302 한다 — 순서를 바꾸면서 소셜 로그인 진입
        // 자체가 막히지 않았는지도 같은 테스트가 확인한다.
        for (int i = 1; i <= 2; i++) {
            MvcResult ok = mockMvc.perform(get(ENTRY_POINT)
                            .param("state", "abc123")
                            .header("X-Real-IP", clientIp))
                    .andReturn();
            assertThat(ok.getResponse().getStatus())
                    .as("한도 안(%d/2)의 진입은 302 여야 한다", i)
                    .isEqualTo(302);
            assertThat(ok.getResponse().getRedirectedUrl())
                    .as("공급자 인가 URL 로 나가야 한다 — 여기가 깨지면 소셜 로그인 자체가 막힌 것이다")
                    .contains("kauth.kakao.com");
        }

        int blocked = mockMvc.perform(get(ENTRY_POINT)
                        .param("state", "abc123")
                        .header("X-Real-IP", clientIp))
                .andReturn().getResponse().getStatus();

        assertThat(blocked)
                .as("계약(openapi.yaml)이 이 경로에 429 를 선언했다. 실제로 나지 않으면 계약이 거짓말이다")
                .isEqualTo(429);
    }

    @Test
    @DisplayName("한도를 넘긴 진입 요청은 세션을 만들지 않는다")
    void blockedEntryPointRequest_createsNoSession() throws Exception {
        String clientIp = "198.51.100.22";

        for (int i = 0; i < 2; i++) {
            mockMvc.perform(get(ENTRY_POINT).param("state", "abc123").header("X-Real-IP", clientIp));
        }

        MvcResult blocked = mockMvc.perform(get(ENTRY_POINT)
                        .param("state", "abc123")
                        .header("X-Real-IP", clientIp))
                .andReturn();

        assertThat(blocked.getResponse().getStatus()).isEqualTo(429);
        assertThat(blocked.getRequest().getSession(false))
                .as("거절된 요청이 세션을 만들면, 인증 없는 GET 반복만으로 세션 저장소를 부풀릴 수 있다")
                .isNull();
    }
}
