package com.heattrip.heat_trip_backend.push;

import com.heattrip.heat_trip_backend.OAuth.jwt.JWTProvider;
import com.heattrip.heat_trip_backend.chat.ChatRoomService;
import com.heattrip.heat_trip_backend.chat.ChatRoomView;
import com.heattrip.heat_trip_backend.push.entity.DeviceToken;
import com.heattrip.heat_trip_backend.push.repository.DeviceTokenRepository;
import com.heattrip.heat_trip_backend.push.service.DeviceTokenService;
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

import java.util.List;
import java.util.concurrent.atomic.AtomicLong;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * 기기 토큰 등록 · 전체 끄기 · 방 음소거의 HTTP 표면 — 이슈 #83.
 *
 * <ul>
 *   <li>등록은 upsert 다 — 같은 토큰을 다시 보내면 행이 늘지 않고, 다른 계정이 보내면 주인이 바뀐다.</li>
 *   <li>사용자당 살아 있는 토큰은 상한이 있다 — 넘치면 가장 오래 안 보인 것부터 폐기된다.</li>
 *   <li>빠진 필드는 400 이다 — {@code {}} 가 "끄기" 나 "해제" 로 읽히면 안 된다.</li>
 *   <li>음소거는 멤버만 할 수 있고, 방 목록에 {@code muted} 로 실린다.</li>
 * </ul>
 */
@SpringBootTest
@AutoConfigureMockMvc
class PushRegistrationIntegrationTest extends AbstractMySqlIntegrationTest {

    private static final AtomicLong SEQUENCE = new AtomicLong();

    @Autowired private MockMvc mockMvc;
    @Autowired private JWTProvider jwtProvider;
    @Autowired private UserRepository users;
    @Autowired private DeviceTokenRepository tokenRows;
    @Autowired private DeviceTokenService deviceTokens;
    @Autowired private PushProperties properties;
    @Autowired private ChatRoomService chatRooms;

    // ─────────────────────────── 토큰 ───────────────────────────

