package com.heattrip.heat_trip_backend.dog;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.heattrip.heat_trip_backend.OAuth.jwt.JWTProvider;
import com.heattrip.heat_trip_backend.S3.FileStorage;
import com.heattrip.heat_trip_backend.S3.StoredObject;
import com.heattrip.heat_trip_backend.S3.UploadRequest;
import com.heattrip.heat_trip_backend.support.AbstractMySqlIntegrationTest;
import com.heattrip.heat_trip_backend.user.entity.User;
import com.heattrip.heat_trip_backend.user.repository.UserRepository;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.ResultActions;
import org.springframework.web.multipart.MultipartFile;

import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Collection;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicLong;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.atLeastOnce;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.multipart;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * 아이 프로필 사진 — 이슈 #448 (#451 5번의 앞 조각).
 *
 * <p>{@code POST /media}(PROFILE_IMAGE) 로 올린 미디어 id 를 {@code PUT /api/dogs/{id}/avatar} 에 붙인다.
 * {@code FileStorage} 는 목이다 — S3 는 밖이고, {@code MediaAttachmentIntegrationTest} 와 같은 목이라
 * 스프링 컨텍스트가 하나 더 뜨지 않는다(#21 §5).
 */
@SpringBootTest
@AutoConfigureMockMvc
class DogAvatarIntegrationTest extends AbstractMySqlIntegrationTest {

    private static final ObjectMapper MAPPER = new ObjectMapper();
    private static final AtomicLong ACCOUNT_SEQUENCE = new AtomicLong();
    private static final String CDN = "https://cdn.test/";

    @Autowired private MockMvc mockMvc;
    @Autowired private UserRepository userRepository;
    @Autowired private JWTProvider jwtProvider;
    @Autowired private JdbcTemplate jdbc;

    @MockitoBean
    private FileStorage storage;

    @BeforeEach
    void fakeStorage() {
        when(storage.upload(any(), any())).thenAnswer(invocation -> {
            MultipartFile file = invocation.getArgument(0);
            UploadRequest request = invocation.getArgument(1);
            String key = request.category().prefix + "/" + request.ownerId() + "/"
                    + UUID.randomUUID() + "_" + file.getOriginalFilename();
            return new StoredObject(key, CDN + key, file.getContentType(), file.getSize());
        });
        when(storage.publicUrl(anyString())).thenAnswer(invocation -> CDN + invocation.getArgument(0));
    }

    @Test
    @DisplayName("올린 사진의 id 를 붙이면 avatarUrl 이 채워지고, 목록·상세에도 같은 값이 나온다 — 행에는 키만 남는다")
    void attachesAnUploadedPhoto() throws Exception {
        Account me = account("보리아빠");
        long dogId = newDog(me, "보리");
        assertThat(body(detail(me, dogId)).path("avatarUrl").isNull()).as("아직 사진이 없다").isTrue();

        long mediaId = uploadId(me, "bori.jpg");
        JsonNode dog = body(setAvatar(me, dogId, mediaId).andExpect(status().isOk()));

        String url = dog.path("avatarUrl").asText();
        assertThat(url).startsWith(CDN + "profiles/" + me.id() + "/").endsWith("_bori.jpg");
        assertThat(body(detail(me, dogId)).path("avatarUrl").asText()).isEqualTo(url);
        assertThat(itemById(list(me), dogId).path("avatarUrl").asText()).isEqualTo(url);

        String stored = jdbc.queryForObject("select avatar from dog where id = ?", String.class, dogId);
        assertThat(stored)
                .as("행에는 objectKey 만 — 완성된 URL 을 박으면 CDN 을 옮길 때 행마다 고쳐야 한다")
                .doesNotStartWith("http")
                .isEqualTo(url.substring(CDN.length()));
        assertThat(jdbc.queryForObject("select ref_type from media_objects where id = ?", String.class, mediaId))
                .as("미디어 행이 그 아이의 것으로 붙는다 — 고아 청소가 거두지 않는다")
                .isEqualTo("DOG");
    }

    @Test
    @DisplayName("다시 붙이면 갈아 끼운다 — 옛 사진은 파일까지 지워지고, 같은 id 를 두 번 보내도 같다")
    void replacingDeletesTheOldPhoto() throws Exception {
        Account me = account("갈아끼움");
        long dogId = newDog(me, "탄");
        long first = uploadId(me, "first.jpg");
        String firstUrl = body(setAvatar(me, dogId, first).andExpect(status().isOk())).path("avatarUrl").asText();

        long second = uploadId(me, "second.jpg");
        String secondUrl = body(setAvatar(me, dogId, second).andExpect(status().isOk())).path("avatarUrl").asText();

        assertThat(secondUrl).isNotEqualTo(firstUrl).endsWith("_second.jpg");
        assertThat(jdbc.queryForObject("select count(*) from media_objects where id = ?", Integer.class, first))
                .as("옛 사진의 행은 사라진다").isZero();
        assertThat(deletedKeys()).contains(firstUrl.substring(CDN.length()));

        assertThat(body(setAvatar(me, dogId, second).andExpect(status().isOk())).path("avatarUrl").asText())
                .as("같은 id 를 다시 보내도 200 이고 그대로다 — 재시도가 안전하다")
                .isEqualTo(secondUrl);
    }

    @Test
    @DisplayName("떼면 avatarUrl 이 null 이고 파일도 지워진다 — 없는데 떼도 200")
    void removingClearsThePhoto() throws Exception {
        Account me = account("떼는사람");
        long dogId = newDog(me, "콩");
        long mediaId = uploadId(me, "kong.jpg");
        String url = body(setAvatar(me, dogId, mediaId).andExpect(status().isOk())).path("avatarUrl").asText();

        JsonNode dog = body(removeAvatar(me, dogId).andExpect(status().isOk()));

        assertThat(dog.path("avatarUrl").isNull()).isTrue();
        assertThat(jdbc.queryForObject("select avatar from dog where id = ?", String.class, dogId)).isNull();
        assertThat(deletedKeys()).contains(url.substring(CDN.length()));
        assertThat(body(removeAvatar(me, dogId).andExpect(status().isOk())).path("avatarUrl").isNull())
                .as("멱등 — 없는데 떼도 200").isTrue();
    }

    @Test
    @DisplayName("남의 미디어 · 아직 안 올라온 것 · 이미 다른 데 붙은 것은 400 이다 — 붙이기가 조건부 UPDATE 로 거른다")
    void rejectsMediaThatIsNotMineOrNotReady() throws Exception {
        Account me = account("주인");
        Account other = account("남");
        long dogId = newDog(me, "보리");

        long theirs = uploadId(other, "theirs.jpg");
        setAvatar(me, dogId, theirs).andExpect(status().isBadRequest());

        long mine = uploadId(me, "mine.jpg");
        jdbc.update("update media_objects set status = 'pending' where id = ?", mine);
        setAvatar(me, dogId, mine).andExpect(status().isBadRequest());

        long attachedElsewhere = uploadId(me, "elsewhere.jpg");
        long otherDog = newDog(me, "둘째");
        setAvatar(me, otherDog, attachedElsewhere).andExpect(status().isOk());
        setAvatar(me, dogId, attachedElsewhere)
                .andExpect(status().isBadRequest());

        assertThat(body(detail(me, dogId)).path("avatarUrl").isNull())
                .as("셋 다 거절됐으니 아이는 그대로 사진이 없다").isTrue();
    }

    @Test
    @DisplayName("남의 아이와 없는 아이는 같은 404 · 게스트는 401")
    void othersDogIsNotFoundAndGuestsAreUnauthorized() throws Exception {
        Account me = account("나");
        Account other = account("남");
        long theirDog = newDog(other, "남의개");
        long mediaId = uploadId(me, "x.jpg");

        setAvatar(me, theirDog, mediaId).andExpect(status().isNotFound());
        setAvatar(me, 987654321L, mediaId).andExpect(status().isNotFound());
        removeAvatar(me, theirDog).andExpect(status().isNotFound());

        mockMvc.perform(put("/api/dogs/{dogId}/avatar", theirDog)
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"mediaId\":" + mediaId + "}"))
                .andExpect(status().isUnauthorized());
    }

    @Test
    @DisplayName("아이를 지우면 사진도 함께 거둔다 — 되살리기가 없는 소프트 삭제라 파일을 남길 이유가 없다")
    void deletingTheDogRemovesThePhoto() throws Exception {
        Account me = account("이별");
        long dogId = newDog(me, "하늘");
        long mediaId = uploadId(me, "sky.jpg");
        String url = body(setAvatar(me, dogId, mediaId).andExpect(status().isOk())).path("avatarUrl").asText();

        mockMvc.perform(delete("/api/dogs/{dogId}", dogId)
                        .header("Authorization", "Bearer " + me.token()))
                .andExpect(status().isNoContent());

        assertThat(jdbc.queryForObject("select count(*) from media_objects where id = ?", Integer.class, mediaId))
                .isZero();
        assertThat(deletedKeys()).contains(url.substring(CDN.length()));
    }

    // ─────────────────────────── 지그 ───────────────────────────

    private ResultActions setAvatar(Account who, long dogId, long mediaId) throws Exception {
        return mockMvc.perform(put("/api/dogs/{dogId}/avatar", dogId)
                .header("Authorization", "Bearer " + who.token())
                .contentType(MediaType.APPLICATION_JSON)
                .content("{\"mediaId\":" + mediaId + "}"));
    }

    private ResultActions removeAvatar(Account who, long dogId) throws Exception {
        return mockMvc.perform(delete("/api/dogs/{dogId}/avatar", dogId)
                .header("Authorization", "Bearer " + who.token()));
    }

    private ResultActions detail(Account who, long dogId) throws Exception {
        return mockMvc.perform(get("/api/dogs/{dogId}", dogId)
                .header("Authorization", "Bearer " + who.token()));
    }

    private JsonNode list(Account who) throws Exception {
        return body(mockMvc.perform(get("/api/dogs")
                        .header("Authorization", "Bearer " + who.token()))
                .andExpect(status().isOk()));
    }

    private long newDog(Account who, String name) throws Exception {
        JsonNode created = body(mockMvc.perform(post("/api/dogs")
                        .header("Authorization", "Bearer " + who.token())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"name\":\"" + name + "\",\"species\":\"dog\",\"size\":\"small\"}"))
                .andExpect(status().isCreated()));
        return created.path("id").asLong();
    }

    private long uploadId(Account who, String name) throws Exception {
        MockMultipartFile file = new MockMultipartFile("files", name, "image/jpeg", new byte[64]);
        JsonNode uploaded = body(mockMvc.perform(multipart("/media").file(file)
                        .param("category", "PROFILE_IMAGE")
                        .param("width", "800").param("height", "800")
                        .header("Authorization", "Bearer " + who.token()))
                .andExpect(status().isOk()));
        return uploaded.get(0).path("id").asLong();
    }

    @SuppressWarnings("unchecked")
    private List<String> deletedKeys() {
        ArgumentCaptor<Collection<String>> captor = ArgumentCaptor.forClass(Collection.class);
        verify(storage, atLeastOnce()).deleteAll(captor.capture());
        List<String> all = new ArrayList<>();
        captor.getAllValues().forEach(all::addAll);
        return all;
    }

    private static JsonNode itemById(JsonNode list, long dogId) {
        for (JsonNode item : list) {
            if (item.path("id").asLong() == dogId) {
                return item;
            }
        }
        throw new AssertionError("목록에 id=" + dogId + " 이 없다");
    }

    private static JsonNode body(ResultActions actions) throws Exception {
        return MAPPER.readTree(actions.andReturn().getResponse().getContentAsString(StandardCharsets.UTF_8));
    }

    private Account account(String nickname) {
        long serial = ACCOUNT_SEQUENCE.incrementAndGet();
        User user = consented(userRepository.save(User.builder()
                .provider(User.PROVIDER_LOCAL)
                .role(User.ROLE_USER)
                .email("dogavatar-%d-%d@example.com".formatted(System.nanoTime(), serial))
                .name(nickname)
                .nickname(nickname)
                .build()));
        return new Account(user.getId(), jwtProvider.createAccessToken(user.getId(), user.getRole()));
    }

    private record Account(long id, String token) { }
}
