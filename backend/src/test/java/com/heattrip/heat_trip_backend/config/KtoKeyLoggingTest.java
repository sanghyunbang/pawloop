package com.heattrip.heat_trip_backend.config;

import ch.qos.logback.classic.Level;
import ch.qos.logback.classic.LoggerContext;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.slf4j.LoggerFactory;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * 관광공사 서비스 키가 로그로 새지 않는가 — 이슈 #192.
 *
 * <h2>무엇이 샜나</h2>
 * <p>{@code ExchangeFunctions} 가 DEBUG 에서 나가는 요청 URL 을 통째로 찍는다. KTO 호출은
 * {@code serviceKey} 를 쿼리스트링에 실어야 해서(KTO 가 헤더 인증을 안 받는다) 그 줄에 키가
 * <b>평문으로</b> 남았다. 실제로 로컬 백엔드 로그에서 발견했다.
 *
 * <h2>우리 코드가 아니라 프레임워크가 찍었다</h2>
 * <p>{@link KtoWebClientConfig} 는 이 위험을 이미 알고 있었다 — 그 javadoc 이 "키는 호출부가
 * URI 를 조립할 때만 붙이고, 호출부는 URL 을 로그에 찍지 않는다" 고 정한다. 그 규칙은
 * 지켜지고 있었다. 새는 것은 <b>스프링 자신의 로거</b>였다.
 *
 * <h2>이 테스트가 재는 것과 못 재는 것</h2>
 * <p><b>재는 것</b> — (1) 눌러 두는 설정이 파일에 있고 환경변수로 열려 있지 않다,
 * (2) 부모를 DEBUG 로 올려도 자식 설정이 이긴다는 로그백의 성질. 두 번째가 이 방어의
 * 전제이고, 그것이 참이 아니면 첫 번째는 아무 의미가 없다.
 *
 * <p><b>못 재는 것</b> — 실제로 뜬 애플리케이션에서 그 레벨이 적용되는가. 그것을 재려면
 * 컨텍스트를 띄워야 하고 이 저장소에서는 MySQL 컨테이너가 딸려 온다. 로그 레벨 하나를
 * 확인하려고 DB 를 띄우는 것은 값을 못 한다고 봤다.
 */
@DisplayName("KTO 서비스 키가 로그로 새지 않는다 (#192)")
class KtoKeyLoggingTest {

    /** URL 을 통째로 찍는 로거들. 하나라도 DEBUG 면 키가 남는다. */
    private static final String PARENT = "org.springframework.web";
    private static final String LEAKING = "org.springframework.web.reactive.function.client";
    private static final String EXCHANGE_FUNCTIONS = LEAKING + ".ExchangeFunctions";

    /**
     * <b>들어오는</b> 쪽에서 URL 을 통째로 찍는 로거. #192 가 놓친 자리다.
     *
     * <p>{@code PARENT} 를 DEBUG 로 올리면 이것도 함께 올라가고, 그러면 요청 URL 이
     * 쿼리스트링째 로그에 남는다 — {@code ?lat=..&lng=..} 가 사용자의 현위치다.
     * {@code parameters} 는 마스킹되는데 URL 은 안 된다.
     */
    private static final String INBOUND = "org.springframework.web.servlet.DispatcherServlet";

    @AfterEach
    void resetLevels() {
        LoggerContext context = (LoggerContext) LoggerFactory.getILoggerFactory();
        context.getLogger(PARENT).setLevel(null);
        context.getLogger(LEAKING).setLevel(null);
        context.getLogger(INBOUND).setLevel(null);
    }

    @Test
    @DisplayName("눌러 두는 설정이 파일에 있고 환경변수로 열려 있지 않다")
    void theLevelIsPinnedNotParameterised() throws IOException {
        String properties = Files.readString(
                Path.of("src/main/resources/application.properties"));

        // 값이 ${...} 면 .env 가 DEBUG 로 올리는 순간 다시 샌다. 실제로 그 파일이
        // LOG_LEVEL_ORG_SPRINGFRAMEWORK_WEB=DEBUG 를 들고 있다.
        assertThat(properties)
                .as("환경변수로 열어 두면 언젠가 올라간다")
                .contains("logging.level." + LEAKING + "=INFO")
                .contains("logging.level.reactor.netty.http.client=INFO");

        assertThat(properties)
                .as("""
                        들어오는 쪽도 눌러야 한다. #192 는 나가는 호출만 막았고, 그 사이 \
                        DispatcherServlet 이 GET "/api/places/nearby?lat=..&lng=.." 를 찍고 \
                        있었다 — 실측이다. 새는 값이 키가 아니라 **사용자의 현위치**라 \
                        위치정보법 쪽으로도 걸린다.""")
                .contains("logging.level." + INBOUND + "=INFO");
    }

    @Test
    @DisplayName("부모를 DEBUG 로 올려도 자식 설정이 이긴다 — 이 방어의 전제다")
    void theChildLoggerWinsOverTheParent() {
        LoggerContext context = (LoggerContext) LoggerFactory.getILoggerFactory();

        // .env 가 하는 일을 그대로 재현한다.
        context.getLogger(PARENT).setLevel(Level.DEBUG);
        // application.properties 가 하는 일.
        context.getLogger(LEAKING).setLevel(Level.INFO);

        // 들어오는 쪽도 같은 자리에 있다 — PARENT 의 직계 자식이라 같은 성질을 딛는다.
        context.getLogger(INBOUND).setLevel(Level.INFO);
        assertThat(context.getLogger(INBOUND).getEffectiveLevel().isGreaterOrEqual(Level.INFO))
                .as("자식이 안 이기면 .env 가 DEBUG 인 동안 요청 URL 이 쿼리스트링째 남는다")
                .isTrue();

        Level effective = context.getLogger(EXCHANGE_FUNCTIONS).getEffectiveLevel();

        assertThat(effective.isGreaterOrEqual(Level.INFO))
                .as("자식이 안 이기면 부모를 올리는 순간 serviceKey 가 URL 째로 남는다 — 지금 %s",
                        effective)
                .isTrue();
    }

    @Test
    @DisplayName("자식을 안 눌러 두면 실제로 샌다 — 위 테스트가 무엇을 막는지 보인다")
    void withoutThePinTheParentLeaks() {
        LoggerContext context = (LoggerContext) LoggerFactory.getILoggerFactory();

        context.getLogger(PARENT).setLevel(Level.DEBUG);
        // 자식은 안 건드린다 = application.properties 에 그 줄이 없는 상태.

        assertThat(context.getLogger(EXCHANGE_FUNCTIONS).isDebugEnabled())
                .as("이것이 참이라는 사실이 이 이슈의 원인이다")
                .isTrue();
    }
}
