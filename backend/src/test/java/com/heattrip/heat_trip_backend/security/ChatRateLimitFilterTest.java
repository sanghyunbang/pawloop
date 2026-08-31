package com.heattrip.heat_trip_backend.security;

import static org.assertj.core.api.Assertions.assertThat;

import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.servlet.FilterChain;
import java.util.List;
import org.junit.jupiter.api.AfterEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockFilterChain;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.context.SecurityContextHolder;

/**
 * 채팅 rate limit — <b>사용자 단위로 센다</b>는 것이 이 필터의 존재 이유다. (이슈 #80)
 *
 * <p>기존 {@code ApiRateLimitFilter} 는 체인 맨 앞이라 IP 로만 셀 수 있고, 그러면 가족 넷이 한
 * 공유기에서 폴링할 때 넷이 한 카운터로 합쳐진다. 이 테스트가 지키는 것은 그것이 아니라는 것이다.
 */
class ChatRateLimitFilterTest {

    private static final ObjectMapper MAPPER = new ObjectMapper();

    @AfterEach
    void clearContext() {
        SecurityContextHolder.clearContext();
    }

    private static RateLimitProperties props(int poll, int send, int join) {
        return props(poll, send, join, 10);
    }

    private static RateLimitProperties props(int poll, int send, int join, int report) {
        RateLimitProperties p = new RateLimitProperties();
        p.setEnabled(true);
        p.setWindowSeconds(3600);
        p.setChatPollMaxRequests(poll);
        p.setChatSendMaxRequests(send);
        p.setChatJoinMaxRequests(join);
        p.setChatReportMaxRequests(report);
        return p;
    }

    private static ChatRateLimitFilter filter(RateLimitProperties p) {
        return new ChatRateLimitFilter(p, MAPPER);
    }

    private static void authenticateAs(long userId) {
        // principal 의 정확한 모양은 이 필터의 관심사가 아니다. 필요한 성질은 하나뿐이다 —
        // 같은 사용자면 같고 다른 사용자면 다르다.
        SecurityContextHolder.getContext().setAuthentication(
                new UsernamePasswordAuthenticationToken(
                        "user-" + userId, null, List.of(new SimpleGrantedAuthority("ROLE_USER"))));
    }

    private static MockHttpServletRequest get(String path, String ip) {
        MockHttpServletRequest request = new MockHttpServletRequest("GET", path);
        request.setRequestURI(path);
        request.setRemoteAddr(ip);
        return request;
    }

    private static MockHttpServletRequest post(String path, String ip) {
        MockHttpServletRequest request = new MockHttpServletRequest("POST", path);
        request.setRequestURI(path);
        request.setRemoteAddr(ip);
        return request;
    }

    private static int statusAfter(ChatRateLimitFilter filter, MockHttpServletRequest request) throws Exception {
        MockHttpServletResponse response = new MockHttpServletResponse();
        FilterChain chain = new MockFilterChain();
        filter.doFilter(request, response, chain);
        return response.getStatus();
    }

    // ─────────────────────── 열쇠 ───────────────────────

    @Test
    @DisplayName("같은 IP 뒤의 두 계정이 서로의 한도를 잡아먹지 않는다 — 이 필터의 존재 이유")
    void twoAccountsBehindOneIpDoNotShareTheBudget() throws Exception {
        ChatRateLimitFilter filter = filter(props(2, 60, 10));
        String sharedIp = "203.0.113.7";

        authenticateAs(1);
        assertThat(statusAfter(filter, get("/api/chat/rooms", sharedIp))).isEqualTo(200);
        assertThat(statusAfter(filter, get("/api/chat/rooms", sharedIp))).isEqualTo(200);
        assertThat(statusAfter(filter, get("/api/chat/rooms", sharedIp)))
                .as("첫 계정은 자기 한도를 다 썼다")
                .isEqualTo(429);

        authenticateAs(2);
        assertThat(statusAfter(filter, get("/api/chat/rooms", sharedIp)))
                .as("""
                        같은 공유기 뒤의 다른 가족이다. 첫 계정이 한도를 다 썼다고 해서 이 사람이
                        막히면 안 된다 — 그게 이 필터를 따로 만든 이유다.
                        """)
                .isEqualTo(200);
    }

