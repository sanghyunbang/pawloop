package com.heattrip.heat_trip_backend.user.signup;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.heattrip.heat_trip_backend.support.AbstractMySqlIntegrationTest;
import com.heattrip.heat_trip_backend.user.UserTime;
import com.heattrip.heat_trip_backend.user.mail.Mailer;
import com.heattrip.heat_trip_backend.user.repository.UserRepository;

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
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * 이메일 가입이 <b>인증을 거쳐야</b> 끝난다 — 이슈 #635.
 *
 * <h2>메일을 가로채서 코드를 읽는다</h2>
 * <p>코드는 해시로 저장되므로 DB 에서 못 읽는다. 그래서 {@link Mailer} 를 받아 적는 것으로
 * 갈아 끼우고 <b>실제로 나간 본문</b>에서 여섯 자리를 뽑는다 — 사용자가 하는 일과 같다.
 *
 * <p>이렇게 하면 본문에 코드가 실제로 들어 있는지까지 함께 잰다. 서비스가 코드를 만들고도
 * 메일에 안 넣으면 여기서 빨간불이다.
 */
@SpringBootTest
@AutoConfigureMockMvc
@ContextConfiguration(classes = EmailSignupVerificationIntegrationTest.RecordingMail.class)
class EmailSignupVerificationIntegrationTest extends AbstractMySqlIntegrationTest {

    /** 보낸 메일 한 통. */
    record Sent(String to, String subject, String body) {
    }

    @TestConfiguration
    static class RecordingMail {
        static final List<Sent> SENT = new ArrayList<>();

        /**
         * 발송이 성공했다고 할까. 기본은 참이고, 자격이 없는 환경을 흉낼 때 거짓으로 둔다 —
         * 그때 {@code mailSent} 가 무엇을 흘리는지가 드러난다.
         */
        static boolean succeeds = true;

        @Bean
        @Primary
        Mailer recordingMailer() {
            return (to, subject, body) -> {
                SENT.add(new Sent(to, subject, body));
                return succeeds;
            };
        }
    }

    private static final Pattern SIX_DIGITS = Pattern.compile("\\b(\\d{6})\\b");

    @Autowired
    private MockMvc mockMvc;
    @Autowired
    private ObjectMapper objectMapper;
    @Autowired
    private UserRepository users;
    @Autowired
    private PendingSignupRepository pending;
    @Autowired
    private PendingSignupPurgeScheduler purge;

    @BeforeEach
    void reset() {
        RecordingMail.SENT.clear();
        RecordingMail.succeeds = true;
        pending.deleteAll();
    }

    // ─────────────────────── 가입 → 인증 ───────────────────────

    @Test
    @DisplayName("가입 요청은 계정을 안 만든다 — 202 와 메일 한 통뿐이다")
    void signupDoesNotCreateTheAccountYet() throws Exception {
        String email = "walker+" + System.nanoTime() + "@example.test";

        signup(email).andExpect(status().isAccepted())
                .andExpect(jsonPath("$.mailSent").value(true));

        assertThat(users.findByEmail(email))
                .as("인증 전에 계정이 생기면 미인증 행이 그 주소를 막는다")
                .isEmpty();
        assertThat(pending.findByEmail(email)).isPresent();
        assertThat(RecordingMail.SENT).hasSize(1);
        assertThat(RecordingMail.SENT.get(0).to()).isEqualTo(email);
    }

    @Test
    @DisplayName("메일의 코드를 넣으면 계정이 생기고 바로 로그인된다")
    void verifyingTheCodeCreatesTheAccountAndSignsIn() throws Exception {
        String email = "walker+" + System.nanoTime() + "@example.test";
        signup(email).andExpect(status().isAccepted());

        verify(email, codeFromMail()).andExpect(status().isOk())
                // 토큰 한 벌이 그대로 와야 한다. refresh 가 빠지면 한 시간 뒤 조용히 로그아웃된다(#9).
                .andExpect(jsonPath("$.accessToken").isNotEmpty())
                .andExpect(jsonPath("$.refreshToken").isNotEmpty())
                // 라우터가 이 값으로 온보딩을 연다(#12). false 면 새 가입자가 온보딩을 못 본다.
                .andExpect(jsonPath("$.isNew").value(true))
                .andExpect(jsonPath("$.user.email").value(email));

        assertThat(users.findByEmail(email)).isPresent();
        assertThat(pending.findByEmail(email))
                .as("대기 행이 남으면 비밀번호 해시가 쓸 일 없이 계속 산다")
                .isEmpty();
    }

