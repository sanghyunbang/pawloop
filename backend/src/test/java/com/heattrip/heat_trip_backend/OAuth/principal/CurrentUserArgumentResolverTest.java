package com.heattrip.heat_trip_backend.OAuth.principal;

import com.heattrip.heat_trip_backend.user.CurrentUser;

import com.heattrip.heat_trip_backend.user.UnauthenticatedException;

import com.heattrip.heat_trip_backend.user.entity.User;
import com.heattrip.heat_trip_backend.user.repository.UserRepository;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.core.MethodParameter;
import org.springframework.security.authentication.AnonymousAuthenticationToken;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.authority.AuthorityUtils;
import org.springframework.security.core.context.SecurityContextHolder;

import java.lang.reflect.Method;
import java.util.List;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.when;

/**
 * 인증 주체 해석의 유일한 지점이 어떤 입력에서도 <b>null 을 돌려주지 않는지</b> 확인한다. (이슈 #5)
 *
 * <p>null 을 돌려주면 컨트롤러 본문에서 NPE 가 나고 그건 401 이 아니라 500 이다.
 * 이 이슈의 완료 조건이 "어떤 입력에서도 500 이 아니라 401" 이므로 여기가 그 마지막 관문이다.
 */
@ExtendWith(MockitoExtension.class)
class CurrentUserArgumentResolverTest {

    @Mock
    private UserRepository userRepository;

    @AfterEach
    void clearContext() {
        SecurityContextHolder.clearContext();
    }

    private CurrentUserArgumentResolver resolver() {
        return new CurrentUserArgumentResolver(userRepository);
    }

    // ─────────────────────────── supportsParameter ───────────────────────────

    @Test
    @DisplayName("@CurrentUser 가 붙은 User 파라미터만 이 리졸버가 맡는다")
    void supportsParameter_onlyAnnotatedUserParameters() throws Exception {
        assertThat(resolver().supportsParameter(parameterOf("annotatedUser", 0))).isTrue();
        assertThat(resolver().supportsParameter(parameterOf("annotatedString", 0)))
                .as("애너테이션만 보고 타입을 안 보면 String 파라미터에 User 를 밀어 넣게 된다")
                .isFalse();
        assertThat(resolver().supportsParameter(parameterOf("plainUser", 0)))
                .as("애너테이션 없는 User 파라미터까지 가로채면 다른 리졸버의 자리를 뺏는다")
                .isFalse();
    }

    // ─────────────────────────── resolveArgument ───────────────────────────

    @Test
    @DisplayName("principal 의 users.id 로 사용자 행을 찾아 그대로 주입한다")
    void resolveArgument_loadsUserById() throws Exception {
        User bori = User.builder().id(42L).nickname("보리").build();
        SecurityContextHolder.getContext().setAuthentication(authenticatedAs(42L));
        when(userRepository.findById(42L)).thenReturn(Optional.of(bori));

        assertThat(resolver().resolveArgument(parameterOf("annotatedUser", 0), null, null, null))
                .isSameAs(bori);
    }

    @Test
    @DisplayName("인증이 아예 없으면 401 로 매핑되는 예외를 던진다")
    void resolveArgument_throwsWhenNoAuthentication() throws Exception {
        assertUnauthenticated();
    }

    @Test
    @DisplayName("익명 인증이면 401 로 매핑되는 예외를 던진다")
    void resolveArgument_throwsForAnonymousAuthentication() throws Exception {
        SecurityContextHolder.getContext().setAuthentication(new AnonymousAuthenticationToken(
                "key", "anonymousUser", AuthorityUtils.createAuthorityList("ROLE_ANONYMOUS")));

        assertUnauthenticated();
    }

    @Test
    @DisplayName("principal 이 AuthenticatedUser 가 아니면 401 로 매핑되는 예외를 던진다")
    void resolveArgument_throwsWhenPrincipalTypeIsWrong() throws Exception {
        // 필터의 principal 을 문자열로 되돌리면 여기로 온다. 조용히 null 을 주입하지 않는 것이 핵심이다.
        SecurityContextHolder.getContext().setAuthentication(new UsernamePasswordAuthenticationToken(
                "bori@example.com", null, AuthorityUtils.createAuthorityList("ROLE_USER")));

        assertUnauthenticated();
    }

    @Test
    @DisplayName("서명도 형식도 멀쩡한데 그 users.id 의 행이 없으면 401 로 매핑되는 예외를 던진다")
    void resolveArgument_throwsWhenRowIsGone() throws Exception {
        SecurityContextHolder.getContext().setAuthentication(authenticatedAs(42L));
        when(userRepository.findById(42L)).thenReturn(Optional.empty());

        // orElse(null) 로 바꾸면 컨트롤러 본문에서 NPE → 500 이 된다. 탈퇴한 계정의 살아 있는 토큰이 그 경로다.
        assertUnauthenticated();
    }

    @Test
    @DisplayName("예외 메시지에는 users.id 도 이메일도 담기지 않는다")
    void unauthenticatedException_carriesNoIdentifier() {
        assertThat(new UnauthenticatedException().getMessage())
                // GlobalExceptionHandler 가 예외 메시지를 응답 본문에 그대로 싣는 처리기를 갖고 있다 (이슈 #6)
                .doesNotContain("@")
                .doesNotContainPattern("\\d");
    }

    // ─────────────────────────── 지그 ───────────────────────────

    private void assertUnauthenticated() throws Exception {
        MethodParameter parameter = parameterOf("annotatedUser", 0);
        assertThatThrownBy(() -> resolver().resolveArgument(parameter, null, null, null))
                .isInstanceOf(UnauthenticatedException.class);
    }

    private static UsernamePasswordAuthenticationToken authenticatedAs(long userId) {
        return new UsernamePasswordAuthenticationToken(
                new AuthenticatedUser(userId, "ROLE_USER"), null,
                AuthorityUtils.createAuthorityList("ROLE_USER"));
    }

    private static MethodParameter parameterOf(String methodName, int index) throws Exception {
        for (Method method : Handlers.class.getDeclaredMethods()) {
            if (method.getName().equals(methodName)) {
                return new MethodParameter(method, index);
            }
        }
        throw new IllegalStateException(methodName + " 지그 메서드가 없다.");
    }

    /** 파라미터 모양만 빌려 쓰는 지그. 호출되지 않는다. */
    @SuppressWarnings("unused")
    static class Handlers {
        void annotatedUser(@CurrentUser User user) { }

        void annotatedString(@CurrentUser String user) { }

        void plainUser(User user) { }

        void unrelated(List<String> values) { }
    }
}
