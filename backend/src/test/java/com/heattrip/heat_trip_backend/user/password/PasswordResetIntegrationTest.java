package com.heattrip.heat_trip_backend.user.password;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.heattrip.heat_trip_backend.support.AbstractMySqlIntegrationTest;
import com.heattrip.heat_trip_backend.user.UserTime;
import com.heattrip.heat_trip_backend.user.entity.User;
import com.heattrip.heat_trip_backend.user.mail.Mailer;
import com.heattrip.heat_trip_backend.user.repository.RefreshTokenRepository;
import com.heattrip.heat_trip_backend.user.repository.UserRepository;
import com.heattrip.heat_trip_backend.user.verification.VerificationPurgeScheduler;

import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Primary;
import org.springframework.http.MediaType;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.test.context.ContextConfiguration;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.ResultActions;

import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.List;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * 비밀번호를 잊어도 <b>메일로 되찾는다</b> — 이슈 #635 조각 ③.
 *
 * <h2>여기가 가입 여부를 묻기 가장 편한 문이다</h2>
 * <p>로그인은 비밀번호가 있어야 하지만 재설정은 <b>주소만 넣으면 된다.</b> 그래서 이 검사의
 * 절반은 "있는 주소와 없는 주소의 답이 바이트까지 같은가" 다.
 *
 * <p>코드는 해시로 저장되므로 DB 에서 못 읽는다. {@link Mailer} 를 받아 적는 것으로 갈아
 * 끼우고 <b>실제로 나간 본문</b>에서 여섯 자리를 뽑는다 — 사용자가 하는 일과 같다.
 */
@SpringBootTest
@AutoConfigureMockMvc
@ContextConfiguration(classes = PasswordResetIntegrationTest.RecordingMail.class)
class PasswordResetIntegrationTest extends AbstractMySqlIntegrationTest {

    record Sent(String to, String subject, String body) {
    }

    @TestConfiguration
    static class RecordingMail {
        static final List<Sent> SENT = new ArrayList<>();

        @Bean
        @Primary
        Mailer recordingMailer() {
            return (to, subject, body) -> {
                SENT.add(new Sent(to, subject, body));
                return true;
            };
        }
    }

    private static final Pattern SIX_DIGITS = Pattern.compile("\\b(\\d{6})\\b");
    private static final String OLD_PASSWORD = "Passw0rd!23";
    private static final String NEW_PASSWORD = "N3wPassw0rd!";

    @Autowired
    private MockMvc mockMvc;
    @Autowired
    private ObjectMapper objectMapper;
    @Autowired
    private UserRepository users;
    @Autowired
    private PasswordResetRepository resets;
    @Autowired
    private PasswordEncoder passwordEncoder;
    @Autowired
    private RefreshTokenRepository refreshTokens;
    @Autowired
    private VerificationPurgeScheduler purge;

    /** 트랜잭션 롤백에 기대지 않으므로 만든 행을 직접 지운다 — {@link #cleanUpCreatedRows}. */
    private final List<String> createdEmails = new ArrayList<>();

    @BeforeEach
    void reset() {
        RecordingMail.SENT.clear();
        resets.deleteAll();
    }

    /**
     * 트랜잭션 롤백에 기대지 않으므로 <b>만든 행을 직접 지운다.</b>
     *
     * <p>이 검사는 커밋된 상태를 봐야 해서 {@code @Transactional} 이 없다. 그러면 여기서 만든
     * 사용자와 refresh 토큰이 <b>남아서 다른 검사의 셈을 흐린다</b> — {@code UserRepositoryTest}
     * 는 "세 명을 넣었으니 세 명" 을 재고, 남은 행이 있으면 열한 명이 된다. 실제로 그렇게
     * 빨간불이 났다(2026-09-17). {@code AuthContractIntegrationTest} 와 같은 방식이다.
     */
    @AfterEach
    void cleanUpCreatedRows() {
        for (String email : createdEmails) {
            users.findByEmail(email).ifPresent(user -> {
                refreshTokens.deleteByUserId(user.getId());
                users.delete(user);
            });
        }
        createdEmails.clear();
    }

