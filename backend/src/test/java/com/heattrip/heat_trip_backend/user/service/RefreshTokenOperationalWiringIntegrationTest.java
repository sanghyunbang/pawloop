package com.heattrip.heat_trip_backend.user.service;

import ch.qos.logback.classic.Level;
import ch.qos.logback.classic.Logger;
import ch.qos.logback.classic.spi.ILoggingEvent;
import ch.qos.logback.core.read.ListAppender;

import com.heattrip.heat_trip_backend.support.AbstractMySqlIntegrationTest;
import com.heattrip.heat_trip_backend.support.TestProjectPaths;
import com.heattrip.heat_trip_backend.user.entity.User;
import com.heattrip.heat_trip_backend.user.repository.RefreshTokenRepository;
import com.heattrip.heat_trip_backend.user.repository.UserRepository;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.context.ApplicationContext;
import org.springframework.scheduling.config.ScheduledTask;
import org.springframework.scheduling.config.ScheduledTaskHolder;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.MessageDigest;
import java.util.ArrayList;
import java.util.HexFormat;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.stream.Collectors;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * refresh 토큰을 둘러싼 <b>운영 배선</b>이 실제로 켜져 있는지 본다 — 이슈 #9.
 *
 * <p>여기 있는 두 보증은 모두 "구현은 맞는데 배선이 빠져서 아무 일도 일어나지 않는" 종류의
 * 결함을 겨냥한다. 둘 다 되돌리면 앱은 멀쩡히 뜨고 나머지 테스트도 전부 초록불이다.
 *
 * <ul>
 *   <li><b>만료 정리 잡</b> — {@code @Scheduled} 는 {@code @EnableScheduling} 없이는 완전히
 *       무력하다(빈은 뜨지만 잡이 영원히 등록되지 않는다). 애너테이션의 존재만 리플렉션으로
 *       확인하는 테스트는 그 배선을 보지 못한다. 여기서는 <b>살아 있는 컨텍스트에 실제로
 *       등록된 잡 목록</b>을 읽는다.</li>
 *   <li><b>바인딩 로그 위생</b> — 원장에 저장되는 것은 refresh 토큰의 SHA-256 해시인데,
 *       그 값을 로그로 흘리는 것은 애플리케이션 로거가 아니라 <b>Hibernate 바인딩 로거</b>다.
 *       목 기반 로그 위생 테스트({@code OAuthLoggingHygieneTest})는 그 경로를 원리적으로
 *       지나지 않는다 — 감시 대상이 애플리케이션 로거뿐이기 때문이다.</li>
 * </ul>
 *
 * <p>애너테이션이 {@code @SpringBootTest} + {@code @AutoConfigureMockMvc} 두 줄인 것은 의도다 —
 * {@code AuthTokenRefreshIntegrationTest} 와 글자 그대로 같아야 컨텍스트 캐시를 공유한다.
 */
@SpringBootTest
@AutoConfigureMockMvc
class RefreshTokenOperationalWiringIntegrationTest extends AbstractMySqlIntegrationTest {

    /** Hibernate 가 바인딩 파라미터를 찍는 로거. 이 이름이 바뀌면 아래 통제 단언이 먼저 깨진다. */
    private static final String HIBERNATE_BIND_LOGGER = "org.hibernate.orm.jdbc.bind";

    /** 운영 기본값이 적힌 설정 파일들. 하나라도 바인딩 로그를 TRACE 로 올리면 해시가 새어 나간다. */
    private static final List<String> CONFIG_FILES = List.of(
            "src/main/resources/application.properties",
            "src/main/resources/application-dev.properties",
            "src/main/resources/application-prod.properties");

    @Autowired private ApplicationContext applicationContext;
    @Autowired private RefreshTokenService refreshTokenService;
    @Autowired private RefreshTokenRepository refreshTokenRepository;
    @Autowired private UserRepository userRepository;

    private final List<Long> createdUserIds = new ArrayList<>();

