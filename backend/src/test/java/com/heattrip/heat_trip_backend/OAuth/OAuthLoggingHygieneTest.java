package com.heattrip.heat_trip_backend.OAuth;

import ch.qos.logback.classic.Level;
import ch.qos.logback.classic.Logger;
import ch.qos.logback.classic.spi.ILoggingEvent;
import ch.qos.logback.core.read.ListAppender;
import com.heattrip.heat_trip_backend.OAuth.handler.OAuth2SuccessHandler;
import com.heattrip.heat_trip_backend.OAuth.jwt.JWTProvider;
import com.heattrip.heat_trip_backend.OAuth.service.CustomOAuth2UserService;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.slf4j.LoggerFactory;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.security.oauth2.core.OAuth2AuthenticationException;

import java.util.ArrayList;
import java.util.List;
import java.util.regex.Pattern;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * 인증 경로의 로그 위생을 잠근다. (이슈 #6)
 *
 * 토큰 원문(eyJ...), 시크릿, 시크릿 길이, 이메일, 소셜 providerId 는 어떤 로그 레벨에도
 * 남으면 안 된다. 세 로거에 ListAppender 를 붙이고 레벨을 TRACE 까지 열어 둔 뒤
 * 로그인 한 번을 그대로 돌려서 캡처된 메시지를 검사한다.
 */
class OAuthLoggingHygieneTest {

    /** 이메일 형태 문자열. 캡처된 로그에 하나라도 있으면 안 된다. */
    private static final Pattern EMAIL_PATTERN =
            Pattern.compile("[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}");

    private final List<Logger> watched = new ArrayList<>();
    private final List<Level> originalLevels = new ArrayList<>();
    private ListAppender<ILoggingEvent> appender;

    @BeforeEach
    void attachAppender() {
        appender = new ListAppender<>();
        appender.start();

        for (Class<?> type : List.of(JWTProvider.class, OAuth2SuccessHandler.class, CustomOAuth2UserService.class)) {
            Logger logger = (Logger) LoggerFactory.getLogger(type);
            watched.add(logger);
            originalLevels.add(logger.getLevel());
            logger.setLevel(Level.TRACE); // debug/trace 로 강등한 로그도 전부 잡는다
            logger.addAppender(appender);
        }
    }

    @AfterEach
    void detachAppender() {
        for (int i = 0; i < watched.size(); i++) {
            Logger logger = watched.get(i);
            logger.detachAppender(appender);
            logger.setLevel(originalLevels.get(i));
        }
        watched.clear();
        originalLevels.clear();
        appender.stop();
    }

    @Test
    @DisplayName("로그인 한 번을 수행해도 인증 로그에 토큰 원문·시크릿·시크릿 길이가 남지 않는다.")
    void 로그인후_인증로그에_토큰과시크릿이없다() throws Exception {
        String token = OAuthLoginProbe.runLogin();

        List<String> messages = capturedMessages();

        assertThat(messages).isNotEmpty(); // 아무것도 안 찍혔다면 이 테스트는 아무것도 지키지 못한다
        assertThat(messages).noneMatch(m -> m.contains("eyJ"));
        assertThat(messages).noneMatch(m -> m.contains(token));
        assertThat(messages).noneMatch(m -> m.toLowerCase().contains("secret"));
    }

    @Test
    @DisplayName("로그인 한 번을 수행해도 인증 로그에 이메일과 소셜 providerId 가 남지 않는다.")
    void 로그인후_인증로그에_이메일과소셜ID가없다() throws Exception {
        OAuthLoginProbe.runLogin();

        List<String> messages = capturedMessages();

        assertThat(messages).isNotEmpty();
        assertThat(messages).noneMatch(m -> m.contains(OAuthLoginProbe.EMAIL));
        assertThat(messages).noneMatch(m -> EMAIL_PATTERN.matcher(m).find());
        assertThat(messages).noneMatch(m -> m.contains(OAuthLoginProbe.PROVIDER_ID));
        // provider_providerId 형태(= CustomOAuth2User.getName())도 소셜 ID 다
        assertThat(messages).noneMatch(m -> m.contains("google_"));
    }

    @Test
    @DisplayName("토큰을 발급해도 JWTProvider 로그에는 사용자 식별자와 시크릿 길이가 남지 않는다.")
    void 토큰발급시_JWTProvider로그에_식별자가없다() {
        JWTProvider provider = OAuthLoginProbe.jwtProvider();

        String token = provider.createAccessToken(OAuthLoginProbe.ASSIGNED_USER_ID, "ROLE_USER");

        List<String> messages = capturedMessages();
        assertThat(messages).noneMatch(m -> m.contains(token));
        assertThat(messages).noneMatch(m -> m.contains("eyJ"));
        assertThat(messages).noneMatch(m -> m.contains(OAuthLoginProbe.PROVIDER_ID));
        assertThat(messages).noneMatch(m -> m.contains(OAuthLoginProbe.SECRET));
        // "secret length = 34" 같은 줄은 공격자의 탐색 공간을 좁혀 준다. 어떤 형태로도 금지.
        assertThat(messages).noneMatch(m -> m.toLowerCase().contains("secret"));
    }

    // ─────────────────── 이메일이 오가는 실패·충돌 분기 (이슈 #7) ───────────────────
    //
    // 위 세 테스트는 '신규 가입 성공' 경로 하나만 돈다. 그래서 이 PR 이 새로 만든
    // 이메일 경로 세 곳(가입 거절 / 저장 충돌 / 갱신 건너뜀)에서는 이메일을 로그에
    // 흘려도 스위트가 초록불이었다. 아래가 그 세 곳을 실제로 태운다.

    @Test
    @DisplayName("이메일 충돌로 가입이 거절돼도 로그·예외 메시지·예외 cause 어디에도 이메일이 없다.")
    void 이메일충돌로_가입거절시_이메일이_남지않는다() {
        OAuth2AuthenticationException thrown = OAuthLoginProbe.runEmailCollisionLogin();

        assertThat(thrown.getError().getErrorCode()).isEqualTo("email_already_registered");
        assertNoEmailAnywhere(thrown);
    }

    @Test
    @DisplayName("저장이 무결성 제약에 걸려도 DB 예외 메시지(이메일 원문 포함)가 로그·예외로 새지 않는다.")
    void 무결성위반시_DB예외메시지가_새지않는다() {
        OAuth2AuthenticationException thrown = OAuthLoginProbe.runIntegrityViolationLogin();

        assertThat(thrown.getError().getErrorCode()).isEqualTo("account_conflict");
        // cause 로 실으면 예외 스택 전체가 인증 실패 로그로 흘러간다 — DB 메시지에는 이메일이 있다.
        assertThat(thrown.getCause())
                .as("DataIntegrityViolationException 을 cause 로 싣지 않는다")
                .isNull();
        assertThat(thrown).isNotInstanceOf(DataIntegrityViolationException.class);
        assertNoEmailAnywhere(thrown);
    }

    @Test
    @DisplayName("공급자 이메일이 다른 계정에 있어 갱신을 건너뛸 때도 그 이메일이 로그에 남지 않는다.")
    void 이메일갱신_건너뛸때_이메일이_남지않는다() {
        OAuthLoginProbe.runEmailUpdateSkippedLogin();

        List<String> messages = capturedMessages();
        assertThat(messages).isNotEmpty();
        assertThat(messages).noneMatch(m -> m.contains(OAuthLoginProbe.EMAIL));
        assertThat(messages).noneMatch(m -> EMAIL_PATTERN.matcher(m).find());
    }

    /** 로그에도, 예외 메시지에도 이메일이 없어야 한다. */
    private void assertNoEmailAnywhere(Exception thrown) {
        List<String> messages = new ArrayList<>(capturedMessages());
        messages.add(String.valueOf(thrown.getMessage()));
        for (Throwable cause = thrown.getCause(); cause != null; cause = cause.getCause()) {
            messages.add(String.valueOf(cause.getMessage()));
        }

        assertThat(messages).isNotEmpty();
        assertThat(messages).noneMatch(m -> m.contains(OAuthLoginProbe.EMAIL));
        assertThat(messages).noneMatch(m -> EMAIL_PATTERN.matcher(m).find());
        assertThat(messages).noneMatch(m -> m.contains(OAuthLoginProbe.PROVIDER_ID));
    }

    /** 캡처된 이벤트의 포맷된 메시지 + 예외 메시지까지 한 줄씩 모은다. */
    private List<String> capturedMessages() {
        List<String> messages = new ArrayList<>();
        for (ILoggingEvent event : appender.list) {
            messages.add(event.getFormattedMessage());
            if (event.getThrowableProxy() != null) {
                messages.add(event.getThrowableProxy().getMessage());
            }
        }
        return messages;
    }
}
