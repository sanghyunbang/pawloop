package com.heattrip.heat_trip_backend.OAuth.state;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import jakarta.servlet.http.HttpSession;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.util.regex.Pattern;

/**
 * 앱이 만든 {@code state} 를 소셜 로그인 왕복 동안 붙들고 있는다. (이슈 #14)
 *
 * <h2>왜 필요한가</h2>
 * {@code state} 는 <b>앱이 만들어 앱이 대조해야</b> 의미가 있다. 서버가 만들어 서버가
 * 대조하면 응답 바꿔치기를 막지 못한다 — 공격자가 자기 로그인의 결과를 피해자 앱에
 * 밀어 넣는 시나리오에서 걸러야 하는 쪽은 앱이다.
 *
 * <p>그런데 앱이 여는 URL({@code /oauth2/authorization/{provider}})과 앱이 돌아오는
 * 딥링크 사이에는 공급자 왕복이 끼어 있고, 그 사이 요청들은 서로 다른 HTTP 요청이다.
 * 앱이 붙인 {@code state} 를 성공 핸들러까지 옮길 자리가 필요하다.
 *
 * <h2>왜 세션인가</h2>
 * Spring Security 의 기본 {@code HttpSessionOAuth2AuthorizationRequestRepository} 가
 * <b>이미</b> 같은 창(진입 → 공급자 → {@code /login/oauth2/code/*})을 세션으로 잇고 있다.
 * 즉 이 필터는 새 제약을 만들지 않는다 — 이미 성립하는 연속성에 값 하나를 얹을 뿐이다.
 * ({@code SessionCreationPolicy.STATELESS} 는 <b>SecurityContext</b> 를 세션에 담지
 * 않는다는 뜻이지 서블릿 세션을 금지하는 설정이 아니다.)
 *
 * <p>쿠키를 새로 굽지 않은 이유도 같다. 굽는 순간 SameSite·Secure·수명·삭제 시점을
 * 우리가 다 정해야 하고, 그건 이미 있는 세션이 하는 일과 겹친다.
 *
 * <h2>무엇을 통과시키는가</h2>
 * {@code [A-Za-z0-9_-]{1,128}} 만. 이 값은 나중에 딥링크 쿼리에 그대로 실리므로,
 * 걸러 두지 않으면 {@code &}·{@code #} 한 글자로 딥링크에 파라미터를 주입할 수 있다.
 * 통과하지 못한 값은 <b>없는 것으로 취급</b>한다 — 잘라 쓰거나 인코딩해 넘기면 앱이
 * 대조에 실패하는 이유를 알 수 없게 된다.
 */
@Component
public class OAuthAppStateFilter extends OncePerRequestFilter {

    private static final Logger log = LoggerFactory.getLogger(OAuthAppStateFilter.class);

    /** Spring Security 가 만드는 소셜 진입점의 접두사. */
    static final String ENTRY_POINT_PREFIX = "/oauth2/authorization/";

    /** 세션에 담아 두는 이름. 성공 핸들러가 같은 이름으로 꺼내 간다. */
    public static final String SESSION_ATTRIBUTE = "HEATTRIP_OAUTH_APP_STATE";

    /** 딥링크 쿼리에 그대로 붙여도 되는 형태만 통과시킨다. */
    private static final Pattern SAFE_STATE = Pattern.compile("[A-Za-z0-9_-]{1,128}");

    @Override
    protected void doFilterInternal(HttpServletRequest request,
                                    HttpServletResponse response,
                                    FilterChain filterChain) throws ServletException, IOException {
        if (request.getRequestURI().startsWith(ENTRY_POINT_PREFIX)) {
            capture(request);
        }
        filterChain.doFilter(request, response);
    }

    private void capture(HttpServletRequest request) {
        String state = request.getParameter("state");
        if (state == null || !SAFE_STATE.matcher(state).matches()) {
            // 값이 없는 것은 정상이다 — 옛 앱은 state 를 보내지 않는다. 형태가 이상한 것은
            // 주입 시도일 수 있으나, 값을 로그에 남기지는 않는다 (이슈 #6).
            if (state != null) {
                log.warn("[OAuth2 로그인] 허용되지 않은 형태의 state 를 무시했다.");
            }
            return;
        }
        HttpSession session = request.getSession(true);
        session.setAttribute(SESSION_ATTRIBUTE, state);
    }

    /**
     * 담아 둔 값을 꺼내면서 지운다. 없으면 빈 문자열.
     *
     * <p>지우는 이유: 한 세션으로 두 번 로그인하면 앞의 {@code state} 가 뒤의 딥링크에
     * 실릴 수 있고, 그러면 앱의 대조가 우연히 성공한다. 그건 검사가 아니라 통과다.
     */
    public static String consume(HttpServletRequest request) {
        HttpSession session = request.getSession(false);
        if (session == null) {
            return "";
        }
        Object value = session.getAttribute(SESSION_ATTRIBUTE);
        session.removeAttribute(SESSION_ATTRIBUTE);
        return value instanceof String s ? s : "";
    }
}
