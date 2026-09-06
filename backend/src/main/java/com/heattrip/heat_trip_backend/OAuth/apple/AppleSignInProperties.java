package com.heattrip.heat_trip_backend.OAuth.apple;

import lombok.Getter;
import lombok.Setter;

import org.springframework.boot.context.properties.ConfigurationProperties;

/**
 * Sign in with Apple 의 개발자 키 — 이슈 #301.
 *
 * <p>카카오·구글은 {@code client-secret} 이 고정 문자열이라 Spring Security 가 그대로 보낸다.
 * Apple 은 다르다 — <b>{@code client_secret} 이 우리가 개발자 키(.p8)로 서명한 JWT</b>이고
 * 6개월 안에 만료돼야 한다. 그래서 등록의 {@code client-secret} 은 자리표시이고, 실제 값은
 * 토큰 요청 직전에 {@link AppleClientSecret} 이 이 세 값으로 만든다.
 *
 * <p>세 값 다 <b>사장님이 Apple Developer 에서 발급</b>한다({@code .env.example} 의 절차).
 * 비어 있으면 {@link #isConfigured()} 가 거짓이고, Apple 로그인은 앱에 {@code error=apple_not_configured}
 * 로 돌아간다 — 서버는 뜨고 카카오·구글은 그대로 된다.
 */
@Getter
@Setter
@ConfigurationProperties(prefix = "app.security.oauth.apple")
public class AppleSignInProperties {

    /** Apple Developer → Membership 의 Team ID. 10자. {@code iss} 클레임이다. */
    private String teamId;

    /** Keys 에서 만든 "Sign in with Apple" 키의 Key ID. 10자. JWT 헤더의 {@code kid} 다. */
    private String keyId;

    /**
     * 그 키의 .p8 파일 내용. PEM 그대로여도 되고({@code -----BEGIN PRIVATE KEY-----} 포함),
     * 머리·꼬리와 줄바꿈을 뗀 base64 한 줄이어도 된다 — {@code .env} 한 줄에 넣기 좋게.
     */
    private String privateKey;

    /** 셋 다 있어야 서명할 수 있다. 자리표시({@code change-me…}·{@code dev-…})는 없는 것으로 본다. */
    public boolean isConfigured() {
        return present(teamId) && present(keyId) && present(privateKey);
    }

    private static boolean present(String value) {
        if (value == null || value.isBlank()) {
            return false;
        }
        String v = value.strip();
        return !v.startsWith("change-me") && !v.startsWith("dev-");
    }
}
