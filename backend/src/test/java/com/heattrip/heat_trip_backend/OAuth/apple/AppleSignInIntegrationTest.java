package com.heattrip.heat_trip_backend.OAuth.apple;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;

import com.heattrip.heat_trip_backend.OAuth.AppleOidcUserService;
import com.heattrip.heat_trip_backend.OAuth.user.CustomOidcUser;
import com.heattrip.heat_trip_backend.support.AbstractMySqlIntegrationTest;
import com.heattrip.heat_trip_backend.user.entity.User;
import com.heattrip.heat_trip_backend.user.repository.UserRepository;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.security.oauth2.client.oidc.userinfo.OidcUserRequest;
import org.springframework.security.oauth2.client.registration.ClientRegistration;
import org.springframework.security.oauth2.client.registration.ClientRegistrationRepository;
import org.springframework.security.oauth2.core.OAuth2AccessToken;
import org.springframework.security.oauth2.core.oidc.OidcIdToken;
import org.springframework.security.oauth2.core.oidc.user.OidcUser;
import org.springframework.test.web.servlet.MockMvc;

import java.net.URLDecoder;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.List;
import java.util.Optional;

/**
 * Sign in with Apple 의 서버 쪽 — 이슈 #301. Apple 자체는 부르지 않는다(키가 없고, 있어도 CI 가
 * Apple 을 부르면 안 된다). 잰 것은 <b>우리 쪽 두 끝</b>이다: 진입점이 Apple 로 보내는 302 의
 * 모양과, 검증이 끝난 id_token 클레임으로 계정이 생기고 다시 알아보는지.
 */
@SpringBootTest
@AutoConfigureMockMvc
class AppleSignInIntegrationTest extends AbstractMySqlIntegrationTest {

    private static final String SUB = "001234.abcdef0123456789.1234";

    @Autowired
    private MockMvc mockMvc;
    @Autowired
    private ClientRegistrationRepository registrations;
    @Autowired
    private AppleOidcUserService service;
    @Autowired
    private UserRepository users;
    @Autowired
    private JdbcTemplate jdbc;

    @BeforeEach
    @AfterEach
    void cleanUp() {
        jdbc.update("delete from refresh_token where user_id in (select id from users where provider = 'apple')");
        jdbc.update("delete from users where provider = 'apple'");
    }

    // ─────────────────────────── 진입점 ───────────────────────────

    @Test
    @DisplayName("/oauth2/authorization/apple 이 Apple 로 302 하고 form_post · openid email · nonce 를 싣는다")
    void entryPointRedirectsToAppleWithFormPost() throws Exception {
        MockHttpServletResponse response = mockMvc.perform(get("/oauth2/authorization/apple"))
                .andReturn().getResponse();

        assertThat(response.getStatus()).isEqualTo(302);
        String location = URLDecoder.decode(response.getRedirectedUrl(), StandardCharsets.UTF_8);
        assertThat(location)
                .startsWith("https://appleid.apple.com/auth/authorize")
                .as("email 을 받으려면 Apple 이 form_post 를 요구한다 — 콜백이 POST 로 온다")
                .contains("response_mode=form_post")
                .contains("client_id=test-apple-services-id")
                .contains("redirect_uri=http://localhost:8080/login/oauth2/code/apple")
                .contains("response_type=code")
                .contains("nonce=");
        assertThat(location).as("openid 가 있어야 OIDC 경로(id_token 검증)를 탄다").contains("scope=openid email");
    }

    @Test
    @DisplayName("계약 래퍼 GET /auth/oauth/apple 도 302 다")
    void contractWrapperKnowsApple() throws Exception {
        MockHttpServletResponse response = mockMvc.perform(get("/auth/oauth/apple")).andReturn().getResponse();
        assertThat(response.getStatus()).isEqualTo(302);
        assertThat(response.getHeader("Location")).isEqualTo("/oauth2/authorization/apple");
    }

    // ─────────────────────────── id_token → 계정 ───────────────────────────

    @Test
    @DisplayName("id_token 클레임으로 계정이 생기고(sub 가 열쇠, 이름 없이 기본 닉네임) 두 번째는 같은 계정이다")
    void idTokenClaimsCreateAndThenReuseTheAccount() {
        OidcUser first = service.loadUser(request(SUB, "hidden@privaterelay.appleid.com"));

        assertThat(first).isInstanceOf(CustomOidcUser.class);
        CustomOidcUser principal = (CustomOidcUser) first;
        assertThat(principal.isNew()).isTrue();
        assertThat(principal.getUserId()).isNotNull();
        assertThat(principal.getName()).isEqualTo("apple_" + SUB);
        assertThat(principal.getIdToken().getSubject()).isEqualTo(SUB);

        Optional<User> row = users.findByProviderAndSocialId("apple", SUB);
        assertThat(row).isPresent();
        assertThat(row.get().getEmail()).isEqualTo("hidden@privaterelay.appleid.com");
        assertThat(row.get().getName()).as("Apple 은 이름을 안 준다").isNull();
        assertThat(row.get().getNickname()).as("이름이 없으면 기본 닉네임").startsWith("반려인");
        assertThat(row.get().getRole()).isEqualTo(User.ROLE_USER);

        OidcUser second = service.loadUser(request(SUB, "hidden@privaterelay.appleid.com"));
        assertThat(((CustomOidcUser) second).isNew()).isFalse();
        assertThat(((CustomOidcUser) second).getUserId()).isEqualTo(principal.getUserId());
        assertThat(jdbc.queryForObject("select count(*) from users where provider = 'apple'", Integer.class)).isEqualTo(1);
    }

    @Test
    @DisplayName("이메일을 안 준 사용자도 가입된다 — sub 만 있으면 된다")
    void emailIsOptional() {
        OidcUser user = service.loadUser(request(SUB, null));
        assertThat(((CustomOidcUser) user).getUserId()).isNotNull();
        assertThat(users.findByProviderAndSocialId("apple", SUB).orElseThrow().getEmail()).isNull();
    }

    private OidcUserRequest request(String sub, String email) {
        ClientRegistration apple = registrations.findByRegistrationId("apple");
        Instant now = Instant.now();
        OidcIdToken.Builder idToken = OidcIdToken.withTokenValue("id-token")
                .issuer("https://appleid.apple.com")
                .audience(List.of(apple.getClientId()))
                .subject(sub)
                .issuedAt(now)
                .expiresAt(now.plusSeconds(600))
                .claim("email_verified", "true")
                .claim("is_private_email", "true");
        if (email != null) {
            idToken.claim("email", email);
        }
        OAuth2AccessToken accessToken = new OAuth2AccessToken(
                OAuth2AccessToken.TokenType.BEARER, "access-token", now, now.plusSeconds(600));
        return new OidcUserRequest(apple, accessToken, idToken.build());
    }
}
