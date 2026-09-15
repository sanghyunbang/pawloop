package com.heattrip.heat_trip_backend.chatweb;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.heattrip.heat_trip_backend.OAuth.jwt.JWTProvider;
import com.heattrip.heat_trip_backend.S3.FileStorage;
import com.heattrip.heat_trip_backend.S3.StoredObject;
import com.heattrip.heat_trip_backend.S3.UploadCategory;
import com.heattrip.heat_trip_backend.S3.UploadRequest;
import com.heattrip.heat_trip_backend.S3.media.MediaObjectRepository;
import com.heattrip.heat_trip_backend.S3.media.MediaService;
import com.heattrip.heat_trip_backend.chat.ChatMessagePosted;
import com.heattrip.heat_trip_backend.chat.ChatRoomService;
import com.heattrip.heat_trip_backend.chat.ChatRoomView;
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
import org.springframework.test.context.event.ApplicationEvents;
import org.springframework.test.context.event.RecordApplicationEvents;
import org.springframework.test.web.servlet.MockMvc;
import org.springframework.test.web.servlet.ResultActions;
import org.springframework.test.web.servlet.request.MockHttpServletRequestBuilder;
import org.springframework.web.multipart.MultipartFile;

import java.nio.charset.StandardCharsets;
import java.util.UUID;
import java.util.concurrent.atomic.AtomicLong;

/**
 * 말풍선 사진 — 이슈 #452. 사진 하나에 메시지 하나이고, 사진은 메시지와 <b>한 몸</b>이다:
 * 남의 사진이면 메시지도 안 생기고(번호도 안 태운다), 메시지를 지우면 사진도 사라진다.
 *
 * <p>버킷은 가짜다({@code FileStorage} 목) — 재는 것은 S3 가 아니라 붙이기·응답·삭제의 계약이다.
 * 올리기는 {@code POST /media} 를 지나지 않고 {@link MediaService#uploadMany} 를 바로 부른다 — 업로드
 * 버킷의 한도가 분당 20 이라 {@code WalkMediaIntegrationTest}(16장) 와 같은 창에 들면 둘 중 하나가 429 로
 * 죽는다. 그 경로에 채팅만의 코드는 없다(카테고리는 enum 값 하나다).
 * 스프링 컨텍스트 설정은 {@code WalkMediaIntegrationTest} 와 같아 캐시된 것을 다시 쓴다(#21).
 */
@SpringBootTest
@AutoConfigureMockMvc
@RecordApplicationEvents
class ChatPhotoMessageIntegrationTest extends AbstractMySqlIntegrationTest {

    private static final ObjectMapper MAPPER = new ObjectMapper();
    private static final AtomicLong SEQUENCE = new AtomicLong();
    private static final String CDN = "https://cdn.test/";

    @Autowired private MockMvc mockMvc;
    @Autowired private UserRepository userRepository;
    @Autowired private JWTProvider jwtProvider;
    @Autowired private MediaObjectRepository mediaRepository;
    @Autowired private MediaService mediaService;
    @Autowired private ChatRoomService chatRooms;
    @Autowired private ApplicationEvents events;

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
    @DisplayName("CHAT_IMAGE 로 올린 사진을 mediaId 로 보내면 image 메시지가 되고, 응답 · 장 · 델타에 media 가 든다 — 행은 CHAT/message.id")
    void aPhotoMessageCarriesItsPicture() throws Exception {
        Account me = account("사진보내는사람");
        Room room = roomWith(me);
        long photo = upload(me, "a.jpg");

        JsonNode sent = body(send(me, room.id(), "{\"mediaId\":" + photo + ",\"clientMsgId\":\"photo-1\"}")
                .andExpect(status().isCreated()));

        assertThat(sent.path("contentType").asText()).isEqualTo("image");
        assertThat(sent.path("body").asText()).as("캡션이 없으면 빈 문자열 — null 이 아니다").isEmpty();
        JsonNode media = sent.path("media");
        assertThat(media.path("id").asLong()).isEqualTo(photo);
        assertThat(media.path("kind").asText()).isEqualTo("image");
        assertThat(media.path("url").asText()).startsWith(CDN + "chats/" + me.id() + "/");
        assertThat(media.path("width").asInt()).isEqualTo(1200);
        assertThat(media.path("height").asInt()).isEqualTo(1600);
        assertThat(media.path("posterUrl").isNull()).isTrue();

        JsonNode page = messages(me, room.id(), null);
        assertThat(page.path("items").get(0).path("media").path("id").asLong()).as("장(page)에도").isEqualTo(photo);
        JsonNode delta = messages(me, room.id(), 0L);
        assertThat(delta.path("items").get(0).path("media").path("id").asLong()).as("델타(afterSeq)에도").isEqualTo(photo);

        var row = mediaRepository.findById(photo).orElseThrow();
        assertThat(row.getRefType()).isEqualTo("CHAT");
        assertThat(row.getRefId()).isEqualTo(String.valueOf(sent.path("id").asLong()));
    }

