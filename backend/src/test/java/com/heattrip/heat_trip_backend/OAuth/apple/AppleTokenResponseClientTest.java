package com.heattrip.heat_trip_backend.OAuth.apple;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.security.oauth2.client.endpoint.OAuth2AuthorizationCodeGrantRequest;
import org.springframework.security.oauth2.client.registration.ClientRegistration;
import org.springframework.security.oauth2.core.AuthorizationGrantType;
import org.springframework.security.oauth2.core.ClientAuthenticationMethod;
import org.springframework.security.oauth2.core.OAuth2AccessToken;
import org.springframework.security.oauth2.core.endpoint.OAuth2AccessTokenResponse;
import org.springframework.security.oauth2.core.endpoint.OAuth2AuthorizationExchange;
import org.springframework.security.oauth2.core.endpoint.OAuth2AuthorizationRequest;
import org.springframework.security.oauth2.core.endpoint.OAuth2AuthorizationResponse;

import java.security.KeyPairGenerator;
import java.security.spec.ECGenParameterSpec;
import java.time.Clock;
import java.util.Base64;
import java.util.concurrent.atomic.AtomicReference;

import static org.assertj.core.api.Assertions.assertThat;

/** 토큰 교환 직전의 끼워 넣기 — Apple 만, 나머지는 그대로. 이슈 #301. */
class AppleTokenResponseClientTest {

    private static ClientRegistration registration(String id, String secret) {
        return ClientRegistration.withRegistrationId(id)
                .clientId("client-" + id)
                .clientSecret(secret)
                .clientAuthenticationMethod(ClientAuthenticationMethod.CLIENT_SECRET_POST)
                .authorizationGrantType(AuthorizationGrantType.AUTHORIZATION_CODE)
                .redirectUri("https://api.test/login/oauth2/code/" + id)
                .authorizationUri("https://provider.test/authorize")
                .tokenUri("https://provider.test/token")
                .build();
    }

    private static OAuth2AuthorizationCodeGrantRequest request(ClientRegistration registration) {
        OAuth2AuthorizationRequest authorizationRequest = OAuth2AuthorizationRequest.authorizationCode()
                .clientId(registration.getClientId())
                .authorizationUri(registration.getProviderDetails().getAuthorizationUri())
                .redirectUri(registration.getRedirectUri())
                .state("s")
                .build();
        OAuth2AuthorizationResponse response = OAuth2AuthorizationResponse.success("code")
                .redirectUri(registration.getRedirectUri()).state("s").build();
        return new OAuth2AuthorizationCodeGrantRequest(registration,
                new OAuth2AuthorizationExchange(authorizationRequest, response));
    }

    private static AppleClientSecret realSigner() throws Exception {
        KeyPairGenerator generator = KeyPairGenerator.getInstance("EC");
        generator.initialize(new ECGenParameterSpec("secp256r1"));
        AppleSignInProperties props = new AppleSignInProperties();
        props.setTeamId("TEAM123456");
        props.setKeyId("KEY1234567");
        props.setPrivateKey(Base64.getEncoder().encodeToString(generator.generateKeyPair().getPrivate().getEncoded()));
        return new AppleClientSecret(props, Clock.systemUTC());
    }

    private static OAuth2AccessTokenResponse anyResponse() {
        return OAuth2AccessTokenResponse.withToken("at").tokenType(OAuth2AccessToken.TokenType.BEARER).build();
    }

    @Test
    @DisplayName("Apple 요청은 client_secret 이 서명한 JWT 로 바뀌어 위임된다 — 나머지 요청 내용은 그대로")
    void appleGetsASignedSecret() throws Exception {
        AtomicReference<OAuth2AuthorizationCodeGrantRequest> seen = new AtomicReference<>();
        AppleTokenResponseClient client = new AppleTokenResponseClient(r -> {
            seen.set(r);
            return anyResponse();
        }, realSigner());

        OAuth2AuthorizationCodeGrantRequest original = request(registration("apple", "placeholder"));
        client.getTokenResponse(original);

        ClientRegistration delegated = seen.get().getClientRegistration();
        assertThat(delegated.getClientSecret()).as("세 조각짜리 JWT").matches("[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+");
        assertThat(delegated.getClientId()).isEqualTo("client-apple");
        assertThat(delegated.getRegistrationId()).isEqualTo("apple");
        assertThat(seen.get().getAuthorizationExchange()).isSameAs(original.getAuthorizationExchange());
    }

    @Test
    @DisplayName("카카오·구글 요청은 손대지 않고 같은 객체를 넘긴다")
    void othersPassThroughUntouched() throws Exception {
        AtomicReference<OAuth2AuthorizationCodeGrantRequest> seen = new AtomicReference<>();
        AppleTokenResponseClient client = new AppleTokenResponseClient(r -> {
            seen.set(r);
            return anyResponse();
        }, realSigner());

        OAuth2AuthorizationCodeGrantRequest kakao = request(registration("kakao", "kakao-secret"));
        client.getTokenResponse(kakao);

        assertThat(seen.get()).isSameAs(kakao);
        assertThat(seen.get().getClientRegistration().getClientSecret()).isEqualTo("kakao-secret");
    }
}
