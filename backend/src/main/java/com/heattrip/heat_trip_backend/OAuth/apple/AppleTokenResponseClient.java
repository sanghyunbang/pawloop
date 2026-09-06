package com.heattrip.heat_trip_backend.OAuth.apple;

import org.springframework.security.oauth2.client.endpoint.OAuth2AccessTokenResponseClient;
import org.springframework.security.oauth2.client.endpoint.OAuth2AuthorizationCodeGrantRequest;
import org.springframework.security.oauth2.client.registration.ClientRegistration;
import org.springframework.security.oauth2.core.endpoint.OAuth2AccessTokenResponse;

/**
 * 토큰 교환 직전에 Apple 등록의 {@code client_secret} 을 서명한 JWT 로 바꿔 끼운다 — 이슈 #301.
 *
 * <p>카카오·구글 요청은 손대지 않고 그대로 넘긴다. Apple 요청만 {@link ClientRegistration} 을
 * 복사해 {@code clientSecret} 을 {@link AppleClientSecret#current(String)} 로 채운 뒤 넘긴다 —
 * Spring Security 의 기본 클라이언트는 그 값을 {@code client_secret_post} 로 본문에 싣는다.
 *
 * <p>등록 자체를 바꾸지 않는 이유: 등록은 기동 때 한 번 만들어지는 불변 객체이고, JWT 는
 * 만료된다. 요청마다 새로 서명해 끼우는 것이 맞다.
 */
public class AppleTokenResponseClient implements OAuth2AccessTokenResponseClient<OAuth2AuthorizationCodeGrantRequest> {

    /** {@code spring.security.oauth2.client.registration.<이것>}. */
    public static final String REGISTRATION_ID = "apple";

    private final OAuth2AccessTokenResponseClient<OAuth2AuthorizationCodeGrantRequest> delegate;
    private final AppleClientSecret clientSecret;

    public AppleTokenResponseClient(OAuth2AccessTokenResponseClient<OAuth2AuthorizationCodeGrantRequest> delegate,
                                    AppleClientSecret clientSecret) {
        this.delegate = delegate;
        this.clientSecret = clientSecret;
    }

    @Override
    public OAuth2AccessTokenResponse getTokenResponse(OAuth2AuthorizationCodeGrantRequest request) {
        ClientRegistration registration = request.getClientRegistration();
        if (!REGISTRATION_ID.equals(registration.getRegistrationId())) {
            return delegate.getTokenResponse(request);
        }
        ClientRegistration signed = ClientRegistration.withClientRegistration(registration)
                .clientSecret(clientSecret.current(registration.getClientId()))
                .build();
        return delegate.getTokenResponse(
                new OAuth2AuthorizationCodeGrantRequest(signed, request.getAuthorizationExchange()));
    }
}
