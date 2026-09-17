package com.heattrip.heat_trip_backend.OAuth;

import lombok.Getter;
import lombok.Setter;
import org.springframework.boot.context.properties.ConfigurationProperties;

import java.util.ArrayList;
import java.util.List;

/**
 * 소셜 로그인 하드닝 설정. (이슈 #14)
 *
 * <h2>왜 설정으로 뺐나</h2>
 * 딥링크 대상({@code pawloop://login-callback})이 코드에 박혀 있었다. 그 자체는 당장
 * 위험하지 않지만, 웹 콜백이나 스테이징용 스킴을 하나 더 붙이는 날 "요청에서 받은
 * {@code redirect_uri} 로 리다이렉트한다" 는 흔한 실수를 하기 쉬운 구조였다. 허용 목록을
 * 밖으로 빼고, <b>목록에 없는 값은 절대 리다이렉트 대상이 되지 않게</b> 한다.
 *
 * <p>목록의 <b>첫 항목이 기본 대상</b>이다. 요청이 대상을 말하지 않았거나, 말했지만 목록에
 * 없으면 이 기본값으로 간다.
 */
@Getter
@Setter
@ConfigurationProperties(prefix = "app.security.oauth")
public class OAuthSecurityProperties {

    /**
     * 소셜 로그인 종료 후 리다이렉트해도 되는 대상. <b>정확히 일치</b>하는 값만 통과한다.
     *
     * <p>접두사 비교를 쓰지 않는 이유: {@code pawloop://login-callback} 을 접두사로 허용하면
     * {@code pawloop://login-callback.evil.example} 같은 값이 통과한다. 호스트 파싱으로
     * 비교하지 않는 이유는 커스텀 스킴 URI 에 권위 있는 호스트 개념이 없어서다.
     */
    private List<String> redirectAllowlist = new ArrayList<>(List.of("pawloop://login-callback"));

    /**
     * 1회용 인가 코드의 수명(초). 이슈가 요구한 상한은 60초다.
     *
     * <p>짧을수록 좋지만 0 에 가까우면 브라우저→앱 복귀가 느린 기기에서 정상 로그인이
     * 실패한다. 60초는 "가로챈 코드를 쓸 시간을 주지 않는다" 와 "느린 기기도 성공한다"
     * 사이의 값이다.
     */
    private long codeTtlSeconds = 60;

    /** 기본 리다이렉트 대상 — 목록의 첫 항목. 목록이 비면 설정이 잘못된 것이다. */
    public String defaultRedirect() {
        if (redirectAllowlist == null || redirectAllowlist.isEmpty()) {
            throw new IllegalStateException(
                    "app.security.oauth.redirect-allowlist 가 비어 있습니다. "
                            + "소셜 로그인이 앱으로 돌아갈 대상이 없습니다.");
        }
        return redirectAllowlist.get(0).trim();
    }

    /**
     * 요청이 말한 대상을 허용 목록과 대조해 <b>실제로 쓸</b> 대상을 정한다.
     *
     * <p>목록에 없으면 예외를 던지는 대신 기본값으로 떨어진다. 이유: 이 값의 출처는
     * 공격자가 헤더 한 줄로 넣을 수 있는 자리이므로, 거부를 오류로 끝내면 헤더 하나로
     * 남의 로그인을 못 하게 만드는 수단이 된다. <b>주입된 값은 절대 쓰이지 않되</b>
     * 로그인은 성립하는 쪽이 옳다.
     *
     * @param requested 요청이 말한 대상. {@code null}·공백이면 기본값
     */
    public String resolveRedirect(String requested) {
        if (requested == null || requested.isBlank()) {
            return defaultRedirect();
        }
        String candidate = requested.trim();
        for (String allowed : redirectAllowlist) {
            if (allowed != null && allowed.trim().equals(candidate)) {
                return candidate;
            }
        }
        return defaultRedirect();
    }
}
