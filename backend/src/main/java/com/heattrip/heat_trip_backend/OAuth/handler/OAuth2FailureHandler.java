package com.heattrip.heat_trip_backend.OAuth.handler;

import java.io.IOException;
import java.util.Locale;
import java.util.regex.Pattern;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.security.core.AuthenticationException;
import org.springframework.security.oauth2.core.OAuth2AuthenticationException;
import org.springframework.security.oauth2.core.OAuth2Error;
import org.springframework.security.web.authentication.AuthenticationFailureHandler;
import org.springframework.stereotype.Component;

import com.heattrip.heat_trip_backend.config.OAuthSecurityProperties;

import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

/**
 * 소셜 로그인 <b>실패</b>를 앱이 이해할 수 있는 형태로 끝낸다. (이슈 #7)
 *
 * <p>이게 없으면 Spring Security 기본값인 {@code SimpleUrlAuthenticationFailureHandler} 가
 * {@code /login?error} 로 302 를 준다. 이 프로젝트에는 그 경로에 핸들러가 없어
 * {@code NoResourceFoundException} → 전역 예외 처리기의 catch-all → <b>500</b> 이 된다.
 * 즉 {@code CustomOAuth2UserService} 가 공들여 만든 {@code email_already_registered} 같은
 * 원인 코드가 사용자에게도 앱에게도 전혀 닿지 않았다.
 *
 * <p>게다가 앱은 {@code flutter_web_auth_2} 로 {@code heattrip://login-callback} 을 기다린다
 * ({@link OAuth2SuccessHandler} 참고). 실패가 그 커스텀 스킴으로 돌아오지 않으면 로그인 시트는
 * 사용자가 취소할 때까지 멈춰 있는다. 그래서 성공과 같은 딥링크로, 대신 토큰이 아니라
 * 에러 코드만 실어 돌려보낸다.
 *
 * <pre>
 *   성공: heattrip://login-callback?token=&lt;access-token&gt;
 *   실패: heattrip://login-callback?error=email_already_registered
 * </pre>
 *
 * <p><b>에러 파라미터에는 코드만 담는다.</b> 이메일·토큰·소셜 ID·예외 메시지 원문은 넣지 않는다.
 * 리다이렉트 URL 은 액세스 로그와 리버스 프록시 로그에 남는다(이슈 #6). 코드는
 * {@code [a-z0-9_]} 화이트리스트를 통과한 값만 쓰고, 통과하지 못하면
 * {@link #DEFAULT_ERROR_CODE} 로 바꾼다 — 공급자가 리다이렉트로 돌려보내는 error 파라미터도
 * 결국 {@link OAuth2Error#getErrorCode()} 가 되므로 그대로 붙이면 딥링크에 주입이 가능하다.
 */
@Component
public class OAuth2FailureHandler implements AuthenticationFailureHandler {

    private static final Logger log = LoggerFactory.getLogger(OAuth2FailureHandler.class);

    /**
     * 성공 경로와 <b>같은</b> 리다이렉트 대상을 쓴다. 값은 설정의 허용 목록이 정한다 (이슈 #14).
     *
     * <p>예전에는 여기에 {@code "heattrip://login-callback"} 이 박혀 있었다. 성공 경로만
     * 설정으로 빼면 웹 콜백을 추가하는 날 실패만 옛 스킴으로 가고, 그 로그인 시트는
     * 사용자가 취소할 때까지 멈춰 있는다.
     */
    private final OAuthSecurityProperties oauthProperties;

    public OAuth2FailureHandler(OAuthSecurityProperties oauthProperties) {
        this.oauthProperties = oauthProperties;
    }

    /** 알 수 없는/안전하지 않은 코드는 전부 이 값으로 뭉갠다. */
    static final String DEFAULT_ERROR_CODE = "authentication_failed";

    /** 딥링크 쿼리에 그대로 붙여도 되는 형태만 통과시킨다. */
    private static final Pattern SAFE_ERROR_CODE = Pattern.compile("[a-z0-9_]{1,64}");

    @Override
    public void onAuthenticationFailure(HttpServletRequest request,
                                        HttpServletResponse response,
                                        AuthenticationException exception) throws IOException {
        String code = errorCode(exception);

        // 예외 메시지에는 provider 이름만 들어가지만, 원문을 로그로 흘리지 않는 쪽이 안전하다.
        // 남기는 것은 정규화된 코드 하나뿐이다. (이슈 #6)
        log.warn("[OAuth2 로그인] 인증 실패 — error={}", code);

        // 요청이 말한 대상은 허용 목록에 있을 때만 쓰인다. Referer·X-Forwarded-Host 는 읽지 않는다.
        response.sendRedirect(oauthProperties.resolveRedirect(request.getParameter("redirect_uri"))
                + "?error=" + code);
    }

    /**
     * 앱으로 돌려보낼 에러 코드.
     *
     * <p>{@code OAuth2AuthenticationException} 이면 {@link OAuth2Error#getErrorCode()} 를 쓰되,
     * 화이트리스트를 통과한 값만 쓴다. 그 외 인증 예외는 전부 {@link #DEFAULT_ERROR_CODE} 다 —
     * 예외 클래스 이름조차 노출하지 않는다.
     */
    static String errorCode(AuthenticationException exception) {
        if (!(exception instanceof OAuth2AuthenticationException oauthException)) {
            return DEFAULT_ERROR_CODE;
        }
        OAuth2Error error = oauthException.getError();
        if (error == null || error.getErrorCode() == null) {
            return DEFAULT_ERROR_CODE;
        }
        String code = error.getErrorCode().trim().toLowerCase(Locale.ROOT);
        return SAFE_ERROR_CODE.matcher(code).matches() ? code : DEFAULT_ERROR_CODE;
    }
}
