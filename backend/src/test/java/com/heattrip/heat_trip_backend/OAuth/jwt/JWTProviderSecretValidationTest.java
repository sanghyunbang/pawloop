package com.heattrip.heat_trip_backend.OAuth.jwt;

import com.heattrip.heat_trip_backend.HeatTripBackendApplication;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.boot.builder.SpringApplicationBuilder;
import org.springframework.boot.test.context.assertj.AssertableApplicationContext;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;
import org.springframework.context.ConfigurableApplicationContext;
import org.springframework.test.util.ReflectionTestUtils;

import java.io.IOException;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.nio.charset.StandardCharsets;
import java.util.Properties;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * jwt.secret 이 비었거나 HS256 최소 길이(32바이트)에 못 미치면 **부팅 시점에** 죽어야 한다. (이슈 #6)
 *
 * 짧은 시크릿으로 컨텍스트가 뜨지 않는 것을 @SpringBootTest 로는 검증할 수 없다 —
 * 컨텍스트 로드 실패는 테스트 실패로 보고되지 기대값이 되지 않는다. 그래서
 * (1) ApplicationContextRunner 로 빈 생성 실패를, (2) SpringApplicationBuilder 로 실제
 * 애플리케이션 기동 실패를 각각 잡는다.
 */
class JWTProviderSecretValidationTest {

    /** application-test.properties 의 jwt.secret 과 같은 값(34바이트). */
    private static final String VALID_SECRET = "test-only-secret-key-32bytes-min!!";

    /** 정확히 32바이트 — 경계 그 자체. */
    private static final String EXACTLY_32_SECRET = "01234567890123456789012345678901";

    /** 정확히 31바이트 — 경계 바로 아래. */
    private static final String TOO_SHORT_SECRET = "0123456789012345678901234567890";

    private JWTProvider providerWith(String secret) {
        JWTProvider provider = new JWTProvider();
        ReflectionTestUtils.setField(provider, "secret", secret);
        ReflectionTestUtils.setField(provider, "expirationMillis", 3_600_000L);
        return provider;
    }

    private void init(JWTProvider provider) {
        ReflectionTestUtils.invokeMethod(provider, "init");
    }

    @Test
    @DisplayName("application-test.properties 에 들어 있는 jwt.secret 은 최소 키 길이 검증을 통과한다.")
    void 테스트용시크릿은_검증을통과한다() throws IOException {
        Properties properties = new Properties();
        try (InputStream in = getClass().getResourceAsStream("/application-test.properties")) {
            assertThat(in).as("application-test.properties 가 테스트 클래스패스에 있어야 한다").isNotNull();
            properties.load(new InputStreamReader(in, StandardCharsets.UTF_8));
        }
        String secret = properties.getProperty("jwt.secret");

        assertThat(secret).isNotBlank();
        assertThat(secret.getBytes(StandardCharsets.UTF_8).length)
                .isGreaterThanOrEqualTo(JWTProvider.MIN_SECRET_BYTES);

        JWTProvider provider = providerWith(secret);
        assertThatCode(() -> init(provider)).doesNotThrowAnyException();
    }

    @Test
    @DisplayName("경계값 확인 — 31바이트는 최소 길이 바로 아래이고 32바이트는 경계 그 자체다.")
    void 경계값_31바이트와32바이트다() {
        assertThat(TOO_SHORT_SECRET.getBytes(StandardCharsets.UTF_8))
                .hasSize(JWTProvider.MIN_SECRET_BYTES - 1);
        assertThat(EXACTLY_32_SECRET.getBytes(StandardCharsets.UTF_8))
                .hasSize(JWTProvider.MIN_SECRET_BYTES);
    }

    @Test
    @DisplayName("jwt.secret 이 빈 문자열이면 초기화가 실패하고 메시지에 최소 키 길이가 드러난다.")
    void init_시크릿이비어있으면_예외를던진다() {
        JWTProvider provider = providerWith("");

        assertThatThrownBy(() -> init(provider))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("jwt.secret")
                .hasMessageContaining(String.valueOf(JWTProvider.MIN_SECRET_BYTES));
    }

    @Test
    @DisplayName("jwt.secret 이 31바이트면 초기화가 실패하고 메시지에 최소 키 길이가 드러난다.")
    void init_시크릿이31바이트면_예외를던진다() {
        JWTProvider provider = providerWith(TOO_SHORT_SECRET);

        assertThatThrownBy(() -> init(provider))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("jwt.secret")
                .hasMessageContaining(String.valueOf(JWTProvider.MIN_SECRET_BYTES));
    }

    @Test
    @DisplayName("실패 메시지에는 시크릿 원문도, 실제 시크릿 길이도 들어가지 않는다.")
    void init_실패메시지에_시크릿이나그길이가없다() {
        JWTProvider provider = providerWith(TOO_SHORT_SECRET);

        assertThatThrownBy(() -> init(provider))
                .isInstanceOf(IllegalStateException.class)
                .satisfies(e -> {
                    assertThat(e.getMessage()).doesNotContain(TOO_SHORT_SECRET);
                    // 31 = 실제 시크릿 길이. 이게 노출되면 공격자의 탐색 공간이 좁아진다.
                    assertThat(e.getMessage()).doesNotContain("31");
                });
    }

    @Test
    @DisplayName("jwt.secret 이 정확히 32바이트면 정상 초기화되고 토큰이 발급된다.")
    void init_시크릿이32바이트면_정상초기화된다() {
        JWTProvider provider = providerWith(EXACTLY_32_SECRET);

        assertThatCode(() -> init(provider)).doesNotThrowAnyException();
        assertThat(provider.createAccessToken("user-1", "ROLE_USER")).isNotBlank();
    }

    @Test
    @DisplayName("스프링 컨텍스트에서도 31바이트 jwt.secret 이면 JWTProvider 빈 생성이 실패한다.")
    void 스프링컨텍스트_31바이트시크릿이면_빈생성이실패한다() {
        new ApplicationContextRunner()
                .withUserConfiguration(JWTProvider.class)
                .withPropertyValues("jwt.secret=" + TOO_SHORT_SECRET, "jwt.expiration=3600000")
                .run(context -> assertThat(context)
                        .hasFailed()
                        .getFailure()
                        .rootCause()
                        .isInstanceOf(IllegalStateException.class)
                        .hasMessageContaining(String.valueOf(JWTProvider.MIN_SECRET_BYTES)));
    }

    @Test
    @DisplayName("스프링 컨텍스트에서 32바이트 시크릿이면 JWTProvider 빈이 정상으로 뜬다.")
    void 스프링컨텍스트_32바이트시크릿이면_빈이정상으로뜬다() {
        new ApplicationContextRunner()
                .withUserConfiguration(JWTProvider.class)
                .withPropertyValues("jwt.secret=" + VALID_SECRET, "jwt.expiration=1800000")
                .run((AssertableApplicationContext context) -> {
                    assertThat(context).hasNotFailed();
                    assertThat(context.getBean(JWTProvider.class).getExpiresInSeconds()).isEqualTo(1800L);
                });
    }

    @Test
    @DisplayName("31바이트 jwt.secret 으로 애플리케이션을 띄우면 기동이 실패한다.")
    void 애플리케이션기동_31바이트시크릿이면_실패한다() {
        // --jwt.secret 은 커맨드라인 인자라 application-test.properties 보다 우선한다.
        // 웹 타입은 그대로 두고 포트만 0(임의 포트)으로 — 컨텍스트가 죽으면 바로 반납된다.
        SpringApplicationBuilder builder = new SpringApplicationBuilder(HeatTripBackendApplication.class)
                .bannerMode(org.springframework.boot.Banner.Mode.OFF);

        assertThatThrownBy(() -> {
            try (ConfigurableApplicationContext context =
                         builder.run("--spring.profiles.active=test", "--server.port=0", "--jwt.secret=" + TOO_SHORT_SECRET)) {
                // 여기에 도달하면 검증이 없는 것이다.
            }
        })
                .rootCause()
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("jwt.secret")
                .hasMessageContaining(String.valueOf(JWTProvider.MIN_SECRET_BYTES));
    }
}
