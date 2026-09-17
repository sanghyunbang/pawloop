package com.heattrip.heat_trip_backend.OAuth.apple;

import com.nimbusds.jose.JWSAlgorithm;
import com.nimbusds.jose.crypto.ECDSAVerifier;
import com.nimbusds.jwt.SignedJWT;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.security.oauth2.core.OAuth2AuthorizationException;

import java.security.KeyPair;
import java.security.KeyPairGenerator;
import java.security.interfaces.ECPublicKey;
import java.security.spec.ECGenParameterSpec;
import java.time.Clock;
import java.time.Instant;
import java.time.ZoneOffset;
import java.util.Base64;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * Apple {@code client_secret} JWT — 이슈 #301. 진짜 .p8 없이 잰다: 테스트가 P-256 키 쌍을 만들어
 * 개인키를 프로퍼티에 넣고 공개키로 서명을 검증한다.
 */
class AppleClientSecretTest {

    private static final Instant NOW = Instant.parse("2026-09-06T03:00:00Z");
    private static final Clock CLOCK = Clock.fixed(NOW, ZoneOffset.UTC);

    private static KeyPair keyPair() throws Exception {
        KeyPairGenerator generator = KeyPairGenerator.getInstance("EC");
        generator.initialize(new ECGenParameterSpec("secp256r1"));
        return generator.generateKeyPair();
    }

    private static AppleSignInProperties configured(KeyPair pair, boolean pemHeaders) {
        String base64 = Base64.getEncoder().encodeToString(pair.getPrivate().getEncoded());
        AppleSignInProperties props = new AppleSignInProperties();
        props.setTeamId("TEAM123456");
        props.setKeyId("KEY1234567");
        props.setPrivateKey(pemHeaders
                ? "-----BEGIN PRIVATE KEY-----\n" + base64.replaceAll("(.{64})", "$1\n") + "\n-----END PRIVATE KEY-----\n"
                : base64);
        return props;
    }

    @Test
    @DisplayName("ES256 으로 서명되고 kid·iss·sub·aud·10분 수명이 Apple 규격대로다")
    void signsAppleShapedJwt() throws Exception {
        KeyPair pair = keyPair();
        String secret = new AppleClientSecret(configured(pair, true), CLOCK).current("app.pawloop.signin");

        SignedJWT jwt = SignedJWT.parse(secret);
        assertThat(jwt.verify(new ECDSAVerifier((ECPublicKey) pair.getPublic())))
                .as("우리 개인키로 서명됐어야 공개키 검증이 통과한다")
                .isTrue();
        assertThat(jwt.getHeader().getAlgorithm()).isEqualTo(JWSAlgorithm.ES256);
        assertThat(jwt.getHeader().getKeyID()).isEqualTo("KEY1234567");
        assertThat(jwt.getJWTClaimsSet().getIssuer()).isEqualTo("TEAM123456");
        assertThat(jwt.getJWTClaimsSet().getSubject()).isEqualTo("app.pawloop.signin");
        assertThat(jwt.getJWTClaimsSet().getAudience()).containsExactly("https://appleid.apple.com");
        assertThat(jwt.getJWTClaimsSet().getIssueTime().toInstant()).isEqualTo(NOW);
        assertThat(jwt.getJWTClaimsSet().getExpirationTime().toInstant()).isEqualTo(NOW.plus(AppleClientSecret.LIFETIME));
    }

    @Test
    @DisplayName("머리·꼬리 없는 base64 한 줄도 읽는다 — .env 한 줄에 넣는 형태다")
    void acceptsBareBase64() throws Exception {
        KeyPair pair = keyPair();
        String secret = new AppleClientSecret(configured(pair, false), CLOCK).current("id");
        assertThat(SignedJWT.parse(secret).verify(new ECDSAVerifier((ECPublicKey) pair.getPublic()))).isTrue();
    }

    @Test
    @DisplayName("키가 비어 있으면 apple_not_configured 다 — 로그인 실패이지 500 이 아니다")
    void missingKeysAreAnAuthorizationError() {
        AppleSignInProperties empty = new AppleSignInProperties();
        empty.setTeamId("TEAM123456");
        empty.setKeyId("");
        empty.setPrivateKey("change-me-apple-private-key");

        assertThat(empty.isConfigured()).isFalse();
        assertThatThrownBy(() -> new AppleClientSecret(empty, CLOCK).current("id"))
                .isInstanceOf(OAuth2AuthorizationException.class)
                .satisfies(e -> assertThat(((OAuth2AuthorizationException) e).getError().getErrorCode())
                        .isEqualTo(AppleClientSecret.ERROR_NOT_CONFIGURED));
    }

    @Test
    @DisplayName("EC 키가 아니면 같은 코드로 실패하고, 키 값은 메시지에 싣지 않는다")
    void rejectsANonEcKeyWithoutEchoingIt() {
        AppleSignInProperties props = new AppleSignInProperties();
        props.setTeamId("TEAM123456");
        props.setKeyId("KEY1234567");
        props.setPrivateKey("bm90LWEta2V5");   // "not-a-key"

        assertThatThrownBy(() -> new AppleClientSecret(props, CLOCK).current("id"))
                .isInstanceOf(OAuth2AuthorizationException.class)
                .hasMessageNotContaining("bm90LWEta2V5")
                .satisfies(e -> assertThat(((OAuth2AuthorizationException) e).getError().getErrorCode())
                        .isEqualTo(AppleClientSecret.ERROR_NOT_CONFIGURED));
    }
}