    @Test
    @DisplayName("틀린 코드는 401 이고 계정이 안 생긴다")
    void aWrongCodeCreatesNothing() throws Exception {
        String email = "walker+" + System.nanoTime() + "@example.test";
        signup(email).andExpect(status().isAccepted());

        String wrong = codeFromMail().equals("000000") ? "111111" : "000000";
        verify(email, wrong).andExpect(status().isUnauthorized());

        assertThat(users.findByEmail(email)).isEmpty();
        assertThat(pending.findByEmail(email).orElseThrow().getAttempts())
                .as("틀린 시도가 안 세어지면 무차별 시도를 막을 수단이 없다")
                .isEqualTo(1);
    }

    @Test
    @DisplayName("여러 번 틀리면 코드가 죽는다 — 맞는 코드를 넣어도 410 이다")
    void tooManyWrongAttemptsKillTheCode() throws Exception {
        String email = "walker+" + System.nanoTime() + "@example.test";
        signup(email).andExpect(status().isAccepted());
        String right = codeFromMail();
        String wrong = right.equals("000000") ? "111111" : "000000";

        for (int i = 0; i < 5; i++) {
            verify(email, wrong).andExpect(status().isUnauthorized());
        }

        verify(email, right)
                .andExpect(status().isGone());
        assertThat(users.findByEmail(email)).isEmpty();
    }

    // ─────────────────────── 가입 여부를 안 흘린다 ───────────────────────

    @Test
    @DisplayName("이미 가입된 주소도 같은 202 다 — 409 면 가입 여부를 묻는 수단이 된다")
    void anExistingEmailLooksTheSameFromOutside() throws Exception {
        String email = "walker+" + System.nanoTime() + "@example.test";
        signup(email).andExpect(status().isAccepted());
        verify(email, codeFromMail()).andExpect(status().isOk());
        RecordingMail.SENT.clear();

        signup(email)
                .andExpect(status().isAccepted())
                .andExpect(jsonPath("$.mailSent").value(true));

        // 밖에서 보는 답은 같지만, **그 주소의 주인에게는** 무슨 일이 있었는지 알린다.
        assertThat(RecordingMail.SENT).hasSize(1);
        assertThat(RecordingMail.SENT.get(0).body())
                .as("주인이 상황을 알 수 있어야 한다")
                .contains("이미 계정이 있습니다");
        assertThat(RecordingMail.SENT.get(0).body())
                .as("그 메일에 코드가 들어가면 남이 남의 계정을 가져간다")
                .doesNotMatch("(?s).*\\b\\d{6}\\b.*");
    }

    @Test
    @DisplayName("대기가 없는 주소로 다시 보내기를 해도 같은 202 다")
    void resendingForAnUnknownEmailLooksTheSame() throws Exception {
        mockMvc.perform(post("/auth/signup/resend")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"email\":\"nobody+" + System.nanoTime() + "@example.test\"}"))
                .andExpect(status().isAccepted());

