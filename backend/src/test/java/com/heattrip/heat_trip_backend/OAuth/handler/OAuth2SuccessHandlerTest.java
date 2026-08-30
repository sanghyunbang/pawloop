package com.heattrip.heat_trip_backend.OAuth.handler;

import com.heattrip.heat_trip_backend.OAuth.code.AuthCode;
import com.heattrip.heat_trip_backend.OAuth.code.AuthCodeStore;
import com.heattrip.heat_trip_backend.OAuth.state.OAuthAppStateFilter;
import com.heattrip.heat_trip_backend.OAuth.user.CustomOAuth2User;
import com.heattrip.heat_trip_backend.OAuth.user.GoogleOAuth2User;
import com.heattrip.heat_trip_backend.OAuth.user.OAuth2UserInfo;
import com.heattrip.heat_trip_backend.config.OAuthSecurityProperties;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.security.oauth2.client.authentication.OAuth2AuthenticationToken;

import java.net.URI;
import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.Set;
import java.util.function.Consumer;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * 성공 딥링크에 <b>무엇이 실려 나가는가</b> 를 잠근다 — 이슈 #14 완료 조건 1·5·9.
 *
 * <p>스프링 컨텍스트도 네트워크도 없다. 성공 핸들러 하나만 태우고
 * {@code MockHttpServletResponse.getRedirectedUrl()} 을 {@link URI} 로 파싱한다.
 *
 * <p><b>"token 문자열이 없다" 로 단언하지 않는다.</b> 쿼리 <b>키 집합 동등 비교</b>다 —
 * 그래야 {@code token} 을 {@code accessToken} 이나 {@code at} 으로 이름만 바꿔 되살리는
 * 회귀도 걸린다. 딥링크를 {@code ?token=} 형태로 되돌리면 이 클래스가 빨간불이다(완료 조건 9).
 */
class OAuth2SuccessHandlerTest {

    /** 구글이 준 소셜 ID. 예전에는 이 값이 그대로 JWT subject 였다. */
    private static final String PROVIDER_ID = "109876543210987654321";

    private static final long USER_ID = 42L;

    private static final String ALLOWED = "heattrip://login-callback";

    private static final Instant BASE = Instant.parse("2026-08-30T12:00:00Z");

    // ─────────────────── A. 딥링크에 실리는 것 (완료 조건 1·9) ───────────────────

    @Test
    @DisplayName("성공 딥링크의 쿼리 키 집합은 정확히 {code, state} 다 — token·accessToken 은 없다")
    void 성공딥링크의_쿼리키집합은_code와_state뿐이다() throws Exception {
        String url = redirect(principal(USER_ID), request -> {}).getRedirectedUrl();

        assertThat(queryKeys(url))
                .as("키 집합 동등 비교여야 이름만 바꾼 회귀(token→accessToken)도 걸린다")
                .containsExactlyInAnyOrder("code", "state");
    }

    @Test
    @DisplayName("딥링크 어디에도 액세스 토큰·refresh 토큰이 실리지 않는다")
    void 딥링크에_토큰이_실리지_않는다() throws Exception {
        String url = redirect(principal(USER_ID), request -> {}).getRedirectedUrl();

        // 커스텀 스킴은 어느 앱이든 등록할 수 있고, 이 URL 은 302 의 Location 헤더와
        // 브라우저 히스토리에 남는다. 그 채널로 14일짜리 자격증명이 나가고 있었다.
        assertThat(url).doesNotContain("token=", "refresh=", "eyJ");
    }

    @Test
    @DisplayName("딥링크의 code 는 저장소에 살아 있는 1회용 코드다 — 교환이 실제로 성립한다")
    void 딥링크의_code는_교환가능한_코드다() throws Exception {
        AuthCodeStore store = store();
        MockHttpServletResponse response = redirect(principal(USER_ID), store, request -> {});

        String code = queryParam(response.getRedirectedUrl(), "code");
        Optional<AuthCode> consumed = store.consume(code);

        assertThat(consumed).isPresent();
        assertThat(consumed.get().userId()).isEqualTo(USER_ID);
        assertThat(consumed.get().provider())
                .as("교환 요청의 경로 변수와 대조하려면 공급자가 코드에 실려 있어야 한다")
                .isEqualTo("google");
    }

    @Test
    @DisplayName("신규 가입 여부가 코드에 실린다 — 소셜 온보딩 분기가 여기서 살아난다")
    void 신규가입여부가_코드에_실린다() throws Exception {
        AuthCodeStore store = store();
        MockHttpServletResponse response = redirect(newUserPrincipal(), store, request -> {});

        AuthCode consumed = store.consume(queryParam(response.getRedirectedUrl(), "code")).orElseThrow();

        assertThat(consumed.isNew())
                .as("URL 쿼리로는 표현할 방법이 없어 소셜 신규 가입자가 온보딩으로 가지 못했다")
                .isTrue();
    }

