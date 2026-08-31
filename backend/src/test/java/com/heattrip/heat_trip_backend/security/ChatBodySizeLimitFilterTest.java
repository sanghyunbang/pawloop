package com.heattrip.heat_trip_backend.security;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import java.io.IOException;
import java.nio.charset.StandardCharsets;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;

/**
 * 채팅 본문 크기 상한. (이슈 #129)
 *
 * <p>지키는 것은 셋이다 — <b>읽기 전에</b> 막는가, <b>헤더가 거짓일 때도</b> 막는가,
 * <b>미디어 업로드를 건드리지 않는가</b>.
 */
class ChatBodySizeLimitFilterTest {

    private static final ObjectMapper MAPPER = new ObjectMapper();
    private static final String SEND_PATH = "/api/chat/rooms/7/messages";

    private static ChatBodySizeLimitFilter filter() {
        return new ChatBodySizeLimitFilter(MAPPER);
    }

    /** 체인이 불렸는지, 그때 본문을 읽었는지 기록하는 체인. */
    private static final class RecordingChain implements FilterChain {
        boolean called;
        int bytesRead;
        IOException thrown;

        @Override
        public void doFilter(jakarta.servlet.ServletRequest request,
                             jakarta.servlet.ServletResponse response) throws IOException {
            called = true;
            // 컨트롤러가 본문을 읽는 것을 흉내 낸다. 세는 스트림은 여기서 던진다.
            try (var in = request.getInputStream()) {
                byte[] buffer = new byte[8192];
                int count;
                while ((count = in.read(buffer, 0, buffer.length)) > 0) {
                    bytesRead += count;
                }
            } catch (IOException e) {
                thrown = e;
                throw e;
            }
        }
    }

    private static MockHttpServletRequest send(byte[] body) {
        MockHttpServletRequest request = new MockHttpServletRequest("POST", SEND_PATH);
        request.setRequestURI(SEND_PATH);
        request.setContentType("application/json");
        request.setContent(body);
        return request;
    }

    /** {@code Content-Length} 를 숨기는 요청 — chunked 인코딩과 같은 상황이다. */
    private static MockHttpServletRequest sendWithoutContentLength(byte[] body) {
        MockHttpServletRequest request = new MockHttpServletRequest("POST", SEND_PATH) {
            @Override
            public long getContentLengthLong() {
                return -1;
            }

            @Override
            public int getContentLength() {
                return -1;
            }
        };
        request.setRequestURI(SEND_PATH);
        request.setContentType("application/json");
        request.setContent(body);
        return request;
    }

    private static byte[] bytes(int size) {
        byte[] body = new byte[size];
        java.util.Arrays.fill(body, (byte) 'a');
        return body;
    }

    @Test
    @DisplayName("헤더가 밝힌 크기가 상한을 넘으면 본문을 한 바이트도 안 읽고 400 이다")
    void oversizedContentLengthIsRejectedWithoutReadingTheBody() throws Exception {
        HttpServletRequest request = send(bytes(ChatBodySizeLimitFilter.MAX_REQUEST_BYTES + 1));
        MockHttpServletResponse response = new MockHttpServletResponse();
        RecordingChain chain = new RecordingChain();

        filter().doFilter(request, response, chain);

        assertThat(response.getStatus()).isEqualTo(400);
        assertThat(chain.called)
                .as("""
                        체인이 불렸다면 본문이 읽힌다. 이 필터의 존재 이유가 그것을 막는 것이다 —
                        20MB 본문을 String 으로 올린 뒤 400 을 내던 것이 404ms 였다.
                        """)
                .isFalse();
    }

    @Test
    @DisplayName("400 본문이 error.code/message/traceId 계약을 지킨다")
    void rejectionBodyFollowsTheErrorContract() throws Exception {
        MockHttpServletResponse response = new MockHttpServletResponse();

        filter().doFilter(
                send(bytes(ChatBodySizeLimitFilter.MAX_REQUEST_BYTES + 1)),
                response,
                new RecordingChain());

        var body = MAPPER.readTree(response.getContentAsString(StandardCharsets.UTF_8));
        assertThat(body.has("error")).isTrue();
        assertThat(body.get("error").get("code").asText()).isEqualTo("PAYLOAD_TOO_LARGE");
        assertThat(body.get("error").has("message")).isTrue();
        assertThat(body.get("error").has("traceId"))
                .as("조사에 필요한 것은 traceId 다. 한도 값이나 실제 크기를 싣지 않는다")
                .isTrue();
        assertThat(body.get("error").toString())
                .as("상한 숫자를 본문에 실으면 내부 분류를 알려 주는 것이다")
                .doesNotContain(String.valueOf(ChatBodySizeLimitFilter.MAX_REQUEST_BYTES));
    }

