package com.heattrip.heat_trip_backend.user;

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
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.ResultActions;
import org.springframework.transaction.annotation.Transactional;

import java.nio.charset.StandardCharsets;
import java.util.concurrent.atomic.AtomicLong;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * 사용자가 고른 동네 — 이슈 #342.
 *
 * <h2>여기서 재는 것</h2>
 * <ul>
 *   <li><b>이름은 서버가 붙인다.</b> 본문으로 받으면 아무나 자기 동네를 "청와대" 라고 적어
 *       글 카드에 띄울 수 있다. 코드만 받고 250줄 표에서 이름을 찾는지 본다.</li>
 *   <li><b>모르는 코드는 400 이다.</b> 확인 없이 저장하면 아무 문자열이나 들어가고,
 *       커뮤니티의 "우리 동네" 가 조용히 아무것도 안 준다 — 화면에서는 "글이 없다" 와
 *       구별되지 않는다.</li>
 *   <li><b>응답에 좌표가 없다.</b> 이 기능이 위치정보가 아닌 이유가 그것이다(#235 A안).
 *       서버는 좌표를 받지도 저장하지도 않는다.</li>
 *   <li><b>빈 문자열이면 지운다.</b> "동네 안 쓸래" 를 표현할 방법이 있어야 한다.</li>
 * </ul>
 */
@SpringBootTest
@AutoConfigureMockMvc
@Transactional
class NeighborhoodIntegrationTest extends AbstractMySqlIntegrationTest {

    /** 서울특별시 성동구 왕십리2동. 앞 다섯 자리 {@code 11200} 이 성동구다. */
    private static final String SEONGSU = "1120052000";

    private static final AtomicLong SEQUENCE = new AtomicLong();
    private static final ObjectMapper MAPPER = new ObjectMapper();

    @Autowired MockMvc mockMvc;
    @Autowired UserRepository userRepository;
    @Autowired JWTProvider jwtProvider;
    @Autowired NeighborhoodCatalog catalog;

    @Test
    @DisplayName("동네를 고르면 시군구 이름이 붙어 돌아온다 — 이름은 본문으로 안 받는다")
    void choosingANeighborhoodAnswersWithTheDistrictName() throws Exception {
        User me = existingUser();

        JsonNode updated = body(updateMe(me, "{\"neighborhoodCode\":\"" + SEONGSU + "\"}")
                .andExpect(status().isOk()));

        assertThat(updated.path("neighborhood").path("code").asText()).isEqualTo(SEONGSU);
        assertThat(updated.path("neighborhood").path("sigungu").asText())
                .as("""
                        이름을 앱이 보내 준 문자열로 쓰면 아무나 자기 동네를 '청와대' 라고 적어 \
                        글 카드에 띄울 수 있다. 서버의 표에서만 나온다.""")
                .isEqualTo("성동구");
        assertThat(updated.path("neighborhood").path("sido").asText()).isEqualTo("서울특별시");

        JsonNode read = body(mockMvc.perform(get("/auth/me")
                        .header("Authorization", "Bearer " + token(me)))
                .andExpect(status().isOk()));
        assertThat(read.path("neighborhood").path("sigungu").asText()).isEqualTo("성동구");
    }

    @Test
    @DisplayName("응답에 좌표가 없다 — 이 값이 위치정보가 아닌 이유가 그것이다 (#235 A안)")
    void theResponseCarriesNoCoordinates() throws Exception {
        User me = existingUser();

        String json = updateMe(me, "{\"neighborhoodCode\":\"" + SEONGSU + "\"}")
                .andExpect(status().isOk())
                .andReturn().getResponse().getContentAsString(StandardCharsets.UTF_8);

        assertThat(json)
                .as("""
                        지도의 중심 좌표는 앱이 내장 자산에서 읽는다. 서버가 그것을 실어 주기 \
                        시작하면 '좌표가 사는 자리' 가 하나 늘고, 그 자리는 언젠가 새어 나간다.""")
                .doesNotContain("\"lat\"")
                .doesNotContain("\"lng\"")
                .doesNotContain("latitude")
                .doesNotContain("longitude");
    }

    @Test
    @DisplayName("모르는 코드는 400 이고 값이 안 바뀐다")
    void anUnknownCodeIsRejected() throws Exception {
        User me = existingUser();
        updateMe(me, "{\"neighborhoodCode\":\"" + SEONGSU + "\"}").andExpect(status().isOk());

        // 형식은 맞지만(열 자리) 우리 표에 없는 시군구다.
        updateMe(me, "{\"neighborhoodCode\":\"9999952000\"}")
                .andExpect(status().isBadRequest());

        assertThat(userRepository.findById(me.getId()).orElseThrow().getNeighborhoodCode())
                .as("400 을 주고도 값이 바뀌었으면 그게 더 나쁘다")
                .isEqualTo(SEONGSU);
    }

    @Test
    @DisplayName("열 자리가 아니면 형식에서 400 이다")
    void aMalformedCodeIsRejected() throws Exception {
        User me = existingUser();

        updateMe(me, "{\"neighborhoodCode\":\"1120\"}").andExpect(status().isBadRequest());
        updateMe(me, "{\"neighborhoodCode\":\"성동구\"}").andExpect(status().isBadRequest());
    }

    @Test
    @DisplayName("빈 문자열이면 지운다 — '동네 안 쓸래' 를 표현할 방법이 있어야 한다")
    void anEmptyStringClearsIt() throws Exception {
        User me = existingUser();
        updateMe(me, "{\"neighborhoodCode\":\"" + SEONGSU + "\"}").andExpect(status().isOk());

        JsonNode cleared = body(updateMe(me, "{\"neighborhoodCode\":\"\"}")
                .andExpect(status().isOk()));

        assertThat(cleared.path("neighborhood").isNull()).isTrue();
        assertThat(userRepository.findById(me.getId()).orElseThrow().getNeighborhoodCode()).isNull();
    }

    @Test
    @DisplayName("안 보내면 안 바꾼다 — 부분 수정의 규칙 그대로다")
    void omittingItChangesNothing() throws Exception {
        User me = existingUser();
        updateMe(me, "{\"neighborhoodCode\":\"" + SEONGSU + "\"}").andExpect(status().isOk());

        updateMe(me, "{\"age\":30}").andExpect(status().isOk());

        assertThat(userRepository.findById(me.getId()).orElseThrow().getNeighborhoodCode())
                .isEqualTo(SEONGSU);
    }

    @Test
    @DisplayName("동네를 안 고른 사람의 응답에는 neighborhood 가 null 이다")
    void withoutANeighborhoodTheFieldIsNull() throws Exception {
        User me = existingUser();

        JsonNode read = body(mockMvc.perform(get("/auth/me")
                        .header("Authorization", "Bearer " + token(me)))
                .andExpect(status().isOk()));

        assertThat(read.path("neighborhood").isNull()).isTrue();
    }

    @Test
    @DisplayName("시군구 표가 250줄 전부 읽혔다 — 비어 있으면 모든 동네 저장이 400 이 된다")
    void theCatalogIsFullyLoaded() {
        assertThat(catalog.size())
                .as("표가 반만 읽히면 그 절반의 사람들만 조용히 막힌다")
                .isGreaterThanOrEqualTo(250);
        assertThat(catalog.find(SEONGSU)).isPresent();
        assertThat(catalog.find("11200")).as("동 코드는 열 자리다 — 다섯 자리는 안 받는다").isEmpty();
        assertThat(catalog.find(null)).isEmpty();
    }

    // ─────────────────────────── 지그 ───────────────────────────

    private String token(User me) {
        return jwtProvider.createAccessToken(me.getId(), me.getRole());
    }

    private ResultActions updateMe(User me, String body) throws Exception {
        return mockMvc.perform(put("/auth/me")
                .header("Authorization", "Bearer " + token(me))
                .contentType(MediaType.APPLICATION_JSON)
                .content(body));
    }

    private static JsonNode body(ResultActions actions) throws Exception {
        return MAPPER.readTree(
                actions.andReturn().getResponse().getContentAsString(StandardCharsets.UTF_8));
    }

    private User existingUser() {
        long serial = SEQUENCE.incrementAndGet();
        return userRepository.save(User.builder()
                .provider(User.PROVIDER_LOCAL)
                .role(User.ROLE_USER)
                .email("hood-%d-%d@example.com".formatted(System.nanoTime(), serial))
                .name("이름")
                .nickname("동네사람")
                .build());
    }
}