    @Test
    @DisplayName("앱이 보낸 state 가 딥링크로 그대로 돌아온다 — 앱이 대조할 수 있어야 한다")
    void 앱이보낸_state가_그대로_돌아온다() throws Exception {
        // state 는 앱이 만들어 앱이 대조해야 의미가 있다. 서버가 만들어 서버가 대조하면
        // 응답 바꿔치기를 막지 못한다.
        String url = redirect(principal(USER_ID), request -> {
            request.setRequestURI("/oauth2/authorization/google");
            request.setParameter("state", "app-state-xyz");
            captureState(request);
        }).getRedirectedUrl();

        assertThat(queryParam(url, "state")).isEqualTo("app-state-xyz");
    }

    @Test
    @DisplayName("state 를 보내지 않은 요청에도 state 키는 남는다 — 앱쪽 대조가 실패해야 하기 때문이다")
    void state가없으면_빈값으로_나간다() throws Exception {
        String url = redirect(principal(USER_ID), request -> {}).getRedirectedUrl();

        assertThat(queryKeys(url)).contains("state");
        assertThat(queryParam(url, "state"))
                .as("state 없이 성공시키면 검사가 있다고 말할 수 없다")
                .isEmpty();
    }

    @Test
    @DisplayName("성공 리다이렉트 응답에 Cache-Control: no-store 가 붙는다")
    void 성공리다이렉트에_no_store가_붙는다() throws Exception {
        MockHttpServletResponse response = redirect(principal(USER_ID), request -> {});

        assertThat(response.getHeader("Cache-Control")).isEqualTo("no-store");
    }

    // ─────────────────── B. users.id 가 없을 때 ───────────────────

    @Test
    @DisplayName("users.id 를 모르는 principal 이 오면 코드를 발급하지 않고 실패 딥링크로 돌려보낸다")
    void userId가없으면_코드없이_실패딥링크로_보낸다() throws Exception {
        AuthCodeStore store = store();

        MockHttpServletResponse response = redirect(principal(null), store, request -> {});

        assertThat(response.getRedirectedUrl())
                .isEqualTo("heattrip://login-callback?error=account_state_invalid");
        assertThat(store.size())
                .as("주체 없는 코드를 발급하면 교환 시점에 sub=\"null\" 토큰이 되어 그 계정은 영구 401 이다")
                .isZero();
    }

    // ─────────────────── C. 리다이렉트 allowlist (완료 조건 5) ───────────────────

    @Test
    @DisplayName("요청 파라미터 redirect_uri 로 외부 URL 을 주입해도 허용 목록의 대상으로만 간다")
    void 요청이_말한_대상은_허용목록에_없으면_쓰이지_않는다() throws Exception {
        String url = redirect(principal(USER_ID), request ->
                request.setParameter("redirect_uri", "https://evil.example/steal")).getRedirectedUrl();

        assertThat(url).startsWith(ALLOWED + "?");
        assertThat(url).doesNotContain("evil.example");
    }

    @Test
    @DisplayName("Referer·X-Forwarded-Host 헤더로 외부 URL 을 주입해도 리다이렉트 대상이 바뀌지 않는다")
    void 헤더로_주입한_URL은_대상이_되지_않는다() throws Exception {
        // 이 헤더들은 아예 읽지 않는다. 읽지 않는 것이 검사하는 것보다 강하다.
        String url = redirect(principal(USER_ID), request -> {
            request.addHeader("Referer", "https://evil.example/login");
            request.addHeader("X-Forwarded-Host", "evil.example");
            request.addHeader("Host", "evil.example");
        }).getRedirectedUrl();

        assertThat(url).startsWith(ALLOWED + "?");
        assertThat(url).doesNotContain("evil.example");
    }

    @Test
    @DisplayName("허용 목록에 있는 값을 요청하면 그 대상으로 간다")
    void 허용목록에_있는_대상은_그대로_쓰인다() throws Exception {
        OAuthSecurityProperties props = props(List.of(ALLOWED, "heattrip-staging://login-callback"));

        String url = redirect(principal(USER_ID), store(props), props, request ->
                request.setParameter("redirect_uri", "heattrip-staging://login-callback")).getRedirectedUrl();

        assertThat(url).startsWith("heattrip-staging://login-callback?");
    }

    @Test
    @DisplayName("설정에서 허용 목록을 바꾸면 실제 리다이렉트 대상도 따라 바뀐다 — 값이 코드에 박혀 있지 않다")
    void 설정을_바꾸면_리다이렉트_대상도_바뀐다() throws Exception {
        // 완료 조건 5 를 "값 하드코딩이 아니라 설정" 으로 확인하는 지점이다.
        // 스프링 컨텍스트 없이 프로퍼티 객체를 직접 갈아 끼운다 — @TestPropertySource 로
        // 같은 것을 확인하려면 MySQL 컨테이너를 띄우는 통합 테스트가 되고, 그 비용은
        // 이 단언이 재는 것(문자열이 어디서 오는가)과 아무 관계가 없다.
        OAuthSecurityProperties props = props(List.of("myapp://done"));

        String url = redirect(principal(USER_ID), store(props), props, request -> {}).getRedirectedUrl();

        assertThat(url).startsWith("myapp://done?code=");
    }

