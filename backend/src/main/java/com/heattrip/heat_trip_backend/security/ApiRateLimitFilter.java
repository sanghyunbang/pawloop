package com.heattrip.heat_trip_backend.security;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.heattrip.heat_trip_backend.S3.media.error.GlobalExceptionHandler;
import com.heattrip.heat_trip_backend.observability.logging.CorrelationIdFilter;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import lombok.RequiredArgsConstructor;
import org.slf4j.MDC;
import org.springframework.http.HttpStatus;
import org.springframework.http.MediaType;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.time.Instant;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;
import java.util.concurrent.atomic.AtomicLong;

@Component
@RequiredArgsConstructor
public class ApiRateLimitFilter extends OncePerRequestFilter {

    private record CounterWindow(long startedAtEpochSecond, int count) {}
    private record Rule(String bucket, int limit) {}

    private final RateLimitProperties rateLimitProperties;
    private final ObjectMapper objectMapper;
    private final Map<String, CounterWindow> counters = new ConcurrentHashMap<>();

    /** 마지막으로 스테일 항목을 훑은 창. 같은 창에서 두 번 훑지 않기 위한 것뿐이다. */
    private final AtomicLong lastSweptWindow = new AtomicLong(Long.MIN_VALUE);

    /** {@link #trustedProxies()} 가 채운다. 기동 뒤 바뀌지 않는 값이라 한 번만 파싱한다. */
    private volatile TrustedProxies trustedProxies;

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain filterChain)
            throws ServletException, IOException {
        var rule = resolveRule(request);
        if (!rateLimitProperties.isEnabled() || rule == null || rule.limit() <= 0) {
            filterChain.doFilter(request, response);
            return;
        }

        long now = Instant.now().getEpochSecond();
        long windowSeconds = Math.max(1, rateLimitProperties.getWindowSeconds());
        long currentWindow = now / windowSeconds;
        String key = resolveClientIp(request) + "|" + rule.bucket();

        CounterWindow result = counters.compute(key, (k, current) -> {
            if (current == null || current.startedAtEpochSecond() != currentWindow) {
                return new CounterWindow(currentWindow, 1);
            }
            return new CounterWindow(current.startedAtEpochSecond(), current.count() + 1);
        });

        if (result != null && result.count() > rule.limit()) {
            writeTooManyRequests(response, windowSeconds);
            return;
        }

        cleanupStaleEntries(currentWindow);
        filterChain.doFilter(request, response);
    }

    private Rule resolveRule(HttpServletRequest request) {
        String method = request.getMethod();
        String path = request.getRequestURI();

        if ("POST".equals(method) && "/auth/login".equals(path)) {
            return new Rule("login", rateLimitProperties.getLoginMaxRequests());
        }
        // 회원가입도 login 버킷을 쓴다. 이 줄이 없던 동안 `POST /auth/signup` 은 **무제한**
        // 이었다 — `resolveRule` 이 null 을 돌려주면 필터가 그대로 통과시키기 때문이다.
        // 계정 대량 생성은 이메일 열거·스팸 계정의 입구이고, 비용은 로그인 시도와 같은 급이라
        // 버킷을 나누지 않고 함께 쓴다.
        if ("POST".equals(method) && "/auth/signup".equals(path)) {
            return new Rule("login", rateLimitProperties.getLoginMaxRequests());
        }
        // ── 인증 버킷 (이슈 #14) ────────────────────────────────────────────────
        // 세 분기를 하나의 || 로 합치지 않는다. 합치면 "어느 경로가 언제 목록에서
        // 빠졌는지" 가 한 줄 안에 묻히고, 한 경로만 지웠을 때 어느 테스트가 빨간불이
        // 되는지도 흐려진다. 셋은 같은 버킷을 쓰되 서로 다른 문장이다.
        //
        // ⚠️ #9 는 refresh 경로가 rate limit 없이 열려 있다는 사실을 여기로 넘겼다.
        //    이 분기를 지우면 ApiRateLimitFilterTest.refreshEndpoint_isRateLimited 가 죽는다.
        if ("POST".equals(method) && "/auth/token/refresh".equals(path)) {
            return new Rule("auth", rateLimitProperties.getAuthMaxRequests());
        }
        // 1회용 코드 교환. 자격증명을 만들어 내는 경로라 무제한이면 코드 추측이 공짜다.
        if ("POST".equals(method) && path.matches("^/auth/oauth/[^/]+/callback$")) {
            return new Rule("auth", rateLimitProperties.getAuthMaxRequests());
        }
        // 소셜 진입. 여기는 토큰을 주지 않지만, 공급자로 나가는 302 를 무한히 뽑아낼 수 있으면
        // 우리 서버가 공급자에 대한 트래픽 증폭기가 된다.
        if (path.startsWith("/oauth2/authorization/")) {
            return new Rule("auth", rateLimitProperties.getAuthMaxRequests());
        }
        // ── 가족·채팅 쓰기 버킷 (이슈 #75 · 📌 #86 원칙 4) ─────────────────────
        //
        // 요청 한 건이 **행을 만드는** 두 경로다. `POST /api/groups` 하나가
        // family_group·chat_room·chat_room_member 세 행을 만들고, 초대 발급 하나가
        // "7일 동안 인증 없이 방에 들어올 수 있는 열쇠" 를 하나 더 만든다.
        //
        // 이 둘이 표에 없던 동안 실제로 무제한이었다 — 한 계정으로 POST /api/groups 를
        // 200번, 같은 방에 초대 발급을 200번 불러 429 가 **0건**이었다(OWASP API4).
        // `/auth/signup` 이 같은 이유로 무제한이었던 것과 같은 모양이고, 여기가 그 사고를
        // 두 번 반복하지 않기로 한 자리다.
        //
        // 버킷을 새로 만든 것은 한도를 따로 움직일 수 있게 하려는 것이다 — 이 둘은 피드백
        // 전송과 성격이 달라서(행을 만들고 열쇠를 만든다) 같은 숫자에 묶어 두면 한쪽을
        // 조일 때 다른 쪽이 함께 조여진다.
        //
        // **채팅 네 경로(#79)는 여기에 없다 — 즉 무제한이다.**
        //   GET  /api/chat/rooms
        //   GET  /api/chat/rooms/{roomId}/messages
        //   POST /api/chat/rooms/{roomId}/messages
        //   POST /api/chat/rooms/{roomId}/read
        // 📌 #86 원칙 4 는 새 엔드포인트를 이 표에 등재하라고 한다. 넷을 지금 넣지 않은 것은
        // 이슈 **#80** 이 채팅 버킷을 소유하고, 숫자가 앱의 폴링 주기와 함께 정해져야 근거가
        // 생기기 때문이다. 전송과 읽음은 성격이 초대 발급에 가깝고(행을 만든다) 조회 둘은
        // 폴링이라 초당 호출 수 자체가 다르므로, group-write 에 묶는 것은 답이 아니다.
        //
        // **표에 없는 경로는 한도가 0 이 아니라 무한이다** — resolveRule 이 null 을 돌려주면
        // doFilterInternal 이 카운터를 건드리지 않고 그대로 통과시킨다(:46). 미룬 것이지
        // 안전한 것이 아니다. 지금 이 넷은 한 계정으로 몇 번을 불러도 429 가 나오지 않고,
        // 전송에 걸려 있는 것은 본문 길이 검사와 방 행 잠금(방 단위 직렬화)뿐이다.
        //
        // **요청 본문 크기 상한도 아직 없다 — 같이 #80 으로 넘긴다.** #78 이 넘긴 항목인데
        // 이번에도 넣지 않았다. `ChatRoomService.validBody` 는 본문을 **다 읽은 뒤** 컬럼 폭
        // (65,535바이트)으로 거절한다 — 20MB 본문을 던지면 그것을 전부 String 으로 올린 뒤
        // 400 을 낸다(실측 404ms). 지금 앞에서 막는 것은 운영 nginx 의
        // `client_max_body_size 20m` 하나뿐이고(docs/operations/.../nginx-production-template.conf),
        // 그건 이 저장소의 애플리케이션 설정이 아니다. 한도 표와 같은 이유로 #80 이 함께
        // 정한다 — 폴링 주기와 본문 상한이 같은 계산의 두 변수다.
        if ("POST".equals(method) && "/api/groups".equals(path)) {
            return new Rule("group-write", rateLimitProperties.getGroupWriteMaxRequests());
        }
        if ("POST".equals(method) && path.matches("^/api/chat/rooms/\\d+/invites$")) {
            return new Rule("group-write", rateLimitProperties.getGroupWriteMaxRequests());
        }
        // 회수(DELETE .../invites/{code})는 넣지 않는다. 자기 방의 코드를 죽이는 것뿐이라
        // 반복해도 새로 생기는 것이 없고, 유출 대응을 한도로 막으면 그게 더 나쁘다.
        //
        // **참여 경로(`POST /api/chat/invites/{code}/join`)는 여전히 표에 없다 — 즉 무제한이다.**
        // #75 의 NOTE 가 "코드 추측 공격을 견디는지는 M2.6 의 rate limit 이슈에서 참여 경로에
        // 버킷을 붙여 다룬다" 고 정했고 그 판단을 따랐다. **미룬 것이지 안전한 것이 아니다** —
        // 표에 없는 경로는 한도가 0 이 아니라 무한이고(resolveRule 이 null 을 돌려주면 필터가
        // 그대로 통과시킨다), 지금 그것을 견디는 것은 초대코드의 길이 하나뿐이다(50비트,
        // `InviteCodeGenerator`). M2.6 에서 이 자리에 `chat-invite` 버킷을 넣는다.
        //
        // ── 케어 쓰기 둘 (이슈 #76) ─────────────────────────────────────────
        //
        // POST care-logs 는 행을 하나 만들고, PUT walk-notes 는 **가족 모두가 보는 문서를
        // 통째로** 바꾼다. 둘 다 그룹 안의 다른 사람 화면을 바꾸는 쓰기라 그룹 생성·초대
        // 발급과 성격이 같고, 그래서 버킷을 새로 만들지 않고 group-write 를 함께 쓴다.
        //
        // **읽기 둘(GET care-logs · GET walk-notes)은 넣지 않았다.** GET /api/groups/me 가
        // 표 밖인 것과 같은 판단이다. 미룬 것이지 안전한 것이 아니다 — 위에 적은 대로 표에
        // 없는 경로는 한도가 무한이다. 이 둘은 홈 화면이 진입할 때마다 부르는 경로라
        // 숫자를 정하려면 앱의 폴링 주기부터 정해야 하고, 그건 M2.6 이다.
        if ("POST".equals(method) && path.matches("^/api/groups/\\d+/care-logs$")) {
            return new Rule("group-write", rateLimitProperties.getGroupWriteMaxRequests());
        }
        if ("PUT".equals(method) && path.matches("^/api/groups/\\d+/walk-notes$")) {
            return new Rule("group-write", rateLimitProperties.getGroupWriteMaxRequests());
        }
        if (path.startsWith("/api/curation/")) {
            return new Rule("curation", rateLimitProperties.getCurationMaxRequests());
        }
        if ("GET".equals(method) && "/api/explore/places/search".equals(path)) {
            return new Rule("search", rateLimitProperties.getSearchMaxRequests());
        }
        if ("POST".equals(method) && "/feedback".equals(path)) {
            return new Rule("feedback", rateLimitProperties.getFeedbackMaxRequests());
        }
        if ("POST".equals(method) && path.matches("^/api/explore/places/\\d+/feedback$")) {
            return new Rule("feedback", rateLimitProperties.getFeedbackMaxRequests());
        }
        if (path.startsWith("/media")) {
            return new Rule("upload", rateLimitProperties.getUploadMaxRequests());
        }
        if (path.startsWith("/journeys/v2/entries/") && path.endsWith("/images")) {
            return new Rule("upload", rateLimitProperties.getUploadMaxRequests());
        }
        if ("POST".equals(method) && "/journeys/v2/entries/with-images".equals(path)) {
            return new Rule("upload", rateLimitProperties.getUploadMaxRequests());
        }
        return null;
    }

    /**
     * 카운터의 열쇠가 될 클라이언트 주소. <b>신뢰 경계를 명시한다.</b> (이슈 #14)
     *
     * <h2>무엇이 문제였나</h2>
     * 예전 구현은 {@code X-Forwarded-For} 의 <b>첫 원소</b>를 무조건 취했다. 그런데 이
     * 저장소의 nginx 템플릿({@code nginx-production-template.conf:34},
     * {@code nginx-rate-limit-example.conf:27})은 {@code $proxy_add_x_forwarded_for} 라서
     * <b>클라이언트가 보낸 값 뒤에</b> 실제 IP 를 덧붙인다. 즉 첫 원소는 배포된 환경에서도
     * 공격자가 정하는 문자열이었고, 요청마다 다른 값을 적으면 카운터가 갈라져 한도가
     * 통째로 사라졌다 — 한도 5 에 1000 요청, 429 <b>0건</b>.
     *
     * <h2>두 개의 벽</h2>
     * <ol>
     *   <li><b>연결 반대편이 신뢰 프록시가 아니면 헤더를 아예 읽지 않는다.</b> 헤더가 의미를
     *       갖는 조건은 "우리가 통제하는 프록시가 붙였다" 하나뿐이고, 그것을 확인할 수 있는
     *       값은 {@code getRemoteAddr()} 뿐이다. 프록시 없이 노출된 배포에서는 헤더가
     *       그냥 무시된다 — 위조가 통하지 않는다.</li>
     *   <li><b>목록형 헤더는 마지막 원소를 취한다.</b> 신뢰 프록시가 1단일 때 그 자리가
     *       프록시가 실제로 본 주소다. 앞쪽은 전부 클라이언트가 적은 값이다.
     *       ({@code X-Real-IP} 는 단일 값이라 마지막 = 전체다.)</li>
     * </ol>
     *
     * <p>둘 중 하나만 두면 부족하다. 1번만 두면 신뢰 프록시 뒤에서 첫 원소 위조가 그대로
     * 살아 있고, 2번만 두면 프록시 없는 배포에서 아무나 헤더를 붙일 수 있다.
     */
    private String resolveClientIp(HttpServletRequest request) {
        String remoteAddr = request.getRemoteAddr();
        String connectionPeer = (remoteAddr == null || remoteAddr.isBlank()) ? "unknown" : remoteAddr;

        if (!trustedProxies().contains(connectionPeer)) {
            return connectionPeer;
        }

        String headerName = rateLimitProperties.getIpHeader();
        String forwarded = headerName == null ? null : request.getHeader(headerName);
        if (forwarded == null || forwarded.isBlank()) {
            return connectionPeer;
        }

        String[] hops = forwarded.split(",");
        String nearest = hops[hops.length - 1].trim();
        return nearest.isEmpty() ? connectionPeer : nearest;
    }

    /**
     * 신뢰 프록시 목록은 기동 뒤 바뀌지 않는다. 요청마다 CIDR 을 다시 파싱하지 않도록
     * 한 번만 만들어 둔다.
     */
    private TrustedProxies trustedProxies() {
        TrustedProxies cached = this.trustedProxies;
        if (cached == null) {
            cached = TrustedProxies.parse(rateLimitProperties.getTrustedProxies());
            this.trustedProxies = cached;
        }
        return cached;
    }

    /**
     * 429 본문. <b>계약({@code openapi.yaml} 의 {@code Error})의 봉투 그대로다.</b> (이슈 #14)
     *
     * <p>예전에는 {@code {status, error(문자열), message, windowSeconds, limit}} 평면 구조였다.
     * 계약은 {@code {error:{code,message,traceId}}} 이고 앱은 {@code error.code} 로 분기한다 —
     * 평면 구조가 오면 그 분기가 그 자리에서 깨진다. 봉투 타입을 새로 만들지 않고
     * {@link GlobalExceptionHandler.ErrorResponse} 를 그대로 쓰는 이유가 그것이다.
     * 사본을 만들면 한쪽만 낡는다.
     *
     * <p><b>버킷 이름과 한도 수치를 싣지 않는다.</b> 그건 서버 내부의 경로 분류이고, 응답에
     * 실으면 어떤 경로가 어떤 버킷인지·한도가 얼마인지가 그대로 새어 나간다. 사용자가 알아야
     * 하는 것은 "잠시 후 다시" 하나뿐이고, 조사에 필요한 것은 {@code traceId} 다.
     */
    private void writeTooManyRequests(HttpServletResponse response, long windowSeconds) throws IOException {
        response.setStatus(HttpStatus.TOO_MANY_REQUESTS.value());
        response.setContentType(MediaType.APPLICATION_JSON_VALUE);
        response.setCharacterEncoding(StandardCharsets.UTF_8.name());
        // 초 단위 재시도 힌트. 표준 헤더라 클라이언트가 해석할 수 있고, 본문에 한도를 싣는 것과
        // 달리 내부 분류를 노출하지 않는다.
        response.setHeader("Retry-After", String.valueOf(windowSeconds));

        var body = new GlobalExceptionHandler.ErrorResponse(
                new GlobalExceptionHandler.ErrorResponse.ErrorBody(
                        "RATE_LIMITED",
                        "요청이 너무 잦습니다. 잠시 후 다시 시도해 주세요.",
                        MDC.get(CorrelationIdFilter.MDC_KEY)));

        objectMapper.writeValue(response.getWriter(), body);
    }

    /**
     * 지난 창의 항목을 치운다. <b>창이 바뀔 때만</b> 훑는다. (이슈 #14)
     *
     * <p>예전에는 차단되지 않은 <b>모든 요청</b>이 맵 전체를 순회했다. 그 상태에서 카운터
     * 열쇠를 공격자가 정할 수 있었으므로(위 {@code resolveClientIp} 참조) 맵을 부풀린 만큼
     * 요청당 CPU 가 함께 올라갔다 — 실측으로 맵 크기가 2배가 되자 요청당 비용이 3.7배가 됐다.
     * 인증 없이 보낼 수 있는 요청으로 서버 CPU 를 증폭시킬 수 있다는 뜻이다.
     *
     * <p>열쇠 위조를 막은 것이 근본 수정이고, 이 게이트는 그 위의 두 번째 벽이다.
     * 창 하나에 순회 한 번이면 정리 주기는 그대로이고 요청당 비용은 O(1) 이 된다.
     */
    private void cleanupStaleEntries(long currentWindow) {
        long previous = lastSweptWindow.get();
        if (previous == currentWindow) {
            return;
        }
        // 진 쪽은 그냥 건너뛴다. 청소는 다음 요청이 해도 되는 일이라 재시도할 이유가 없다.
        if (!lastSweptWindow.compareAndSet(previous, currentWindow)) {
            return;
        }
        counters.entrySet().removeIf(entry -> entry.getValue().startedAtEpochSecond() + 2 < currentWindow);
    }
}
