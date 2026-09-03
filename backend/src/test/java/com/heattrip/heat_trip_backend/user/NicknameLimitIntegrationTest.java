package com.heattrip.heat_trip_backend.user;

import com.heattrip.heat_trip_backend.support.AbstractMySqlIntegrationTest;
import com.heattrip.heat_trip_backend.user.entity.User;
import com.heattrip.heat_trip_backend.user.repository.UserRepository;
import com.heattrip.heat_trip_backend.OAuth.jwt.JWTProvider;
import com.heattrip.heat_trip_backend.support.TestProjectPaths;

import org.springframework.jdbc.core.JdbcTemplate;
import org.yaml.snakeyaml.Yaml;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.util.Map;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.ResultActions;
import org.springframework.transaction.annotation.Transactional;

import java.util.concurrent.atomic.AtomicLong;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * 닉네임 상한 — 이슈 #229.
 *
 * <h2>왜 HTTP 로 재는가</h2>
 * <p>이 버그의 정체는 <b>{@code @Size} 가 없다</b>가 아니라 <b>{@code @Valid} 가 없어서
 * 붙여도 안 걸린다</b>였다. 서비스 단위 테스트로는 그 둘을 구별할 수 없다 — 어느 쪽이든
 * 서비스는 받은 값을 그대로 저장한다. 애노테이션이 실제로 작동하는지는 요청이 컨트롤러를
 * 지나가야만 드러난다.
 *
 * <h2>왜 닉네임인가</h2>
 * <p>{@code post.handle}·{@code comment.handle}·{@code chat_message.sender_name} 이 이 값을
 * 스냅샷하고, 가족 멤버 목록과 케어 기록이 이 값을 표시한다. #170 에서 {@code post.handle}
 * 이 {@code VARCHAR(50)} 이라 51자 닉네임을 가진 사람의 <b>모든 글쓰기가 영구히 500</b> 이
 * 됐는데, 그 진짜 원인이 여기 상한이 없다는 것이었다. 좁은 컬럼을 넓히는 것은 증상을 고친
 * 것이고, 이 이슈가 원인을 고친다.
 */
@SpringBootTest
@AutoConfigureMockMvc
@Transactional
class NicknameLimitIntegrationTest extends AbstractMySqlIntegrationTest {

    private static final AtomicLong SEQUENCE = new AtomicLong();

    @Autowired MockMvc mockMvc;
    @Autowired UserRepository userRepository;
    @Autowired JWTProvider jwtProvider;
    @Autowired JdbcTemplate jdbc;

    // ─────────────────────── 가입 ───────────────────────

    @Test
    @DisplayName("상한을 넘는 닉네임으로는 가입할 수 없다 — 가입도 무방비였다")
    void signupRejectsALongNickname() throws Exception {
        signup(over(User.MAX_NICKNAME_LENGTH), "이름")
                .andExpect(status().isBadRequest());
    }

    @Test
    @DisplayName("상한 딱 맞는 닉네임은 가입된다 — 경계에서 한 칸 틀리면 20자 쓰던 사람이 막힌다")
    void signupAcceptsExactlyTheLimit() throws Exception {
        signup("가".repeat(User.MAX_NICKNAME_LENGTH), "이름")
                .andExpect(status().isCreated());
    }

    @Test
    @DisplayName("상한을 넘는 이름으로도 가입할 수 없다 — 닉네임이 비면 이름이 표시값이 된다")
    void signupRejectsALongName() throws Exception {
        signup("닉", over(User.MAX_NAME_LENGTH))
                .andExpect(status().isBadRequest());
    }

    // ─────────────────────── 프로필 수정 ───────────────────────

    @Test
    @DisplayName("상한을 넘는 닉네임으로는 프로필을 고칠 수 없다")
    void updateRejectsALongNickname() throws Exception {
        User me = existingUser("짧은닉");

        updateMe(me, "{\"nickname\":\"" + over(User.MAX_NICKNAME_LENGTH) + "\"}")
                .andExpect(status().isBadRequest());

        assertThat(userRepository.findById(me.getId()).orElseThrow().getNickname())
                .as("400 을 주고도 값이 바뀌었으면 그게 더 나쁘다")
                .isEqualTo("짧은닉");
    }

    @Test
    @DisplayName("닉네임을 안 보내는 부분 수정은 그대로 통과한다 — null 은 '안 바꿈' 이다")
    void updateWithoutNicknameStillWorks() throws Exception {
        User me = existingUser("짧은닉");

        updateMe(me, "{\"age\":30}").andExpect(status().isOk());

        assertThat(userRepository.findById(me.getId()).orElseThrow().getNickname())
                .isEqualTo("짧은닉");
    }

    @Test
    @DisplayName("이미 저장된 긴 닉네임이 있어도 다른 필드는 고칠 수 있다")
    void aUserWithAnOverLongNicknameIsNotLockedOut() throws Exception {
        // 상한이 생기기 전에 저장된 행. 여기서 막히면 그 사람은 프로필을 영영 못 고친다 —
        // #170 의 '쓰기만 죽은 상태' 와 같은 모양이다. nickname 을 안 보내면 안 걸린다.
        User me = existingUser(over(User.MAX_NICKNAME_LENGTH));

        updateMe(me, "{\"age\":31}").andExpect(status().isOk());
    }