    @Test
    @DisplayName("실패 딥링크의 대상도 같은 설정을 따른다 — 성공만 옮기면 실패가 옛 스킴으로 샌다")
    void 실패딥링크도_같은_설정을_따른다() throws Exception {
        OAuthSecurityProperties props = props(List.of("myapp://done"));

        String url = redirect(principal(null), store(props), props, request -> {}).getRedirectedUrl();

        assertThat(url).isEqualTo("myapp://done?error=account_state_invalid");
    }

    // ─────────────────────────── 지그 ───────────────────────────

    private static CustomOAuth2User principal(Long userId) {
        Map<String, Object> attributes = Map.of("sub", PROVIDER_ID, "name", "프로브 사용자");
        OAuth2UserInfo userInfo = new GoogleOAuth2User(attributes);
        return new CustomOAuth2User(userInfo, attributes, userId, "ROLE_USER", false);
    }

    private static CustomOAuth2User newUserPrincipal() {
        Map<String, Object> attributes = Map.of("sub", PROVIDER_ID, "name", "프로브 사용자");
        OAuth2UserInfo userInfo = new GoogleOAuth2User(attributes);
        return new CustomOAuth2User(userInfo, attributes, USER_ID, "ROLE_USER", true);
    }

    private static OAuthSecurityProperties props(List<String> allowlist) {
        OAuthSecurityProperties p = new OAuthSecurityProperties();
        p.setRedirectAllowlist(allowlist);
        p.setCodeTtlSeconds(60);
        return p;
    }

    private static AuthCodeStore store() {
        return store(props(List.of(ALLOWED)));
    }

    private static AuthCodeStore store(OAuthSecurityProperties props) {
        return new AuthCodeStore(Clock.fixed(BASE, ZoneOffset.UTC), props);
    }

    private static MockHttpServletResponse redirect(CustomOAuth2User principal,
                                                    Consumer<MockHttpServletRequest> tweak) throws Exception {
        return redirect(principal, store(), tweak);
    }

    private static MockHttpServletResponse redirect(CustomOAuth2User principal,
                                                    AuthCodeStore store,
                                                    Consumer<MockHttpServletRequest> tweak) throws Exception {
        return redirect(principal, store, props(List.of(ALLOWED)), tweak);
    }

    private static MockHttpServletResponse redirect(CustomOAuth2User principal,
                                                    AuthCodeStore store,
                                                    OAuthSecurityProperties props,
                                                    Consumer<MockHttpServletRequest> tweak) throws Exception {
        MockHttpServletRequest request = new MockHttpServletRequest();
        tweak.accept(request);

        MockHttpServletResponse response = new MockHttpServletResponse();
        new OAuth2SuccessHandler(store, props).onAuthenticationSuccess(
                request, response,
                new OAuth2AuthenticationToken(principal, principal.getAuthorities(), "google"));
        return response;
    }

    /** 진입 요청에서 state 를 붙드는 필터를 실제로 태운다 — 세션에 값이 담기는 경로를 흉내내지 않는다. */
    private static void captureState(MockHttpServletRequest request) {
        try {
            new OAuthAppStateFilter().doFilter(request, new MockHttpServletResponse(),
                    new org.springframework.mock.web.MockFilterChain());
        } catch (Exception e) {
            throw new IllegalStateException(e);
        }
    }

    /** 딥링크의 쿼리 <b>키</b> 집합. 값이 비어 있어도 키는 센다. */
    private static Set<String> queryKeys(String url) {
        Set<String> keys = new LinkedHashSet<>();
        for (String pair : rawQuery(url).split("&")) {
            int eq = pair.indexOf('=');
            keys.add(eq >= 0 ? pair.substring(0, eq) : pair);
        }
        return keys;
    }

    private static String queryParam(String url, String name) {
        Map<String, String> params = new LinkedHashMap<>();
        for (String pair : rawQuery(url).split("&")) {
            int eq = pair.indexOf('=');
            if (eq >= 0) {
                params.put(pair.substring(0, eq), pair.substring(eq + 1));
            }
        }
        assertThat(params).as("딥링크에 %s 파라미터가 없다: %s", name, url).containsKey(name);
        return params.get(name);
    }

    /**
     * 커스텀 스킴 URI 는 {@code java.net.URI} 가 opaque 로 보므로 {@code getRawQuery()} 가
     * {@code null} 이다. 스킴 부분을 http 로 바꿔 계층형으로 만든 뒤 파싱한다 —
     * 문자열을 손으로 자르는 것보다 파서의 판단에 맡기는 편이 낫다.
     */
    private static String rawQuery(String url) {
        URI uri = URI.create(url.replaceFirst("^[a-zA-Z][a-zA-Z0-9+.-]*://", "http://"));
        String query = uri.getRawQuery();
        assertThat(query).as("딥링크에 쿼리스트링이 없다: %s", url).isNotNull();
        return query;
    }
}
