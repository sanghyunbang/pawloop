package com.heattrip.heat_trip_backend.OAuth.principal;

import com.heattrip.heat_trip_backend.user.CurrentUser;
import com.heattrip.heat_trip_backend.user.ViewerId;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.core.MethodParameter;
import org.springframework.security.authentication.AnonymousAuthenticationToken;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.authority.AuthorityUtils;
import org.springframework.security.core.context.SecurityContextHolder;

import java.lang.reflect.Method;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * {@code @ViewerId Long} 리졸버 — 이슈 #223.
 *
 * <p>{@code CurrentUserArgumentResolverTest} 와 짝이다. 그쪽은 실패가 전부 401 이어야 하고,
 * 여기는 실패가 전부 {@code null} 이어야 한다. 둘이 같은 자리를 읽으면서 반대로 끝나는 것이
 * 설계라, 여기서 <b>{@code null} 이 나오는 세 경우</b>를 하나씩 못박는다 — 하나라도 예외로
 * 바뀌면 게스트가 커뮤니티를 못 읽는다.
 */
class ViewerIdArgumentResolverTest {

    @AfterEach
    void clearContext() {
        SecurityContextHolder.clearContext();
    }

    private final ViewerIdArgumentResolver resolver = new ViewerIdArgumentResolver();

    // ─────────────────────────── supportsParameter ───────────────────────────

    @Test
    @DisplayName("@ViewerId 가 붙은 Long 파라미터만 이 리졸버가 맡는다")
    void supportsParameter_onlyAnnotatedLongParameters() throws Exception {
        assertThat(resolver.supportsParameter(parameterOf("annotatedLong", 0))).isTrue();
        assertThat(resolver.supportsParameter(parameterOf("annotatedString", 0)))
                .as("타입을 안 보면 String 파라미터에 Long 을 밀어 넣게 된다")
                .isFalse();
        assertThat(resolver.supportsParameter(parameterOf("plainLong", 0)))
                .as("애너테이션 없는 Long 까지 가로채면 @RequestParam Long 이 전부 이쪽으로 온다")
                .isFalse();
        assertThat(resolver.supportsParameter(parameterOf("currentUserLong", 0)))
                .as("@CurrentUser 는 다른 리졸버의 것이다 — 뜻이 반대라 겹치면 안 된다")
                .isFalse();
    }

    // ─────────────────────────── resolveArgument ───────────────────────────

    @Test
    @DisplayName("로그인한 사람이면 principal 의 users.id 다")
    void resolveArgument_returnsIdWhenAuthenticated() throws Exception {
        SecurityContextHolder.getContext().setAuthentication(
                new UsernamePasswordAuthenticationToken(new AuthenticatedUser(42L, "ROLE_USER"), null,
                        AuthorityUtils.createAuthorityList("ROLE_USER")));

        assertThat(resolve()).isEqualTo(42L);
    }

    @Test
    @DisplayName("인증이 없으면 null — 게스트다, 401 이 아니다")
    void resolveArgument_isNullWithoutAuthentication() throws Exception {
        assertThat(resolve()).isNull();
    }

    @Test
    @DisplayName("익명 인증도 null 이다")
    void resolveArgument_isNullForAnonymousAuthentication() throws Exception {
        SecurityContextHolder.getContext().setAuthentication(new AnonymousAuthenticationToken(
                "key", "anonymousUser", AuthorityUtils.createAuthorityList("ROLE_ANONYMOUS")));

        assertThat(resolve()).isNull();
    }

    @Test
    @DisplayName("principal 이 AuthenticatedUser 가 아니면 null 이다 — 문자열에서 id 를 파싱하지 않는다")
    void resolveArgument_isNullWhenPrincipalTypeIsWrong() throws Exception {
        // 필터의 principal 을 문자열로 되돌리면 여기로 온다. "AuthenticatedUser[id=7, ...]" 를
        // 파싱해서 7 을 꺼내는 것이 #5 의 버그로 돌아가는 길이다 — 게스트로 본다.
        SecurityContextHolder.getContext().setAuthentication(new UsernamePasswordAuthenticationToken(
                "AuthenticatedUser[id=7, role=ROLE_USER]", null,
                AuthorityUtils.createAuthorityList("ROLE_USER")));

        assertThat(resolve()).isNull();
    }

    // ─────────────────────────── 지그 ───────────────────────────

    private Long resolve() throws Exception {
        return resolver.resolveArgument(parameterOf("annotatedLong", 0), null, null, null);
    }

    private static MethodParameter parameterOf(String method, int index) throws Exception {
        Method m = Samples.class.getDeclaredMethod(method, method.equals("annotatedString") ? String.class : Long.class);
        return new MethodParameter(m, index);
    }

    @SuppressWarnings("unused")
    static class Samples {
        void annotatedLong(@ViewerId Long viewerId) { }
        void annotatedString(@ViewerId String viewerId) { }
        void plainLong(Long viewerId) { }
        void currentUserLong(@CurrentUser Long viewerId) { }
    }
}