    @Test
    @DisplayName("헤더가 없어도 막힌다 — 헤더는 보내는 쪽이 적는 문자열이라 아무것도 증명하지 않는다")
    void chunkedBodyIsStillLimited() throws Exception {
        HttpServletRequest request =
                sendWithoutContentLength(bytes(ChatBodySizeLimitFilter.MAX_REQUEST_BYTES + 8192));
        RecordingChain chain = new RecordingChain();

        assertThatThrownBy(() -> filter().doFilter(request, new MockHttpServletResponse(), chain))
                .as("""
                        Content-Length 가 없으면(chunked) 첫 번째 벽이 통과된다. 그때는 실제로 읽히는
                        바이트를 세야 한다.

                        여기서 던진 IOException 은 스프링의 메시지 변환기가
                        HttpMessageNotReadableException 으로 감싸고, GlobalExceptionHandler 가 이미
                        400 계약으로 다룬다 — 새 핸들러가 필요 없다.
                        """)
                .isInstanceOf(IOException.class);

        assertThat(chain.bytesRead)
                .as("상한을 넘긴 직후 멈춰야 한다. 다 읽고 나서 던지면 막은 것이 아니다")
                .isLessThanOrEqualTo(ChatBodySizeLimitFilter.MAX_REQUEST_BYTES + 8192);
    }

    @Test
    @DisplayName("정상 크기 본문은 그대로 통과한다 — 여기서 막으면 정상 메시지가 안 간다")
    void normalBodyPassesThrough() throws Exception {
        // 컬럼 폭(65,535바이트)을 꽉 채운 메시지도 통과해야 한다. 그 판정은 validBody 의 일이다.
        HttpServletRequest request = send(bytes(70_000));
        MockHttpServletResponse response = new MockHttpServletResponse();
        RecordingChain chain = new RecordingChain();

        filter().doFilter(request, response, chain);

        assertThat(chain.called).isTrue();
        assertThat(chain.bytesRead).isEqualTo(70_000);
        assertThat(response.getStatus()).isEqualTo(200);
    }

    @Test
    @DisplayName("신고도 같은 상한을 받는다 — 사유를 자르는 것은 파싱이 끝난 뒤다")
    void reportingIsLimitedToo() throws Exception {
        MockHttpServletRequest request =
                new MockHttpServletRequest("POST", "/api/chat/rooms/5/reports");
        request.setRequestURI("/api/chat/rooms/5/reports");
        request.setContentType("application/json");
        request.setContent(bytes(20 * 1024 * 1024));
        MockHttpServletResponse response = new MockHttpServletResponse();
        RecordingChain chain = new RecordingChain();

        filter().doFilter(request, response, chain);

        assertThat(chain.called)
                .as("""
                        ChatReportService 가 사유를 500자에서 자르지만 그건 파싱이 끝난 뒤다.
                        20MB 사유를 보내면 그것을 전부 힙에 올린 뒤에 자른다 —
                        validBody 가 그랬던 것과 같은 구멍이다.
                        """)
                .isFalse();
        assertThat(response.getStatus()).isEqualTo(400);
    }

    @Test
    @DisplayName("미디어 업로드는 건드리지 않는다 — 원래 큰 파일을 받는 경로다")
    void mediaUploadIsUntouched() throws Exception {
        MockHttpServletRequest request = new MockHttpServletRequest("POST", "/media/presigned");
        request.setRequestURI("/media/presigned");
        request.setContent(bytes(ChatBodySizeLimitFilter.MAX_REQUEST_BYTES * 4));
        RecordingChain chain = new RecordingChain();

        filter().doFilter(request, new MockHttpServletResponse(), chain);

        assertThat(chain.called)
                .as("전역 상한을 걸면 아바타·사진 업로드가 깨진다")
                .isTrue();
    }

    @Test
    @DisplayName("채팅이라도 전송 경로가 아니면 건드리지 않는다")
    void otherChatPathsAreUntouched() throws Exception {
        for (String path : new String[] {
            "/api/chat/rooms",
            "/api/chat/rooms/7/read",
            "/api/chat/invites/ABC/join",
        }) {
            MockHttpServletRequest request = new MockHttpServletRequest("POST", path);
            request.setRequestURI(path);
            request.setContent(bytes(ChatBodySizeLimitFilter.MAX_REQUEST_BYTES + 1));
            RecordingChain chain = new RecordingChain();

            filter().doFilter(request, new MockHttpServletResponse(), chain);

            assertThat(chain.called).as(path).isTrue();
        }
    }

    @Test
    @DisplayName("GET 은 건드리지 않는다 — 같은 경로라도 본문이 없다")
    void getIsUntouched() throws ServletException, IOException {
        MockHttpServletRequest request = new MockHttpServletRequest("GET", SEND_PATH);
        request.setRequestURI(SEND_PATH);
        RecordingChain chain = new RecordingChain();

        filter().doFilter(request, new MockHttpServletResponse(), chain);

        assertThat(chain.called).isTrue();
    }

    @Test
    @DisplayName("상한은 컬럼 폭보다 넉넉하다 — 정상 최대 메시지가 여기서 걸리면 안 된다")
    void limitLeavesRoomForTheColumnWidth() {
        assertThat(ChatBodySizeLimitFilter.MAX_REQUEST_BYTES)
                .as("""
                        chat_message.body 는 65,535바이트다. 한글은 JSON 에서 이스케이프가 없어 그대로
                        65,535바이트이고, clientMsgId 와 키 이름을 더해도 약 66KB 다.

                        상한이 그보다 작으면 정상 최대 길이의 메시지가 이 필터에서 걸린다 —
                        그러면 validBody 의 판정이 도달하지 않는다.
                        """)
                .isGreaterThan(65_535 * 2);
    }
}