    // ─────────────────────── 값의 출처 ───────────────────────

    @Test
    @DisplayName("계약의 maxLength 와 코드의 상수가 같은 수다 — 한쪽만 고치면 앱이 다른 수를 믿는다")
    void contractAndCodeAgreeOnTheNumber() {
        assertThat(contractMaxLength("User", "nickname")).isEqualTo(User.MAX_NICKNAME_LENGTH);
        assertThat(contractMaxLength("SignupInput", "nickname")).isEqualTo(User.MAX_NICKNAME_LENGTH);
        assertThat(contractMaxLength("UserUpdate", "nickname")).isEqualTo(User.MAX_NICKNAME_LENGTH);

        assertThat(contractMaxLength("User", "name")).isEqualTo(User.MAX_NAME_LENGTH);
        assertThat(contractMaxLength("SignupInput", "name")).isEqualTo(User.MAX_NAME_LENGTH);
        assertThat(contractMaxLength("UserUpdate", "name")).isEqualTo(User.MAX_NAME_LENGTH);
    }

    @Test
    @DisplayName("닉네임을 스냅샷하는 컬럼들이 이 상한보다 좁지 않다 — 좁으면 그 도메인의 쓰기가 죽는다")
    void snapshotColumnsAreNotNarrowerThanTheLimit() {
        // post.handle 이 VARCHAR(50) 이라 51자 닉네임이 글쓰기를 막은 것이 #170 이다.
        // 상한이 20 이 된 지금은 여유가 크지만, 상한을 올리는 날 이 단언이 먼저 걸린다.
        assertThat(columnLength("post", "handle")).isGreaterThanOrEqualTo(User.MAX_NICKNAME_LENGTH);
        assertThat(columnLength("comment", "handle")).isGreaterThanOrEqualTo(User.MAX_NICKNAME_LENGTH);
        assertThat(columnLength("chat_message", "sender_name"))
                .isGreaterThanOrEqualTo(User.MAX_NICKNAME_LENGTH);
    }

    // ─────────────────────── 도구 ───────────────────────

    private static String over(int max) {
        return "가".repeat(max + 1);
    }

    /** 계약의 {@code maxLength}. 없으면 실패한다 — 못 읽고 통과하면 아무것도 안 지킨다. */
    @SuppressWarnings("unchecked")
    private static int contractMaxLength(String schema, String property) {
        Map<String, Object> spec;
        try {
            spec = (Map<String, Object>) new Yaml().load(Files.readString(
                    TestProjectPaths.requireFile("../docs/04-api/openapi.yaml"), StandardCharsets.UTF_8));
        } catch (IOException e) {
            throw new IllegalStateException("openapi.yaml 을 읽지 못했다", e);
        }
        Map<String, Object> schemas =
                (Map<String, Object>) ((Map<String, Object>) spec.get("components")).get("schemas");
        Map<String, Object> props =
                (Map<String, Object>) ((Map<String, Object>) schemas.get(schema)).get("properties");
        Object max = ((Map<String, Object>) props.get(property)).get("maxLength");
        if (max == null) {
            throw new AssertionError(schema + "." + property + " 에 maxLength 가 없다");
        }
        return ((Number) max).intValue();
    }

    /** 실제 스키마의 컬럼 폭. 엔티티가 아니라 <b>DB 를</b> 본다. */
    private int columnLength(String table, String column) {
        Integer length = jdbc.queryForObject("""
                select character_maximum_length from information_schema.columns
                 where table_schema = database() and table_name = ? and column_name = ?
                """, Integer.class, table, column);
        if (length == null) {
            throw new AssertionError(table + "." + column + " 을 못 찾았다");
        }
        return length;
    }

    private ResultActions signup(String nickname, String name) throws Exception {
        long serial = SEQUENCE.incrementAndGet();
        String body = """
                {"email":"nick-%d-%d@example.com","password":"password123",
                 "nickname":"%s","name":"%s","agreeTos":true,"agreePrivacy":true}
                """.formatted(System.nanoTime(), serial, nickname, name);
        return mockMvc.perform(post("/auth/signup")
                .contentType(MediaType.APPLICATION_JSON)
                .content(body));
    }

    private ResultActions updateMe(User me, String body) throws Exception {
        return mockMvc.perform(put("/auth/me")
                .header("Authorization", "Bearer " + jwtProvider.createAccessToken(me.getId(), me.getRole()))
                .contentType(MediaType.APPLICATION_JSON)
                .content(body));
    }

    private User existingUser(String nickname) {
        long serial = SEQUENCE.incrementAndGet();
        return userRepository.save(User.builder()
                .provider(User.PROVIDER_LOCAL)
                .role(User.ROLE_USER)
                .email("nick-existing-%d-%d@example.com".formatted(System.nanoTime(), serial))
                .name("이름")
                .nickname(nickname)
                .build());
    }
}
