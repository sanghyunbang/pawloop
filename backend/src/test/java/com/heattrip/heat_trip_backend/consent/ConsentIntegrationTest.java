package com.heattrip.heat_trip_backend.consent;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.heattrip.heat_trip_backend.OAuth.jwt.JWTProvider;
import com.heattrip.heat_trip_backend.support.AbstractMySqlIntegrationTest;
import com.heattrip.heat_trip_backend.user.entity.User;
import com.heattrip.heat_trip_backend.user.repository.UserRepository;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.request.MockMvcRequestBuilders;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.ResultActions;

import java.util.concurrent.atomic.AtomicLong;

/**
 * 약관 동의의 HTTP 경로 — 이슈 #190.
 *
 * <h2>여기서 재는 것</h2>
 * <ul>
 *   <li>적으면 읽힌다. 철회도 적힌다. <b>행을 고치지 않고 쌓는다.</b></li>
 *   <li>주체는 토큰의 주인이다 — 남의 것이 섞이지 않는다.</li>
 *   <li>버전 모양이 틀리면 400 이고 아무것도 안 적힌다.</li>
 *   <li>{@code at} 이 오프셋 있는 시각으로 나가고, 저장은 UTC 다.</li>
 * </ul>
 */
@SpringBootTest
@AutoConfigureMockMvc
class ConsentIntegrationTest extends AbstractMySqlIntegrationTest {

    private static final ObjectMapper MAPPER = new ObjectMapper();
    private static final AtomicLong SEQ = new AtomicLong();

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private UserRepository userRepository;

    @Autowired
    private JWTProvider jwtProvider;

    @Autowired
    private JdbcTemplate jdbc;

