package com.heattrip.heat_trip_backend.user.controller;

import com.heattrip.heat_trip_backend.OAuth.user.CustomOAuth2User;
import com.heattrip.heat_trip_backend.OAuth.user.KakaoOAuth2User;
import com.heattrip.heat_trip_backend.OAuth.user.OAuth2UserInfo;
import com.heattrip.heat_trip_backend.support.AbstractMySqlIntegrationTest;
import com.heattrip.heat_trip_backend.user.entity.RefreshToken;
import com.heattrip.heat_trip_backend.user.entity.User;
import com.heattrip.heat_trip_backend.user.repository.RefreshTokenRepository;
import com.heattrip.heat_trip_backend.user.repository.UserRepository;

import jakarta.servlet.Filter;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.security.oauth2.client.authentication.OAuth2AuthenticationToken;
import org.springframework.security.oauth2.client.web.OAuth2LoginAuthenticationFilter;
import org.springframework.security.web.FilterChainProxy;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.authentication.AuthenticationSuccessHandler;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;

import java.nio.charset.StandardCharsets;
import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;

/**
 * refresh 토큰의 발급·회전·재사용 감지·폐기를 <b>실제 MySQL 위에서 끝까지</b> 돌린다 — 이슈 #9.
 *
 * <p>왜 통합인가: 이 이슈의 핵심 보증 두 개가 목으로는 정의상 잡히지 않는다.
 * <ul>
 *   <li><b>재사용 감지의 지속성</b> — "전량 폐기를 커밋한 뒤 401 을 던진다"는 동작은,
 *       회전을 하나의 트랜잭션으로 감싸는 순간 던지는 그 예외가 폐기를 함께 롤백시켜
 *       조용히 거짓이 된다. 단위 테스트의 {@code verify} 는 호출됐다는 사실만 알 뿐
 *       그것이 <b>남았는지</b>는 모른다. 그래서 이 클래스는 {@code @Transactional} 을
 *       <b>일부러 붙이지 않는다</b> — 붙이면 모든 요청이 한 트랜잭션을 공유해 같은 결함을 가린다.</li>
 *   <li><b>401 의 출처</b> — {@code /auth/token/refresh} 는 permitAll 이라 이 401 을 Spring
 *       Security 가 만들지 않는다. 서비스 예외 → 예외 핸들러 매핑이 끊기면 같은 요청이
 *       500 으로 샌다.</li>
 * </ul>
 *
 * <p>애너테이션이 {@code @SpringBootTest} + {@code @AutoConfigureMockMvc} 두 줄뿐인 것은 의도다.
 * {@code AuthMeIntegrationTest}·{@code AuthEndpointAuthorizationTest} 와 글자 그대로 같아야
 * 스프링 컨텍스트 캐시를 공유한다.
 */
@SpringBootTest
@AutoConfigureMockMvc
class AuthTokenRefreshIntegrationTest extends AbstractMySqlIntegrationTest {

    private static final String SOCIAL_ID_PREFIX = "rt-int-";

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private UserRepository userRepository;

    @Autowired
    private RefreshTokenRepository refreshTokenRepository;

    @Autowired
    private FilterChainProxy springSecurityFilterChain;

    /** 트랜잭션 롤백에 기대지 않으므로 만든 행을 직접 지운다. */
    private final List<Long> createdUserIds = new ArrayList<>();

    @AfterEach
    void cleanUp() {
        for (Long userId : createdUserIds) {
            refreshTokenRepository.deleteByUserId(userId);
            userRepository.findById(userId).ifPresent(userRepository::delete);
        }
        createdUserIds.clear();
    }

    // ─────────────────── 회전과 재사용 감지 (완료 조건 1·2·3·4) ───────────────────

    @Test
    @DisplayName("소셜 로그인 딥링크로 받은 refresh 토큰으로 갱신하면 새 액세스 토큰과 새 refresh 토큰을 받는다")
    void 유효한_refresh토큰으로_갱신하면_새_토큰쌍을_받는다() throws Exception {
        Session session = loginBySocial();

        MvcResult refreshed = refresh(session.refreshToken());

        assertThat(refreshed.getResponse().getStatus()).isEqualTo(200);
        String body = body(refreshed);
        assertThat(body).contains("\"accessToken\"", "\"refreshToken\"", "\"expiresIn\"");
        assertThat(jsonValue(body, "refreshToken"))
                .as("회전이다 — 같은 토큰을 다시 주는 것이 아니다 (완료 조건 2)")
                .isNotEqualTo(session.refreshToken());
        assertThat(jsonValue(body, "accessToken")).startsWith("eyJ");
    }

