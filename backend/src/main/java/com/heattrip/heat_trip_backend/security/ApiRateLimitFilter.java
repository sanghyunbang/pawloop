package com.heattrip.heat_trip_backend.security;

import com.fasterxml.jackson.databind.ObjectMapper;
import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;
import org.springframework.stereotype.Component;
import org.springframework.web.filter.OncePerRequestFilter;

import java.io.IOException;
import java.time.Instant;

@Component
public class ApiRateLimitFilter extends OncePerRequestFilter {

    private record Rule(String bucket, int limit) {}

    private final RateLimitProperties rateLimitProperties;

    /** 오류 본문을 만드는 곳. 계약이 여러 벌이 되지 않게 필터들이 같은 것을 쓴다 (#80 · #129). */
    private final ErrorBodyWriter errors;
    /** 세는 일은 여기가 한다. 채팅 필터도 같은 것을 쓴다 (#80). */
    private final RateLimitWindow window = new RateLimitWindow();

    /** 신뢰 프록시 판정이 걸린 자리라 복사하지 않는다. 채팅 필터도 같은 것을 쓴다 (#80). */
    private final ClientIpResolver clientIp;

    public ApiRateLimitFilter(RateLimitProperties rateLimitProperties, ObjectMapper objectMapper) {
        this.rateLimitProperties = rateLimitProperties;
        this.errors = new ErrorBodyWriter(objectMapper);
        this.clientIp = new ClientIpResolver(rateLimitProperties);
    }

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

        // 열쇠가 IP 인 것은 이 필터가 체인 맨 앞이라 사용자가 누구인지 모르기 때문이다.
        // 채팅처럼 사용자 단위로 세야 하는 경로는 인증 뒤의 ChatRateLimitFilter 가 맡는다 (#80).
        String key = clientIp.resolve(request) + "|" + rule.bucket();

        if (!window.tryAcquire(key, rule.limit(), currentWindow)) {
            errors.tooManyRequests(response, windowSeconds);
            return;
        }