    // ─────────────────────── 되찾는 길 ───────────────────────

    @Test
    @DisplayName("코드를 받아 새 비밀번호를 정하면 그것으로 로그인된다")
    void theCodeLetsYouSetANewPassword() throws Exception {
        User member = member();

        requestReset(member.getEmail()).andExpect(status().isAccepted());

        resetWith(member.getEmail(), codeFromMail(), NEW_PASSWORD)
                .andExpect(status().isOk())
                // 토큰 한 벌이 그대로 와야 한다. refresh 가 빠지면 한 시간 뒤 조용히 로그아웃된다(#9).
                .andExpect(jsonPath("$.accessToken").isNotEmpty())
                .andExpect(jsonPath("$.refreshToken").isNotEmpty())
                // 이미 있는 계정이다 — 참이면 앱이 온보딩을 다시 연다(#12).
                .andExpect(jsonPath("$.isNew").value(false));

        User after = users.findByEmail(member.getEmail()).orElseThrow();
        assertThat(passwordEncoder.matches(NEW_PASSWORD, after.getPassword()))
                .as("새 비밀번호로 안 바뀌었다 — 코드를 맞혔는데 아무 일도 안 일어난 것이다")
                .isTrue();
        assertThat(passwordEncoder.matches(OLD_PASSWORD, after.getPassword()))
                .as("옛 비밀번호가 그대로 살아 있으면 잃어버린 사람이 둘 다 못 쓴다")
                .isFalse();
        assertThat(resets.findByUserId(after.getId()))
                .as("쓴 재설정이 남으면 그 코드로 또 바꿀 수 있다")
                .isEmpty();
    }