    @Test
    @DisplayName("방금 회전에 쓴 옛 refresh 토큰으로 다시 갱신하면 401 이고, 그 직후 정상적으로 받았던 새 refresh 토큰도 401 이 된다")
    void 옛_refresh토큰_재사용은_그_사용자의_모든_세션을_끊는다() throws Exception {
        Session session = loginBySocial();
        String rotated = jsonValue(body(refresh(session.refreshToken())), "refreshToken");

        // 완료 조건 3 — 한 번 쓴 RT 는 죽는다.
        assertThat(refresh(session.refreshToken()).getResponse().getStatus()).isEqualTo(401);

        // 완료 조건 4 — 그 재사용이 유출의 신호이므로 살아 있던 새 RT 까지 함께 끊긴다.
        // 이 단언이 '전량 폐기가 커밋되었는가' 를 확인하는 지점이다. 회전을 하나의 트랜잭션으로
        // 감싸면 폐기가 예외와 함께 롤백되어 여기가 200 이 된다.
        assertThat(refresh(rotated).getResponse().getStatus())
                .as("재사용 감지가 실제로 남지 않으면 탈취자와 정당한 사용자가 나란히 세션을 유지한다")
                .isEqualTo(401);
    }

    @Test
    @DisplayName("유효하지 않은 refresh 토큰의 응답은 500 이 아니라 본문도 Content-Type 도 없는 401 이다")
    void 무효한_refresh토큰은_본문없는_401이다() throws Exception {
        MvcResult result = refresh("this-token-was-never-issued");

        assertThat(result.getResponse().getStatus())
                .as("permitAll 경로라 이 401 은 Security 가 아니라 예외 핸들러 매핑이 만든다 — "
                        + "매핑이 끊기면 조용히 500 이 된다")
                .isEqualTo(401);
        assertThat(body(result))
                .as("인증 실패의 원인을 본문으로 알려 주면 그 자체가 탐색 수단이 된다 (#6)")
                .isEmpty();
        assertThat(result.getResponse().getContentType()).isNull();
    }

    @Test
    @DisplayName("본문에 refreshToken 이 없거나 비어 있어도 400 이 아니라 401 이다")
    void 빈_refreshToken은_401이다() throws Exception {
        MvcResult empty = mockMvc.perform(post("/auth/token/refresh")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{}")).andReturn();

        assertThat(empty.getResponse().getStatus()).isEqualTo(401);
        assertThat(body(empty)).isEmpty();
    }

    // ─────────────────── 형식이 깨진 요청 (계약의 400·415·405) ───────────────────

    @Test
    @DisplayName("형식이 깨진 refresh 요청은 500 이 아니라 400·415·405 다")
    void 형식이_깨진_요청은_500이_아니다() throws Exception {
        // 이 경로는 비인증 공개 표면이라 누구나 이 입력들을 보낼 수 있다. 핸들러가 없으면
        // 전부 catch-all 에 잡혀 500 이 되고, 계약에 없는 코드가 나가는 데다 앱은
        // "다시 로그인하라" 와 "서버가 고장났다" 를 구분하지 못해 재시도 루프를 돈다.
        assertThat(mockMvc.perform(post("/auth/token/refresh")
                        .contentType(MediaType.APPLICATION_JSON).content("{"))
                        .andReturn().getResponse().getStatus())
                .as("읽을 수 없는 JSON — HttpMessageNotReadableException 핸들러가 없으면 500 이다")
                .isEqualTo(400);

        assertThat(mockMvc.perform(post("/auth/token/refresh")
                        .contentType(MediaType.APPLICATION_JSON).content("[]"))
                        .andReturn().getResponse().getStatus())
                .as("배열 본문도 같은 예외다")
                .isEqualTo(400);

        assertThat(mockMvc.perform(post("/auth/token/refresh")
                        .contentType(MediaType.APPLICATION_JSON).content("{\"refreshToken\":{}}"))
                        .andReturn().getResponse().getStatus())
                .as("문자열 자리에 객체가 오는 것도 본문을 읽지 못하는 경우다")
                .isEqualTo(400);

        assertThat(mockMvc.perform(post("/auth/token/refresh")
                        .contentType(MediaType.TEXT_PLAIN).content("{\"refreshToken\":\"x\"}"))
                        .andReturn().getResponse().getStatus())
                .as("Content-Type 불일치는 415 다 — HttpMediaTypeNotSupportedException 핸들러가 없으면 500")
                .isEqualTo(415);

        assertThat(mockMvc.perform(
                        org.springframework.test.web.servlet.request.MockMvcRequestBuilders
                                .get("/auth/token/refresh"))
                        .andReturn().getResponse().getStatus())
                .as("메서드 불일치는 405 다 — HttpRequestMethodNotSupportedException 핸들러가 없으면 500")
                .isEqualTo(405);
    }

    @Test
    @DisplayName("400 응답 본문에 요청으로 보낸 refresh 토큰 조각이 실리지 않는다")
    void 형식오류_응답은_요청본문을_되비추지_않는다() throws Exception {
        // Jackson 의 파싱 실패 메시지에는 요청 본문 조각이 그대로 섞인다. 그 본문이
        // refresh 토큰 원문인 경로에서 그건 곧 유출이다 (#6).
        String secret = "leak-canary-refresh-token-value";

        MvcResult broken = mockMvc.perform(post("/auth/token/refresh")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"refreshToken\":\"" + secret + "\"")).andReturn();

        assertThat(broken.getResponse().getStatus()).isEqualTo(400);
        assertThat(body(broken))
                .as("예외 메시지를 그대로 실으면 요청 본문이 응답으로 되돌아온다")
                .doesNotContain(secret)
                .doesNotContain("JsonParseException", "HttpMessageNotReadableException");
    }