        filterChain.doFilter(request, response);
    }

    /** 커뮤니티에서 상태를 바꾸는 메서드 전부. 여기 빠진 메서드는 한도가 무한이 된다. */
    private static final java.util.Set<String> WRITE_METHODS =
            java.util.Set.of("POST", "PUT", "PATCH", "DELETE");

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
        // 소셜 공급자가 돌려보내는 자리 (#232). SecurityConfig 가 "/login/**" 로 열어 두는데
        // 표에 없었다 — 여기가 무한이면 코드 교환을 무한히 시도할 수 있다.
        // /auth/oauth/{provider}/callback 과 같은 일을 하므로 같은 버킷이다.
        if (path.startsWith("/login/oauth2/code/")) {
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
        // ── 반려동물 등록 (이슈 #145) ─────────────────────────
        //
        // 요청 한 건이 행을 만든다. `POST /api/groups` 와 성격이 같아 버킷을 새로 만들지
        // 않고 group-write 를 함께 쓴다 — 한도를 따로 움직일 이유가 아직 없다.
        //
        // **읽기 둘(GET /api/dogs · GET /api/dogs/{dogId})은 넣지 않았다.** 표에 없는 경로는
        // 한도가 0 이 아니라 **무한**이다. 미룬 것이지 안전한 것이 아니고, 숫자를 정하려면
        // 앱이 이 목록을 언제 얼마나 부르는지부터 정해져야 한다.
        //
        // rate limit 은 **속도**를 잴 뿐 **총량**을 재지 않는다 — 하루에 조금씩 넣으면
        // 한도에 안 걸린다. 그래서 계정당 총 마리 수는 `DogService.MAX_PETS` 가 막는다.
        if ("POST".equals(method) && "/api/dogs".equals(path)) {
            return new Rule("group-write", rateLimitProperties.getGroupWriteMaxRequests());
        }
        // ── 산책 쓰기 (이슈 #145) ──────────────────────────────
        //
        // group-write 에 얹지 않고 버킷을 새로 만든다. 산책 저장은 **오프라인 큐가 한 번에
        // 여러 건을 밀어 넣는** 경로라, 가족 만들기와 같은 숫자로 묶으면 밀린 기록을 올리는
        // 정상 사용자가 429 를 맞는다. 그건 이 이슈가 없애려던 바로 그 경험이다.
        //
        // 삭제도 같은 버킷이다 — 잘못 저장한 것을 지우는 일은 저장과 같은 빈도로 일어난다.
        //
        // **읽기 셋(GET /api/walks · /{walkId} · /stats/weekly)은 넣지 않았다.** 표에 없는
        // 경로는 한도가 0 이 아니라 무한이다. 미룬 것이지 안전한 것이 아니고, 숫자를 정하려면
        // 앱이 이 셋을 언제 얼마나 부르는지부터 정해져야 한다 — 홈·기록·통계 세 화면이
        // 진입할 때마다 부른다.
        if ("POST".equals(method) && "/api/walks".equals(path)) {
            return new Rule("walk-write", rateLimitProperties.getWalkWriteMaxRequests());
        }
        if ("DELETE".equals(method) && path.matches("^/api/walks/\\d+$")) {
            return new Rule("walk-write", rateLimitProperties.getWalkWriteMaxRequests());
        }
        // 회고 글 교체(#187)도 같은 버킷이다. 글을 고치는 일이 산책을 저장하는 일보다
        // 잦을 이유가 없고, 한도를 따로 움직일 근거가 아직 없다.
        if ("PUT".equals(method) && path.matches("^/api/walks/\\d+/memo$")) {
            return new Rule("walk-write", rateLimitProperties.getWalkWriteMaxRequests());
        }
        if (path.startsWith("/api/curation/")) {
            return new Rule("curation", rateLimitProperties.getCurationMaxRequests());
        }
        // 관광공사 프록시(#40). 인증 없는 공개 경로라 등재가 특히 중요하다 —
        // 표에 없으면 한도가 0 이 아니라 무한이다.
        if ("GET".equals(method) && "/api/places/nearby".equals(path)) {
            return new Rule("places", rateLimitProperties.getPlacesMaxRequests());
        }
        if ("GET".equals(method) && path.matches("^/api/places/[^/]+$")) {
            return new Rule("places-detail", rateLimitProperties.getPlacesDetailMaxRequests());
        }
        if ("GET".equals(method) && "/api/explore/places/search".equals(path)) {
            return new Rule("search", rateLimitProperties.getSearchMaxRequests());
        }
        // explore 읽기 다섯 — 목록·스크롤·상세·features·emotional-reviews (#232).
        //
        // **SecurityConfig 가 "/api/explore/**" 로 통째로 열어 둔 자리다.** 인증이 없으므로
        // 남은 방어선이 이 줄 하나뿐인데, 2026-09-03 이전에는 이 줄이 없어서 다섯이 전부
        // 무한이었다 — 표에 없으면 한도가 0 이 아니라 무한이다.
        //
        // 패턴이 [^/]+ 인 것은 permitAll 과 **같은 집합을 덮기 위해서**다. [0-9]+ 로 좁히면
        // GET /api/explore/places/abc 가 인증 없음 + 한도 무한으로 남는다 — places 가 같은
        // 함정을 이미 겪었다.
        if ("GET".equals(method) && path.startsWith("/api/explore/places")) {
            return new Rule("explore-read", rateLimitProperties.getExploreReadMaxRequests());
        }
        if ("POST".equals(method) && "/feedback".equals(path)) {
            return new Rule("feedback", rateLimitProperties.getFeedbackMaxRequests());
        }
        if ("POST".equals(method) && path.matches("^/api/explore/places/\\d+/feedback$")) {
            return new Rule("feedback", rateLimitProperties.getFeedbackMaxRequests());
        }
        // ── 커뮤니티 (이슈 #170 · ADR-0016 결정 3) ─────────────────────────
        //
        // **읽기 셋이 게스트에게 열려 있다.** 그 전까지 이 경로를 막고 있던 것은
        // anyRequest().authenticated() 였는데 그 방어선이 사라졌다 — 표에 없으면
        // 한도가 0 이 아니라 **무한**이다(resolveRule 이 null 을 주면 그대로 통과).
        //
        // 패턴이 SecurityConfig 의 permitAll 과 **같은 집합을 덮어야 한다.** 거기는
        // "/api/community/posts/*" 라 임의의 한 세그먼트를 열므로, 여기서 [0-9]+ 만
        // 덮으면 GET /api/community/posts/abc 가 **인증 없음 + 한도 무한**이 된다.
        // /api/places/** 를 거부한 근거와 같은 모양이라 [^/]+ 로 맞춘다.
        if ("GET".equals(method)
                && ("/api/community/posts".equals(path)
                    || path.matches("^/api/community/posts/[^/]+$")
                    || path.matches("^/api/community/posts/[^/]+/comments$"))) {
            return new Rule("community-read", rateLimitProperties.getCommunityReadMaxRequests());
        }
        // 쓰기 전부. 버킷을 나눈 이유는 목록을 새로고침하다 한도에 닿아 글을 못 쓰게
        // 되면 안 되기 때문이다. 반응이 여기 있는 것도 의도다 — 멱등이라 행은 안 늘지만
        // 요청은 그대로 오고 매번 집계 쿼리가 돈다.
        //
        // **메서드를 열거한다.** 처음엔 POST·DELETE 둘만 적었는데, #211 이 PATCH 를 열면서
        // 그것이 한도 없는 쓰기 경로가 될 뻔했다 — 표에 없으면 한도가 0 이 아니라 무한이다.
        // `!GET` 으로 뒤집지 않는 이유는 OPTIONS 다. CORS 예비 요청이 쓰기 버킷을 태우면
        // 사용자가 아무것도 안 썼는데 글쓰기가 막힌다.
        // **신고를 쓰기보다 먼저 본다.** 순서를 뒤집으면 아래 community-write 가 먼저
        // 걸려서 이 줄이 영영 안 잡히고, 글을 쏟아부어 신고를 막을 수 있게 된다 (#166).
        if ("POST".equals(method) && path.startsWith("/api/community/") && path.endsWith("/reports")) {
            return new Rule("community-report", rateLimitProperties.getCommunityReportMaxRequests());
        }
        if (WRITE_METHODS.contains(method)
                && path.startsWith("/api/community/")) {
            return new Rule("community-write", rateLimitProperties.getCommunityWriteMaxRequests());
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


}
