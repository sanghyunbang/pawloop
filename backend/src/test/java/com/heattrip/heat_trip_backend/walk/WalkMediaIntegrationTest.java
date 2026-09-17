package com.heattrip.heat_trip_backend.walk;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.multipart;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.heattrip.heat_trip_backend.OAuth.jwt.JWTProvider;
import com.heattrip.heat_trip_backend.S3.FileStorage;
import com.heattrip.heat_trip_backend.S3.StoredObject;
import com.heattrip.heat_trip_backend.S3.UploadRequest;
import com.heattrip.heat_trip_backend.S3.media.MediaObjectRepository;
import com.heattrip.heat_trip_backend.support.AbstractMySqlIntegrationTest;
import com.heattrip.heat_trip_backend.user.entity.User;
import com.heattrip.heat_trip_backend.user.repository.UserRepository;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.http.MediaType;
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.ResultActions;
import org.springframework.web.multipart.MultipartFile;

import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.ArrayList;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicLong;

/**
 * 산책에 붙는 사진 — 이슈 #450. 글의 사진(#429)과 같은 두 단계다: {@code POST /media}(WALK_IMAGE)
 * 로 올리고, {@code POST /api/walks} 의 {@code mediaIds} 로 붙인다.
 *
 * <p>진짜 MySQL · 진짜 JWT. S3 만 가짜다 — 파일 바이트가 어디 가는지는 이 테스트의 관심이 아니다.
 */
@SpringBootTest
@AutoConfigureMockMvc
class WalkMediaIntegrationTest extends AbstractMySqlIntegrationTest {

    private static final ObjectMapper MAPPER = new ObjectMapper();
    private static final AtomicLong ACCOUNT_SEQUENCE = new AtomicLong();
    private static final String CDN = "https://cdn.test/";

    @Autowired private MockMvc mockMvc;
    @Autowired private UserRepository userRepository;
    @Autowired private JWTProvider jwtProvider;
    @Autowired private MediaObjectRepository mediaRepository;

    @MockitoBean
    private FileStorage storage;

