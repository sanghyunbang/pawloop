package com.heattrip.heat_trip_backend.security;

import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import java.io.IOException;
import java.time.Instant;
import org.springframework.security.core.Authentication;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

/**
 * 채팅 경로의 rate limit. <b>사용자 단위로 센다.</b> (이슈 #80)
 *
 * <h2>왜 필터가 둘인가</h2>
 * <p>{@link ApiRateLimitFilter} 는 체인 <b>맨 앞</b>에 있다. 그 자리는 #14 가 정한 것이고
 * 되돌리면 소셜 진입점이 다시 무제한이 된다 — 리다이렉트 필터가 302 를 쓰고 체인을 끊어서
 * 뒤에 있는 필터까지 요청이 오지 않기 때문이다. {@code ApiRateLimitFilterChainOrderIntegrationTest}
 * 가 그 순서를 지킨다.
 *
 * <p>그런데 맨 앞이라는 것은 <b>인증이 아직 안 끝났다</b>는 뜻이고, 그래서 그 필터는 IP 로만
 * 셀 수 있다. 채팅에서는 그게 문제가 된다.
 *
 * <blockquote>
 * 가족 넷이 한 집 공유기에서 동시에 폴링하면 넷이 한 카운터로 합쳐진다.
 * <b>가족 단위 서비스에서 실제로 일어난다.</b>
 * </blockquote>
 *
 * <p>이건 공유 저장소로 풀 문제가 아니라 <b>열쇠를 고칠 문제</b>다. 그래서 채팅 버킷만
 * {@code JWTAuthenticationFilter} <b>뒤</b>에 두고 인증 주체로 센다.
 *
 * <h2>열쇠를 어떻게 얻는가</h2>
 * <p>{@code Authentication#getName()} 하나만 쓴다. 도메인 타입을 import 하지 않는다 —
 * {@code OAuth.principal.AuthenticatedUser} 를 직접 부르면 {@code security -> OAuth} 간선이
 * 새로 생기고, 그건 #106 이 방금 끊은 방향이다.
 *
 * <p>그 문자열이 정확히 무엇인지는 <b>중요하지 않다.</b> 필요한 성질은 하나뿐이다 —
 * <b>같은 사용자면 같고 다른 사용자면 다르다.</b> 지금은 principal 인 record 의
 * {@code toString()} 이라 {@code AuthenticatedUser[id=7, role=ROLE_USER]} 같은 모양이고,
 * 그 모양이 바뀌어도 카운터가 한 번 리셋될 뿐 정확성은 그대로다.
 *
 * <p>인증이 없으면 IP 로 떨어진다. 채팅 경로는 전부 인증이 필요하므로 그런 요청은 곧 401 이
 * 되지만, 그 401 조차 무제한이면 안 된다.
 *
 * <h2>한도의 근거</h2>
 * <p>#81 이 정한 폴링 정책이 <b>방을 보는 중 3초 / 백그라운드 30초 / 빈 응답이 이어지면
 * 단계적 증가</b> 다. 3초면 스트림 하나당 분당 20회이고, 방 목록과 메시지를 함께 보면 40회다.
 * 화면 전환과 포그라운드 복귀의 즉시 1회를 더해도 분당 60회를 넘기 어렵다.
 *
 * <p>그래서 폴링은 <b>분당 120</b> — 정상 사용자의 두 배다. 사용자 단위라 가족 수와 무관하다.
 *
 * <p>전송은 <b>분당 60</b>. 사람이 1초에 한 번씩 1분 내내 보내는 것이 상한이고, 실제로는
 * 그보다 훨씬 적다. 이 숫자가 막는 것은 사람이 아니라 스크립트다.
 *
 * <p>참여는 <b>분당 10</b>. 사람이 방에 들어가는 것은 한 번이면 된다. 초대코드가 50비트라
 * 추측이 현실적이지 않지만({@code InviteCodeGenerator}), 그 하나에만 기대지 않는다.
 */
@Component
public class ChatRateLimitFilter extends OncePerRequestFilter {

    private record Rule(String bucket, int limit) {}

    private final RateLimitProperties rateLimitProperties;
    private final ErrorBodyWriter errors;
    private final ClientIpResolver clientIp;
    private final RateLimitWindow window = new RateLimitWindow();