    @Test
    @DisplayName("한 번도 안 적은 계정은 빈 목록이다")
    void aFreshAccountHasNoConsents() throws Exception {
        Account me = account();

        mockMvc.perform(get("/api/consents").header("Authorization", "Bearer " + me.token()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.consents").isArray())
                .andExpect(jsonPath("$.consents.length()").value(0));
    }

    @Test
    @DisplayName("적으면 읽힌다 — 문서별 마지막 기록이고 at 은 오프셋이 붙는다")
    void recordedConsentsAreReadBack() throws Exception {
        Account me = account();

        JsonNode body = body(putConsents(me, """
                {"consents": [
                  {"kind": "TERMS", "version": "v1.2", "agreed": true},
                  {"kind": "PRIVACY", "version": "v1.3", "agreed": true},
                  {"kind": "LOCATION", "version": "v1.1", "agreed": true},
                  {"kind": "MARKETING", "version": "v1.0", "agreed": false}
                ]}""").andExpect(status().isOk()));

        assertThat(body.get("consents")).hasSize(4);
        JsonNode terms = find(body, "TERMS");
        assertThat(terms.get("version").asText()).isEqualTo("v1.2");
        assertThat(terms.get("agreed").asBoolean()).isTrue();
        assertThat(terms.get("at").asText())
                .as("계약이 date-time 이라 오프셋이 있어야 한다 — 없으면 앱이 존을 추측한다")
                .endsWith("Z");
        assertThat(find(body, "MARKETING").get("agreed").asBoolean()).isFalse();

        JsonNode again = body(mockMvc.perform(get("/api/consents")
                .header("Authorization", "Bearer " + me.token())).andExpect(status().isOk()));
        assertThat(again.get("consents")).hasSize(4);
    }

    @Test
    @DisplayName("철회는 새 행이다 — 마지막 상태는 바뀌고 앞선 동의 행은 남는다")
    void revocationAppendsInsteadOfOverwriting() throws Exception {
        Account me = account();
        putConsents(me, """
                {"consents": [{"kind": "LOCATION", "version": "v1.1", "agreed": true}]}""")
                .andExpect(status().isOk());

        JsonNode body = body(putConsents(me, """
                {"consents": [{"kind": "LOCATION", "version": "v1.1", "agreed": false}]}""")
                .andExpect(status().isOk()));

        assertThat(find(body, "LOCATION").get("agreed").asBoolean()).isFalse();
        Integer rows = jdbc.queryForObject(
                "select count(*) from user_consent where user_id = ? and kind = 'LOCATION'",
                Integer.class, me.id());
        assertThat(rows)
                .as("덮어쓰면 '언제까지 동의 상태였는지' 가 사라진다 — 제24조의 경계 시각이다")
                .isEqualTo(2);
    }

    @Test
    @DisplayName("주체는 토큰의 주인이다 — 남의 동의가 섞이지 않는다")
    void consentsAreScopedToTheCaller() throws Exception {
        Account me = account();
        Account other = account();
        putConsents(other, """
                {"consents": [{"kind": "TERMS", "version": "v1.2", "agreed": true}]}""")
                .andExpect(status().isOk());

        mockMvc.perform(get("/api/consents").header("Authorization", "Bearer " + me.token()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.consents.length()").value(0));
    }

    @Test
    @DisplayName("버전 모양이 틀리면 400 이고 아무것도 안 적힌다")
    void aMalformedVersionIsRejectedWholesale() throws Exception {
        Account me = account();

        putConsents(me, """
                {"consents": [
                  {"kind": "TERMS", "version": "v1.2", "agreed": true},
                  {"kind": "PRIVACY", "version": "1.3", "agreed": true}
                ]}""").andExpect(status().isBadRequest());

        Integer rows = jdbc.queryForObject(
                "select count(*) from user_consent where user_id = ?", Integer.class, me.id());
        assertThat(rows)
                .as("절반만 적히면 '동의했다' 가 반쪽 진실이 된다 — 검증은 본문 전체에 걸린다")
                .isZero();
    }

    @Test
    @DisplayName("agreed 가 빠지면 400 이다 — 빠진 것과 철회한 것은 다르다")
    void aMissingAgreedFlagIsRejected() throws Exception {
        Account me = account();

        putConsents(me, """
                {"consents": [{"kind": "TERMS", "version": "v1.2"}]}""")
                .andExpect(status().isBadRequest());
    }

    @Test
    @DisplayName("토큰이 없으면 401 이다")
    void anonymousIsRejected() throws Exception {
        mockMvc.perform(get("/api/consents")).andExpect(status().isUnauthorized());
    }

    @Test
    @DisplayName("저장된 시각은 UTC 다 — JVM 존이 어디든")
    void storedTimestampIsUtc() throws Exception {
        Account me = account();
        putConsents(me, """
                {"consents": [{"kind": "TERMS", "version": "v1.2", "agreed": true}]}""")
                .andExpect(status().isOk());

        // DB 의 UTC_TIMESTAMP 와 저장값의 차이가 몇 초 안이어야 한다. 서비스 존(KST)으로
        // 찍었으면 9시간 어긋난다.
        Integer skew = jdbc.queryForObject(
                "select abs(timestampdiff(second, created_at, utc_timestamp(6))) from user_consent "
                        + "where user_id = ? order by id desc limit 1",
                Integer.class, me.id());
        assertThat(skew).isLessThan(60);
    }

    // ─────────────────────────── 지그 ───────────────────────────

    private ResultActions putConsents(Account who, String json) throws Exception {
        return mockMvc.perform(MockMvcRequestBuilders.put("/api/consents")
                .header("Authorization", "Bearer " + who.token())
                .contentType(MediaType.APPLICATION_JSON)
                .content(json));
    }

    private static JsonNode body(ResultActions actions) throws Exception {
        return MAPPER.readTree(actions.andReturn().getResponse().getContentAsString());
    }

    private static JsonNode find(JsonNode body, String kind) {
        for (JsonNode c : body.get("consents")) {
            if (kind.equals(c.get("kind").asText())) {
                return c;
            }
        }
        throw new AssertionError(kind + " 가 응답에 없다: " + body);
    }

    private Account account() {
        long serial = SEQ.incrementAndGet();
        User user = userRepository.save(User.builder()
                .provider(User.PROVIDER_LOCAL)
                .role(User.ROLE_USER)
                .email("consent-%d-%d@example.com".formatted(System.nanoTime(), serial))
                .name("동의" + serial)
                .nickname("동의" + serial)
                .build());
        return new Account(user.getId(), jwtProvider.createAccessToken(user.getId(), user.getRole()));
    }

    private record Account(long id, String token) { }
}