    @Test
    @DisplayName("인증이 없으면 IP 로 떨어진다 — 401 조차 무제한이면 안 된다")
    void unauthenticatedRequestsFallBackToIp() throws Exception {
        ChatRateLimitFilter filter = filter(props(1, 60, 10));

        assertThat(statusAfter(filter, get("/api/chat/rooms", "198.51.100.9"))).isEqualTo(200);
        assertThat(statusAfter(filter, get("/api/chat/rooms", "198.51.100.9"))).isEqualTo(429);
        assertThat(statusAfter(filter, get("/api/chat/rooms", "198.51.100.10")))
                .as("다른 IP 는 다른 카운터다")
                .isEqualTo(200);
    }

    // ─────────────────────── 버킷 ───────────────────────

    @Test
    @DisplayName("폴링과 전송은 다른 버킷이다 — 한쪽을 조일 때 다른 쪽이 함께 조여지면 안 된다")
    void pollAndSendAreSeparateBuckets() throws Exception {
        ChatRateLimitFilter filter = filter(props(1, 1, 10));
        authenticateAs(1);

        assertThat(statusAfter(filter, get("/api/chat/rooms/5/messages", "10.1.1.1"))).isEqualTo(200);
        assertThat(statusAfter(filter, get("/api/chat/rooms/5/messages", "10.1.1.1"))).isEqualTo(429);

        assertThat(statusAfter(filter, post("/api/chat/rooms/5/messages", "10.1.1.1")))
                .as("폴링 버킷이 찼다고 전송이 막히면 안 된다")
                .isEqualTo(200);
    }

    @Test
    @DisplayName("읽음 표시는 폴링 버킷이다 — 행을 만들지 않는 멱등 갱신이고 빈도가 폴링과 같다")
    void readWatermarkSharesThePollBucket() throws Exception {
        ChatRateLimitFilter filter = filter(props(1, 60, 10));
        authenticateAs(1);

        assertThat(statusAfter(filter, get("/api/chat/rooms", "10.1.1.1"))).isEqualTo(200);
        assertThat(statusAfter(filter, post("/api/chat/rooms/5/read", "10.1.1.1")))
                .as("같은 버킷을 쓴다")
                .isEqualTo(429);
    }

    @Test
    @DisplayName("초대코드 참여에 한도가 있다 — #75 가 미뤄 둔 자리이고 그동안 무제한이었다")
    void joiningByInviteCodeIsLimited() throws Exception {
        ChatRateLimitFilter filter = filter(props(120, 60, 2));
        authenticateAs(1);

        assertThat(statusAfter(filter, post("/api/chat/invites/ABC123/join", "10.1.1.1"))).isEqualTo(200);
        assertThat(statusAfter(filter, post("/api/chat/invites/ABC123/join", "10.1.1.1"))).isEqualTo(200);
        assertThat(statusAfter(filter, post("/api/chat/invites/DEF456/join", "10.1.1.1")))
                .as("코드가 달라도 같은 사람이면 같은 카운터다 — 추측을 막는 것이 목적이다")
                .isEqualTo(429);
    }

    @Test
    @DisplayName("신고에 한도가 있다 — 표에 없으면 한도가 0 이 아니라 무한이다")
    void reportingIsMetered() throws Exception {
        ChatRateLimitFilter filter = filter(props(60, 60, 10, 1));
        authenticateAs(1);

        assertThat(statusAfter(filter, post("/api/chat/rooms/5/reports", "10.1.1.1"))).isEqualTo(200);
        assertThat(statusAfter(filter, post("/api/chat/rooms/5/reports", "10.1.1.1")))
                .as("""
                        신고는 쓰기다. 한 사람이 같은 방을 계속 신고하면 운영자가 봐야 할 표가
                        그만큼 늘고, 그건 진짜 신고를 묻는 방식의 공격이 된다.
                        """)
                .isEqualTo(429);
    }