    @BeforeEach
    void fakeBucket() {
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
    @DisplayName("WALK_IMAGE 로 올린 사진을 mediaIds 로 붙이면 응답 · 상세 · 목록에 올린 순서로 든다 — 행은 WALK/walk.id 를 가리킨다")
    void aWalkCarriesItsPhotos() throws Exception {
        Account me = account("사진산책");
        long dogId = dog(me, "보리");
        long first = upload(me, "a.jpg");
        long second = upload(me, "b.jpg");

        JsonNode created = body(save(me, walkJson(dogId, "[" + second + "," + first + "]"))
                .andExpect(status().isCreated()));
        long walkId = created.path("id").asLong();

        assertThat(idsOf(created.path("media"))).as("올린 순서(id 순)다").containsExactly(first, second);
        JsonNode photo = created.path("media").get(0);
        assertThat(photo.path("kind").asText()).isEqualTo("image");
        assertThat(photo.path("url").asText()).startsWith(CDN + "walks/" + me.id() + "/");
        assertThat(photo.path("width").asInt()).isEqualTo(1200);
        assertThat(photo.path("height").asInt()).isEqualTo(1600);
        assertThat(photo.path("posterUrl").isNull()).isTrue();

        JsonNode detail = body(mockMvc.perform(get("/api/walks/" + walkId)
                .header("Authorization", "Bearer " + me.token())).andExpect(status().isOk()));
        assertThat(idsOf(detail.path("media"))).containsExactly(first, second);

        JsonNode page = body(mockMvc.perform(get("/api/walks")
                .header("Authorization", "Bearer " + me.token())).andExpect(status().isOk()));
        assertThat(idsOf(page.path("items").get(0).path("media"))).as("목록도 같은 사진").containsExactly(first, second);

        var row = mediaRepository.findById(first).orElseThrow();
        assertThat(row.getRefType()).isEqualTo("WALK");
        assertThat(row.getRefId()).isEqualTo(String.valueOf(walkId));
    }

    @Test
    @DisplayName("사진 없는 산책은 media 가 빈 배열이다 — null 이 아니다")
    void aWalkWithoutPhotosHasAnEmptyArray() throws Exception {
        Account me = account("맨몸산책");
        long dogId = dog(me, "보리");

        JsonNode created = body(save(me, walkJson(dogId, null)).andExpect(status().isCreated()));

        assertThat(created.path("media").isArray()).isTrue();
        assertThat(created.path("media").size()).isZero();
    }

    @Test
    @DisplayName("남의 사진은 내 산책에 안 붙고, 그때 산책도 안 생긴다 — 400")
    void someoneElsesPhotoRefusesTheWholeWalk() throws Exception {
        Account owner = account("사진주인");
        Account thief = account("가져가는사람");
        long theirs = upload(owner, "theirs.jpg");
        long dogId = dog(thief, "보리");

        save(thief, walkJson(dogId, "[" + theirs + "]")).andExpect(status().isBadRequest());

        JsonNode page = body(mockMvc.perform(get("/api/walks")
                .header("Authorization", "Bearer " + thief.token())).andExpect(status().isOk()));
        assertThat(page.path("items").size()).as("산책 행이 남지 않는다").isZero();
        assertThat(mediaRepository.findById(theirs).orElseThrow().getRefType())
                .as("남의 사진은 그대로 안 붙은 채다").isNull();
    }

    @Test
    @DisplayName("열한 장은 400 이다 — 한 산책에 열 장까지")
    void elevenPhotosAreTooMany() throws Exception {
        Account me = account("열한장");
        long dogId = dog(me, "보리");
        StringBuilder ids = new StringBuilder("[");
        for (int i = 0; i < 11; i++) {
            if (i > 0) ids.append(',');
            ids.append(upload(me, "p" + i + ".jpg"));
        }
        ids.append(']');

        save(me, walkJson(dogId, ids.toString())).andExpect(status().isBadRequest());
    }

    @Test
    @DisplayName("같은 clientWalkId 로 다시 보내면 200 이고, 처음에 붙인 사진이 그대로 온다")
    void resendKeepsThePhotos() throws Exception {
        Account me = account("재전송");
        long dogId = dog(me, "보리");
        long photo = upload(me, "one.jpg");
        String json = walkJson(dogId, "[" + photo + "]");

        JsonNode first = body(save(me, json).andExpect(status().isCreated()));
        JsonNode again = body(save(me, json).andExpect(status().isOk()));

        assertThat(again.path("id").asLong()).isEqualTo(first.path("id").asLong());
        assertThat(idsOf(again.path("media"))).containsExactly(photo);
    }

    @Test
    @DisplayName("산책을 지우면 사진 행도 사라진다 — 붙은 채 남은 파일은 아무도 못 본다")
    void deletingTheWalkRemovesItsPhotos() throws Exception {
        Account me = account("지우는사람");
        long dogId = dog(me, "보리");
        long photo = upload(me, "gone.jpg");
        long walkId = body(save(me, walkJson(dogId, "[" + photo + "]")).andExpect(status().isCreated()))
                .path("id").asLong();

        mockMvc.perform(delete("/api/walks/" + walkId)
                .header("Authorization", "Bearer " + me.token())).andExpect(status().isNoContent());

        assertThat(mediaRepository.findById(photo)).isEmpty();
    }

    // ─────────────────────────── 도우미 ───────────────────────────

    private static String walkJson(long dogId, String mediaIds) {
        String media = mediaIds == null ? "" : ",\"mediaIds\":" + mediaIds;
        return """
                {"dogId":%d,"clientWalkId":"%s","startedAt":"%s","distanceM":1200,"durationS":900%s}
                """.formatted(dogId, UUID.randomUUID(), Instant.now().minusSeconds(3600), media);
    }

    private static List<Long> idsOf(JsonNode media) {
        List<Long> ids = new ArrayList<>();
        for (JsonNode m : media) {
            ids.add(m.path("id").asLong());
        }
        return ids;
    }

    private long upload(Account who, String name) throws Exception {
        MockMultipartFile file = new MockMultipartFile("files", name, "image/jpeg", new byte[64]);
        JsonNode items = body(mockMvc.perform(multipart("/media").file(file)
                        .param("category", "WALK_IMAGE")
                        .param("width", "1200").param("height", "1600")
                        .header("Authorization", "Bearer " + who.token()))
                .andExpect(status().isOk()));
        return items.get(0).path("id").asLong();
    }

    private ResultActions save(Account account, String json) throws Exception {
        return mockMvc.perform(post("/api/walks")
                .header("Authorization", "Bearer " + account.token())
                .contentType(MediaType.APPLICATION_JSON)
                .content(json));
    }

    private long dog(Account account, String name) throws Exception {
        return body(mockMvc.perform(post("/api/dogs")
                        .header("Authorization", "Bearer " + account.token())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"name\":\"%s\",\"size\":\"small\"}".formatted(name)))
                .andExpect(status().isCreated()))
                .path("id").asLong();
    }

    private static JsonNode body(ResultActions actions) throws Exception {
        return MAPPER.readTree(actions.andReturn().getResponse().getContentAsString(StandardCharsets.UTF_8));
    }

    private Account account(String nickname) {
        long serial = ACCOUNT_SEQUENCE.incrementAndGet();
        User user = consented(userRepository.save(User.builder()
                .provider(User.PROVIDER_LOCAL)
                .role(User.ROLE_USER)
                .email("walk-media-%d-%d@example.com".formatted(System.nanoTime(), serial))
                .name(nickname)
                .nickname(nickname)
                .build()));
        return new Account(user.getId(), jwtProvider.createAccessToken(user.getId(), user.getRole()));
    }

    private record Account(long id, String token) { }
}
