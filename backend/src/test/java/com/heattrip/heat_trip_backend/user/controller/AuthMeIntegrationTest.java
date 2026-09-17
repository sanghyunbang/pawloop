package com.heattrip.heat_trip_backend.user.controller;

import com.heattrip.heat_trip_backend.OAuth.state.OAuthAppStateFilter;
import com.heattrip.heat_trip_backend.support.AbstractMySqlIntegrationTest;
import com.heattrip.heat_trip_backend.OAuth.user.CustomOAuth2User;
import com.heattrip.heat_trip_backend.OAuth.user.GoogleOAuth2User;
import com.heattrip.heat_trip_backend.OAuth.user.KakaoOAuth2User;
import com.heattrip.heat_trip_backend.OAuth.user.OAuth2UserInfo;
import com.heattrip.heat_trip_backend.user.dto.LoginRequest;
import com.heattrip.heat_trip_backend.user.entity.User;
import com.heattrip.heat_trip_backend.user.repository.UserRepository;
import com.heattrip.heat_trip_backend.user.service.UserService;

import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.SignatureAlgorithm;
import io.jsonwebtoken.security.Keys;

import jakarta.servlet.Filter;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.oauth2.client.authentication.OAuth2AuthenticationToken;
import org.springframework.security.oauth2.client.web.OAuth2LoginAuthenticationFilter;
import org.springframework.security.web.FilterChainProxy;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.authentication.AuthenticationSuccessHandler;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.MvcResult;
import org.springframework.transaction.annotation.Transactional;

import java.nio.charset.StandardCharsets;
import java.util.Date;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;

/**
 * 인증 주체 해석의 끝-끝 잠금 — 이슈 #5.
 *
 * <p>왜 통합 테스트인가: 이 이슈의 버그는 클래스 하나가 아니라 <b>세 지점의 합의</b>가 깨져서 생겼다.
 * 토큰을 발급하는 곳({@code OAuth2SuccessHandler}·{@code UserService.login})과
 * 그 subject 를 읽는 곳(필터·리졸버)이 서로 다른 값을 가정했다. 목을 쓰는 슬라이스 테스트는
 * 그 불일치를 정의상 잡을 수 없다 — 스텁이 양쪽의 가정을 각각 만족시켜 주기 때문이다.
 *
 * <p>애너테이션이 {@code @SpringBootTest} + {@code @AutoConfigureMockMvc} 두 줄뿐인 것은 의도다.
 * {@code AuthEndpointAuthorizationTest} 와 글자 그대로 같아야 스프링 컨텍스트 캐시를 공유한다.
 * {@code @MockBean}·{@code @TestPropertySource}·{@code @ActiveProfiles} 를 하나라도 붙이면
 * 캐시 키가 갈라져 컨텍스트가 한 번 더 뜬다(현재 스위트에서 가장 비싼 항목).
 */
@SpringBootTest
@AutoConfigureMockMvc
@Transactional
class AuthMeIntegrationTest extends AbstractMySqlIntegrationTest {

    /** src/test/resources/application-test.properties 의 jwt.secret 과 같은 값. */
    private static final String SECRET = "test-only-secret-key-32bytes-min!!";

    /** 카카오가 준 소셜 ID. 이 값이 subject 로 새어 나가면 안 된다. */
    private static final long KAKAO_SOCIAL_ID = 1234567890L;

    /** 구글이 준 소셜 ID. 위와 같은 이유로 subject 에 나타나면 안 된다. */
    private static final String GOOGLE_SOCIAL_ID = "109876543210987654321";

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private UserRepository userRepository;

    @Autowired
    private UserService userService;

    @Autowired
    private PasswordEncoder passwordEncoder;

    @Autowired
    private FilterChainProxy springSecurityFilterChain;

    // ─────────────────────────── a·b·c: 두 가입 경로가 같은 코드로 200 ───────────────────────────