    // ─────────────────── 만료 (완료 조건 5) ───────────────────

    @Test
    @DisplayName("만료된 refresh 토큰은 401 이지만 그 사용자의 다른 세션은 살아남는다")
    void 만료된_refresh토큰은_다른세션을_끊지않는다() throws Exception {
        // 만료는 유출의 증거가 아니라 시간의 경과다. 이걸 유출로 오해하면 아무 일도 없었는데
        // 시계만 지나도 그 사용자의 모든 기기가 끊긴다.
        Session session = loginBySocial();
        String expiredRaw = "expired-plaintext-" + session.userId();
        refreshTokenRepository.save(RefreshToken.builder()
                .userId(session.userId())
                .tokenHash(sha256Hex(expiredRaw))
                .expiresAt(LocalDateTime.now().minusDays(1))
                .createdAt(LocalDateTime.now().minusDays(15))
                .build());

        assertThat(refresh(expiredRaw).getResponse().getStatus()).isEqualTo(401);

        assertThat(refresh(session.refreshToken()).getResponse().getStatus())
                .as("만료 하나가 살아 있는 세션을 끊으면 안 된다 (완료 조건 5)")
                .isEqualTo(200);
    }

    // ─────────────────── 로그아웃 (완료 조건 6) ───────────────────

    @Test
    @DisplayName("로그아웃한 뒤에는 그 refresh 토큰으로 갱신할 수 없다")
    void 로그아웃_후_refresh는_401이다() throws Exception {
        Session session = loginBySocial();

        int logoutStatus = mockMvc.perform(post("/auth/logout")
                .header("Authorization", "Bearer " + session.accessToken()))
                .andReturn().getResponse().getStatus();

        assertThat(logoutStatus).isEqualTo(204);
        assertThat(refresh(session.refreshToken()).getResponse().getStatus())
                .as("UserService.logout 이 다시 빈 껍데기가 되면 여기가 200 이 된다 (완료 조건 6)")
                .isEqualTo(401);
    }

    @Test
    @DisplayName("로그아웃은 멱등이다 — 폐기할 것이 남아 있지 않아도 204 다")
    void 로그아웃은_멱등이다() throws Exception {
        Session session = loginBySocial();

        mockMvc.perform(post("/auth/logout").header("Authorization", "Bearer " + session.accessToken()));
        int second = mockMvc.perform(post("/auth/logout")
                .header("Authorization", "Bearer " + session.accessToken()))
                .andReturn().getResponse().getStatus();

        assertThat(second).isEqualTo(204);
    }

    // ─────────────────── 탈퇴·저장 형태 (완료 조건 7·8) ───────────────────

    @Test
    @DisplayName("회원 탈퇴 후에는 그 사용자의 refresh_token 행이 하나도 남지 않는다")
    void 탈퇴하면_refresh토큰_행이_남지않는다() throws Exception {
        Session session = loginBySocial();
        assertThat(rowsOf(session.userId())).isNotEmpty();

        int status = mockMvc.perform(delete("/auth/me")
                .header("Authorization", "Bearer " + session.accessToken()))
                .andReturn().getResponse().getStatus();

        assertThat(status).isEqualTo(204);
        assertThat(rowsOf(session.userId()))
                .as("users 로의 FK 가 없으므로 DB 가 대신 정리해 주지 않는다 (완료 조건 7)")
                .isEmpty();
    }

    @Test
    @DisplayName("원장에 저장된 token_hash 는 클라이언트가 받은 refresh 토큰 문자열과 다르고, 그 문자열의 SHA-256 과 같다")
    void 원장에는_평문이_아니라_해시가_저장된다() throws Exception {
        Session session = loginBySocial();

        List<RefreshToken> rows = rowsOf(session.userId());

        assertThat(rows).hasSize(1);
        assertThat(rows.get(0).getTokenHash())
                .as("평문 저장이면 DB 유출이 곧 전 계정 탈취다 (완료 조건 8)")
                .isNotEqualTo(session.refreshToken())
                .isEqualTo(sha256Hex(session.refreshToken()));
    }

