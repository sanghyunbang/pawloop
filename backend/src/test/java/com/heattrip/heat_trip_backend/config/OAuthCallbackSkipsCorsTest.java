package com.heattrip.heat_trip_backend.config;

import com.heattrip.heat_trip_backend.support.AbstractMySqlIntegrationTest;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.mock.web.MockFilterChain;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.security.web.FilterChainProxy;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * 애플 로그인이 {@code Invalid CORS request} 로 막히던 것을 잡아 둔다. (이슈 #695)
 *
 * <p>사장님이 아이폰 실기기에서 애플 로그인을 눌렀더니 그 메시지가 떴다. 운영 서버에
 * 직접 쏴 보니 <b>{@code Origin} 헤더 하나로 갈렸다</b> — 붙이면 403, 빼면 302 로
 * 정상 흐름이었다.
 *
 * <p>애플만 깨지는 이유가 있다. 카카오·구글은 {@code response_mode=query} 라 <b>GET</b>
 * 리다이렉트로 돌아오고, 브라우저는 최상위 GET 내비게이션에 {@code Origin} 을 붙이지 않는다.
 * 애플만 {@code response_mode=form_post} 라 <b>POST</b> 로 돌아오는데, 크로스사이트 POST
 * 내비게이션에는 브라우저가 {@code Origin: https://appleid.apple.com} 을 붙인다. 허용
 * 목록에 없는 출처라 스프링의 CORS 필터가 <b>OAuth 처리에 닿기도 전에</b> 잘랐다.
 *
 * <p><b>왜 살아 있는 필터체인을 태우나.</b> {@code corsConfigurationSource()} 를 직접 불러
 * {@code null} 이 나오는지만 재면, 그 빈이 체인에 안 붙어 있어도 초록이 된다. 여기서는
 * {@link FilterChainProxy} 에 진짜 요청을 태워 <b>배포된 체인이 어떻게 답하는지</b>를 잰다.
 *
 * <p>반대쪽도 같이 잰다 — 콜백만 빠지고 <b>나머지 경로에서는 CORS 가 그대로 살아 있어야</b>
 * 한다. 그 검사가 없으면 CORS 를 통째로 꺼 버려도 이 파일이 초록이다.
 */
@SpringBootTest
class OAuthCallbackSkipsCorsTest extends AbstractMySqlIntegrationTest {

    /** 스프링이 CORS 를 거절할 때 쓰는 본문. 사장님이 화면에서 본 그 문장이다. */
    private static final String REJECTED = "Invalid CORS request";

    private static final String APPLE_ORIGIN = "https://appleid.apple.com";

    @Autowired
    private FilterChainProxy springSecurityFilterChain;

    /** 애플의 form_post 콜백과 같은 모양으로 쏜다 — POST · 폼 · {@code Origin} 헤더. */
    private MockHttpServletResponse postThroughChain(String path, String origin) throws Exception {
        MockHttpServletRequest request = new MockHttpServletRequest("POST", path);
        request.setServletPath(path);
        request.setContentType(MediaType.APPLICATION_FORM_URLENCODED_VALUE);
        request.setParameter("code", "dummy");
        request.setParameter("state", "dummy");
        if (origin != null) {
            request.addHeader("Origin", origin);
        }
        MockHttpServletResponse response = new MockHttpServletResponse();
        springSecurityFilterChain.doFilter(request, response, new MockFilterChain());
        return response;
    }

    @Test
    @DisplayName("애플 콜백은 Origin 이 붙어도 CORS 에 안 잘린다 — form_post 는 스크립트가 아니다")
    void appleCallback_isNotRejectedByCors() throws Exception {
        MockHttpServletResponse response =
                postThroughChain("/login/oauth2/code/apple", APPLE_ORIGIN);

        assertThat(response.getContentAsString())
                .as("""
                        애플이 form_post 로 돌아올 때 붙이는 Origin 이다. 여기서 잘리면 사용자는 \
                        로그인 화면에서 "invalid cors request" 만 보고 끝난다 — 사장님이 아이폰에서 \
                        본 그것이다(#695).""")
                .isNotEqualTo(REJECTED);
        assertThat(response.getStatus())
                .as("CORS 거절은 403 이다. 여기까지 왔으면 OAuth 처리로 넘어갔다는 뜻이다")
                .isNotEqualTo(403);
    }

    @Test
    @DisplayName("Origin 을 빼도 같은 답이다 — 헤더 하나로 갈리면 안 된다")
    void appleCallback_sameWithAndWithoutOrigin() throws Exception {
        MockHttpServletResponse withOrigin =
                postThroughChain("/login/oauth2/code/apple", APPLE_ORIGIN);
        MockHttpServletResponse withoutOrigin =
                postThroughChain("/login/oauth2/code/apple", null);

        assertThat(withOrigin.getStatus())
                .as("""
                        고치기 전에는 붙이면 403, 빼면 302 였다. 운영 서버에 직접 쏴서 본 차이다. \
                        같은 요청이 헤더 하나로 갈리면 안 된다.""")
                .isEqualTo(withoutOrigin.getStatus());
    }

    @Test
    @DisplayName("콜백이 아닌 경로에서는 CORS 가 그대로 산다 — 통째로 끄면 이 검사가 잡는다")
    void otherPaths_stillEnforceCors() throws Exception {
        MockHttpServletResponse response =
                postThroughChain("/api/consents", "https://evil.example");

        assertThat(response.getStatus())
                .as("""
                        허용 목록에 없는 출처가 /api 를 부르면 여전히 잘려야 한다. 이 검사가 없으면 \
                        CORS 를 통째로 꺼 버려도 위의 두 검사가 초록이다.""")
                .isEqualTo(403);
        assertThat(response.getContentAsString()).isEqualTo(REJECTED);
    }

    @Test
    @DisplayName("구글·카카오 콜백도 같이 빠진다 — 애플만 특별취급하지 않는다")
    void allProviderCallbacks_skipCors() throws Exception {
        for (String provider : new String[] {"google", "kakao", "apple"}) {
            MockHttpServletResponse response =
                    postThroughChain("/login/oauth2/code/" + provider, APPLE_ORIGIN);

            assertThat(response.getContentAsString())
                    .as("""
                            %s 콜백이 CORS 에 잘렸다. 지금 Origin 을 붙여 오는 것은 애플뿐이지만, \
                            공급자가 response_mode 를 바꾸면 같은 일이 난다 — 경로로 빼 둔 이유다.""",
                            provider)
                    .isNotEqualTo(REJECTED);
        }
    }
}