    @Test
    @DisplayName("글자 메시지의 media 는 null 이고, 사진 메시지의 본문은 캡션이라 있으면 그대로 실린다")
    void textHasNoMediaAndCaptionStaysWithThePhoto() throws Exception {
        Account me = account("캡션");
        Room room = roomWith(me);
        long photo = upload(me, "c.jpg");

        JsonNode text = body(send(me, room.id(), "{\"body\":\"글자만\"}").andExpect(status().isCreated()));
        JsonNode captioned = body(send(me, room.id(),
                "{\"body\":\"공원이에요\",\"mediaId\":" + photo + ",\"contentType\":\"image\"}")
                .andExpect(status().isCreated()));

        assertThat(text.path("media").isNull()).isTrue();
        assertThat(text.path("contentType").asText()).isEqualTo("text");
        assertThat(captioned.path("body").asText()).isEqualTo("공원이에요");
        assertThat(captioned.path("media").path("id").asLong()).isEqualTo(photo);
    }

    @Test
    @DisplayName("같은 clientMsgId 로 다시 보내면 200 이고 같은 메시지 · 같은 사진이다 — 두 번 붙이지 않는다")
    void resendReturnsTheSamePhoto() throws Exception {
        Account me = account("재전송");
        Room room = roomWith(me);
        long photo = upload(me, "r.jpg");
        String payload = "{\"mediaId\":" + photo + ",\"clientMsgId\":\"again\"}";

        JsonNode first = body(send(me, room.id(), payload).andExpect(status().isCreated()));
        JsonNode again = body(send(me, room.id(), payload).andExpect(status().isOk()));

        assertThat(again.path("id").asLong()).isEqualTo(first.path("id").asLong());
        assertThat(again.path("roomSeq").asLong()).isEqualTo(first.path("roomSeq").asLong());
        assertThat(again.path("media").path("id").asLong()).isEqualTo(photo);
        assertThat(messages(me, room.id(), null).path("items")).as("메시지는 한 줄").hasSize(1);
    }

    @Test
    @DisplayName("남의 사진은 안 붙고 그때 메시지도 안 생긴다 — 400, 번호도 안 태운다(INSERT 와 붙이기가 한 트랜잭션)")
    void someoneElsesPhotoRefusesTheWholeMessage() throws Exception {
        Account owner = account("사진주인");
        Account thief = account("가져가는사람");
        Room room = roomWith(thief);
        long theirs = upload(owner, "theirs.jpg");
        long before = messages(thief, room.id(), null).path("lastSeq").asLong();

        send(thief, room.id(), "{\"mediaId\":" + theirs + ",\"clientMsgId\":\"steal\"}")
                .andExpect(status().isBadRequest());

        JsonNode page = messages(thief, room.id(), null);
        assertThat(page.path("items").size()).as("사진 없는 사진 메시지가 남지 않는다").isZero();
        assertThat(page.path("lastSeq").asLong()).as("번호도 안 태운다").isEqualTo(before);
        assertThat(mediaRepository.findById(theirs).orElseThrow().getRefType())
                .as("남의 사진은 그대로 안 붙은 채다").isNull();
    }

    @Test
    @DisplayName("사진과 종류가 어긋나면 400 — image 인데 사진이 없거나, 사진이 있는데 text. 글자 메시지의 빈 본문도 여전히 400")
    void mismatchedPhotoAndTypeAreRejected() throws Exception {
        Account me = account("어긋남");
        Room room = roomWith(me);
        long photo = upload(me, "m.jpg");

        send(me, room.id(), "{\"contentType\":\"image\"}").andExpect(status().isBadRequest());
        send(me, room.id(), "{\"body\":\"x\",\"contentType\":\"text\",\"mediaId\":" + photo + "}")
                .andExpect(status().isBadRequest());
        send(me, room.id(), "{\"body\":\"\"}").andExpect(status().isBadRequest());

        assertThat(messages(me, room.id(), null).path("items").size()).isZero();
        assertThat(mediaRepository.findById(photo).orElseThrow().getRefType())
                .as("거절된 요청은 사진을 안 붙인다").isNull();
    }

