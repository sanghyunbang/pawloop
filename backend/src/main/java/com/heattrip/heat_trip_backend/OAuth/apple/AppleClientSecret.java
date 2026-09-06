package com.heattrip.heat_trip_backend.OAuth.apple;

import com.nimbusds.jose.JOSEException;
import com.nimbusds.jose.JWSAlgorithm;
import com.nimbusds.jose.JWSHeader;
import com.nimbusds.jose.crypto.ECDSASigner;
import com.nimbusds.jwt.JWTClaimsSet;
import com.nimbusds.jwt.SignedJWT;

import org.springframework.security.oauth2.core.OAuth2AuthorizationException;
import org.springframework.security.oauth2.core.OAuth2Error;
import org.springframework.stereotype.Component;

import java.security.KeyFactory;
import java.security.interfaces.ECPrivateKey;
import java.security.spec.PKCS8EncodedKeySpec;
import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.util.Base64;
import java.util.Date;

/**
 * Apple 토큰 교환에 보내는 {@code client_secret} — 개발자 키로 서명한 JWT. 이슈 #301.
 *
 * <p>Apple 규격(Generate and validate tokens): ES256, 헤더 {@code kid} = Key ID,
 * 클레임 {@code iss} = Team ID · {@code sub} = client_id(Services ID) · {@code aud} =
 * {@code https://appleid.apple.com} · {@code iat}/{@code exp}(최대 6개월). 우리는 <b>요청마다
 * 10분짜리를 새로 만든다</b> — 캐시할 만큼 비싸지 않고(서명 한 번), 짧을수록 새는 날 피해가 작다.
 *
 * <h2>키가 없으면 로그인 실패이지 서버 실패가 아니다</h2>
 * <p>{@link OAuth2AuthorizationException}({@code apple_not_configured})을 던진다. Spring 의
 * 로그인 필터가 그것을 인증 실패로 받아 {@code OAuth2FailureHandler} 로 보내고, 앱은
 * {@code heattrip://login-callback?error=apple_not_configured} 를 받는다. 500 이 아니다.
 *
 * <p>키 값은 로그에 남기지 않는다. 남기는 것은 "설정됐는가" 뿐이다.
 */
@Component
public class AppleClientSecret {

    /** Apple 이 요구하는 {@code aud}. */
    static final String AUDIENCE = "https://appleid.apple.com";

    /** 한 장의 수명. Apple 상한은 6개월이지만 길 이유가 없다. */
    static final Duration LIFETIME = Duration.ofMinutes(10);

    static final String ERROR_NOT_CONFIGURED = "apple_not_configured";

    private final AppleSignInProperties properties;
    private final Clock clock;

    /** 한 번 파싱한 키. 프로퍼티는 기동 뒤 안 바뀐다. */
    private volatile ECPrivateKey cachedKey;

    public AppleClientSecret(AppleSignInProperties properties, Clock clock) {
        this.properties = properties;
        this.clock = clock;
    }

    /**
     * @param clientId Apple 에 등록한 Services ID — 등록의 {@code client-id} 그대로. {@code sub} 클레임이다
     */
    public String current(String clientId) {
        if (!properties.isConfigured()) {
            throw new OAuth2AuthorizationException(new OAuth2Error(ERROR_NOT_CONFIGURED,
                    "Apple 로그인 키(APPLE_TEAM_ID · APPLE_KEY_ID · APPLE_PRIVATE_KEY)가 설정되지 않았습니다.", null));
        }
        Instant now = clock.instant();
        JWTClaimsSet claims = new JWTClaimsSet.Builder()
                .issuer(properties.getTeamId().strip())
                .subject(clientId)
                .audience(AUDIENCE)
                .issueTime(Date.from(now))
                .expirationTime(Date.from(now.plus(LIFETIME)))
                .build();
        JWSHeader header = new JWSHeader.Builder(JWSAlgorithm.ES256)
                .keyID(properties.getKeyId().strip())
                .build();
        SignedJWT jwt = new SignedJWT(header, claims);
        try {
            jwt.sign(new ECDSASigner(privateKey()));
        } catch (JOSEException e) {
            throw new OAuth2AuthorizationException(new OAuth2Error(ERROR_NOT_CONFIGURED,
                    "Apple 개발자 키로 서명하지 못했습니다 — 키 형식을 확인하세요.", null), e);
        }
        return jwt.serialize();
    }

    private ECPrivateKey privateKey() {
        ECPrivateKey key = cachedKey;
        if (key == null) {
            key = parse(properties.getPrivateKey());
            cachedKey = key;
        }
        return key;
    }

    /**
     * .p8 내용을 EC 개인키로. PEM 머리·꼬리와 공백·줄바꿈을 전부 떼고 base64 로 읽는다 —
     * {@code .env} 에 한 줄로 넣어도 되게.
     */
    static ECPrivateKey parse(String pem) {
        String body = pem
                .replace("-----BEGIN PRIVATE KEY-----", "")
                .replace("-----END PRIVATE KEY-----", "")
                .replace("\\n", "")
                .replaceAll("\\s", "");
        try {
            byte[] der = Base64.getDecoder().decode(body);
            return (ECPrivateKey) KeyFactory.getInstance("EC").generatePrivate(new PKCS8EncodedKeySpec(der));
        } catch (Exception e) {
            // 키 값은 예외 메시지에 싣지 않는다.
            throw new OAuth2AuthorizationException(new OAuth2Error(ERROR_NOT_CONFIGURED,
                    "APPLE_PRIVATE_KEY 가 PKCS#8 EC 키(.p8)가 아닙니다.", null), e);
        }
    }
}
