package com.heattrip.heat_trip_backend.OAuth.state;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockFilterChain;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * 앱이 만든 {@code state} 가 소셜 왕복을 건너오는 자리. (이슈 #14)
 *
 * <p>이 필터가 값을 붙들지 못하면 성공 딥링크의 {@code state} 가 항상 비고, 앱쪽 대조는
 * 늘 실패한다 — 즉 소셜 로그인이 통째로 죽는다. 그 실패는 실기기에서만 보이므로
 * 여기서 잡아 둔다.
 */
class OAuthAppStateFilterTest {

    private final OAuthAppStateFilter filter = new OAuthAppStateFilter();

    private MockHttpServletRequest entryRequest(String state) throws Exception {
        MockHttpServletRequest request = new MockHttpServletRequest("GET", "/oauth2/authorization/kakao");
        request.setRequestURI("/oauth2/authorization/kakao");
        if (state != null) {
            request.setParameter("state", state);
        }
        filter.doFilter(request, new MockHttpServletResponse(), new MockFilterChain());
        return request;
    }

    @Test
    @DisplayName("진입 요청의 state 를 붙들었다가 그대로 돌려준다")
    void 진입요청의_state를_붙든다() throws Exception {
        MockHttpServletRequest request = entryRequest("abc123_-XYZ");

        assertThat(OAuthAppStateFilter.consume(request)).isEqualTo("abc123_-XYZ");
    }

    @Test
    @DisplayName("한 번 꺼내면 사라진다 — 앞 로그인의 state 가 뒤 딥링크에 실리면 대조가 우연히 성공한다")
    void 한번_꺼내면_사라진다() throws Exception {
        MockHttpServletRequest request = entryRequest("abc123");

        assertThat(OAuthAppStateFilter.consume(request)).isEqualTo("abc123");
        assertThat(OAuthAppStateFilter.consume(request)).isEmpty();
    }

    @Test
    @DisplayName("state 를 보내지 않은 진입은 빈 문자열이다 — 세션을 만들지도 않는다")
    void state가_없으면_빈문자열이다() throws Exception {
        MockHttpServletRequest request = entryRequest(null);

        assertThat(request.getSession(false)).isNull();
        assertThat(OAuthAppStateFilter.consume(request)).isEmpty();
    }

    @Test
    @DisplayName("딥링크에 주입 가능한 문자가 섞인 state 는 없는 것으로 취급한다")
    void 주입가능한_state는_버린다() throws Exception {
        // 이 값은 나중에 딥링크 쿼리에 그대로 실린다. `&` 한 글자면 파라미터를 하나 더 만든다.
        for (String hostile : new String[]{"a&token=stolen", "a#frag", "a b", "a/../b", "a%26b"}) {
            MockHttpServletRequest request = entryRequest(hostile);
            assertThat(OAuthAppStateFilter.consume(request))
                    .as("거부해야 할 state: %s", hostile)
                    .isEmpty();
        }
    }

    @Test
    @DisplayName("128자를 넘는 state 는 버린다")
    void 지나치게_긴_state는_버린다() throws Exception {
        MockHttpServletRequest request = entryRequest("a".repeat(129));

        assertThat(OAuthAppStateFilter.consume(request)).isEmpty();
    }

    @Test
    @DisplayName("소셜 진입점이 아닌 경로의 state 파라미터는 붙들지 않는다")
    void 진입점이_아니면_붙들지_않는다() throws Exception {
        MockHttpServletRequest request = new MockHttpServletRequest("GET", "/auth/me");
        request.setRequestURI("/auth/me");
        request.setParameter("state", "abc123");

        filter.doFilter(request, new MockHttpServletResponse(), new MockFilterChain());

        assertThat(OAuthAppStateFilter.consume(request)).isEmpty();
    }

    @Test
    @DisplayName("필터는 체인을 계속 태운다 — 여기서 요청을 끝내면 소셜 진입이 죽는다")
    void 체인을_계속_태운다() throws Exception {
        MockHttpServletRequest request = new MockHttpServletRequest("GET", "/oauth2/authorization/kakao");
        request.setRequestURI("/oauth2/authorization/kakao");
        MockFilterChain chain = new MockFilterChain();

        filter.doFilter(request, new MockHttpServletResponse(), chain);

        assertThat(chain.getRequest()).isSameAs(request);
    }
}
