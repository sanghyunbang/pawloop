package com.heattrip.heat_trip_backend.security;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.heattrip.heat_trip_backend.consent.ConsentStatus;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

import org.springframework.http.HttpMethod;
import org.springframework.stereotype.Component;
import org.springframework.util.AntPathMatcher;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;

/**
 * 필수 약관에 동의하지 않은 사람의 요청을 막는다 — 이슈 #660.
 *
 * <h2>왜 서버에 있나</h2>
 *
 * <p>예전에는 막는 것이 앱의 화면 전환 한 줄이 전부였다({@code auth_redirect.dart} 의
 * {@code consented == false} 분기). 그런데 <b>토큰은 동의보다 먼저 발급된다</b> — 소셜 로그인이
 * 끝나는 순간 계정이 만들어지고 토큰이 나간다. 그러니 앱을 거치지 않고 그 토큰으로 부르면 다 됐다.
 * 화면 전환은 사용자에게 길을 알려 주는 것이지 자물쇠가 아니다.
 *
 * <p>{@code ConsentKind} 의 주석은 "막는 자리는 앱의 동의 화면" 이라고 적고 있었다. 기록 모듈이
 * 판정하지 않는다는 원칙은 옳지만, 그러면 다른 누군가가 막아야 하는데 그 누군가가 없었다. 여기가
 * 그 자리다 — {@code ApiRateLimitFilter} 가 한도를 강제하는 것과 같은 층이다.
 *
 * <h2>어디를 막나 — "인증이 지키던 것" 과 정확히 같은 범위</h2>
 *
 * <p>막는 범위는 <b>{@code /api/**} 중에서 인증이 필요한 것</b>이다. 세 가지를 뺀다.
 *
 * <ul>
 *   <li><b>{@code /api/consents}</b> — 동의를 적는 경로. 이걸 막으면 <b>영영 동의할 수 없다</b>:
 *       동의하려면 동의를 적어야 하는데 그 경로가 동의를 요구하는 고리가 된다.
 *   <li><b>{@link PublicPaths#PUBLIC_MATCHERS}</b> — 토큰 없이도 열리는 경로(지도·산책 안전
 *       지수 등). 여기를 막으면 <b>로그인한 사람이 게스트보다 못한 처지</b>가 된다. 막아 봐야
 *       얻는 것도 없다 — 같은 요청을 토큰 없이 보내면 그만이다.
 *   <li><b>{@link PublicPaths#COMMUNITY_GUEST_GETS} 의 GET</b> — 같은 이유. <b>메서드를 보는
 *       것이 요점</b>이다: 경로만 보고 열면 같은 주소의 {@code POST}(글쓰기)까지 새어 나간다.
 * </ul>
 *
 * <p>{@code /auth/**} 는 애초에 {@code /api/} 로 시작하지 않아 이 필터의 범위 밖이다 — 그래서
 * <b>탈퇴({@code DELETE /auth/me})가 열려 있다.</b> 동의를 거부한 사람이 계정을 지우지도 못하고
 * 갇히면 안 된다. 개인정보를 남겨 둔 채로.
 *
 * <p>목록을 여기에 옮겨 적지 않고 {@link PublicPaths} 를 읽는 이유: 사본이 둘이 되면 그쪽에서
 * 한 줄을 지웠을 때 이쪽은 모른 채 계속 열어 둔다.
 *
 * <h2>인증 안 된 요청은 지나간다</h2>
 *
 * <p>토큰이 없으면 여기서 아무것도 하지 않고 넘긴다. 그건 이 필터의 일이 아니라 시큐리티 설정의
 * 일이다({@code anyRequest().authenticated()}). <b>동의는 "누구인지 아는 사람" 에게만 묻는다.</b>
 *
 * <h2>순서</h2>
 *
 * <p>{@code JWTAuthenticationFilter} <b>뒤</b>여야 한다. 그 필터가 SecurityContext 를 채워야 누구인지
 * 알 수 있다. 앞에 두면 인증 정보가 늘 비어 있어 이 필터가 아무도 안 막는다 — 초록불인 채로.
 */
@Component
public class ConsentRequiredFilter extends OncePerRequestFilter {

    private final ConsentStatus consents;

    /** 지금 요청이 누구 것인지. 방향을 뒤집어 받는 이유는 그 인터페이스의 javadoc 에 있다. */
    private final AuthenticatedUserIds userIds;

    /**
     * 거절 본문을 만드는 곳. <b>빈이 아니라 직접 만든다</b> — {@code ErrorBodyWriter} 는 스프링 빈이
     * 아니고(상태가 없어 공유할 이유가 없다), {@code ApiRateLimitFilter}·{@code ChatRateLimitFilter}
     * 도 같은 방식으로 {@code ObjectMapper} 를 받아 만든다. 주입받으려 들면 컨텍스트가 뜨지 않는다.
     */
    private final ErrorBodyWriter errors;

    public ConsentRequiredFilter(ConsentStatus consents, AuthenticatedUserIds userIds,
                                ObjectMapper objectMapper) {
        this.consents = consents;
        this.userIds = userIds;
        this.errors = new ErrorBodyWriter(objectMapper);
    }

    /** {@code /api/places/*} 같은 매처를 실제 경로와 견준다. 스프링 시큐리티가 쓰는 것과 같은 문법. */
    private static final AntPathMatcher PATHS = new AntPathMatcher();

    /** 동의를 적는 경로. 접두사가 아니라 <b>정확히</b> 이것이다 — {@code /api/consents-x} 까지 열지 않는다. */
    private static final String CONSENTS = "/api/consents";

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response,
                                    FilterChain chain) throws ServletException, IOException {
        if (!isGuarded(request.getMethod(), request.getRequestURI())) {
            chain.doFilter(request, response);
            return;
        }

        Long userId = userIds.ofCurrentRequest();
        if (userId == null) {
            // 인증 안 된 요청 — 이 필터의 일이 아니다. 위 javadoc 참조.
            chain.doFilter(request, response);
            return;
        }

        if (consents.hasAgreedToRequired(userId)) {
            chain.doFilter(request, response);
            return;
        }

        // 401 이 아니라 403 이다. 토큰은 멀쩡하고, 모자란 것은 동의다. 앱이 둘을 다르게 다룬다 —
        // 401 이면 로그인 화면으로 보내는데, 그러면 이미 로그인한 사람이 로그인을 다시 하게 되고
        // 그래도 같은 답이 돌아온다. 빠져나올 수 없는 고리다.
        errors.forbidden(response, "CONSENT_REQUIRED",
                "서비스 이용에 필요한 약관에 동의해 주세요.");
    }

    /** 이 요청이 "동의해야 열리는" 것인가. 판단 근거는 위 javadoc 의 표와 같다. */
    private boolean isGuarded(String method, String uri) {
        if (uri == null || !uri.startsWith("/api/")) return false;
        if (CONSENTS.equals(uri)) return false;

        for (String pattern : PublicPaths.PUBLIC_MATCHERS) {
            if (PATHS.match(pattern, uri)) return false;
        }
        if (HttpMethod.GET.matches(method)) {
            for (String pattern : PublicPaths.COMMUNITY_GUEST_GETS) {
                if (PATHS.match(pattern, uri)) return false;
            }
        }
        return true;
    }
}
