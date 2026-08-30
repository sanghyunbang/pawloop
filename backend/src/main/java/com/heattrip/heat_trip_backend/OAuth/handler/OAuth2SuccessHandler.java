package com.heattrip.heat_trip_backend.OAuth.handler;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.security.core.Authentication;
import org.springframework.security.oauth2.client.authentication.OAuth2AuthenticationToken;
import org.springframework.security.web.authentication.AuthenticationSuccessHandler;
import org.springframework.stereotype.Component;

import com.heattrip.heat_trip_backend.OAuth.code.AuthCodeStore;
import com.heattrip.heat_trip_backend.OAuth.state.OAuthAppStateFilter;
import com.heattrip.heat_trip_backend.OAuth.user.CustomOAuth2User;
import com.heattrip.heat_trip_backend.config.OAuthSecurityProperties;

import java.io.IOException;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

/**
 * 소셜 로그인 성공을 앱으로 되돌려 보낸다 — <b>토큰이 아니라 1회용 코드로.</b> (이슈 #14)
 *
 * <h2>무엇이 바뀌었나</h2>
 * <pre>
 *   예전: heattrip://login-callback?token=&lt;AT&gt;&amp;refresh=&lt;RT&gt;
 *   지금: heattrip://login-callback?code=&lt;1회용 코드&gt;&amp;state=&lt;앱이 만든 난수&gt;
 * </pre>
 *
 * <p>커스텀 스킴({@code heattrip://})은 <b>어느 앱이든 등록할 수 있다.</b> 같은 스킴을
 * 선언한 앱이 설치돼 있으면 선택 다이얼로그가 뜨거나 경우에 따라 가로채진다. 게다가 이
 * URL 은 302 의 {@code Location} 헤더(액세스·프록시 로그)와 브라우저 히스토리에 남는다.
 * 예전 형태에서는 그 채널로 <b>1시간짜리 AT 와 14일짜리 RT</b> 가 함께 나갔다.
 *
 * <p>지금 나가는 것은 60초 살고 한 번 쓰면 죽는 난수뿐이다. 가로채도 쓸 수 있는 창이
 * 사실상 없고, 정당한 앱이 먼저 교환하면 그 코드는 그 자리에서 죽는다.
 * 토큰은 {@code POST /auth/oauth/{provider}/callback} 의 응답 본문으로만 나간다.
 *
 * <h2>리다이렉트 대상은 설정이 정한다</h2>
 * 대상 문자열을 여기 박아 두지 않는다. {@link OAuthSecurityProperties#resolveRedirect(String)}
 * 가 허용 목록과 대조해 정하고, <b>요청이 말한 값은 목록에 있을 때만</b> 쓰인다.
 * {@code Referer}·{@code X-Forwarded-Host} 같은 헤더는 아예 읽지 않는다 — 읽지 않는 것이
 * 검사하는 것보다 강하다.
 */
@Component
public class OAuth2SuccessHandler implements AuthenticationSuccessHandler {

    private static final Logger log = LoggerFactory.getLogger(OAuth2SuccessHandler.class);

    /** 1회용 코드의 발급소. 토큰은 여기서 만들지 않는다. */
    private final AuthCodeStore authCodeStore;

    /** 리다이렉트 허용 목록. */
    private final OAuthSecurityProperties oauthProperties;

    public OAuth2SuccessHandler(AuthCodeStore authCodeStore, OAuthSecurityProperties oauthProperties) {
        this.authCodeStore = authCodeStore;
        this.oauthProperties = oauthProperties;
    }

    /**
     * 인증 성공 시 실행되는 메서드.
     *
     * @param request        사용자의 요청 객체
     * @param response       서버의 응답 객체
     * @param authentication 인증 성공 후의 사용자 정보 객체 (Principal, 권한 등 포함)
     */
    @Override
    public void onAuthenticationSuccess(HttpServletRequest request,
                                        HttpServletResponse response,
                                        Authentication authentication) throws IOException, ServletException {

        // 진입 여부만 남긴다. 소셜 ID 도 users.id 도 로그에 남기지 않는다. (이슈 #6)
        log.debug("OAuth2 로그인 성공 처리 진입");

        // 캐시 경로를 닫는다. 코드는 짧게 살지만 그래도 자격증명이다.
        response.setHeader("Cache-Control", "no-store");

        String redirectBase = oauthProperties.resolveRedirect(request.getParameter("redirect_uri"));

        // subject 는 users.id 다. 예전에는 authentication.getName()(= "kakao_1234567890")을
        // 그대로 썼고, 그 값이 소비처에서 이메일로 해석되는 바람에 모든 소셜 계정에서
        // /auth/me 계열이 400 이었다. (이슈 #5) 이제 그 값은 토큰이 아니라 코드에 실린다.
        CustomOAuth2User principal = (CustomOAuth2User) authentication.getPrincipal();
        Long userId = principal.getUserId();

        if (userId == null) {
            // users.id 를 모르는 principal 로는 코드를 만들 수 없다. 여기서 주체 없는 코드를
            // 발급하면 교환 시점에 sub="null" 토큰이 되고, 그 계정은 재로그인 전까지 영구 401 이다.
            // 실패 딥링크는 OAuth2FailureHandler 와 같은 모양이다 — 앱은 이미 그 형태를 기다린다.
            log.warn("[OAuth2 로그인] 인증 주체에 users.id 가 없어 코드를 발급하지 않는다.");
            response.sendRedirect(redirectBase + "?error=account_state_invalid");
            return;
        }

        // 권한은 코드에 싣지 않는다. 교환 시점에 users 행에서 다시 읽는다 —
        // 발급~교환 사이(≤60초)의 탈퇴·권한 변경이 반영돼야 하기 때문이다.
        String provider = providerOf(authentication);

        // 앱이 인증 시작 때 붙여 보낸 난수. 없으면 빈 문자열이고, 그때는 앱쪽 대조가 실패한다 —
        // 그게 옳다. state 없이 성공시키면 검사가 있다고 말할 수 없다.
        String state = OAuthAppStateFilter.consume(request);

        String code = authCodeStore.issue(userId, provider, state, principal.isNew());

        // 코드와 state 는 Base64URL/화이트리스트를 통과한 값이라 URL 인코딩이 필요 없다.
        response.sendRedirect(redirectBase + "?code=" + code + "&state=" + state);

        // URL 에 코드가 실려 있으므로 URL 자체를 로그로 남기지 않는다. (이슈 #6)
        log.debug("OAuth2 로그인 성공 — 1회용 코드로 앱에 복귀");
    }

    /** 이 코드를 만든 공급자. 교환 요청의 경로 변수와 대조하는 데 쓴다. */
    private static String providerOf(Authentication authentication) {
        if (authentication instanceof OAuth2AuthenticationToken token) {
            return token.getAuthorizedClientRegistrationId();
        }
        return "";
    }
}