    @AfterEach
    void cleanUp() {
        for (Long userId : createdUserIds) {
            refreshTokenRepository.deleteByUserId(userId);
            userRepository.findById(userId).ifPresent(userRepository::delete);
        }
        createdUserIds.clear();
    }

    // ─────────────────── 만료 정리 잡이 실제로 등록되는가 ───────────────────

    @Test
    @DisplayName("만료 정리 잡이 살아 있는 컨텍스트에 실제로 등록된다 — @EnableScheduling 이 빠지면 여기가 빨간불이다")
    void purgeJob_isActuallyRegisteredInTheRunningContext() {
        // getBeanProvider(...).stream() 으로는 잡히지 않는다 — 스케줄 등록을 담당하는
        // ScheduledAnnotationBeanPostProcessor 는 인프라스트럭처 빈이라 일반 주입 후보에서
        // 빠진다. getBeansOfType 은 그것까지 돌려준다.
        Map<String, ScheduledTaskHolder> holders =
                applicationContext.getBeansOfType(ScheduledTaskHolder.class);

        assertThat(holders)
                .as("@EnableScheduling 이 꺼지면 스케줄 등록 주체 자체가 컨텍스트에 없다 — "
                        + "그래도 앱은 뜨고 @Scheduled 는 조용히 무시된다")
                .isNotEmpty();

        // 등록된 잡의 표현은 Task#toString() 이고 그건 대상 메서드의 FQN 이다. 러너블 타입으로
        // 거르지 않는 이유: Spring 6.1 이 관측을 위해 ScheduledMethodRunnable 을
        // Task$OutcomeTrackingRunnable 로 감싸서, 타입 검사로 거르면 전부 빠져나간다(실측).
        Set<String> scheduledTasks = holders.values().stream()
                .flatMap(holder -> holder.getScheduledTasks().stream())
                .map(ScheduledTask::getTask)
                .map(String::valueOf)
                .collect(Collectors.toSet());

        assertThat(scheduledTasks)
                .as("스케줄 잡이 등록되지 않았다면 @EnableScheduling 이 꺼진 것이다 — "
                        + "그래도 앱은 뜨고 만료된 refresh_token 행만 영원히 쌓인다")
                .contains(RefreshTokenPurgeScheduler.class.getName() + ".purgeExpiredRefreshTokens");
    }

    // ─────────────────── 바인딩 로그로 해시가 새지 않는가 ───────────────────

    @Test
    @DisplayName("운영 설정이 정한 로그 레벨에서는 발급·회전이 refresh 토큰의 원문도 SHA-256 해시도 로그에 남기지 않는다")
    void hibernateBindLog_doesNotLeakTheTokenHashAtTheShippedLevel() throws Exception {
        long userId = seedUser();
        Logger bindLogger = (Logger) LoggerFactory.getLogger(HIBERNATE_BIND_LOGGER);
        Level originalLevel = bindLogger.getLevel();
        ListAppender<ILoggingEvent> appender = new ListAppender<>();
        appender.start();
        bindLogger.addAppender(appender);
        try {
            // ① 통제: 이 채널이 실제로 살아 있음을 먼저 증명한다. 이게 없으면 아래 ② 는
            //    "아무것도 못 잡는 앤더를 붙여 놓고 아무것도 없다고 단언하는" 공허한 초록불이다.
            bindLogger.setLevel(Level.TRACE);
            appender.list.clear();
            String leaked = refreshTokenService.issueFor(userId);
            assertThat(captured(appender))
                    .as("바인딩 로거를 TRACE 로 올리면 해시가 그대로 찍힌다 — 이게 닫아야 할 채널이다")
                    .contains(sha256Hex(leaked));

            // ② 본 단언: 운영 설정이 정한 레벨에서는 같은 경로가 아무것도 남기지 않는다.
            //    설정 파일이 다시 TRACE 로 돌아가면 여기가 빨간불이다.
            bindLogger.setLevel(shippedBindLogLevel());
            appender.list.clear();
            String raw = refreshTokenService.issueFor(userId);
            String rotated = refreshTokenService.rotate(raw).refreshToken();

            String logged = captured(appender);
            assertThat(logged)
                    .as("14일짜리 자격증명의 원문이 로그에 남으면 로그를 가진 사람이 곧 그 계정이다 (#6)")
                    .doesNotContain(raw, rotated);
            assertThat(logged)
                    .as("해시는 자격증명이 아니지만 결정적이라 원장의 그 행을 정확히 지목한다 — 규약 #6 이 해시를 함께 금지한 이유다")
                    .doesNotContain(sha256Hex(raw), sha256Hex(rotated));
        } finally {
            bindLogger.detachAppender(appender);
            appender.stop();
            bindLogger.setLevel(originalLevel);
        }
    }

