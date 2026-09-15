package com.heattrip.heat_trip_backend.S3.media;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ArrayNode;
import com.fasterxml.jackson.databind.node.ObjectNode;
import com.heattrip.heat_trip_backend.OAuth.jwt.JWTProvider;
import com.heattrip.heat_trip_backend.S3.FileStorage;
import com.heattrip.heat_trip_backend.S3.StoredObject;
import com.heattrip.heat_trip_backend.S3.UploadCategory;
import com.heattrip.heat_trip_backend.S3.UploadRequest;
import com.heattrip.heat_trip_backend.community.repository.PostRepository;
import com.heattrip.heat_trip_backend.support.AbstractMySqlIntegrationTest;
import com.heattrip.heat_trip_backend.user.entity.User;
import com.heattrip.heat_trip_backend.user.repository.UserRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.mockito.ArgumentCaptor;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.autoconfigure.web.servlet.MultipartProperties;
import org.springframework.boot.test.autoconfigure.web.servlet.AutoConfigureMockMvc;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.dao.DataAccessException;
import org.springframework.http.MediaType;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.mock.web.MockMultipartFile;
import org.springframework.test.context.TestPropertySource;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.ResultActions;
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder;
import org.springframework.web.multipart.MultipartFile;

import java.net.URI;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Collection;
import java.util.List;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicLong;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.atLeastOnce;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.multipart;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.patch;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/**
 * 사진을 올리고 글에 붙이는 길을 <b>HTTP 로</b> 확인한다 — 이슈 #429.
 *
 * <h2>여기서 가장 중요한 것</h2>
 * <p><b>남의 사진과 이미 붙은 사진이 붙지 않는가.</b> {@code mediaIds} 는 앱이 보내는 숫자
 * 목록이라 아무 값이나 올 수 있다. 서버가 소유·미첨부를 <b>조건부 UPDATE 의 영향 행 수</b>로
 * 재지 않으면(#86 원칙 5), 남의 사진이 내 글에 붙거나 한 사진이 두 글에 붙는다. 그리고 그때
 * <b>글이 안 생겨야</b> 한다 — 사진 없는 글이 조용히 남으면 사용자는 올린 줄 안다.
 *
 * <p>그다음이 <b>글을 지우면 파일도 사라지는가</b>다. 행만 지우면 버킷에 고아가 쌓이고,
 * 그건 요금 고지서로만 보인다.
 *
 * <h2>{@code FileStorage} 를 목으로 가는 이유 — S3 는 밖이다</h2>
 * <p>진짜 {@code S3FileStorageService} 는 dev 자리표시 자격 증명으로 만들어져 {@code putObject}
 * 에서 실패한다. 테스트는 네트워크 없이 돌아야 한다(#21). 이 한 줄 때문에 스프링 컨텍스트가
 * <b>하나 늘어난다</b>(#21 §5 — {@code @MockitoBean} 은 캐시 키를 가른다). 근거: 저장소를
 * 갈아끼우는 테스트가 이것뿐이고, {@code WalkSafetyEndpointIntegrationTest} 가 같은 이유로
 * 외부 클라이언트를 목으로 간다.
 *
 * <p>{@code @Transactional} 을 안 붙인다 — 붙이기가 벌크 UPDATE 라 커밋된 상태를 봐야 한다.
 */
@SpringBootTest
@AutoConfigureMockMvc
// 업로드 버킷이 IP 당 분당 20 이다(app.security.rate-limit.upload-max-requests). 이 클래스는 한 번에
// 스무 번 넘게 올리므로 뒤의 테스트가 429 를 받는다 — 실제로 그렇게 일곱 건이 빨개졌다. 이미
// @MockitoBean 으로 컨텍스트가 갈라져 있어 여기 하나 더 붙여도 컨텍스트 수는 같다(#21 §5).
@TestPropertySource(properties = "app.security.rate-limit.upload-max-requests=10000")
class MediaAttachmentIntegrationTest extends AbstractMySqlIntegrationTest {

