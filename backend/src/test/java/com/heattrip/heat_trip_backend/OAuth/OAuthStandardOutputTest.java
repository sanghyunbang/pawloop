package com.heattrip.heat_trip_backend.OAuth;

import ch.qos.logback.classic.Level;
import ch.qos.logback.classic.Logger;
import com.heattrip.heat_trip_backend.OAuth.jwt.JWTProvider;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.slf4j.LoggerFactory;

import java.io.ByteArrayOutputStream;
import java.io.PrintStream;
import java.nio.charset.StandardCharsets;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * 인증 경로가 표준출력·표준에러로 아무것도 쏟지 않는지 잠근다. (이슈 #6)
 *
 * System.out 은 로그 레벨로 끌 수 없어서 운영 로그 수집기에 그대로 들어간다.
 * 예전에는 OAuth 패키지에 System.out.println 10건과 printStackTrace 1건이 있었고
 * 그중에는 시크릿 길이와 사용자 식별자를 찍는 줄도 있었다.
 *
 * 이 테스트는 "한 줄이라도 되돌리면 빨간불"이 되도록 버퍼가 완전히 비어 있음을 요구한다.
 * 그래서 로그백이 끼어들지 못하게 루트 로거를 잠시 끄고, 스트림을 바꿔치기 전에
 * 한 번 워밍업해서 클래스 로딩·목 생성 과정의 부수 출력이 섞이지 않게 한다.
 */
class OAuthStandardOutputTest {

    private PrintStream originalOut;
    private PrintStream originalErr;
    private ByteArrayOutputStream capturedOut;
    private ByteArrayOutputStream capturedErr;
    private Level originalRootLevel;

    @BeforeAll
    static void warmUp() throws Exception {
        // 클래스 로딩, 로그백 초기화, Mockito 에이전트 부착 등 최초 1회성 출력을
        // 스트림을 바꿔치기 전에 미리 흘려보낸다.
        OAuthLoginProbe.runLogin();
    }

    @BeforeEach
    void replaceStreams() {
        Logger root = (Logger) LoggerFactory.getLogger(org.slf4j.Logger.ROOT_LOGGER_NAME);
        originalRootLevel = root.getLevel();
        root.setLevel(Level.OFF); // 콘솔 어펜더가 캡처 버퍼로 새어 들어오지 못하게

        originalOut = System.out;
        originalErr = System.err;
        capturedOut = new ByteArrayOutputStream();
        capturedErr = new ByteArrayOutputStream();
        System.setOut(new PrintStream(capturedOut, true, StandardCharsets.UTF_8));
        System.setErr(new PrintStream(capturedErr, true, StandardCharsets.UTF_8));
    }

    @AfterEach
    void restoreStreams() {
        System.setOut(originalOut);
        System.setErr(originalErr);
        ((Logger) LoggerFactory.getLogger(org.slf4j.Logger.ROOT_LOGGER_NAME)).setLevel(originalRootLevel);
    }

    @Test
    @DisplayName("토큰을 발급해도 표준출력과 표준에러에 아무것도 찍히지 않는다.")
    void createAccessToken_표준출력에_아무것도찍지않는다() {
        JWTProvider provider = OAuthLoginProbe.jwtProvider();

        provider.createAccessToken(OAuthLoginProbe.ASSIGNED_USER_ID, "ROLE_USER");

        assertThat(out()).isEmpty();
        assertThat(err()).isEmpty();
    }

    @Test
    @DisplayName("소셜 로그인 성공 처리 전 구간이 표준출력과 표준에러에 아무것도 찍지 않는다.")
    void 로그인전구간_표준출력에_아무것도찍지않는다() throws Exception {
        // loadUser → CustomOAuth2User.getName() → createAccessToken → 리다이렉트까지
        OAuthLoginProbe.runLogin();

        assertThat(out()).isEmpty();
        assertThat(err()).isEmpty();
    }

    @Test
    @DisplayName("CustomOAuth2User.getName() 은 사용자 식별자를 표준출력으로 흘리지 않는다.")
    void getName_표준출력에_식별자를흘리지않는다() {
        String name = OAuthLoginProbe.loadUser().getName();

        assertThat(name).isEqualTo("google_" + OAuthLoginProbe.PROVIDER_ID);
        assertThat(out()).isEmpty();
        assertThat(err()).isEmpty();
    }

    private String out() {
        return capturedOut.toString(StandardCharsets.UTF_8);
    }

    private String err() {
        return capturedErr.toString(StandardCharsets.UTF_8);
    }
}