        assertThat(RecordingMail.SENT)
                .as("없는 대기에 메일을 보내면 그 자체가 신호가 된다")
                .isEmpty();
    }

    @Test
    @DisplayName("다시 보내면 새 코드가 오고 옛 코드는 죽는다")
    void resendingReplacesTheCode() throws Exception {
        String email = "walker+" + System.nanoTime() + "@example.test";
        signup(email).andExpect(status().isAccepted());
        String first = codeFromMail();

        RecordingMail.SENT.clear();
        mockMvc.perform(post("/auth/signup/resend")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"email\":\"" + email + "\"}"))
                .andExpect(status().isAccepted());
        String second = codeFromMail();

        assertThat(second).isNotEqualTo(first);
        verify(email, first)
                .andExpect(status().isUnauthorized());
        verify(email, second).andExpect(status().isOk());
    }

    @Test
    @DisplayName("메일이 안 나가는 환경에서도 둔 경우의 본문이 같다 — mailSent 가 가입 여부를 흘리면 안 된다")
    void mailSentDoesNotLeakWhetherTheEmailIsTaken() throws Exception {
        String taken = "walker+" + System.nanoTime() + "@example.test";
        signup(taken).andExpect(status().isAccepted());
        verify(taken, codeFromMail()).andExpect(status().isOk());

        // 발송 자격이 없는 환경이다. SES 프로덕션 액세스가 승인되기 전의 운영도 이렇게 산다.
        RecordingMail.succeeds = false;
        String fresh = "walker+" + System.nanoTime() + "@example.test";

        String freshBody = signup(fresh).andExpect(status().isAccepted())
                .andReturn().getResponse().getContentAsString();
        String takenBody = signup(taken).andExpect(status().isAccepted())
                .andReturn().getResponse().getContentAsString();

        // 상태 코드를 같게 만들어 놓고 본문에서 갈리면 아무것도 가리지 못한 것이다.
        assertThat(takenBody)
                .as("""
                        이미 가입된 주소와 처음 주소의 응답이 다르다 — 이메일을 하나씩 넣어 보면                         누가 이 앱을 쓰는지 세어 볼 수 있다.""")
                .isEqualTo(freshBody);
    }

    // ───────────────────── 만료된 것을 시간이 지운다 ────────────────────

    @Test
    @DisplayName("만료된 대기 행은 시간이 지운다 — 살아 있는 행은 안 건드린다")
    void thePurgeRemovesOnlyExpiredRows() throws Exception {
        String dead = "walker+" + System.nanoTime() + "@example.test";
        String alive = "walker+" + System.nanoTime() + "@example.test";
        signup(dead).andExpect(status().isAccepted());
        signup(alive).andExpect(status().isAccepted());

        // 인증 흐름은 만료된 행을 **덮어쓰기만** 한다 — 같은 주소로 다시 오는 사람의 것만
        // 정리되고, 다시 안 오는 사람의 이메일과 비밀번호 해시는 영영 남는다. 그래서 시간이
        // 지우는 자리가 따로 필요하고, 이 검사가 그 자리가 실제로 도는지를 잰다.
        PendingSignup expired = pending.findByEmail(dead).orElseThrow();
        expired.setExpiresAt(UserTime.nowUtc().minusMinutes(1));
        pending.saveAndFlush(expired);

        purge.purgeExpiredPendingSignups();

        assertThat(pending.findByEmail(dead))
                .as("만료된 행이 남으면 쓸 일 없는 비밀번호 해시가 계속 산다")
                .isEmpty();
        assertThat(pending.findByEmail(alive))
                .as("아직 살아 있는 대기를 지우면, 메일을 받아 둔 사람이 코드를 넣을 자리를 잃는다")
                .isPresent();
    }

    // ─────────────────────── 도우미 ───────────────────────

    private ResultActions signup(String email) throws Exception {
        String body = objectMapper.writeValueAsString(java.util.Map.of(
                "email", email,
                "password", "Passw0rd!23",
                "nickname", "보리아빠",
                "name", "보리아빠",
                "gender", "unknown",
                "ageGroup", "over14"));
        return mockMvc.perform(post("/auth/signup")
                .contentType(MediaType.APPLICATION_JSON)
                .content(body.getBytes(StandardCharsets.UTF_8)));
    }

    private ResultActions verify(String email, String code) throws Exception {
        return mockMvc.perform(post("/auth/signup/verify")
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"email\":\"" + email + "\",\"code\":\"" + code + "\"}"));
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