    @Test
    @DisplayName("이메일이 없는 카카오 계정도 소셜 로그인이 발급한 토큰으로 GET /auth/me 가 200 이고 자기 id 를 돌려받는다")
    void 소셜계정_토큰으로_내정보조회가_200이다() throws Exception {
        User kakao = seedKakaoUserWithoutEmail();
        String token = tokenIssuedByRealSocialLogin(kakao);

        MvcResult result = mockMvc.perform(get("/auth/me").header("Authorization", "Bearer " + token))
                .andReturn();

        assertThat(result.getResponse().getStatus())
                .as("이메일 없는 카카오 계정으로 프로필 조회가 된다 — #7 완료 조건 2 는 #5 가 들어와야 참이 된다")
                .isEqualTo(200);
        assertThat(body(result)).contains("\"id\":" + kakao.getId());
    }

    @Test
    @DisplayName("구글 계정도 소셜 로그인이 발급한 토큰으로 GET /auth/me 가 200 이고 자기 id 를 돌려받는다")
    void 구글계정_토큰으로_내정보조회가_200이다() throws Exception {
        // 완료 조건 2. 공급자에 따라 갈리는 코드가 남아 있지 않은지 확인하는 것이 목적이다 —
        // 예전 subject 는 "kakao_..."·"google_..." 로 공급자 이름을 품고 있었다.
        User google = userRepository.save(User.builder()
                .provider("google")
                .socialId(GOOGLE_SOCIAL_ID)
                .username("google_" + GOOGLE_SOCIAL_ID)
                .role(User.ROLE_USER)
                .email("bori-google@example.com")
                .name("보리")
                .nickname("보리")
                .build());

        Map<String, Object> attributes = Map.of("sub", GOOGLE_SOCIAL_ID, "name", "보리");
        String token = tokenIssuedByRealSocialLogin(
                new CustomOAuth2User(new GoogleOAuth2User(attributes), attributes,
                        google.getId(), google.getRole(), false),
                "google");

        MvcResult result = mockMvc.perform(get("/auth/me").header("Authorization", "Bearer " + token))
                .andReturn();

        assertThat(result.getResponse().getStatus()).isEqualTo(200);
        assertThat(body(result)).contains("\"id\":" + google.getId());
    }

    @Test
    @DisplayName("이메일/비밀번호로 가입한 계정의 로그인 토큰으로도 GET /auth/me 가 200 이다")
    void 로컬계정_토큰으로_내정보조회가_200이다() throws Exception {
        User local = seedLocalUser("bori@example.com", "test1234");
        String token = tokenIssuedByPasswordLogin("bori@example.com", "test1234");

        MvcResult result = mockMvc.perform(get("/auth/me").header("Authorization", "Bearer " + token))
                .andReturn();

        assertThat(result.getResponse().getStatus())
                .as("#5 는 subject 규약의 '통일'이지 '소셜로의 교체'가 아니다 — 로컬 경로가 함께 살아 있어야 한다")
                .isEqualTo(200);
        assertThat(body(result)).contains("\"id\":" + local.getId());
    }