    @Test
    @DisplayName("PUT /api/push/tokens 는 204 이고, 같은 토큰을 다시 보내도 행은 하나다")
    void registrationIsAnUpsert() throws Exception {
        User me = signUp("등록하는 사람");
        String token = token("phone");

        mockMvc.perform(put("/api/push/tokens").header("Authorization", bearer(me))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"token\":\"" + token + "\",\"platform\":\"android\"}"))
                .andExpect(status().isNoContent());
        mockMvc.perform(put("/api/push/tokens").header("Authorization", bearer(me))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"token\":\"" + token + "\",\"platform\":\"android\"}"))
                .andExpect(status().isNoContent());

        List<DeviceToken> rows = tokenRows.findByUserId(me.getId());
        assertThat(rows).singleElement().satisfies(row -> {
            assertThat(row.getToken()).isEqualTo(token);
            assertThat(row.getPlatform()).isEqualTo("android");
            assertThat(row.isActive()).isTrue();
        });
    }

    @Test
    @DisplayName("같은 기기에서 다른 계정이 등록하면 토큰의 주인이 바뀐다 — 옛 계정의 알림이 새 사람에게 가면 안 된다")
    void theTokenMovesToTheLatestAccount() throws Exception {
        User before = signUp("먼저 쓴 사람");
        User after = signUp("나중에 쓴 사람");
        String token = token("shared-phone");

        register(before, token, "ios");
        register(after, token, "ios");

        assertThat(tokenRows.findByToken(token).orElseThrow().getUserId()).isEqualTo(after.getId());
        assertThat(tokenRows.findByUserId(before.getId())).isEmpty();
    }

    @Test
    @DisplayName("platform 이 android·ios 밖이거나 token 이 비면 400 이다")
    void rejectsBadInput() throws Exception {
        User me = signUp("잘못 보내는 사람");

        mockMvc.perform(put("/api/push/tokens").header("Authorization", bearer(me))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"token\":\"" + token("web") + "\",\"platform\":\"web\"}"))
                .andExpect(status().isBadRequest());
        mockMvc.perform(put("/api/push/tokens").header("Authorization", bearer(me))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"token\":\"  \",\"platform\":\"android\"}"))
                .andExpect(status().isBadRequest());
        assertThat(tokenRows.findByUserId(me.getId())).isEmpty();
    }

    @Test
    @DisplayName("토큰 없이는 401 이다")
    void requiresAuthentication() throws Exception {
        mockMvc.perform(put("/api/push/tokens").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"token\":\"x\",\"platform\":\"android\"}"))
                .andExpect(status().isUnauthorized());
        mockMvc.perform(get("/api/push/settings")).andExpect(status().isUnauthorized());
    }

    @Test
    @DisplayName("사용자당 살아 있는 토큰이 상한을 넘으면 가장 오래 안 보인 것부터 폐기된다")
    void activeTokensAreCapped() {
        User me = signUp("폰이 많은 사람");
        int cap = properties.getMaxActiveTokensPerUser();
        List<String> phones = new java.util.ArrayList<>();
        for (int i = 0; i < cap + 2; i++) {
            phones.add(token("phone-" + i)); // token() 은 부를 때마다 새 값이라 한 번만 만들어 둔다
            deviceTokens.register(me.getId(), phones.get(i), "android");
        }

        List<DeviceToken> rows = tokenRows.findByUserId(me.getId());
        assertThat(rows).hasSize(cap + 2);
        assertThat(rows.stream().filter(DeviceToken::isActive)).hasSize(cap);
        assertThat(tokenRows.findByToken(phones.get(0)).orElseThrow().isActive())
                .as("가장 먼저 등록한 것이 가장 오래 안 보인 것이다").isFalse();
        assertThat(tokenRows.findByToken(phones.get(1)).orElseThrow().isActive()).isFalse();
        assertThat(tokenRows.findByToken(phones.get(cap + 1)).orElseThrow().isActive()).isTrue();
    }

    // ─────────────────────────── 설정 ───────────────────────────

    @Test
    @DisplayName("설정은 기본이 켜짐이고, 끄면 꺼진 채로 읽힌다 — 빈 본문은 400")
    void settingsRoundTrip() throws Exception {
        User me = signUp("설정하는 사람");

        mockMvc.perform(get("/api/push/settings").header("Authorization", bearer(me)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.enabled").value(true));
        mockMvc.perform(put("/api/push/settings").header("Authorization", bearer(me))
                        .contentType(MediaType.APPLICATION_JSON).content("{\"enabled\":false}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.enabled").value(false));
        mockMvc.perform(get("/api/push/settings").header("Authorization", bearer(me)))
                .andExpect(jsonPath("$.enabled").value(false));
        mockMvc.perform(put("/api/push/settings").header("Authorization", bearer(me))
                        .contentType(MediaType.APPLICATION_JSON).content("{}"))
                .andExpect(status().isBadRequest());
    }

    // ─────────────────────────── 방 음소거 ───────────────────────────

    @Test
    @DisplayName("PUT /api/chat/rooms/{roomId}/mute 는 멤버만 할 수 있고 방 목록에 muted 로 실린다")
    void muteRoundTrip() throws Exception {
        User owner = signUp("방장");
        User outsider = signUp("남");
        ChatRoomView room = chatRooms.openRoom("FAMILY", "mute-" + System.nanoTime(), "음소거 방", "FAMILY", owner.getId());

        mockMvc.perform(put("/api/chat/rooms/" + room.id() + "/mute").header("Authorization", bearer(owner))
                        .contentType(MediaType.APPLICATION_JSON).content("{\"muted\":true}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.roomId").value(room.id()))
                .andExpect(jsonPath("$.muted").value(true));
        mockMvc.perform(get("/api/chat/rooms").header("Authorization", bearer(owner)))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$[?(@.id == " + room.id() + ")].muted").value(true));
        mockMvc.perform(put("/api/chat/rooms/" + room.id() + "/mute").header("Authorization", bearer(owner))
                        .contentType(MediaType.APPLICATION_JSON).content("{\"muted\":false}"))
                .andExpect(jsonPath("$.muted").value(false));

        mockMvc.perform(put("/api/chat/rooms/" + room.id() + "/mute").header("Authorization", bearer(outsider))
                        .contentType(MediaType.APPLICATION_JSON).content("{\"muted\":true}"))
                .andExpect(status().isForbidden());
        mockMvc.perform(put("/api/chat/rooms/" + room.id() + "/mute").header("Authorization", bearer(owner))
                        .contentType(MediaType.APPLICATION_JSON).content("{}"))
                .andExpect(status().isBadRequest());
    }

    // ─────────────────────────── 준비물 ───────────────────────────

    private void register(User user, String token, String platform) throws Exception {
        mockMvc.perform(put("/api/push/tokens").header("Authorization", bearer(user))
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"token\":\"" + token + "\",\"platform\":\"" + platform + "\"}"))
                .andExpect(status().isNoContent());
    }

    private String bearer(User user) {
        return "Bearer " + jwtProvider.createAccessToken(user.getId(), User.ROLE_USER);
    }

    private User signUp(String nickname) {
        return consented(users.save(User.builder()
                .provider(User.PROVIDER_LOCAL)
                .role(User.ROLE_USER)
                .email("push-reg-%d-%d@example.com".formatted(System.nanoTime(), SEQUENCE.incrementAndGet()))
                .name(nickname)
                .nickname(nickname)
                .build()));
    }

    private static String token(String device) {
        return "tok-reg-" + SEQUENCE.incrementAndGet() + "-" + device;
    }
}