    private static final ObjectMapper MAPPER = new ObjectMapper();
    private static final AtomicLong ACCOUNT_SEQUENCE = new AtomicLong();
    private static final String CDN = "https://cdn.test/";
    private static final String SIGNED = "https://signed.test/";

    @Autowired private MockMvc mockMvc;
    @Autowired private UserRepository userRepository;
    @Autowired private JWTProvider jwtProvider;
    @Autowired private MediaObjectRepository mediaRepository;
    @Autowired private PostRepository postRepository;
    @Autowired private MediaService mediaService;
    @Autowired private MediaOrphanSweeper sweeper;
    @Autowired private JdbcTemplate jdbc;
    @Autowired private MultipartProperties multipartProperties;

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
        when(storage.presignedUrl(anyString(), any())).thenAnswer(invocation ->
                URI.create(SIGNED + invocation.getArgument(0)).toURL());
    }

    // ───────────── 완료 조건 1 — 폰 사진 크기가 들어온다 ─────────────

    @Test
    @DisplayName("8MB JPEG 가 200 이고, 서버의 파일 상한이 10MB 이상으로 잡혀 있다")
    void anEightMegabyteJpegIsAccepted() throws Exception {
        Account me = account("사진올리는사람");

        JsonNode item = upload(me, "boris.jpg", 8 * 1024 * 1024, 1600, 1200).get(0);

        assertThat(item.path("status").asText()).isEqualTo("ready");
        assertThat(item.path("url").asText()).startsWith(CDN + "posts/" + me.id() + "/");
        assertThat(item.path("width").asInt()).isEqualTo(1600);
        assertThat(item.path("height").asInt()).isEqualTo(1200);
        assertThat(item.path("posterUrl").isNull()).as("사진에는 썸네일이 없다").isTrue();

        // MockMvc 는 서블릿 컨테이너를 안 지나서 multipart 상한을 실제로 걸지 못한다. 설정값이
        // 파싱되어 빈에 들어갔는지까지만 잰다 — Spring 기본값(1MB)이었다면 여기서 빨간불이다.
        assertThat(multipartProperties.getMaxFileSize().toMegabytes())
                .as("Spring 기본값 1MB 는 폰 사진 한 장도 못 받는다 (#429)")
                .isGreaterThanOrEqualTo(10);
    }

    @Test
    @DisplayName("영상은 multipart 로 안 받는다 — 400. 서명 URL 로 S3 에 직접 올린다")
    void videoIsRefusedOnMultipart() throws Exception {
        Account me = account("영상올리는사람");
        MockMultipartFile clip = new MockMultipartFile("files", "walk.mp4", "video/mp4", new byte[1024]);

        mockMvc.perform(multipart("/media").file(clip)
                        .param("category", "POST_VIDEO")
                        .header("Authorization", "Bearer " + me.token()))
                .andExpect(status().isBadRequest());

        verify(storage, never()).upload(any(), any());
    }

    @Test
    @DisplayName("크기는 파일 하나에 하나다 — 여러 장에 한 쌍을 주면 400")
    void dimensionsNeedASingleFile() throws Exception {
        Account me = account("두장올리는사람");
        MockMultipartFile a = new MockMultipartFile("files", "a.jpg", "image/jpeg", new byte[16]);
        MockMultipartFile b = new MockMultipartFile("files", "b.jpg", "image/jpeg", new byte[16]);

        mockMvc.perform(multipart("/media").file(a).file(b)
                        .param("category", "POST_IMAGE")
                        .param("width", "1600").param("height", "1200")
                        .header("Authorization", "Bearer " + me.token()))
                .andExpect(status().isBadRequest());
    }

    // ───────────── 완료 조건 2 — 글이 사진을 든다 ─────────────

    @Test
    @DisplayName("mediaIds 로 만든 글은 응답·목록·상세에 사진을 올린 순서로 든다")
    void aPostCarriesItsMediaInUploadOrder() throws Exception {
        Account me = account("글쓰는사람");
        long first = uploadId(me, "first.jpg");
        long second = uploadId(me, "second.jpg");

        // 앱이 목록을 거꾸로 보내도 순서는 올린 순서다 — 순서를 앱이 정하게 두면 두 기기가 다른 순서를 만든다.
        JsonNode created = body(createPost(me, List.of(second, first)).andExpect(status().isCreated()));
        long postId = created.path("id").asLong();
        assertThat(idsOf(created.path("media"))).containsExactly(first, second);
        assertThat(created.path("media").get(0).path("kind").asText()).isEqualTo("image");
        assertThat(created.path("media").get(0).path("url").asText()).startsWith(CDN);

        JsonNode detail = body(mockMvc.perform(get("/api/community/posts/{id}", postId)
                .header("Authorization", "Bearer " + me.token())).andExpect(status().isOk()));
        assertThat(idsOf(detail.path("media"))).containsExactly(first, second);

        JsonNode feed = body(mockMvc.perform(get("/api/community/posts")
                .header("Authorization", "Bearer " + me.token())).andExpect(status().isOk()));
        JsonNode mine = null;
        for (JsonNode item : feed.path("items")) {
            if (item.path("id").asLong() == postId) {
                mine = item;
            }
        }
        assertThat(mine).as("목록에 방금 쓴 글이 있어야 한다").isNotNull();
        assertThat(idsOf(mine.path("media")))
                .as("목록은 사진을 한 번에 물어 붙인다 — 글마다 물으면 20건 조회에 쿼리가 21개다")
                .containsExactly(first, second);

        MediaObject row = mediaRepository.findById(first).orElseThrow();
        assertThat(row.getRefType()).isEqualTo("POST");
        assertThat(row.getRefId()).isEqualTo(String.valueOf(postId));
    }

    @Test
    @DisplayName("사진 없는 글은 media 가 빈 배열이다 — null 이 아니다")
    void aPostWithoutMediaSaysSo() throws Exception {
        Account me = account("글만쓰는사람");

        JsonNode created = body(createPost(me, List.of()).andExpect(status().isCreated()));

        assertThat(created.path("media").isArray()).isTrue();
        assertThat(created.path("media")).isEmpty();
    }

    // ───────────── 완료 조건 3 — 남의 것·붙은 것은 안 붙는다 ─────────────

    @Test
    @DisplayName("남의 사진은 내 글에 안 붙고, 그때 글도 안 생긴다")
    void someoneElsesMediaDoesNotAttach() throws Exception {
        Account owner = account("사진주인");
        Account thief = account("남의사진쓰는사람");
        long theirs = uploadId(owner, "theirs.jpg");
        long postsBefore = postRepository.count();

        createPost(thief, List.of(theirs)).andExpect(status().isBadRequest());

        assertThat(postRepository.count())
                .as("붙이기가 실패하면 같은 트랜잭션의 글도 되돌아가야 한다 — 사진 없는 글이 조용히 남으면 안 된다")
                .isEqualTo(postsBefore);
        assertThat(mediaRepository.findById(theirs).orElseThrow().getRefType())
                .as("남의 것은 건드리지도 않는다")
                .isNull();
    }

    @Test
    @DisplayName("이미 글에 붙은 사진은 다른 글에 못 붙는다")
    void attachedMediaCannotBeReused() throws Exception {
        Account me = account("두번쓰는사람");
        long photo = uploadId(me, "once.jpg");
        createPost(me, List.of(photo)).andExpect(status().isCreated());

        createPost(me, List.of(photo)).andExpect(status().isBadRequest());
    }

    @Test
    @DisplayName("아직 안 올라온(pending) 것은 안 붙는다")
    void pendingMediaDoesNotAttach() throws Exception {
        Account me = account("서두르는사람");
        long photo = uploadId(me, "soon.jpg");
        MediaObject row = mediaRepository.findById(photo).orElseThrow();
        row.setStatus(MediaStatus.PENDING);
        mediaRepository.save(row);

        createPost(me, List.of(photo)).andExpect(status().isBadRequest());
    }

    @Test
    @DisplayName("열한 장은 400 이다 — 한 글에 열 장까지")
    void elevenIsTooMany() throws Exception {
        Account me = account("많이올리는사람");
        List<Long> ids = new ArrayList<>();
        for (int i = 0; i < 11; i++) {
            ids.add(uploadId(me, "p" + i + ".jpg"));
        }

        createPost(me, ids).andExpect(status().isBadRequest());
    }

    // ───────────── 남의 자리 — 첨부 위조와 임의 키 서명 (#509) ─────────────

    @Test
    @DisplayName("올리면서 남의 글 id 를 실어도 그 글에 안 붙는다 — 올리기는 붙이기가 아니다")
    void uploadNeverAttachesToSomeoneElsesPost() throws Exception {
        Account owner = account("글주인");
        Account sneak = account("끼워넣는사람");
        long theirPost = body(createPost(owner, List.of()).andExpect(status().isCreated()))
                .path("id").asLong();

        MockMultipartFile file = new MockMultipartFile("files", "sneak.jpg", "image/jpeg", new byte[64]);
        JsonNode uploaded = body(mockMvc.perform(multipart("/media").file(file)
                        .param("category", "POST_IMAGE")
                        .param("refType", "POST")
                        .param("refId", String.valueOf(theirPost))
                        .header("Authorization", "Bearer " + sneak.token()))
                .andExpect(status().isOk())).get(0);

        MediaObject row = mediaRepository.findById(uploaded.path("id").asLong()).orElseThrow();
        assertThat(row.getRefType())
                .as("올리기는 참조를 안 적는다 — 붙이는 길은 MediaAttachment.attach 하나뿐이다")
                .isNull();
        assertThat(row.getRefId()).isNull();

        JsonNode detail = body(mockMvc.perform(get("/api/community/posts/{id}", theirPost)
                .header("Authorization", "Bearer " + owner.token())).andExpect(status().isOk()));
        assertThat(detail.path("media"))
                .as("남의 글의 상세에 사진이 끼어들면 글쓴이는 자기가 안 올린 사진을 자기 글에서 본다")
                .isEmpty();
    }

    @Test
    @DisplayName("서명 URL 은 내가 올린 키만 내준다 — 남의 키도, 없는 키도 404")
    void presignedSignsOnlyTheKeysIUploaded() throws Exception {
        Account owner = account("키주인");
        Account stranger = account("키를아는사람");
        String key = mediaRepository.findById(uploadId(owner, "private.jpg"))
                .orElseThrow().getObjectKey();

        JsonNode signed = body(mockMvc.perform(get("/media/presigned").param("key", key)
                .header("Authorization", "Bearer " + owner.token())).andExpect(status().isOk()));
        assertThat(signed.path("url").asText()).startsWith(SIGNED);

        mockMvc.perform(get("/media/presigned").param("key", key)
                        .header("Authorization", "Bearer " + stranger.token()))
                .andExpect(status().isNotFound());
        mockMvc.perform(get("/media/presigned")
                        .param("key", "posts/1/2026/09/there-is-no-such-object.jpg")
                        .header("Authorization", "Bearer " + owner.token()))
                .andExpect(status().isNotFound());
        mockMvc.perform(get("/media/presigned").param("key", key))
                .andExpect(status().isUnauthorized());

        // 키가 밖에 나가 있어도 서명은 주인 것 한 번뿐이다 — 서명은 서버 자격증명으로 한다.
        verify(storage, times(1)).presignedUrl(anyString(), any());
    }

    // ───────────── 완료 조건 4 — 글이 사라지면 파일도 사라진다 ─────────────

    @Test
    @DisplayName("글을 지우면 사진 행과 S3 객체가 함께 사라진다")
    void deletingThePostRemovesRowsAndFiles() throws Exception {
        Account me = account("지우는사람");
        long a = uploadId(me, "a.jpg");
        long b = uploadId(me, "b.jpg");
        String keyA = mediaRepository.findById(a).orElseThrow().getObjectKey();
        String keyB = mediaRepository.findById(b).orElseThrow().getObjectKey();
        long postId = body(createPost(me, List.of(a, b)).andExpect(status().isCreated())).path("id").asLong();

        mockMvc.perform(delete("/api/community/posts/{id}", postId)
                        .header("Authorization", "Bearer " + me.token()))
                .andExpect(status().isNoContent());

        assertThat(mediaRepository.findById(a)).isEmpty();
        assertThat(mediaRepository.findById(b)).isEmpty();
        assertThat(deletedKeys())
                .as("행만 지우면 버킷에 고아가 쌓이고 그건 요금 고지서로만 보인다")
                .contains(keyA, keyB);
    }

    // ───────────── 고치기 — 통째로 갈아 끼운다 ─────────────

    @Test
    @DisplayName("PATCH 의 mediaIds 는 통째로 갈아 끼운다 — 빠진 것은 지워지고, 안 보내면 그대로, 빈 배열이면 전부")
    void patchReplacesTheWholeSet() throws Exception {
        Account me = account("고치는사람");
        long a = uploadId(me, "a.jpg");
        long b = uploadId(me, "b.jpg");
        long c = uploadId(me, "c.jpg");
        String keyA = mediaRepository.findById(a).orElseThrow().getObjectKey();
        long postId = body(createPost(me, List.of(a, b)).andExpect(status().isCreated())).path("id").asLong();

        JsonNode replaced = body(patchPost(me, postId, "{\"mediaIds\":[" + b + "," + c + "]}")
                .andExpect(status().isOk()));
        assertThat(idsOf(replaced.path("media"))).containsExactly(b, c);
        assertThat(mediaRepository.findById(a)).as("뗀 사진은 지워진다 — 사용자가 고치기 화면에서 뗀 것이다").isEmpty();
        assertThat(deletedKeys()).contains(keyA);

        JsonNode untouched = body(patchPost(me, postId, "{\"title\":\"제목만 고침\"}")
                .andExpect(status().isOk()));
        assertThat(idsOf(untouched.path("media")))
                .as("키가 없으면 안 바꾼다 — PostPatch 의 규약이다")
                .containsExactly(b, c);

        JsonNode cleared = body(patchPost(me, postId, "{\"mediaIds\":[]}")
                .andExpect(status().isOk()));
        assertThat(cleared.path("media")).isEmpty();
        assertThat(mediaRepository.findById(b)).isEmpty();
        assertThat(mediaRepository.findById(c)).isEmpty();
    }

    @Test
    @DisplayName("고칠 때도 남의 사진은 안 붙고, 글은 그대로다")
    void patchRefusesSomeoneElsesMedia() throws Exception {
        Account me = account("고치는사람");
        Account other = account("다른사람");
        long mine = uploadId(me, "mine.jpg");
        long theirs = uploadId(other, "theirs.jpg");
        long postId = body(createPost(me, List.of(mine)).andExpect(status().isCreated())).path("id").asLong();

        patchPost(me, postId, "{\"mediaIds\":[" + mine + "," + theirs + "]}")
                .andExpect(status().isBadRequest());

        JsonNode detail = body(mockMvc.perform(get("/api/community/posts/{id}", postId)
                .header("Authorization", "Bearer " + me.token())).andExpect(status().isOk()));
        assertThat(idsOf(detail.path("media"))).as("실패한 고치기는 아무것도 안 바꾼다").containsExactly(mine);
    }

    // ───────────── 완료 조건 5 — 고아만 거둔다 ─────────────

    @Test
    @DisplayName("청소는 안 붙은 채 하루 지난 글 미디어만 거둔다 — 붙은 것과 옛 시절의 행은 그대로")
    void sweepTakesOnlyOldUnattachedPostMedia() throws Exception {
        Account me = account("올려두고간사람");
        long attached = uploadId(me, "attached.jpg");
        long orphan = uploadId(me, "orphan.jpg");
        long fresh = uploadId(me, "fresh.jpg");
        String orphanKey = mediaRepository.findById(orphan).orElseThrow().getObjectKey();
        createPost(me, List.of(attached)).andExpect(status().isCreated());
        MediaObject legacy = mediaRepository.save(MediaObject.of(UploadCategory.PROFILE_IMAGE,
                String.valueOf(me.id()), null, null, "profiles/" + me.id() + "/old.jpg", "old.jpg", "image/jpeg", 10));

        // 서른 시간 전으로 — DB 의 시계로 민다. JVM 시간대와 무관하게 "하루보다 오래" 가 성립한다.
        jdbc.update("UPDATE media_objects SET created_at = created_at - INTERVAL 30 HOUR WHERE id IN (?, ?, ?)",
                attached, orphan, legacy.getId());

        int swept = mediaService.sweepOrphans(sweeper.cutoff());

        assertThat(swept).isEqualTo(1);
        assertThat(mediaRepository.findById(orphan)).isEmpty();
        assertThat(deletedKeys()).contains(orphanKey);
        assertThat(mediaRepository.findById(attached)).as("붙은 것은 글의 것이다").isPresent();
        assertThat(mediaRepository.findById(fresh)).as("어제 안에 올린 것은 아직 쓰는 중일 수 있다").isPresent();
        assertThat(mediaRepository.findById(legacy.getId()))
                .as("감정 여행 시절의 행은 이 잡의 것이 아니다")
                .isPresent();
    }

    // ───────────── 표가 스스로 지키는 것 ─────────────

    @Test
    @DisplayName("모르는 상태는 DB 가 막는다 — 엔티티의 @Check 가 실제 DDL 이 됐다")
    void unknownStatusIsRejectedByTheDatabase() {
        assertThatThrownBy(() -> jdbc.update(
                "INSERT INTO media_objects (created_at, size, media_key, owner_id, category, status) "
                        + "VALUES (NOW(6), 1, 'posts/x/weird.jpg', '1', 'POST_IMAGE', 'done')"))
                // MySQL 의 CHECK 위반(3819)은 Spring 이 DataIntegrityViolation 으로 안 옮긴다 —
                // UncategorizedSQLException 이다. 타입보다 **제약 이름**이 증거다.
                .isInstanceOf(DataAccessException.class)
                .hasMessageContaining("ck_media_status");
    }

    // ─────────────────────────── 지그 ───────────────────────────

    private record Account(long id, String token) { }

    private Account account(String nickname) {
        long serial = ACCOUNT_SEQUENCE.incrementAndGet();
        User user = userRepository.save(User.builder()
                .provider(User.PROVIDER_LOCAL)
                .role(User.ROLE_USER)
                .email("media-%d-%d@example.com".formatted(System.nanoTime(), serial))
                .name(nickname)
                .nickname(nickname)
                .ageGroup(User.AgeGroup.OVER14)
                .build());
        return new Account(user.getId(), jwtProvider.createAccessToken(user.getId(), user.getRole()));
    }

    private JsonNode upload(Account who, String name, int bytes, Integer width, Integer height) throws Exception {
        MockMultipartFile file = new MockMultipartFile("files", name, "image/jpeg", new byte[bytes]);
        MockHttpServletRequestBuilder request = multipart("/media").file(file)
                .param("category", "POST_IMAGE")
                .header("Authorization", "Bearer " + who.token());
        if (width != null) {
            request.param("width", String.valueOf(width)).param("height", String.valueOf(height));
        }
        return body(mockMvc.perform(request).andExpect(status().isOk()));
    }

    private long uploadId(Account who, String name) throws Exception {
        return upload(who, name, 64, 1600, 1200).get(0).path("id").asLong();
    }

    private ResultActions createPost(Account who, List<Long> mediaIds) throws Exception {
        ObjectNode body = MAPPER.createObjectNode()
                .put("board", "free")
                .put("title", "보리 사진")
                .put("body", "오늘 산책하다 찍었어요");
        ArrayNode ids = body.putArray("mediaIds");
        mediaIds.forEach(ids::add);
        return mockMvc.perform(post("/api/community/posts")
                .header("Authorization", "Bearer " + who.token())
                .contentType(MediaType.APPLICATION_JSON)
                .content(body.toString()));
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
        ArgumentCaptor<Collection<String>> captor = ArgumentCaptor.forClass(Collection.class);
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
