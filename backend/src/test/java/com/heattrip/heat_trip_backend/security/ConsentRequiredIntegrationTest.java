package com.heattrip.heat_trip_backend.security;

import com.heattrip.heat_trip_backend.support.AbstractMySqlIntegrationTest;
import com.heattrip.heat_trip_backend.user.entity.User;
import com.heattrip.heat_trip_backend.user.repository.UserRepository;

import io.jsonwebtoken.Jwts;
import io.jsonwebtoken.SignatureAlgorithm;
import io.jsonwebtoken.security.Keys;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.transaction.annotation.Transactional;

import java.nio.charset.StandardCharsets;
import java.util.Date;

import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * 동의하지 않은 토큰으로는 서비스를 못 쓴다 — 이슈 #660.
 *
 * <h2>왜 앱이 아니라 여기서 재나</h2>
 *
 * <p>예전에 막는 것은 앱의 화면 전환 한 줄뿐이었다({@code auth_redirect.dart}). 그런데 <b>토큰은
 * 동의보다 먼저 발급된다</b> — 소셜 로그인이 끝나는 순간 계정이 생기고 토큰이 나간다. 그러니 앱을
 * 거치지 않고 그 토큰으로 부르면 그만이었다.
 *
 * <p>그래서 이 테스트는 <b>앱을 전혀 쓰지 않는다.</b> 토큰 하나만 들고 서버를 직접 부른다. 위젯
 * 테스트는 이 구멍을 정의상 못 잡는다 — 앱의 라우터를 지나기 때문이다.
 *
 * <p>애너테이션이 {@code @SpringBootTest} + {@code @AutoConfigureMockMvc} 두 줄뿐인 것은 의도다.
 * {@code AuthMeIntegrationTest} 와 글자 그대로 같아야 스프링 컨텍스트 캐시를 공유한다 —
 * {@code @MockBean}·{@code @TestPropertySource}·{@code @ActiveProfiles} 를 하나라도 붙이면 캐시
 * 키가 갈라져 컨텍스트가 한 번 더 뜬다(#21).
 */
@SpringBootTest
@AutoConfigureMockMvc
@Transactional
class ConsentRequiredIntegrationTest extends AbstractMySqlIntegrationTest {

    /** src/test/resources/application-test.properties 의 jwt.secret 과 같은 값. */
    private static final String SECRET = "test-only-secret-key-32bytes-min!!";

    /** 필수 셋을 한 번에 적는 본문. 계약의 {@code ConsentsInput} — 버전은 {@code v1.2} 모양이어야 한다. */
    private static final String AGREE_TO_REQUIRED = """
            {"consents":[
              {"kind":"TERMS","version":"v1.0","agreed":true},
              {"kind":"PRIVACY","version":"v1.0","agreed":true},
              {"kind":"LOCATION","version":"v1.0","agreed":true}
            ]}""";

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private UserRepository userRepository;

    // ─────────────────────────── 막는다 ───────────────────────────

    @Test
    @DisplayName("동의하지 않은 토큰으로 내 데이터를 부르면 403 이고 이유를 말한다")
    void withoutConsent_apiIsForbidden() throws Exception {
        String token = tokenFor(freshUser("no-consent@example.test", "9900001"));

        mockMvc.perform(get("/api/dogs").header("Authorization", "Bearer " + token))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.error.code").value("CONSENT_REQUIRED"));
    }

    /**
     * 읽기만 막고 쓰기를 놓치면 <b>동의 없이 글이 남는다.</b> 커뮤니티는 같은 주소에 게스트 GET 과
     * 로그인 POST 가 겹쳐 있어서, 필터가 경로만 보고 열면 이 POST 가 그대로 새어 나간다.
     */
    @Test
    @DisplayName("동의 전에는 글쓰기도 막힌다 — 게스트에게 열린 것은 그 주소의 GET 뿐이다")
    void withoutConsent_writingToAGuestReadablePathIsForbidden() throws Exception {
        String token = tokenFor(freshUser("no-consent-write@example.test", "9900002"));

        mockMvc.perform(post("/api/community/posts")
                        .header("Authorization", "Bearer " + token)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"title\":\"보리 산책\",\"content\":\"오늘 날씨 좋네요\"}"))
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.error.code").value("CONSENT_REQUIRED"));
    }

    // ─────────────────────────── 통과시킨다 ───────────────────────────

    @Test
    @DisplayName("동의를 마치면 그 즉시 통과한다")
    void afterConsent_apiPasses() throws Exception {
        String token = tokenFor(freshUser("will-consent@example.test", "9900003"));

        mockMvc.perform(put("/api/consents")
                        .header("Authorization", "Bearer " + token)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(AGREE_TO_REQUIRED))
                .andExpect(status().isOk());

        mockMvc.perform(get("/api/dogs").header("Authorization", "Bearer " + token))
                .andExpect(status().isOk());
    }

    /**
     * 동의를 적는 경로 자체는 열려 있어야 한다. 이걸 막으면 <b>영영 동의할 수 없다</b> — 동의하려면
     * 동의를 적어야 하는데 그 경로가 동의를 요구하는 고리가 된다.
     */
    @Test
    @DisplayName("동의 전에도 동의를 적는 경로는 열려 있다")
    void consentEndpointItself_isOpen() throws Exception {
        String token = tokenFor(freshUser("open-path@example.test", "9900004"));

        mockMvc.perform(get("/api/consents").header("Authorization", "Bearer " + token))
                .andExpect(status().isOk());
    }

    /**
     * 동의하지 않고 떠날 권리. 이걸 막으면 동의를 거부한 사람이 계정을 지우지도 못하고 갇힌다 —
     * 개인정보를 남겨 둔 채로.
     */
    @Test
    @DisplayName("동의 전에도 탈퇴할 수 있다 — 거부한 사람이 갇히면 안 된다")
    void withdrawal_isOpenBeforeConsent() throws Exception {
        String token = tokenFor(freshUser("leave-now@example.test", "9900005"));

        mockMvc.perform(delete("/auth/me").header("Authorization", "Bearer " + token))
                .andExpect(status().isNoContent());
    }

    /**
     * 토큰이 없는 요청은 이 필터의 일이 아니다. 게스트에게 열어 둔 읽기를 여기서 막아 버리면
     * 로그인하지 않은 사람이 아무것도 못 본다.
     */
    @Test
    @DisplayName("토큰 없는 게스트 읽기는 그대로 지나간다 — 동의는 아는 사람에게만 묻는다")
    void guest_isNotAskedForConsent() throws Exception {
        mockMvc.perform(get("/api/community/posts"))
                .andExpect(status().isOk());
    }

    /**
     * 게스트에게 열린 읽기는 <b>토큰을 들고 있어도</b> 열려 있어야 한다. 막아 봐야 얻는 것이 없다 —
     * 같은 요청을 토큰 없이 보내면 그만이다. 막으면 로그인한 사람이 게스트보다 못한 처지가 된다.
     */
    @Test
    @DisplayName("동의 안 한 사람도 게스트가 보는 것은 본다 — 로그인이 처지를 나쁘게 만들면 안 된다")
    void withoutConsent_guestReadableGetStillPasses() throws Exception {
        String token = tokenFor(freshUser("browsing@example.test", "9900006"));

        mockMvc.perform(get("/api/community/posts").header("Authorization", "Bearer " + token))
                .andExpect(status().isOk());
    }

    // ─────────────────────────── 지그 ───────────────────────────

    private User freshUser(String email, String socialId) {
        return userRepository.save(User.builder()
                .provider("kakao")
                .socialId(socialId)
                .username("kakao_" + socialId)
                .role(User.ROLE_USER)
                .email(email)
                .name("보리")
                .nickname("보리" + socialId)
                .build());
    }

    /**
     * 서명·만료가 멀쩡한 토큰을 직접 만든다.
     *
     * <p>소셜 로그인을 태우지 않는 것이 <b>요점</b>이다. 이 이슈의 구멍은 "토큰만 있으면 된다" 였고,
     * 그 상황을 재현하려면 발급 경로가 아니라 <b>토큰 그 자체</b>에서 출발해야 한다.
     */
    private static String tokenFor(User user) {
        long now = System.currentTimeMillis();
        return Jwts.builder()
                .setSubject(String.valueOf(user.getId()))
                .claim("role", user.getRole())
                .setIssuedAt(new Date(now))
                .setExpiration(new Date(now + 3_600_000L))
                .signWith(Keys.hmacShaKeyFor(SECRET.getBytes(StandardCharsets.UTF_8)),
                        SignatureAlgorithm.HS256)
                .compact();
    }
}