    public ChatRateLimitFilter(RateLimitProperties rateLimitProperties, ObjectMapper objectMapper) {
        this.rateLimitProperties = rateLimitProperties;
        this.errors = new ErrorBodyWriter(objectMapper);
        this.clientIp = new ClientIpResolver(rateLimitProperties);
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain filterChain)
            throws ServletException, IOException {
        Rule rule = resolveRule(request);
        if (!rateLimitProperties.isEnabled() || rule == null || rule.limit() <= 0) {
            filterChain.doFilter(request, response);
            return;
        }

        long windowSeconds = Math.max(1, rateLimitProperties.getWindowSeconds());
        long currentWindow = Instant.now().getEpochSecond() / windowSeconds;

        if (!window.tryAcquire(subjectKey(request) + "|" + rule.bucket(), rule.limit(), currentWindow)) {
            errors.tooManyRequests(response, windowSeconds);
            return;
        }

        filterChain.doFilter(request, response);
    }

    /**
     * 카운터 열쇠. 인증됐으면 사용자, 아니면 IP.
     *
     * <p>{@code "u|"} · {@code "ip|"} 접두를 붙이는 이유: 접두가 없으면 IP 문자열이 우연히
     * 어떤 사용자의 principal 문자열과 같아질 때 두 카운터가 합쳐진다. 지금 모양으로는 일어날
     * 수 없지만, 열쇠를 만드는 자리에서 그 가능성을 남겨 둘 이유가 없다.
     */
    private String subjectKey(HttpServletRequest request) {
        Authentication authentication = SecurityContextHolder.getContext().getAuthentication();
        if (authentication != null && authentication.isAuthenticated()) {
            String name = authentication.getName();
            if (name != null && !name.isBlank()) {
                return "u|" + name;
            }
        }
        return "ip|" + clientIp.resolve(request);
    }

    /**
     * 어느 버킷인가. 표에 없으면 {@code null} 이고, 그러면 <b>한도가 0 이 아니라 무한</b>이다.
     *
     * <p><b>읽음 표시가 왜 폴링 버킷인가.</b> {@code POST /rooms/{id}/read} 는 쓰기지만 행을
     * 만들지 않는다 — {@code GREATEST} 로 워터마크를 올리는 멱등 갱신이고, 호출 빈도가 폴링과
     * 같다(화면을 볼 때마다 한 번). 전송 버킷에 넣으면 전송 한도가 읽음의 빈도까지 흡수해야
     * 해서, 정작 막아야 할 스크립트 전송을 못 막는다.
     *
     * <p><b>초대 발급({@code POST /rooms/{id}/invites})은 여기 없다.</b> 그건 이미
     * {@link ApiRateLimitFilter} 의 {@code group-write} 버킷이 잡는다(#75). 행과 열쇠를 만드는
     * 쓰기라 성격이 그룹 생성에 가깝고, 빈도가 낮아 IP 열쇠로 충분하다. 여기서 다시 세면
     * 같은 요청이 두 카운터에 들어간다.
     */
    private Rule resolveRule(HttpServletRequest request) {
        String method = request.getMethod();
        String path = request.getRequestURI();
        if (path == null) {
            return null;
        }

        if ("GET".equals(method)
                && (path.equals("/api/chat/rooms") || path.matches("^/api/chat/rooms/\\d+/messages$"))) {
            return new Rule("chat-poll", rateLimitProperties.getChatPollMaxRequests());
        }
        if ("POST".equals(method) && path.matches("^/api/chat/rooms/\\d+/read$")) {
            return new Rule("chat-poll", rateLimitProperties.getChatPollMaxRequests());
        }
        if ("POST".equals(method) && path.matches("^/api/chat/rooms/\\d+/messages$")) {
            return new Rule("chat-send", rateLimitProperties.getChatSendMaxRequests());
        }
        if ("POST".equals(method) && path.matches("^/api/chat/rooms/[0-9]+/reports$")) {
            return new Rule("chat-report", rateLimitProperties.getChatReportMaxRequests());
        }
        if ("POST".equals(method) && path.matches("^/api/chat/invites/[^/]+/join$")) {
            return new Rule("chat-join", rateLimitProperties.getChatJoinMaxRequests());
        }
        return null;
    }
}
