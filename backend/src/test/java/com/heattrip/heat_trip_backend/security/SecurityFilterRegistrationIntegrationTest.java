package com.heattrip.heat_trip_backend.security;

import com.heattrip.heat_trip_backend.OAuth.jwt.JWTAuthenticationFilter;
import com.heattrip.heat_trip_backend.OAuth.jwt.JWTProvider;
import com.heattrip.heat_trip_backend.OAuth.state.OAuthAppStateFilter;
import com.heattrip.heat_trip_backend.support.AbstractMySqlIntegrationTest;
import com.heattrip.heat_trip_backend.user.entity.User;
import com.heattrip.heat_trip_backend.user.repository.UserRepository;

import jakarta.servlet.Filter;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.Mockito;
import org.springframework.beans.factory.ListableBeanFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.web.servlet.FilterRegistrationBean;
import org.springframework.boot.web.servlet.ServletContextInitializerBeans;
import org.springframework.http.MediaType;
import org.springframework.security.web.FilterChainProxy;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.context.bean.override.mockito.MockitoSpyBean;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;

import java.util.Arrays;
import java.util.Collections;
import java.util.IdentityHashMap;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.Set;
import java.util.TreeMap;
import java.util.concurrent.atomic.AtomicLong;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * 시큐리티 체인에 붙인 필터는 <b>등록 자리가 하나</b>다 — 이슈 #661.
 *
 * <h2>무엇이 문제였나</h2>
 *
 * <p>스프링 부트는 {@code Filter} 타입 빈을 <b>서블릿 컨테이너에 자동으로도</b> 등록한다. 우리 필터는
 * {@code @Component} 라 빈이고, {@code SecurityConfig} 가 같은 인스턴스를 시큐리티 체인에도 붙인다.
 * 그래서 등록이 둘이었다 — 시큐리티 체인 안의 자리 하나, 서블릿 컨테이너의 자리 하나. 요청 하나에
 * {@code doFilter} 가 두 번 불렸고, 두 번째는 {@code OncePerRequestFilter} 의 중복 방지에 걸려 넘어갔다.
 *
 * <p>평소에는 동작이 똑같다. <b>문제는 {@code SecurityConfig} 의 등록 줄을 지웠을 때다.</b> 서블릿 쪽
 * 자동 등록분이 대신 돌아서 아무 테스트도 빨간불이 되지 않는다(#660 에서 실제로 7개가 전부 초록이었다).
 * 그러면 "이 줄이 막고 있다" 를 아무도 증명할 수 없다. 게다가 그 자리는 인가 필터 <b>뒤</b>라 순서가
 * 다르다 — 본문 크기 검사가 인증 뒤로 밀리고, 진입점 요청은 302 로 끝난 뒤라 아예 못 본다.
 *
 * <h2>여기서 재는 것 셋</h2>
 * <ol>
 *   <li><b>요청 하나에 필터마다 {@code doFilter} 가 한 번</b> — 스파이로 실제 호출 수를 센다. 자동 등록을
 *       되살리면 2 가 된다.</li>
 *   <li><b>체인의 필터 빈은 전부 서블릿 등록이 꺼져 있다</b> — 새 필터를 {@code @Component} 로 만들고
 *       체인에만 붙이면 이 문제가 조용히 다시 생긴다. 부트가 서블릿 컨테이너에 무엇을 등록하는지를
 *       {@link ServletContextInitializerBeans} 로 그대로 읽어 잡는다.</li>
 *   <li><b>체인의 그 줄이 실제로 막는다</b> — 등록이 하나뿐이어야 이 검사가 뜻을 가진다. 채팅 한도가
 *       사용자 단위로 서는지 · 본문 크기가 <b>인증 전에</b> 잘리는지 · 앱의 {@code state} 가 진입점에서
 *       붙드는지를 배포되는 체인으로 잰다. {@code ApiRateLimitFilter} 는
 *       {@link ApiRateLimitFilterChainOrderIntegrationTest} 가, {@code ConsentRequiredFilter} 는
 *       {@link ConsentRequiredIntegrationTest} 가 같은 방식으로 잰다.</li>
 * </ol>
 *
 * <p>{@code JWTAuthenticationFilter} 는 여기 없다 — 빈이 아니라 {@code new} 로 만들어 체인에만 넣으므로
 * 자동 등록 자체가 없다. 2번 검사가 체인에 있는 것을 확인만 한다.
 *
 * <p>{@code @MockitoSpyBean} 과 {@code @TestPropertySource} 가 붙어 있어 이 클래스는 컨텍스트를 하나 더
 * 띄운다(#21). 호출 수는 스파이 없이는 셀 수 없고, 채팅 한도는 낮춰야 3번 요청에서 429 를 볼 수 있다 —
 * 그래서 하나로 모았다.
 */
@SpringBootTest
@AutoConfigureMockMvc
@TestPropertySource(properties = {
        "app.security.rate-limit.enabled=true",
        "app.security.rate-limit.chat-poll-max-requests=2",
        // 창이 짧으면 테스트 도중 창이 넘어가 카운터가 초기화될 수 있다.
        "app.security.rate-limit.window-seconds=3600"
})
class SecurityFilterRegistrationIntegrationTest extends AbstractMySqlIntegrationTest {

    /** 이메일이 UNIQUE 라 테스트끼리 겹치지 않게 번호를 준다. */
    private static final AtomicLong ACCOUNT_SEQUENCE = new AtomicLong();

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private FilterChainProxy filterChainProxy;

    @Autowired
    private ListableBeanFactory beanFactory;

    @Autowired
    private UserRepository userRepository;

    @Autowired
    private JWTProvider jwtProvider;

    @MockitoSpyBean
    private ApiRateLimitFilter apiRateLimitFilter;

    @MockitoSpyBean
    private ChatBodySizeLimitFilter chatBodySizeLimitFilter;

    @MockitoSpyBean
    private ChatRateLimitFilter chatRateLimitFilter;

    @MockitoSpyBean
    private ConsentRequiredFilter consentRequiredFilter;

    @MockitoSpyBean
    private OAuthAppStateFilter oAuthAppStateFilter;

    /** 이름 → 스파이. 스파이의 {@code getClass()} 에 기대지 않고 이름을 직접 적는다. */
    private Map<String, Filter> chainFilterSpies() {
        Map<String, Filter> spies = new LinkedHashMap<>();
        spies.put("ApiRateLimitFilter", apiRateLimitFilter);
        spies.put("ChatBodySizeLimitFilter", chatBodySizeLimitFilter);
        spies.put("ChatRateLimitFilter", chatRateLimitFilter);
        spies.put("ConsentRequiredFilter", consentRequiredFilter);
        spies.put("OAuthAppStateFilter", oAuthAppStateFilter);
        return spies;
    }

    // ─────────────────────── 1. 요청 하나에 한 번 ───────────────────────

    /**
     * 요청은 <b>체인을 끝까지 지나 서블릿에 닿는 것</b>이어야 한다. 401 로 끝나는 요청은 시큐리티 체인
     * 안에서 끊겨 서블릿 쪽 자동 등록분까지 가지 않으므로, 등록이 둘이어도 1 로 보인다 — 그러면 이
     * 검사는 아무것도 못 잡는다. 게스트에게 열린 읽기라 다섯 필터를 전부 지나 컨트롤러까지 간다.
     */
    @Test
    @DisplayName("요청 하나에 체인의 필터마다 doFilter 가 정확히 한 번이다 — 자동 등록이 살아 있으면 두 번이다")
    void eachChainFilter_entersARequestExactlyOnce() throws Exception {
        Map<String, Filter> spies = chainFilterSpies();
        Mockito.clearInvocations(spies.values().toArray());

        mockMvc.perform(get("/api/community/posts")).andExpect(status().isOk());

        Map<String, Long> entries = new TreeMap<>();
        spies.forEach((name, spy) -> entries.put(name, Mockito.mockingDetails(spy).getInvocations().stream()
                .filter(invocation -> "doFilter".equals(invocation.getMethod().getName()))
                .count()));

        Map<String, Long> once = new TreeMap<>();
        spies.keySet().forEach(name -> once.put(name, 1L));

        assertThat(entries)
                .as("""
                        요청 하나에 필터가 들어온 횟수. 2 면 등록이 둘이다 — 시큐리티 체인 한 번, 서블릿 \
                        자동 등록 한 번. 그 필터의 FilterRegistrationBean(setEnabled(false)) 이 \
                        SecurityConfig 에서 사라졌거나, 새 필터를 @Component 로만 만들었다. 0 이면 이 \
                        요청이 그 필터까지 안 간 것이라 검사 자체가 잘못됐다.""")
                .containsExactlyInAnyOrderEntriesOf(once);
    }

    // ─────────────────────── 2. 등록 자리 하나 — 게이트 ───────────────────────

    /**
     * 부트가 서블릿 컨테이너에 등록할 목록을 {@link ServletContextInitializerBeans} 로 읽는다 —
     * 실제 기동에서 {@code ServletWebServerApplicationContext} 가 쓰는 바로 그 목록이다. 등록 빈이 없는
     * {@code Filter} 빈은 여기서 <b>켜진</b> 등록으로 나타나고, {@code setEnabled(false)} 로 둔 것은
     * 꺼진 등록으로 나타난다. {@code MockMvc} 도 같은 목록에서 켜진 것만 붙인다.
     */
    @Test
    @DisplayName("시큐리티 체인에 있는 필터 빈은 전부 서블릿 자동 등록이 꺼져 있다 — 새 @Component 필터가 여기 걸린다")
    void everyChainFilterBean_hasItsServletRegistrationDisabled() {
        Set<Filter> inChain = Collections.newSetFromMap(new IdentityHashMap<>());
        filterChainProxy.getFilterChains().forEach(chain -> inChain.addAll(chain.getFilters()));
        assertThat(inChain)
                .as("체인이 비었다면 아래 단언은 아무것도 안 본다")
                .isNotEmpty();
        assertThat(inChain.stream().map(Filter::getClass).toList())
                .as("JWT 필터는 new 로 만들어 체인에만 넣는다 — 빈이 아니라 자동 등록이 없다")
                .contains(JWTAuthenticationFilter.class);

        // 체인에 있으면서 빈이기도 한 필터 — 자동 등록의 대상이 되는 것들
        Map<String, Filter> chainBeans = new TreeMap<>();
        beanFactory.getBeansOfType(Filter.class).values().stream()
                .filter(inChain::contains)
                .forEach(bean -> chainBeans.put(bean.getClass().getSimpleName(), bean));
        assertThat(chainBeans)
                .as("체인에 있는 필터 빈을 하나도 못 찾았다면 이 검사는 빈 목록을 보고 통과한다")
                .isNotEmpty();

        // 부트가 서블릿 컨테이너에 등록하는 것 — 필터 등록만 추린다
        Map<String, String> servletSide = new TreeMap<>();
        new ServletContextInitializerBeans(beanFactory).stream()
                .filter(FilterRegistrationBean.class::isInstance)
                .map(initializer -> (FilterRegistrationBean<?>) initializer)
                .filter(registration -> inChain.contains(registration.getFilter()))
                .forEach(registration -> servletSide.merge(
                        registration.getFilter().getClass().getSimpleName(),
                        registration.isEnabled() ? "켜짐 — 두 번 등록" : "꺼짐",
                        (a, b) -> a + " + " + b));

        assertThat(servletSide.keySet())
                .as("""
                        체인의 필터 빈마다 서블릿 등록 항목이 하나씩 있어야 한다. 등록 빈이 없으면 부트가 \
                        어댑터를 만들어 '켜짐' 으로 나타나므로, 여기 없다는 것은 목록을 못 읽은 것이다.""")
                .containsExactlyInAnyOrderElementsOf(chainBeans.keySet());

        Map<String, String> allDisabled = new TreeMap<>();
        chainBeans.keySet().forEach(name -> allDisabled.put(name, "꺼짐"));
        assertThat(servletSide)
                .as("""
                        시큐리티 체인에 붙인 필터가 서블릿 컨테이너에도 등록돼 있다. 그러면 요청마다 두 번 \
                        들어오고, 체인의 등록 줄을 지워도 자동 등록분이 대신 돌아 아무 테스트도 빨간불이 \
                        되지 않는다(#661). SecurityConfig 에 그 필터의 FilterRegistrationBean 을 만들어 \
                        setEnabled(false) 로 두어라 — 다른 필터들이 그 본보기다.""")
                .containsExactlyInAnyOrderEntriesOf(allDisabled);
    }

    // ─────────────────────── 3. 체인의 그 줄이 실제로 막는다 ───────────────────────

    /**
     * {@code ChatRateLimitFilter} 는 JWT 필터 <b>뒤</b>라 사용자 단위로 센다(#80). 등록이 둘일 때는 이
     * 줄을 지워도 서블릿 쪽 자동 등록분이 — 그 자리도 인증 뒤라 — 똑같이 세서 초록이었다.
     */
    @Test
    @DisplayName("배포되는 체인에서 채팅 폴링은 한도+1 번째에 429 이고, 같은 IP 의 다른 사용자는 막히지 않는다")
    void chatPolling_isLimitedPerUserOnTheDeployedChain() throws Exception {
        String first = tokenFor(freshConsentedUser("첫째"));
        String second = tokenFor(freshConsentedUser("둘째"));
        String sharedIp = "198.51.100.31";

        for (int i = 1; i <= 2; i++) {
            mockMvc.perform(get("/api/chat/rooms")
                            .header("Authorization", "Bearer " + first)
                            .header("X-Real-IP", sharedIp))
                    .andExpect(status().isOk());
        }
        mockMvc.perform(get("/api/chat/rooms")
                        .header("Authorization", "Bearer " + first)
                        .header("X-Real-IP", sharedIp))
                .andExpect(status().isTooManyRequests());

        mockMvc.perform(get("/api/chat/rooms")
                        .header("Authorization", "Bearer " + second)
                        .header("X-Real-IP", sharedIp))
                .andExpect(status().isOk());
    }

    /**
     * {@code ChatBodySizeLimitFilter} 는 체인 <b>맨 앞</b>이다(#129) — 인증보다도 앞. 그래서 토큰 없이
     * 보내도 401 이 아니라 400 이어야 한다. 이 줄을 지우면 필터가 어디에도 없어 401 이 되고, 인증 뒤로
     * 밀려도 401 이 된다.
     */
    @Test
    @DisplayName("배포되는 체인에서 너무 큰 채팅 본문은 인증보다 먼저 400 이다 — 토큰이 없어도")
    void oversizedChatBody_isRejectedBeforeAuthentication() throws Exception {
        byte[] body = new byte[ChatBodySizeLimitFilter.MAX_REQUEST_BYTES + 1];
        Arrays.fill(body, (byte) 'a');

        mockMvc.perform(post("/api/chat/rooms/1/messages")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(body))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error.code").value("PAYLOAD_TOO_LARGE"));
    }

    /**
     * {@code OAuthAppStateFilter} 는 진입점 리다이렉트 필터 <b>앞</b>이다(#14). 리다이렉트 필터는 302 를
     * 쓰고 체인을 끊으므로, 뒤에 있으면 — 서블릿 쪽 자동 등록분이 정확히 그 자리다 — 앱이 붙인
     * {@code state} 를 영영 못 본다.
     */
    @Test
    @DisplayName("배포되는 체인에서 소셜 진입 요청의 state 가 세션에 붙든다")
    void appState_isCapturedOnTheDeployedChain() throws Exception {
        MvcResult result = mockMvc.perform(get("/oauth2/authorization/kakao").param("state", "abc123_-XYZ"))
                .andReturn();

        assertThat(result.getResponse().getStatus())
                .as("진입은 공급자로 302 여야 한다 — 여기가 깨지면 소셜 로그인 자체가 막힌 것이다")
                .isEqualTo(302);
        assertThat(OAuthAppStateFilter.consume(result.getRequest()))
                .as("체인에서 진입점 리다이렉트보다 뒤면 302 로 끝난 뒤라 여기까지 오지 않는다")
                .isEqualTo("abc123_-XYZ");
    }

    // ─────────────────────── 지그 ───────────────────────

    private User freshConsentedUser(String name) {
        long serial = ACCOUNT_SEQUENCE.incrementAndGet();
        return consented(userRepository.save(User.builder()
                .provider(User.PROVIDER_LOCAL)
                .role(User.ROLE_USER)
                .email("filter661-%d-%d@example.com".formatted(System.nanoTime(), serial))
                .name(name)
                .nickname(name + serial)
                .build()));
    }

    private String tokenFor(User user) {
        return jwtProvider.createAccessToken(user.getId(), user.getRole());
    }
}
