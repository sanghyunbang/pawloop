package com.heattrip.heat_trip_backend.OAuth.apple;

import org.springframework.boot.context.properties.EnableConfigurationProperties;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.security.oauth2.client.endpoint.OAuth2AccessTokenResponseClient;
import org.springframework.security.oauth2.client.endpoint.OAuth2AuthorizationCodeGrantRequest;
import org.springframework.security.oauth2.client.endpoint.RestClientAuthorizationCodeTokenResponseClient;
import org.springframework.security.oauth2.client.oidc.authentication.OidcIdTokenDecoderFactory;
import org.springframework.security.oauth2.client.oidc.authentication.OidcIdTokenValidator;
import org.springframework.security.oauth2.client.registration.ClientRegistration;
import org.springframework.security.oauth2.core.DelegatingOAuth2TokenValidator;
import org.springframework.security.oauth2.core.OAuth2TokenValidator;
import org.springframework.security.oauth2.jwt.Jwt;
import org.springframework.security.oauth2.jwt.JwtDecoderFactory;
import org.springframework.security.oauth2.jwt.JwtIssuerValidator;
import org.springframework.security.oauth2.jwt.JwtTimestampValidator;

/**
 * Sign in with Apple 이 Spring Security 의 OAuth2 로그인에 끼어드는 두 자리 — 이슈 #301.
 *
 * <ol>
 *   <li><b>토큰 교환</b> — {@link AppleTokenResponseClient} 가 Apple 등록의 {@code client_secret}
 *       을 서명한 JWT 로 바꿔 끼운다. 다른 등록은 기본 클라이언트 그대로.</li>
 *   <li><b>id_token 검증</b> — 기본 검증(서명·만료·{@code aud}·{@code nonce})에 <b>발급자</b>
 *       검사를 더한다. {@code issuer-uri} 를 프로퍼티에 적지 않는 이유: 적으면 부트가 뜰 때
 *       Apple 의 discovery 문서를 네트워크로 받으러 가서, 망이 없는 CI·개발기에서 기동이 실패한다.
 *       그래서 발급자를 여기서 손으로 잠근다.</li>
 * </ol>
 */
@Configuration
@EnableConfigurationProperties(AppleSignInProperties.class)
public class AppleSignInConfig {

    /** Apple 이 id_token 의 {@code iss} 에 적는 값. {@code aud} 로 요구하는 값과 같다. */
    static final String APPLE_ISSUER = "https://appleid.apple.com";

    @Bean
    public OAuth2AccessTokenResponseClient<OAuth2AuthorizationCodeGrantRequest> accessTokenResponseClient(
            AppleClientSecret clientSecret) {
        return new AppleTokenResponseClient(new RestClientAuthorizationCodeTokenResponseClient(), clientSecret);
    }

    @Bean
    public JwtDecoderFactory<ClientRegistration> idTokenDecoderFactory() {
        OidcIdTokenDecoderFactory factory = new OidcIdTokenDecoderFactory();
        factory.setJwtValidatorFactory(registration -> {
            OAuth2TokenValidator<Jwt> standard = new DelegatingOAuth2TokenValidator<>(
                    new JwtTimestampValidator(), new OidcIdTokenValidator(registration));
            if (AppleTokenResponseClient.REGISTRATION_ID.equals(registration.getRegistrationId())) {
                return new DelegatingOAuth2TokenValidator<>(standard, new JwtIssuerValidator(APPLE_ISSUER));
            }
            return standard;
        });
        return factory;
    }
}