    // ─────────────────────────── 지그 ───────────────────────────

    private record Session(long userId, String accessToken, String refreshToken) {
    }

    /**
     * 실제 소셜 로그인 성공 경로를 태워 딥링크에서 두 토큰을 꺼낸다.
     *
     * <p>{@code RefreshTokenService} 를 직접 부르지 않는 이유: 그러면 "발급은 되는데 딥링크에
     * 실리지 않는" 상태를 잡지 못한다. 완료 조건 1 이 요구하는 것은 <b>클라이언트에 도달하는
     * 경로</b>다. 살아 있는 필터체인에서 등록된 성공 핸들러를 꺼내 쓴다
     * ({@code AuthMeIntegrationTest} 와 같은 방법).
     */
    private Session loginBySocial() throws Exception {
        String socialId = SOCIAL_ID_PREFIX + System.nanoTime();
        User seeded = userRepository.save(User.builder()
                .provider("kakao")
                .socialId(socialId)
                .username("kakao_" + socialId)
                .role(User.ROLE_USER)
                .email(null)
                .name("보리")
                .nickname("보리")
                .build());
        createdUserIds.add(seeded.getId());

        Map<String, Object> attributes = Map.of("id", socialId);
        OAuth2UserInfo userInfo = new KakaoOAuth2User(attributes);
        CustomOAuth2User principal =
                new CustomOAuth2User(userInfo, attributes, seeded.getId(), seeded.getRole(), false);

        MockHttpServletResponse response = new MockHttpServletResponse();
        registeredSuccessHandler().onAuthenticationSuccess(
                new MockHttpServletRequest(), response,
                new OAuth2AuthenticationToken(principal, principal.getAuthorities(), "kakao"));

        String redirect = response.getRedirectedUrl();
        assertThat(redirect)
                .as("완료 조건 1 — 로그인하면 딥링크에 refreshToken 이 포함된다")
                .startsWith("heattrip://login-callback?token=")
                .contains("&refresh=");
        return new Session(seeded.getId(), queryParam(redirect, "token"), queryParam(redirect, "refresh"));
    }

    private MvcResult refresh(String refreshToken) throws Exception {
        return mockMvc.perform(post("/auth/token/refresh")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"refreshToken\":\"" + refreshToken + "\"}"))
                .andReturn();
    }

    private List<RefreshToken> rowsOf(long userId) {
        return refreshTokenRepository.findAll().stream()
                .filter(row -> row.getUserId() == userId)
                .toList();
    }

    private AuthenticationSuccessHandler registeredSuccessHandler() {
        for (SecurityFilterChain chain : springSecurityFilterChain.getFilterChains()) {
            for (Filter filter : chain.getFilters()) {
                if (filter instanceof OAuth2LoginAuthenticationFilter loginFilter) {
                    return (AuthenticationSuccessHandler)
                            ReflectionTestUtils.getField(loginFilter, "successHandler");
                }
            }
        }
        throw new IllegalStateException("OAuth2LoginAuthenticationFilter 가 필터체인에 없다.");
    }

    /** 딥링크 쿼리스트링에서 파라미터 하나를 꺼낸다. substring 방식은 &refresh= 가 붙으면 깨진다. */
    private static String queryParam(String url, String name) {
        String query = url.substring(url.indexOf('?') + 1);
        for (String pair : query.split("&")) {
            int eq = pair.indexOf('=');
            if (eq > 0 && pair.substring(0, eq).equals(name)) {
                return pair.substring(eq + 1);
            }
        }
        throw new AssertionError("딥링크에 " + name + " 파라미터가 없다: " + url);
    }

    /** 중첩 없는 평평한 JSON 에서 문자열 값을 꺼낸다. */
    private static String jsonValue(String json, String field) {
        String key = "\"" + field + "\":\"";
        int start = json.indexOf(key);
        assertThat(start).as("%s 필드가 응답에 없다: %s", field, json).isNotNegative();
        start += key.length();
        return json.substring(start, json.indexOf('"', start));
    }

    /** 프로덕션 해싱 함수를 부르지 않고 직접 계산한다 — 순환 검증을 피한다. */
    private static String sha256Hex(String raw) throws Exception {
        return java.util.HexFormat.of().formatHex(java.security.MessageDigest.getInstance("SHA-256")
                .digest(raw.getBytes(StandardCharsets.UTF_8)));
    }

    private static String body(MvcResult result) throws Exception {
        return result.getResponse().getContentAsString(StandardCharsets.UTF_8);
    }
}
