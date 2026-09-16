package com.heattrip.heat_trip_backend.dog;

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
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.ResultActions;

import java.nio.charset.StandardCharsets;
import java.util.concurrent.atomic.AtomicLong;

import static org.assertj.core.api.Assertions.assertThat;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * 사진이 없어도 아이 얼굴이 갈리게 — 이슈 #585 조각 1.
 *
 * <h2>무엇을 보증하나</h2>
 *
 * <p>고른 캐릭터가 <b>서버에 남고 다시 읽힌다.</b> 기기에만 두면 같은 아이가 사람마다 다른
 * 얼굴이 되고 기기를 바꾸면 사라진다 — 아이는 집 것이다(#563).
 *
 * <p>그리고 <b>도로 물릴 수 있어야 한다.</b> {@code null} 이 "안 바꿈" 이기만 하면, 한 번
 * 고른 사람은 종류 기본 그림으로 못 돌아간다. {@code birth} 가 같은 이유로 같은 규약을 쓴다.
 */
@SpringBootTest
@AutoConfigureMockMvc
class DogCharacterIntegrationTest extends AbstractMySqlIntegrationTest {

    private static final AtomicLong SEQUENCE = new AtomicLong();

    @Autowired private MockMvc mockMvc;
    @Autowired private ObjectMapper objectMapper;
    @Autowired private UserRepository users;
    @Autowired private JWTProvider jwtProvider;

    @Test
    @DisplayName("안 고르면 비어 있다 — 옛 아이의 화면이 안 바뀐다")
    void notChosenStaysNull() throws Exception {
        String token = account();

        JsonNode dog = register(token, """
                {"name":"보리","species":"dog","size":"small"}""");

        assertThat(dog.path("character").isNull())
                .as("기본값을 서버가 지어내면, 안 고른 아이의 얼굴이 어느 날 갑자기 바뀐다")
                .isTrue();
    }

    @Test
    @DisplayName("등록할 때 고른 캐릭터가 그대로 남는다")
    void chosenAtRegistrationSticks() throws Exception {
        String token = account();

        long id = register(token, """
                {"name":"보리","species":"dog","size":"small","character":"poodle"}""")
                .path("id").asLong();

        assertThat(detail(token, id).path("character").asText()).isEqualTo("poodle");
    }

    @Test
    @DisplayName("나중에 골라도 된다 — 부분 수정으로 붙는다")
    void chosenLaterSticks() throws Exception {
        String token = account();
        long id = register(token, """
                {"name":"보리","species":"dog","size":"small"}""").path("id").asLong();

        assertThat(patchDog(token, id, """
                {"character":"hedgehog"}""").path("character").asText()).isEqualTo("hedgehog");
        assertThat(detail(token, id).path("character").asText()).isEqualTo("hedgehog");
    }

    @Test
    @DisplayName("null 을 보내면 지워진다 — 고른 캐릭터를 도로 물릴 수 있어야 한다")
    void nullClearsIt() throws Exception {
        String token = account();
        long id = register(token, """
                {"name":"보리","species":"dog","size":"small","character":"poodle"}""")
                .path("id").asLong();

        assertThat(patchDog(token, id, """
                {"character":null}""").path("character").isNull())
                .as("""
                        null 이 "안 바꿈" 이기만 하면 한 번 고른 사람은 종류 기본 그림으로 \
                        못 돌아간다 — birth 가 같은 이유로 같은 규약을 쓴다.""")
                .isTrue();
    }

    @Test
    @DisplayName("이름만 고치면 캐릭터는 그대로다 — 안 보낸 것은 안 바꾼다")
    void otherEditsKeepIt() throws Exception {
        String token = account();
        long id = register(token, """
                {"name":"보리","species":"dog","size":"small","character":"poodle"}""")
                .path("id").asLong();

        assertThat(patchDog(token, id, """
                {"name":"보리야"}""").path("character").asText()).isEqualTo("poodle");
    }

    @Test
    @DisplayName("목록 밖의 값은 400 이다 — 앱이 모르는 그림을 고르게 두지 않는다")
    void unknownCharacterIsRejected() throws Exception {
        String token = account();

        mockMvc.perform(post("/api/dogs")
                        .header("Authorization", "Bearer " + token)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"name":"보리","species":"dog","size":"small","character":"용"}"""))
                .andExpect(status().isBadRequest());

        long id = register(token, """
                {"name":"뭉치","species":"dog","size":"small"}""").path("id").asLong();
        mockMvc.perform(patch("/api/dogs/" + id)
                        .header("Authorization", "Bearer " + token)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"character":"dragon"}"""))
                .andExpect(status().isBadRequest());
    }

    @Test
    @DisplayName("캐릭터만 보내도 부분 수정이 성립한다 — 빈 본문으로 안 읽힌다")
    void characterAloneIsNotAnEmptyBody() throws Exception {
        String token = account();
        long id = register(token, """
                {"name":"보리","species":"dog","size":"small"}""").path("id").asLong();

        // isEmpty() 가 이 필드를 안 세면 400 "바꿀 것을 하나는 보내 주세요" 가 나간다.
        assertThat(patchDog(token, id, """
                {"character":"cat_face"}""").path("character").asText()).isEqualTo("cat_face");
    }

    @Test
    @DisplayName("집 아이 목록에도 실린다 — 엄마가 고른 얼굴을 아빠도 본다")
    void theHouseholdListCarriesIt() throws Exception {
        String mom = account();
        long groupId = createGroup(mom);
        long id = register(mom, """
                {"name":"보리","species":"dog","size":"small","character":"poodle"}""")
                .path("id").asLong();

        JsonNode list = body(mockMvc.perform(get("/api/groups/" + groupId + "/dogs")
                        .header("Authorization", "Bearer " + mom))
                .andExpect(status().isOk()));

        JsonNode found = null;
        for (JsonNode dog : list) {
            if (dog.path("id").asLong() == id) {
                found = dog;
            }
        }
        assertThat(found).as("집 아이 목록에 그 아이가 없다").isNotNull();
        assertThat(found.path("character").asText())
                .as("여기에 안 실으면 가족 화면만 옛 얼굴을 그린다 — 같은 아이가 화면마다 달라진다")
                .isEqualTo("poodle");
    }

    // ─────────────────────────── 지그 ───────────────────────────

    private JsonNode register(String token, String json) throws Exception {
        return body(mockMvc.perform(post("/api/dogs")
                        .header("Authorization", "Bearer " + token)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json))
                .andExpect(status().isCreated()));
    }

    private JsonNode patchDog(String token, long id, String json) throws Exception {
        return body(mockMvc.perform(patch("/api/dogs/" + id)
                        .header("Authorization", "Bearer " + token)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(json))
                .andExpect(status().isOk()));
    }

    private JsonNode detail(String token, long id) throws Exception {
        return body(mockMvc.perform(get("/api/dogs/" + id)
                        .header("Authorization", "Bearer " + token))
                .andExpect(status().isOk()));
    }

    private long createGroup(String token) throws Exception {
        return body(mockMvc.perform(post("/api/groups")
                        .header("Authorization", "Bearer " + token)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("""
                                {"name":"보리네"}"""))
                .andExpect(status().isCreated())).path("id").asLong();
    }

    private String account() {
        long serial = SEQUENCE.incrementAndGet();
        User user = users.save(User.builder()
                .provider(User.PROVIDER_LOCAL)
                .role(User.ROLE_USER)
                .email("character-%d-%d@example.com".formatted(System.nanoTime(), serial))
                .name("엄마")
                .nickname("엄마")
                .build());
        return jwtProvider.createAccessToken(user.getId(), user.getRole());
    }

    private JsonNode body(ResultActions actions) throws Exception {
        MockHttpServletResponse response = actions.andReturn().getResponse();
        return objectMapper.readTree(response.getContentAsString(StandardCharsets.UTF_8));
    }
}