    @Test
    @DisplayName("GET /auth/me 의 createdAt·updatedAt 이 오프셋을 달고 나간다 (#248)")
    void 내정보의_시각이_오프셋을_갖는다() throws Exception {
        // 손으로 만든 매퍼로는 못 잰다 — 부트가 WRITE_DATES_AS_TIMESTAMPS 를 끄기 때문이다.
        // 그래서 실제 응답 본문을 본다 (#247 에서 그 차이를 겪었다).
        seedLocalUser("bori-offset@example.com", "test1234");
        String token = tokenIssuedByPasswordLogin("bori-offset@example.com", "test1234");

        MvcResult result = mockMvc.perform(
                        get("/auth/me").header("Authorization", "Bearer " + token))
                .andReturn();

        assertThat(result.getResponse().getStatus()).isEqualTo(200);
        String json = body(result);
        for (String field : java.util.List.of("createdAt", "updatedAt")) {
            // 오프셋이 없으면 앱의 DateTime.parse 가 이것을 기기 지역 시각으로 읽는다.
            // 2026-09-03 이전에는 "2026-09-03T08:33:44.533941" 이 그대로 나갔다.
            assertThat(json)
                    .as("%s 에 오프셋이 없다 — 계약의 format: date-time 은 RFC3339 오프셋을 요구한다", field)
                    .containsPattern("\"" + field + "\":\"\\d{4}-\\d{2}-\\d{2}T[\\d:.]+(Z|[+-]\\d{2}:\\d{2})\"");
        }

        // **오프셋이 붙었는지만 재면 9시간 오차를 못 잡는다.** 형식은 맞고 값이 틀린 상태가
        // 실제로 났다 — 다른 존의 벽시계를 UTC 로 세우면 그렇게 된다 (#248).
        for (String field : java.util.List.of("createdAt", "updatedAt")) {
            java.util.regex.Matcher at = java.util.regex.Pattern
                    .compile("\"" + field + "\":\"([^\"]+)\"").matcher(json);
            assertThat(at.find()).as("%s 를 응답에서 못 찾았다", field).isTrue();

            java.time.Instant moment = java.time.Instant.parse(at.group(1));
            assertThat(java.time.Duration.between(moment, java.time.Instant.now()).abs())
                    .as("%s 가 지금에서 너무 멀다 (%s) — 존이 갈리면 딱 9시간이 난다", field, moment)
                    .isLessThan(java.time.Duration.ofMinutes(5));
        }
    }


    @Test
    @DisplayName("소셜 계정 토큰으로 /auth/me 밖의 소비처인 GET /api/dogs 도 200 이다")
    void 소셜계정_토큰으로_반려동물목록이_200이다() throws Exception {
        // 예전에는 레거시 GET /bookmarks 였다 — #94 로 지워서 같은 뜻의 v2 경로로 바꿨다.
        User kakao = seedKakaoUserWithoutEmail();
        String token = tokenIssuedByRealSocialLogin(kakao);

        int status = mockMvc.perform(get("/api/dogs").header("Authorization", "Bearer " + token))
                .andReturn().getResponse().getStatus();

        assertThat(status)
                .as("주체 해석이 한 곳으로 모였으면 모든 소비처가 같은 답을 낸다 — 완료 조건 4")
                .isEqualTo(200);
    }

    // ─────────────────────────── d·e·f: 거절은 전부 401, 500 도 400 도 아니다 ───────────────────────────

    @Test
    @DisplayName("Authorization 헤더가 없는 GET /auth/me 는 본문 없는 401 이다")
    void 헤더없는_내정보조회는_본문없는_401이다() throws Exception {
        MvcResult result = mockMvc.perform(get("/auth/me")).andReturn();

        assertThat(result.getResponse().getStatus()).isEqualTo(401);
        // 계약(docs/04-api/openapi.yaml components/responses/Unauthorized)이 이 모양을 선언한다.
        // 예전에는 계약이 JSON Error 본문을 선언했는데 서버는 본문을 준 적이 없다 — 앱이 계약대로
        // error.code 로 분기하면 파싱에서 깨진다. 계약을 실제 동작에 맞췄으니 동작도 잠근다. (#5)
        assertThat(body(result))
                .as("인증 실패의 원인을 본문으로 알려 주면 그 자체가 탐색 수단이 된다 (#6)")
                .isEmpty();
    }

    @Test
    @DisplayName("탈퇴한 계정의 살아 있는 토큰도 헤더 없음과 글자 그대로 같은 모양의 401 이다")
    void 인증실패는_원인과_무관하게_같은_모양의_401이다() throws Exception {
        MvcResult noHeader = mockMvc.perform(get("/auth/me")).andReturn();
        MvcResult orphan = mockMvc.perform(get("/auth/me")
                .header("Authorization", "Bearer " + signedToken("999999999", "ROLE_USER"))).andReturn();

        // "토큰 없음"(HttpStatusEntryPoint)과 "그 id 의 행이 없음"(GlobalExceptionHandler)은
        // 서로 다른 코드가 만든다. 둘이 갈라지면 앱은 401 을 두 갈래로 처리해야 하고,
        // 공격자는 두 상태를 구별할 수 있게 된다.
        assertThat(orphan.getResponse().getStatus()).isEqualTo(noHeader.getResponse().getStatus());
        assertThat(body(orphan)).isEqualTo(body(noHeader)).isEmpty();
        assertThat(orphan.getResponse().getContentType()).isEqualTo(noHeader.getResponse().getContentType());
    }

