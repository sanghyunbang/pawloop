package com.heattrip.heat_trip_backend.config;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.boot.test.context.runner.ApplicationContextRunner;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * {@code app.security.oauth.*} 설정 키가 <b>실제로 빈에 닿는지</b> 잠근다. (이슈 #14)
 *
 * <h2>왜 이 파일이 따로 있나</h2>
 * {@code OAuth2SuccessHandlerTest.설정을_바꾸면_리다이렉트_대상도_바뀐다} 는 프로퍼티
 * <b>객체를 직접 만들어</b> 핸들러에 넘긴다. 그것은 "문자열이 코드에 박혀 있지 않다" 의
 * 증명이지, <b>바인딩 경로</b>({@code application.properties} → 프리픽스 → 빈)의 증명이
 * 아니다. 완료 조건 5 의 앞절은 "설정에서 바꾸면 실제로 반영되고" 인데, 그 절은 지금까지
 * 어떤 테스트도 지나가지 않는 자리였다.
 *
 * <p>프리픽스에 오타가 나거나 {@code @EnableConfigurationProperties} 등록이 빠지면 스프링은
 * <b>조용히 클래스 기본값</b>으로 떨어진다. 그 기본값이 운영 설정과 우연히 같아서 어떤
 * 테스트도 어떤 로그도 신호를 내지 않는다. 그 상태에서
 * {@code APP_SECURITY_OAUTH_REDIRECT_ALLOWLIST} 를 바꾸면 "설정을 바꿨는데 반영이 안 된다"
 * 가 된다.
 *
 * <h2>왜 @SpringBootTest 가 아닌가</h2>
 * 이 저장소의 스프링 통합 테스트는 실 MySQL 컨테이너를 띄운다(#49). 여기서 재는 것은
 * "키가 빈에 닿는가" 뿐이라 데이터소스가 필요 없다. {@link ApplicationContextRunner} 는
 * 설정 클래스 하나만 올린 최소 컨텍스트를 만든다 — 컨테이너 없이 같은 것을 증명한다.
 * ({@code OAuth2SuccessHandlerTest} 의 주석이 "@TestPropertySource 로 하면 MySQL 통합
 * 테스트가 된다" 고 적은 것은 이 방법을 빼놓은 서술이었다.)
 */
class OAuthSecurityPropertiesBindingTest {

    private final ApplicationContextRunner runner =
            new ApplicationContextRunner().withUserConfiguration(PublicSecurityConfig.class);

    @Test
    @DisplayName("app.security.oauth.* 가 OAuthSecurityProperties 에 실제로 바인딩된다")
    void oauthPrefix_isBoundToTheBean() {
        runner.withPropertyValues(
                        "app.security.oauth.redirect-allowlist=probe://done,heattrip://login-callback",
                        "app.security.oauth.code-ttl-seconds=17")
                .run(context -> {
                    assertThat(context).hasSingleBean(OAuthSecurityProperties.class);

                    OAuthSecurityProperties props = context.getBean(OAuthSecurityProperties.class);
                    assertThat(props.getRedirectAllowlist())
                            .as("프리픽스 오타나 등록 누락이면 여기서 클래스 기본값이 나온다")
                            .containsExactly("probe://done", "heattrip://login-callback");
                    assertThat(props.getCodeTtlSeconds()).isEqualTo(17);
                    assertThat(props.defaultRedirect())
                            .as("목록의 첫 항목이 기본 대상이다 — 그 규칙까지 설정을 따라야 한다")
                            .isEqualTo("probe://done");
                });
    }

    @Test
    @DisplayName("app.security.rate-limit.* 도 같은 경로로 바인딩된다 — 신뢰 프록시 목록 포함")
    void rateLimitPrefix_isBoundToTheBean() {
        runner.withPropertyValues(
                        "app.security.rate-limit.ip-header=X-Probe-Ip",
                        "app.security.rate-limit.auth-max-requests=3",
                        "app.security.rate-limit.trusted-proxies=10.9.0.0/16,127.0.0.1/32")
                .run(context -> {
                    var rateLimit = context.getBean(PublicSecurityProperties.class).getRateLimit();

                    assertThat(rateLimit.getIpHeader()).isEqualTo("X-Probe-Ip");
                    assertThat(rateLimit.getAuthMaxRequests()).isEqualTo(3);
                    assertThat(rateLimit.getTrustedProxies())
                            .as("이 목록이 바인딩되지 않으면 운영에서 신뢰 경계를 조정할 방법이 없다")
                            .containsExactly("10.9.0.0/16", "127.0.0.1/32");
                });
    }

    @Test
    @DisplayName("아무것도 주지 않으면 클래스 기본값이 그대로 온다 — 위 테스트가 무엇을 증명하는지 대조군")
    void noProperties_fallsBackToTheClassDefaults() {
        runner.run(context -> {
            OAuthSecurityProperties oauth = context.getBean(OAuthSecurityProperties.class);
            assertThat(oauth.getRedirectAllowlist()).containsExactly("heattrip://login-callback");
            assertThat(oauth.getCodeTtlSeconds()).isEqualTo(60);
        });
    }
}
