package com.heattrip.heat_trip_backend.S3.media;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ArrayNode;
import com.fasterxml.jackson.databind.node.ObjectNode;
import com.heattrip.heat_trip_backend.OAuth.jwt.JWTProvider;
import com.heattrip.heat_trip_backend.S3.FileStorage;
import com.heattrip.heat_trip_backend.S3.PresignedUpload;
import com.heattrip.heat_trip_backend.S3.StoredObject;
import com.heattrip.heat_trip_backend.S3.UploadCategory;
import com.heattrip.heat_trip_backend.S3.UploadRequest;
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
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.ResultActions;
import org.springframework.transaction.support.TransactionSynchronizationManager;
import org.springframework.web.multipart.MultipartFile;


import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Collection;
import java.util.List;
import java.util.Map;
import java.util.Optional;
import java.util.UUID;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicBoolean;
import java.util.concurrent.atomic.AtomicLong;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.argThat;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.atLeastOnce;
import static org.mockito.Mockito.doAnswer;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.multipart;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * 영상의 세 단계를 <b>HTTP 로</b> 확인한다 — 이슈 #429.
 *
 * <h2>여기서 가장 중요한 것</h2>
 * <p><b>"올렸다" 는 앱의 말이 아니라 S3 의 답으로 {@code ready} 가 되는가.</b> 서명 PUT 은 크기
 * 조건을 못 걸어서, 앱이 10MB 라 하고 140MB 를 올려도 S3 는 받는다. 서버가 HEAD 로 실제 크기를
 * 재지 않으면 알린 것과 다른 파일이 {@code ready} 가 되고, 아무것도 안 올린 채 {@code complete}
 * 만 불러도 {@code ready} 가 된다 — 그러면 피드에 깨진 영상이 뜬다.
 *
 * <p>그다음이 <b>한 글에 영상 하나</b>다. 이슈가 정한 한도이고, 앱이 아니라 서버가 지켜야 두
 * 기기가 다른 규칙을 갖지 않는다.
 *
 * <h2>{@code FileStorage} 목 — 사진 테스트와 같은 컨텍스트</h2>
 * <p>{@code MediaAttachmentIntegrationTest} 와 애너테이션이 <b>같다</b>(같은 목, 같은 프로퍼티).
 * 그래야 스프링 컨텍스트가 하나 더 뜨지 않는다(#21 §5). 목 버킷은 맵 하나다 — 서명 PUT 이 만든
 * 키를 기억해 두고, 테스트가 "올라왔다" 고 넣어 준 키만 HEAD 에 답한다.
 *
 * <p>{@code @Transactional} 을 안 붙인다 — 붙이기가 벌크 UPDATE 라 커밋된 상태를 봐야 한다.
 */
@SpringBootTest
@AutoConfigureMockMvc
@TestPropertySource(properties = "app.security.rate-limit.upload-max-requests=10000")
class VideoUploadIntegrationTest extends AbstractMySqlIntegrationTest {

    private static final ObjectMapper MAPPER = new ObjectMapper();
    private static final AtomicLong ACCOUNT_SEQUENCE = new AtomicLong();
    private static final String CDN = "https://cdn.test/";
    private static final String PUT_BASE = "https://bucket.test/";

    private static final String MP4 = "video/mp4";
    private static final long CLIP_BYTES = 5_000_000L;
    private static final int CLIP_MS = 12_000;

    @Autowired private MockMvc mockMvc;
    @Autowired private UserRepository userRepository;
    @Autowired private JWTProvider jwtProvider;
    @Autowired private MediaObjectRepository mediaRepository;
    @Autowired private MediaService mediaService;
    @Autowired private MediaOrphanSweeper sweeper;
    @Autowired private JdbcTemplate jdbc;

    @MockitoBean
    private FileStorage storage;

    /** 목 버킷 — "올라왔다" 고 넣어 준 키만 HEAD 에 답한다. */
    private final Map<String, StoredObject> bucket = new ConcurrentHashMap<>();

    @BeforeEach
    void fakeBucket() {
        bucket.clear();
        when(storage.presignedPut(any(), anyString(), anyString(), any())).thenAnswer(invocation -> {
            UploadRequest request = invocation.getArgument(0);
            String fileName = invocation.getArgument(1);
            String key = request.category().prefix + "/" + request.ownerId() + "/"
                    + UUID.randomUUID() + "_" + fileName;
            return new PresignedUpload(key, java.net.URI.create(PUT_BASE + key + "?X-Amz-Signature=fake").toURL());
        });
        when(storage.stat(anyString()))
                .thenAnswer(invocation -> Optional.ofNullable(bucket.get(invocation.<String>getArgument(0))));
        when(storage.upload(any(), any())).thenAnswer(invocation -> {
            MultipartFile file = invocation.getArgument(0);
            UploadRequest request = invocation.getArgument(1);
            String sub = request.subPath() == null ? "" : request.subPath() + "/";
            String key = request.category().prefix + "/" + request.ownerId() + "/" + sub
                    + UUID.randomUUID() + "_" + file.getOriginalFilename();
            return new StoredObject(key, CDN + key, file.getContentType(), file.getSize());
        });
        when(storage.publicUrl(anyString())).thenAnswer(invocation -> CDN + invocation.getArgument(0));
    }

    // ───────────── ① 자리 잡기 ─────────────

    @Test
    @DisplayName("자리를 잡으면 201 에 id·key·uploadUrl 이 오고, 행은 pending 이며 15분짜리 서명 PUT 이 나갔다")
    void reservingGivesATicketAndAPendingRow() throws Exception {
        Account me = account("영상올리는사람");

        JsonNode ticket = body(reserve(me, MP4, CLIP_BYTES, CLIP_MS).andExpect(status().isCreated()));

        assertThat(ticket.path("key").asText())
                .startsWith("posts-video/" + me.id() + "/")
                .endsWith(".mp4");
        assertThat(ticket.path("uploadUrl").asText()).startsWith(PUT_BASE);

        MediaObject row = mediaRepository.findById(ticket.path("id").asLong()).orElseThrow();
        assertThat(row.getStatus()).as("파일이 아직 없다 — ready 면 안 올린 영상이 글에 붙는다").isEqualTo(MediaStatus.PENDING);
        assertThat(row.getCategory()).isEqualTo(UploadCategory.POST_VIDEO);
        assertThat(row.getSize()).as("알린 크기를 기억해야 ③ 에서 실제 크기와 대조한다").isEqualTo(CLIP_BYTES);
        assertThat(row.getDurationMs()).isEqualTo(CLIP_MS);
        assertThat(row.getWidth()).isEqualTo(1280);
        assertThat(row.getRefType()).isNull();

        verify(storage).presignedPut(any(), anyString(), eq(MP4), eq(MediaService.VIDEO_UPLOAD_TTL));
    }

    @Test
    @DisplayName("mp4·mov 가 아니면 400 이고 행이 안 생긴다")
    void refusesWhatIsNotAVideo() throws Exception {
        Account me = account("avi올리는사람");
        long before = mediaRepository.count();

        reserve(me, "video/x-msvideo", CLIP_BYTES, CLIP_MS).andExpect(status().isBadRequest());

        assertThat(mediaRepository.count()).isEqualTo(before);
        verify(storage, never()).presignedPut(any(), anyString(), anyString(), any());
    }

    @Test
    @DisplayName("60초를 넘거나 150MB 를 넘으면 400")
    void refusesTooLongOrTooBig() throws Exception {
        Account me = account("긴영상올리는사람");

        reserve(me, MP4, CLIP_BYTES, 61_000).andExpect(status().isBadRequest());
        reserve(me, MP4, 151L * 1024 * 1024, CLIP_MS).andExpect(status().isBadRequest());

        verify(storage, never()).presignedPut(any(), anyString(), anyString(), any());
    }

    // ───────────── ③ 끝내기 — S3 의 답이 정한다 ─────────────

    @Test
    @DisplayName("S3 에 아직 없으면 409 이고 pending 으로 남는다 — 포스터도 안 올린다")
    void completingBeforeTheFileArrivedIs409() throws Exception {
        Account me = account("서두르는사람");
        long id = reservedId(me);

        complete(me, id, poster()).andExpect(status().isConflict());

        MediaObject row = mediaRepository.findById(id).orElseThrow();
        assertThat(row.getStatus()).isEqualTo(MediaStatus.PENDING);
        assertThat(row.getPosterKey()).isNull();
        verify(storage, never()).upload(any(), any());
    }

    @Test
    @DisplayName("끝내기는 트랜잭션 밖에서 S3 를 부른다 — HEAD 와 포스터 업로드가 커넥션을 쥐지 않는다 (#512)")
    void completingDoesNotHoldADatabaseConnection() throws Exception {
        Account me = account("영상끝내는사람");
        JsonNode ticket = body(reserve(me, MP4, CLIP_BYTES, CLIP_MS).andExpect(status().isCreated()));
        landsInBucket(ticket.path("key").asText(), CLIP_BYTES, MP4);
        AtomicBoolean insideTransaction = new AtomicBoolean(true);
        // when(...) 이 아니라 doAnswer(...) 다 — when 은 그 자리에서 목을 부른다.
        doAnswer(invocation -> {
            insideTransaction.set(TransactionSynchronizationManager.isActualTransactionActive());
            return Optional.ofNullable(bucket.get(invocation.<String>getArgument(0)));
        }).when(storage).stat(anyString());

        complete(me, ticket.path("id").asLong(), poster()).andExpect(status().isOk());

        assertThat(insideTransaction.get())
                .as("밖으로 나가는 호출이 커넥션을 쥐고 있으면 풀이 그만큼 좁아진다")
                .isFalse();
    }

    @Test
    @DisplayName("HEAD 가 알린 크기로 답하면 ready 가 되고 포스터가 붙고, 그 영상은 글에 붙어 video 로 그려진다")
    void completingConfirmsWithHeadAndThenItAttaches() throws Exception {
        Account me = account("영상글쓰는사람");
        JsonNode ticket = body(reserve(me, MP4, CLIP_BYTES, CLIP_MS).andExpect(status().isCreated()));
        long id = ticket.path("id").asLong();
        landsInBucket(ticket.path("key").asText(), CLIP_BYTES, MP4);

        JsonNode item = body(complete(me, id, poster()).andExpect(status().isOk()));

        assertThat(item.path("status").asText()).isEqualTo("ready");
        assertThat(item.path("category").asText()).isEqualTo("POST_VIDEO");
        assertThat(item.path("posterUrl").asText()).startsWith(CDN + "posts/" + me.id() + "/posters/");
        assertThat(item.path("durationMs").asInt()).isEqualTo(CLIP_MS);
        verify(storage).upload(any(), argThat((UploadRequest request) ->
                request.category() == UploadCategory.POST_IMAGE
                        && MediaService.POSTER_SUB_PATH.equals(request.subPath())));

        JsonNode created = body(createPost(me, List.of(id)).andExpect(status().isCreated()));
        JsonNode media = created.path("media").get(0);
        assertThat(media.path("kind").asText()).isEqualTo("video");
        assertThat(media.path("posterUrl").asText()).as("피드는 포스터와 재생 표시만 그린다").startsWith(CDN);
        assertThat(media.path("durationMs").asInt()).isEqualTo(CLIP_MS);
        assertThat(media.path("width").asInt()).isEqualTo(1280);
    }

    @Test
    @DisplayName("올라온 크기가 알린 것과 다르면 400 이고 pending 으로 남는다 — 다른 파일이다")
    void completingWithADifferentSizeIs400() throws Exception {
        Account me = account("다른파일올린사람");
        JsonNode ticket = body(reserve(me, MP4, CLIP_BYTES, CLIP_MS).andExpect(status().isCreated()));
        long id = ticket.path("id").asLong();
        landsInBucket(ticket.path("key").asText(), CLIP_BYTES + 1, MP4);

        complete(me, id, poster()).andExpect(status().isBadRequest());

        assertThat(mediaRepository.findById(id).orElseThrow().getStatus()).isEqualTo(MediaStatus.PENDING);
        verify(storage, never()).upload(any(), any());
    }

    @Test
    @DisplayName("남의 영상은 404 다 — 없는 것과 구별해 주지 않는다")
    void completingSomeoneElsesIs404() throws Exception {
        Account owner = account("영상주인");
        Account other = account("남의영상끝내는사람");
        JsonNode ticket = body(reserve(owner, MP4, CLIP_BYTES, CLIP_MS).andExpect(status().isCreated()));
        landsInBucket(ticket.path("key").asText(), CLIP_BYTES, MP4);

        complete(other, ticket.path("id").asLong(), poster()).andExpect(status().isNotFound());

        assertThat(mediaRepository.findById(ticket.path("id").asLong()).orElseThrow().getStatus())
                .isEqualTo(MediaStatus.PENDING);
    }

    @Test
    @DisplayName("사진에는 이 단계가 없다 — 400")
    void completingAPhotoIs400() throws Exception {
        Account me = account("사진끝내는사람");
        long photo = uploadPhotoId(me, "already.jpg");

        complete(me, photo, poster()).andExpect(status().isBadRequest());
    }

    @Test
    @DisplayName("두 번 불러도 같다 — 이미 ready 면 그대로 돌려주고 둘째 포스터는 안 받는다")
    void completingTwiceIsTheSame() throws Exception {
        Account me = account("두번부르는사람");
        JsonNode ticket = body(reserve(me, MP4, CLIP_BYTES, CLIP_MS).andExpect(status().isCreated()));
        long id = ticket.path("id").asLong();
        landsInBucket(ticket.path("key").asText(), CLIP_BYTES, MP4);
        String firstPoster = body(complete(me, id, poster()).andExpect(status().isOk())).path("posterUrl").asText();

        JsonNode again = body(complete(me, id, poster("second.jpg")).andExpect(status().isOk()));

        assertThat(again.path("posterUrl").asText())
                .as("첫 포스터가 이미 글에 그려지고 있을 수 있다 — 바꾸지 않는다")
                .isEqualTo(firstPoster);
        verify(storage, times(1)).upload(any(), any());
    }

    @Test
    @DisplayName("포스터가 사진이 아니면 400 — HEAD 를 부르기 전에 거른다")
    void posterMustBeAnImage() throws Exception {
        Account me = account("포스터잘못준사람");
        JsonNode ticket = body(reserve(me, MP4, CLIP_BYTES, CLIP_MS).andExpect(status().isCreated()));
        long id = ticket.path("id").asLong();
        landsInBucket(ticket.path("key").asText(), CLIP_BYTES, MP4);

        MockMultipartFile notAnImage = new MockMultipartFile("poster", "poster.mp4", MP4, new byte[512]);
        complete(me, id, notAnImage).andExpect(status().isBadRequest());

        assertThat(mediaRepository.findById(id).orElseThrow().getStatus()).isEqualTo(MediaStatus.PENDING);
        verify(storage, never()).stat(anyString());
        verify(storage, never()).upload(any(), any());
    }

    // ───────────── 한 글에 영상 하나 ─────────────

    @Test
    @DisplayName("한 글에 영상 둘은 400 이고, 영상 하나에 사진은 된다")
    void onlyOneVideoPerPost() throws Exception {
        Account me = account("영상둘붙이는사람");
        long first = readyVideoId(me);
        long second = readyVideoId(me);
        long photo = uploadPhotoId(me, "with.jpg");

        createPost(me, List.of(first, second)).andExpect(status().isBadRequest());
        assertThat(mediaRepository.findById(first).orElseThrow().getRefType())
                .as("거절이면 아무것도 안 붙는다")
                .isNull();

        JsonNode created = body(createPost(me, List.of(first, photo)).andExpect(status().isCreated()));
        assertThat(created.path("media")).hasSize(2);
    }

    @Test
    @DisplayName("고치기로 둘째 영상을 얹는 것도 400 이고, 글은 그대로다")
    void patchCannotAddASecondVideo() throws Exception {
        Account me = account("고치며얹는사람");
        long first = readyVideoId(me);
        long postId = body(createPost(me, List.of(first)).andExpect(status().isCreated())).path("id").asLong();
        long second = readyVideoId(me);

        patchPost(me, postId, "{\"mediaIds\":[" + first + "," + second + "]}").andExpect(status().isBadRequest());

        JsonNode detail = body(mockMvc.perform(get("/api/community/posts/{id}", postId)
                .header("Authorization", "Bearer " + me.token())).andExpect(status().isOk()));
        assertThat(idsOf(detail.path("media"))).containsExactly(first);
    }

    // ───────────── 고치기가 실패하면 파일도 그대로다 ─────────────

    @Test
    @DisplayName("고치기가 거절되면 뗀 사진의 파일도 그대로다 — 붙이기가 먼저고 지우기는 나중이다")
    void aRefusedPatchDeletesNothing() throws Exception {
        Account me = account("고치다실패하는사람");
        Account other = account("사진주인");
        long mine = uploadPhotoId(me, "mine.jpg");
        long theirs = uploadPhotoId(other, "theirs.jpg");
        String mineKey = mediaRepository.findById(mine).orElseThrow().getObjectKey();
        long postId = body(createPost(me, List.of(mine)).andExpect(status().isCreated())).path("id").asLong();

        // 내 것을 떼고 남의 것을 붙이는 고치기 — 붙이기가 거절된다
        patchPost(me, postId, "{\"mediaIds\":[" + theirs + "]}").andExpect(status().isBadRequest());

        verify(storage, never()).deleteAll(argThat((Collection<String> keys) -> keys.contains(mineKey)));
        JsonNode detail = body(mockMvc.perform(get("/api/community/posts/{id}", postId)
                .header("Authorization", "Bearer " + me.token())).andExpect(status().isOk()));
        assertThat(idsOf(detail.path("media")))
                .as("DB 는 되돌아가는데 S3 는 트랜잭션 밖이다 — 먼저 지우면 뗀 적 없는 사진이 화면에서 깨진다")
                .containsExactly(mine);
    }

    // ───────────── 청소는 pending 도 거둔다 ─────────────

    @Test
    @DisplayName("자리만 잡고 하루 지난 영상은 청소가 거둔다 — S3 키까지")
    void sweepTakesAnOldPendingVideo() throws Exception {
        Account me = account("자리만잡은사람");
        JsonNode ticket = body(reserve(me, MP4, CLIP_BYTES, CLIP_MS).andExpect(status().isCreated()));
        long id = ticket.path("id").asLong();
        String key = ticket.path("key").asText();
        jdbc.update("UPDATE media_objects SET created_at = created_at - INTERVAL 30 HOUR WHERE id = ?", id);

        int swept = mediaService.sweepOrphans(sweeper.cutoff());

        assertThat(swept).isGreaterThanOrEqualTo(1);
        assertThat(mediaRepository.findById(id)).isEmpty();
        assertThat(deletedKeys())
                .as("객체가 있든 없든 deleteObjects 는 성공을 준다 — 키를 넘겨야 있던 것이 지워진다")
                .contains(key);
    }

    // ─────────────────────────── 지그 ───────────────────────────

    private record Account(long id, String token) { }

    private Account account(String nickname) {
        long serial = ACCOUNT_SEQUENCE.incrementAndGet();
        User user = consented(userRepository.save(User.builder()
                .provider(User.PROVIDER_LOCAL)
                .role(User.ROLE_USER)
                .email("video-%d-%d@example.com".formatted(System.nanoTime(), serial))
                .name(nickname)
                .nickname(nickname)
                .ageGroup(User.AgeGroup.OVER14)
                .build()));
        return new Account(user.getId(), jwtProvider.createAccessToken(user.getId(), user.getRole()));
    }

    private ResultActions reserve(Account who, String contentType, long size, int durationMs) throws Exception {
        ObjectNode json = MAPPER.createObjectNode()
                .put("contentType", contentType)
                .put("size", size)
                .put("width", 1280)
                .put("height", 720)
                .put("durationMs", durationMs);
        return mockMvc.perform(post("/media/videos")
                .header("Authorization", "Bearer " + who.token())
                .contentType(MediaType.APPLICATION_JSON)
                .content(json.toString()));
    }

    private long reservedId(Account who) throws Exception {
        return body(reserve(who, MP4, CLIP_BYTES, CLIP_MS).andExpect(status().isCreated())).path("id").asLong();
    }

    /** 앱이 서명 PUT 으로 올린 셈 친다 — 이 키는 이제 HEAD 에 답한다. */
    private void landsInBucket(String key, long size, String contentType) {
        bucket.put(key, new StoredObject(key, CDN + key, contentType, size));
    }

    private ResultActions complete(Account who, long mediaId, MockMultipartFile poster) throws Exception {
        return mockMvc.perform(multipart("/media/{mediaId}/complete", mediaId)
                .file(poster)
                .header("Authorization", "Bearer " + who.token()));
    }

    private long readyVideoId(Account who) throws Exception {
        JsonNode ticket = body(reserve(who, MP4, CLIP_BYTES, CLIP_MS).andExpect(status().isCreated()));
        long id = ticket.path("id").asLong();
        landsInBucket(ticket.path("key").asText(), CLIP_BYTES, MP4);
        complete(who, id, poster()).andExpect(status().isOk());
        return id;
    }

    private static MockMultipartFile poster() {
        return poster("poster.jpg");
    }

    private static MockMultipartFile poster(String name) {
        return new MockMultipartFile("poster", name, "image/jpeg", new byte[2048]);
    }

    private long uploadPhotoId(Account who, String name) throws Exception {
        MockMultipartFile file = new MockMultipartFile("files", name, "image/jpeg", new byte[64]);
        JsonNode items = body(mockMvc.perform(multipart("/media").file(file)
                .param("category", "POST_IMAGE")
                .param("width", "1600").param("height", "1200")
                .header("Authorization", "Bearer " + who.token())).andExpect(status().isOk()));
        return items.get(0).path("id").asLong();
    }

    private ResultActions createPost(Account who, List<Long> mediaIds) throws Exception {
        ObjectNode json = MAPPER.createObjectNode()
                .put("board", "free")
                .put("title", "보리 산책 영상")
                .put("body", "오늘 산책하다 찍었어요");
        ArrayNode ids = json.putArray("mediaIds");
        mediaIds.forEach(ids::add);
        return mockMvc.perform(post("/api/community/posts")
                .header("Authorization", "Bearer " + who.token())
                .contentType(MediaType.APPLICATION_JSON)
                .content(json.toString()));
    }

    private ResultActions patchPost(Account who, long postId, String json) throws Exception {
        return mockMvc.perform(patch("/api/community/posts/{id}", postId)
                .header("Authorization", "Bearer " + who.token())
                .contentType(MediaType.APPLICATION_JSON)
                .content(json));
    }

    /** 목 저장소에 지워 달라고 넘긴 키 전부. 호출이 여러 번이면 합친다. */
    @SuppressWarnings("unchecked")
    private List<String> deletedKeys() {
        org.mockito.ArgumentCaptor<Collection<String>> captor =
                org.mockito.ArgumentCaptor.forClass(Collection.class);
        verify(storage, atLeastOnce()).deleteAll(captor.capture());
        List<String> all = new ArrayList<>();
        captor.getAllValues().forEach(all::addAll);
        return all;
    }

    private static List<Long> idsOf(JsonNode array) {
        List<Long> ids = new ArrayList<>();
        array.forEach(node -> ids.add(node.path("id").asLong()));
        return ids;
    }

    private static JsonNode body(ResultActions actions) throws Exception {
        return MAPPER.readTree(actions.andReturn().getResponse().getContentAsString(StandardCharsets.UTF_8));
    }
}