    @Test
    @DisplayName("서명과 만료가 멀쩡해도 subject 가 숫자가 아닌 옛 형식 토큰(sub=kakao_1)은 401 이고 실패한 subject 원문이 응답에 실리지 않는다")
    void 옛형식_subject토큰은_401이고_원문이새지않는다() throws Exception {
        String legacyToken = signedToken("kakao_1", "ROLE_USER");

        MvcResult result = mockMvc.perform(get("/auth/me").header("Authorization", "Bearer " + legacyToken))
                .andReturn();
        int status = result.getResponse().getStatus();

        assertThat(status)
                .as("subject 를 컨트롤러에서 파싱하면 NumberFormatException → 400 이 된다. 거절 지점은 필터여야 한다")
                .isEqualTo(401);
        assertThat(status)
                .as("필터 안에서 예외가 새면 @RestControllerAdvice 가 못 잡아 컨테이너 500 이 된다")
                .isNotEqualTo(500);
        assertThat(body(result))
                .as("파싱에 실패한 subject 는 이메일이거나 소셜 ID 다 — 응답 본문에 실으면 #6 위생 위반이다")
                .doesNotContain("kakao_1")
                .doesNotContain("@");
    }

    @Test
    @DisplayName("서명도 subject 형식도 멀쩡하지만 그 id 의 사용자가 없는 토큰(탈퇴 계정)은 401 이다")
    void 없는사용자의_유효토큰은_401이다() throws Exception {
        String orphanToken = signedToken("999999999", "ROLE_USER");

        MvcResult result = mockMvc.perform(get("/auth/me").header("Authorization", "Bearer " + orphanToken))
                .andReturn();
        int status = result.getResponse().getStatus();

        assertThat(status)
                .as("리졸버의 401 신호가 GlobalExceptionHandler 의 catch-all 에 삼켜지면 500 이 된다")
                .isEqualTo(401);
        assertThat(status).isNotEqualTo(500);
    }

    // ─────────────────────────── 지그 ───────────────────────────

    /** 카카오가 이메일 동의를 주지 않은 계정. 이 행은 email 로는 절대 찾을 수 없다. */
    private User seedKakaoUserWithoutEmail() {
        return userRepository.save(User.builder()
                .provider("kakao")
                .socialId(String.valueOf(KAKAO_SOCIAL_ID))
                .username("kakao_" + KAKAO_SOCIAL_ID)
                .role(User.ROLE_USER)
                .email(null)
                .name("보리")
                .nickname("보리")
                .build());
    }

    private User seedLocalUser(String email, String rawPassword) {
        return userRepository.save(User.builder()
                .provider(User.PROVIDER_LOCAL)
                .role(User.ROLE_USER)
                .email(email)
                .password(passwordEncoder.encode(rawPassword))
                .name("보리아빠")
                .nickname("보리아빠")
                .build());
    }

    /**
     * 앱이 인증 시작 때 붙였을 난수. 실제 로그인에서는 {@code OAuthAppStateFilter} 가
     * 진입 요청에서 이 값을 세션에 담고 성공 핸들러가 꺼내 간다. 이 지그는 진입 요청을
     * 흉내내지 않으므로 세션에 직접 넣는다 — 넣지 않으면 딥링크의 {@code state} 가 빈 값이
     * 되고, 서버는 그 코드를 교환하지 않는다(#14: 빈 state 로 발급된 코드는 401).
     */
    private static final String APP_STATE = "st-jig-ABC123";