    @Test
    @DisplayName("사진 메시지를 지우면 사진 행도 사라진다 — 톰스톤의 media 는 null. 남이 지우려 하면 403 이고 사진은 그대로")
    void deletingAPhotoMessageRemovesThePicture() throws Exception {
        Account me = account("지우는사람");
        Account other = account("다른멤버");
        Room room = roomWith(me, other);
        long photo = upload(me, "gone.jpg");
        long messageId = body(send(me, room.id(), "{\"mediaId\":" + photo + "}").andExpect(status().isCreated()))
                .path("id").asLong();

        mockMvc.perform(delete("/api/chat/messages/" + messageId)
                .header("Authorization", "Bearer " + other.token())).andExpect(status().isForbidden());
        assertThat(mediaRepository.findById(photo).orElseThrow().getRefType())
                .as("남의 삭제 시도에 사진이 사라지면 안 된다").isEqualTo("CHAT");

        mockMvc.perform(delete("/api/chat/messages/" + messageId)
                .header("Authorization", "Bearer " + me.token())).andExpect(status().isNoContent());

        assertThat(mediaRepository.findById(photo)).isEmpty();
        JsonNode tombstone = messages(me, room.id(), null).path("items").get(0);
        assertThat(tombstone.path("deletedAt").isNull()).isFalse();
        assertThat(tombstone.path("media").isNull()).isTrue();
    }

    @Test
    @DisplayName("알림 미리보기 — 캡션이 없으면 '사진', 있으면 캡션이다 (#83 의 PushMessage 가 이 값을 쓴다)")
    void pushPreviewSaysPhoto() throws Exception {
        Account me = account("알림");
        Room room = roomWith(me);
        long plain = upload(me, "p1.jpg");
        long captioned = upload(me, "p2.jpg");

        send(me, room.id(), "{\"mediaId\":" + plain + "}").andExpect(status().isCreated());
        send(me, room.id(), "{\"mediaId\":" + captioned + ",\"body\":\"공원이에요\"}").andExpect(status().isCreated());

        assertThat(events.stream(ChatMessagePosted.class).map(ChatMessagePosted::preview))
                .containsExactly("사진", "공원이에요");
    }

    // ─────────────────────────── 도우미 ───────────────────────────

    /** {@code POST /media} 와 같은 서비스 호출 — CHAT_IMAGE · 1200×1600 · ready. HTTP 를 안 지나는 이유는 클래스 javadoc. */
    private long upload(Account who, String name) {
        MockMultipartFile file = new MockMultipartFile("files", name, "image/jpeg", new byte[64]);
        return mediaService.uploadMany(java.util.List.of(file), UploadCategory.CHAT_IMAGE,
                String.valueOf(who.id()), 1200, 1600).get(0).getId();
    }

    private ResultActions send(Account account, long roomId, String json) throws Exception {
        return mockMvc.perform(post("/api/chat/rooms/{roomId}/messages", roomId)
                .header("Authorization", "Bearer " + account.token())
                .contentType(MediaType.APPLICATION_JSON)
                .content(json));
    }

    private JsonNode messages(Account account, long roomId, Long afterSeq) throws Exception {
        MockHttpServletRequestBuilder request = get("/api/chat/rooms/{roomId}/messages", roomId)
                .header("Authorization", "Bearer " + account.token());
        if (afterSeq != null) {
            request = request.param("afterSeq", String.valueOf(afterSeq));
        }
        return body(mockMvc.perform(request).andExpect(status().isOk()));
    }

    private static JsonNode body(ResultActions actions) throws Exception {
        return MAPPER.readTree(actions.andReturn().getResponse().getContentAsString(StandardCharsets.UTF_8));
    }

    private record Account(long id, String token) { }

    private record Room(long id) { }

    private Account account(String nickname) {
        long serial = SEQUENCE.incrementAndGet();
        User user = userRepository.save(User.builder()
                .provider(User.PROVIDER_LOCAL)
                .role(User.ROLE_USER)
                .email("chat452-%d-%d@example.com".formatted(System.nanoTime(), serial))
                .name(nickname)
                .nickname(nickname)
                .build());
        return new Account(user.getId(), jwtProvider.createAccessToken(user.getId(), user.getRole()));
    }

    /** 방 하나와 멤버들 — 입장은 초대코드 경로(#75) 그대로, 멤버십 행을 손으로 만들지 않는다. */
    private Room roomWith(Account owner, Account... others) {
        long serial = SEQUENCE.incrementAndGet();
        ChatRoomView room = chatRooms.openRoom(
                "CHAT452_TEST", String.valueOf(serial), "방-%d".formatted(serial), "테스트", owner.id());
        for (Account other : others) {
            String code = chatRooms.issueInvite(room.id(), owner.id()).code();
            chatRooms.joinByInviteCode(code, other.id());
        }
        return new Room(room.id());
    }
}