    @Test
    @DisplayName("바꾸고 나면 다른 기기의 refresh 토큰이 죽는다 — 침입자를 쫓아내는 것이 목적이다")
    void resettingKillsOtherSessions() throws Exception {
        User member = member();
        String otherDevice = loginRefreshToken(member.getEmail(), OLD_PASSWORD);

        requestReset(member.getEmail()).andExpect(status().isAccepted());
        resetWith(member.getEmail(), codeFromMail(), NEW_PASSWORD).andExpect(status().isOk());

        // 재설정을 하는 흔한 이유가 "누가 내 계정에 들어온 것 같다" 이다. 비밀번호만 바꾸고
        // 살아 있는 토큰을 두면 **그 사람은 그대로 들어와 있다.**
        mockMvc.perform(post("/auth/token/refresh")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"refreshToken\":\"" + otherDevice + "\"}"))
                .andExpect(status().isUnauthorized());
    }

    // ─────────────────── 가입 여부를 안 흘린다 ───────────────────

    @Test
    @DisplayName("없는 주소도 바이트까지 같은 202 다 — 메일은 안 나간다")
    void anUnknownEmailLooksExactlyTheSame() throws Exception {
        User member = member();

        String known = requestReset(member.getEmail())
                .andExpect(status().isAccepted())
                .andReturn().getResponse().getContentAsString();
        RecordingMail.SENT.clear();

        String unknown = requestReset("nobody+" + System.nanoTime() + "@example.test")
                .andExpect(status().isAccepted())
                .andReturn().getResponse().getContentAsString();

        assertThat(unknown)
                .as("""
                        있는 주소와 없는 주소의 응답이 다르다 — 주소를 하나씩 넣어 보면 \
                        누가 이 앱을 쓰는지 셀 수 있다. 이 경로는 비밀번호도 필요 없어서 \
                        그러기에 가장 편한 문이다.""")
                .isEqualTo(known);
        assertThat(RecordingMail.SENT)
                .as("없는 주소에 메일을 보내면 그 자체가 신호다")
                .isEmpty();
    }

    @Test
    @DisplayName("응답에 본문이 없다 — mailSent 를 주면 그 값이 곧 가입 여부다")
    void theResponseCarriesNoBody() throws Exception {
        requestReset("nobody+" + System.nanoTime() + "@example.test")
                .andExpect(status().isAccepted())
                .andExpect(content().string(""));
    }

    @Test
    @DisplayName("없는 주소로 확인을 해도 410 이다 — 404 면 그것이 조회 수단이 된다")
    void confirmingForAnUnknownEmailIsGoneNotNotFound() throws Exception {
        resetWith("nobody+" + System.nanoTime() + "@example.test", "012345", NEW_PASSWORD)
                .andExpect(status().isGone());
    }

    @Test
    @DisplayName("소셜로만 가입한 사람에게도 메일은 간다 — 다만 코드가 아니라 안내다")
    void aSocialOnlyAccountGetsAnExplanationNotACode() throws Exception {
        User social = remember(users.save(User.builder()
                .provider("kakao")
                .socialId("kakao-" + System.nanoTime())
                .role(User.ROLE_USER)
                .email("social+" + System.nanoTime() + "@example.test")
                .nickname("보리아빠")
                .createdAt(UserTime.nowUtc())
                .build()));

        requestReset(social.getEmail()).andExpect(status().isAccepted());

        // 침묵도 신호다 — 안 보내면 "이 사람은 소셜 가입자다" 를 알려 주는 셈이다.
        assertThat(RecordingMail.SENT).hasSize(1);
        assertThat(RecordingMail.SENT.get(0).body())
                .as("무엇을 해야 하는지 없으면 그 사람은 계속 재설정만 누른다")
                .contains("비밀번호가 없습니다");
        assertThat(RecordingMail.SENT.get(0).body())
                .as("비밀번호가 없는 계정에 코드를 보내면 그 코드로 비밀번호가 생긴다")
                .doesNotMatch("(?s).*\\b\\d{6}\\b.*");
        assertThat(resets.findByUserId(social.getId()))
                .as("행이 생기면 그 표를 읽을 수 있는 사람이 누가 소셜 가입자인지 셀 수 있다")
                .isEmpty();
    }

    // ─────────────────── 무차별 시도를 막는다 ───────────────────

    @Test
    @DisplayName("틀린 코드는 401 이고 비밀번호는 그대로다")
    void aWrongCodeChangesNothing() throws Exception {
        User member = member();
        requestReset(member.getEmail()).andExpect(status().isAccepted());
        String right = codeFromMail();
        String wrong = right.equals("000000") ? "111111" : "000000";

        resetWith(member.getEmail(), wrong, NEW_PASSWORD).andExpect(status().isUnauthorized());

        assertThat(passwordEncoder.matches(OLD_PASSWORD,
                users.findByEmail(member.getEmail()).orElseThrow().getPassword()))
                .as("코드가 틀렸는데 비밀번호가 바뀌었다")
                .isTrue();
        assertThat(resets.findByUserId(member.getId()).orElseThrow().getAttempts())
                .as("틀린 시도가 안 세어지면 무차별 시도를 막을 수단이 없다")
                .isEqualTo(1);
    }

    @Test
    @DisplayName("여러 번 틀리면 코드가 죽는다 — 맞는 코드를 넣어도 410 이다")
    void tooManyWrongAttemptsKillTheCode() throws Exception {
        User member = member();
        requestReset(member.getEmail()).andExpect(status().isAccepted());
        String right = codeFromMail();
        String wrong = right.equals("000000") ? "111111" : "000000";

        for (int i = 0; i < 5; i++) {
            resetWith(member.getEmail(), wrong, NEW_PASSWORD).andExpect(status().isUnauthorized());
        }

        resetWith(member.getEmail(), right, NEW_PASSWORD).andExpect(status().isGone());
        assertThat(passwordEncoder.matches(OLD_PASSWORD,
                users.findByEmail(member.getEmail()).orElseThrow().getPassword()))
                .isTrue();
    }

    @Test
    @DisplayName("다시 요청하면 새 코드가 오고 옛 코드는 죽는다")
    void requestingAgainReplacesTheCode() throws Exception {
        User member = member();
        requestReset(member.getEmail()).andExpect(status().isAccepted());
        String first = codeFromMail();

        RecordingMail.SENT.clear();
        requestReset(member.getEmail()).andExpect(status().isAccepted());
        String second = codeFromMail();

        assertThat(second).isNotEqualTo(first);
        resetWith(member.getEmail(), first, NEW_PASSWORD).andExpect(status().isUnauthorized());
        resetWith(member.getEmail(), second, NEW_PASSWORD).andExpect(status().isOk());
    }

    // ─────────────── 만료된 것을 시간이 지운다 ───────────────

    @Test
    @DisplayName("만료된 재설정도 같은 정리가 지운다 — 표가 늘어도 정리를 잊지 않는다")
    void thePurgeCoversThisTableToo() throws Exception {
        User member = member();
        requestReset(member.getEmail()).andExpect(status().isAccepted());

        PasswordReset row = resets.findByUserId(member.getId()).orElseThrow();
        row.setExpiresAt(UserTime.nowUtc().minusMinutes(1));
        resets.saveAndFlush(row);

        purge.purgeExpired();

        assertThat(resets.findByUserId(member.getId()))
                .as("표마다 정리를 하나씩 두면 두 번째 표를 만드는 날 그것을 잊는다")
                .isEmpty();
        assertThat(purge.purgedRowNames())
                .as("정리가 도는 표 목록에 이 표가 없다 — 있는 척만 하고 안 지운다")
                .contains("비밀번호 재설정", "가입 대기");
    }

    // ─────────────────────────── 지그 ───────────────────────────

    /** 이메일로 가입을 마친 사람 하나. 가입 흐름을 안 거치고 바로 만든다. */
    private User member() {
        return remember(users.save(User.builder()
                .provider(User.PROVIDER_LOCAL)
                .role(User.ROLE_USER)
                .email("walker+" + System.nanoTime() + "@example.test")
                .password(passwordEncoder.encode(OLD_PASSWORD))
                .nickname("보리아빠")
                .name("보리아빠")
                .createdAt(UserTime.nowUtc())
                .build()));
    }

    /** 뒷정리 목록에 올린다. 안 올리면 그 행이 다른 검사의 셈을 흐린다. */
    private User remember(User user) {
        createdEmails.add(user.getEmail());
        return user;
    }

    private ResultActions requestReset(String email) throws Exception {
        return mockMvc.perform(post("/auth/password/reset-request")
                .contentType(MediaType.APPLICATION_JSON)
                .content(("{\"email\":\"" + email + "\"}").getBytes(StandardCharsets.UTF_8)));
    }

    private ResultActions resetWith(String email, String code, String newPassword) throws Exception {
        String body = objectMapper.writeValueAsString(java.util.Map.of(
                "email", email, "code", code, "newPassword", newPassword));
        return mockMvc.perform(post("/auth/password/reset")
                .contentType(MediaType.APPLICATION_JSON)
                .content(body.getBytes(StandardCharsets.UTF_8)));
    }

    private String loginRefreshToken(String email, String password) throws Exception {
        String body = objectMapper.writeValueAsString(
                java.util.Map.of("email", email, "password", password));
        String json = mockMvc.perform(post("/auth/login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(body.getBytes(StandardCharsets.UTF_8)))
                .andExpect(status().isOk())
                .andReturn().getResponse().getContentAsString();
        return objectMapper.readTree(json).get("refreshToken").asText();
    }

    /** 마지막으로 나간 메일에서 여섯 자리를 뽑는다 — 사용자가 하는 일과 같다. */
    private String codeFromMail() {
        assertThat(RecordingMail.SENT).as("메일이 안 나갔다").isNotEmpty();
        String body = RecordingMail.SENT.get(RecordingMail.SENT.size() - 1).body();
        Matcher matcher = SIX_DIGITS.matcher(body);
        assertThat(matcher.find())
                .as("메일 본문에 여섯 자리가 없다 — 코드를 만들고도 안 실은 것이다\n%s", body)
                .isTrue();
        return matcher.group(1);
    }
}