    /**
     * 실제 발급 경로로 토큰을 얻는다.
     *
     * <p>{@code JWTProvider} 로 직접 만들면 "핸들러는 고쳤는데 필터체인에 붙어 있지 않은" 상태를
     * 잡지 못한다. 그래서 살아 있는 {@link FilterChainProxy} 에서 등록된 성공 핸들러를 꺼내 태운다.
     * ({@code OAuth2LoginFailureRedirectTest} 가 실패 경로에서 같은 방법을 쓴다.)
     */
    private String tokenIssuedByRealSocialLogin(User seeded) throws Exception {
        Map<String, Object> attributes = Map.of("id", KAKAO_SOCIAL_ID);
        OAuth2UserInfo userInfo = new KakaoOAuth2User(attributes);
        return tokenIssuedByRealSocialLogin(
                new CustomOAuth2User(userInfo, attributes, seeded.getId(), seeded.getRole(), false),
                "kakao");
    }

    private String tokenIssuedByRealSocialLogin(CustomOAuth2User principal, String registrationId)
            throws Exception {
        MockHttpServletRequest request = new MockHttpServletRequest();
        request.getSession(true)
                .setAttribute(OAuthAppStateFilter.SESSION_ATTRIBUTE, APP_STATE);
        MockHttpServletResponse response = new MockHttpServletResponse();
        registeredSuccessHandler().onAuthenticationSuccess(
                request, response,
                new OAuth2AuthenticationToken(principal, principal.getAuthorities(), registrationId));

        String redirect = response.getRedirectedUrl();
        // #14 이후 딥링크에 토큰은 없다 — 1회용 코드뿐이다. 토큰은 교환 엔드포인트의 응답
        // 본문으로만 나온다. 여기서 실제 HTTP 경로를 태우는 이유는 예전과 같다: 컨트롤러를
        // 직접 부르면 "서비스는 고쳤는데 경로가 붙어 있지 않은" 상태를 잡지 못한다.
        assertThat(redirect)
                .as("소셜 로그인 성공은 1회용 코드를 실은 딥링크로 끝나야 한다 (#14 완료 조건 1)")
                .startsWith("pawloop://login-callback?code=");
        assertThat(redirect)
                .as("딥링크에 토큰이 실리면 #14 가 되돌려진 것이다")
                .doesNotContain("token=", "refresh=");

        String body = mockMvc.perform(post("/auth/oauth/" + registrationId + "/callback")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"code\":\"" + queryParam(redirect, "code") + "\",\"state\":\"" + APP_STATE + "\"}"))
                .andReturn().getResponse().getContentAsString();

        return com.jayway.jsonpath.JsonPath.read(body, "$.accessToken");
    }

    /** 딥링크 쿼리스트링에서 파라미터 하나를 꺼낸다. 값에는 URL 예약문자가 없다(JWT·Base64URL). */
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

    private String tokenIssuedByPasswordLogin(String email, String rawPassword) throws Exception {
        LoginRequest request = new LoginRequest();
        request.setEmail(email);
        request.setPassword(rawPassword);
        // 반환값이 문자열에서 AuthTokens 로 바뀌었다 — 응답에 refresh 토큰을 싣기 위해서다(#10).
        return userService.login(request).accessToken();
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

    /**
     * 임의의 subject 로 유효 서명·미만료 토큰을 만든다.
     *
     * <p>{@code JWTProvider.createAccessToken} 을 쓰지 않는 이유: 그 시그니처가 {@code Long} 으로
     * 좁아지면 "숫자가 아닌 subject" 를 표현할 방법 자체가 사라진다. 이 테스트는 <b>옛 형식 토큰이
     * 이미 사용자 손에 있는 상황</b>을 재현해야 하므로 발급기를 우회해 직접 서명한다.
     */
    private static String signedToken(String subject, String role) {
        long now = System.currentTimeMillis();
        return Jwts.builder()
                .setSubject(subject)
                .claim("role", role)
                .setIssuedAt(new Date(now))
                .setExpiration(new Date(now + 3_600_000L))
                .signWith(Keys.hmacShaKeyFor(SECRET.getBytes(StandardCharsets.UTF_8)),
                        SignatureAlgorithm.HS256)
                .compact();
    }

    private static String body(MvcResult result) throws Exception {
        return result.getResponse().getContentAsString(StandardCharsets.UTF_8);
    }
}