    @Test
    @DisplayName("운영 설정 어디에도 Hibernate 바인딩 로그를 TRACE·DEBUG 로 올려 두지 않는다")
    void shippedConfiguration_keepsBindLoggingOff() throws IOException {
        for (String relativePath : CONFIG_FILES) {
            for (String declared : declaredBindLevels(relativePath)) {
                assertThat(Level.toLevel(declared, Level.INFO).isGreaterOrEqual(Level.INFO))
                        .as("%s 가 바인딩 로그를 %s 로 올린다 — refresh 토큰 해시·이메일·BCrypt 해시가 "
                                + "전부 운영 로그로 나간다 (#6)", relativePath, declared)
                        .isTrue();
            }
        }
    }

    // ─────────────────────────── 지그 ───────────────────────────

    private long seedUser() {
        User seeded = userRepository.save(User.builder()
                .provider(User.PROVIDER_LOCAL)
                .role(User.ROLE_USER)
                .email("bindlog-" + System.nanoTime() + "@example.com")
                .name("보리")
                .build());
        createdUserIds.add(seeded.getId());
        return seeded.getId();
    }

    private static String captured(ListAppender<ILoggingEvent> appender) {
        return appender.list.stream()
                .map(ILoggingEvent::getFormattedMessage)
                .collect(Collectors.joining("\n"));
    }

    /** 운영 설정 파일들이 선언한 바인딩 로그 레벨 중 가장 낮은(가장 많이 찍는) 값. */
    private static Level shippedBindLogLevel() throws IOException {
        Level lowest = Level.INFO;
        for (String relativePath : CONFIG_FILES) {
            for (String declared : declaredBindLevels(relativePath)) {
                Level level = Level.toLevel(declared, Level.INFO);
                if (!level.isGreaterOrEqual(lowest)) {
                    lowest = level;
                }
            }
        }
        return lowest;
    }

    /**
     * 설정 파일에서 바인딩 로거 레벨 선언을 모두 꺼낸다.
     *
     * <p>{@code ${VAR:DEFAULT}} 형태면 배포자가 아무것도 하지 않았을 때 적용되는
     * {@code DEFAULT} 를 읽는다 — 운영의 실제 기본값이 그것이다.
     */
    private static List<String> declaredBindLevels(String relativePath) throws IOException {
        Path file = TestProjectPaths.requireFile(relativePath);
        List<String> levels = new ArrayList<>();
        for (String line : Files.readAllLines(file, StandardCharsets.UTF_8)) {
            String stripped = line.strip();
            if (stripped.startsWith("#") || !stripped.startsWith("logging.level." + HIBERNATE_BIND_LOGGER + "=")) {
                continue;
            }
            String value = stripped.substring(stripped.indexOf('=') + 1).strip();
            if (value.startsWith("${")) {
                int colon = value.indexOf(':');
                value = (colon < 0)
                        ? "INFO" // 기본값 없는 플레이스홀더 — 배포자가 정한다. 여기서는 안전한 쪽으로 읽는다.
                        : value.substring(colon + 1, value.lastIndexOf('}')).strip();
            }
            levels.add(value);
        }
        return levels;
    }

    /** 프로덕션 해싱 함수를 부르지 않고 직접 계산한다 — 순환 검증을 피한다. */
    private static String sha256Hex(String raw) throws Exception {
        return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256")
                .digest(raw.getBytes(StandardCharsets.UTF_8)));
    }
}