    @Test
    @DisplayName("신고와 전송은 다른 버킷이다 — 신고를 쏟아부어 말을 막을 수 없다")
    void reportingAndSendingAreSeparateBuckets() throws Exception {
        ChatRateLimitFilter filter = filter(props(60, 60, 10, 1));
        authenticateAs(1);

        assertThat(statusAfter(filter, post("/api/chat/rooms/5/reports", "10.1.1.1"))).isEqualTo(200);
        assertThat(statusAfter(filter, post("/api/chat/rooms/5/reports", "10.1.1.1"))).isEqualTo(429);

        assertThat(statusAfter(filter, post("/api/chat/rooms/5/messages", "10.1.1.1")))
                .as("신고 버킷이 찼다고 전송이 막히면 안 된다")
                .isEqualTo(200);
    }

    @Test
    @DisplayName("초대 발급은 이 필터가 세지 않는다 — 앞 필터의 group-write 가 이미 잡는다")
    void issuingAnInviteIsNotCountedHere() throws Exception {
        ChatRateLimitFilter filter = filter(props(1, 1, 1));
        authenticateAs(1);

        for (int i = 0; i < 5; i++) {
            assertThat(statusAfter(filter, post("/api/chat/rooms/5/invites", "10.1.1.1")))
                    .as("여기서 또 세면 같은 요청이 두 카운터에 들어간다 (#75 의 group-write)")
                    .isEqualTo(200);
        }
    }

    @Test
    @DisplayName("채팅이 아닌 경로는 이 필터가 건드리지 않는다")
    void nonChatPathsPassThrough() throws Exception {
        ChatRateLimitFilter filter = filter(props(1, 1, 1));
        authenticateAs(1);

        for (int i = 0; i < 5; i++) {
            assertThat(statusAfter(filter, get("/api/groups/me", "10.1.1.1"))).isEqualTo(200);
        }
    }

    // ─────────────────────── 응답 ───────────────────────

    @Test
    @DisplayName("429 본문이 error.code/message/traceId 계약을 지킨다")
    void tooManyRequestsBodyFollowsTheErrorContract() throws Exception {
        ChatRateLimitFilter filter = filter(props(1, 60, 10));
        authenticateAs(1);

        filter.doFilter(get("/api/chat/rooms", "10.1.1.1"), new MockHttpServletResponse(), new MockFilterChain());

        MockHttpServletResponse response = new MockHttpServletResponse();
        filter.doFilter(get("/api/chat/rooms", "10.1.1.1"), response, new MockFilterChain());

        assertThat(response.getStatus()).isEqualTo(429);
        assertThat(response.getHeader("Retry-After"))
                .as("표준 헤더다. 클라이언트가 언제 다시 올지 알 수 있어야 한다")
                .isNotNull();

        var body = MAPPER.readTree(response.getContentAsString(java.nio.charset.StandardCharsets.UTF_8));
        assertThat(body.has("error")).isTrue();
        assertThat(body.get("error").get("code").asText()).isEqualTo("RATE_LIMITED");
        assertThat(body.get("error").has("message")).isTrue();
        assertThat(body.get("error").has("traceId"))
                .as("조사에 필요한 것은 traceId 다. 한도 값은 싣지 않는다 — 내부 분류를 노출한다")
                .isTrue();
    }

    @Test
    @DisplayName("한도가 0 이하이면 아무것도 막지 않는다 — 끄는 방법이 있어야 한다")
    void nonPositiveLimitDisablesTheBucket() throws Exception {
        ChatRateLimitFilter filter = filter(props(0, 60, 10));
        authenticateAs(1);

        for (int i = 0; i < 5; i++) {
            assertThat(statusAfter(filter, get("/api/chat/rooms", "10.1.1.1"))).isEqualTo(200);
        }
    }
}
