package com.heattrip.heat_trip_backend.security;

import com.fasterxml.jackson.databind.ObjectMapper;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.mock.web.MockFilterChain;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;

import java.util.List;
import java.util.Map;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * {@link ApiRateLimitFilter} 의 첫 테스트. (이슈 #14)
 *
 * <p>이 필터에는 테스트가 <b>0건</b>이었다. 그동안 이 필터가 어떤 경로를 어떤 버킷으로
 * 묶는지는 코드를 읽는 사람의 기억에만 있었고, 그래서 {@code POST /auth/token/refresh} 와
 * 소셜 진입점이 목록에서 빠져 있다는 사실도 아무 신호를 내지 않았다.
 *
 * <p>스프링 컨텍스트를 띄우지 않는다. 필터 하나에 {@code MockHttpServletRequest} 를 직접
 * 태운다 — 카운터가 인스턴스 필드({@code ApiRateLimitFilter.counters})이므로
 * <b>테스트마다 필터를 새로 만들어</b> 격리한다. 공유하면 앞 테스트가 소진한 카운터가
 * 뒤 테스트의 판정을 바꾼다.
 *
 * <p><b>이 파일이 볼 수 없는 것:</b> 필터가 배포된 시큐리티 체인의 <b>어느 자리</b>에 있는지.
 * 여기서는 필터를 직접 태우므로 체인에서 앞선 필터가 요청을 끝내 버려도 알 수 없다. 실제로
 * {@code /oauth2/authorization/*} 는 그 이유로 운영에서 제한이 걸리지 않으면서 이 파일은
 * 초록이었다. 그 자리는 {@link ApiRateLimitFilterChainOrderIntegrationTest} 가 잠근다.
 */
class ApiRateLimitFilterTest {

    private static final ObjectMapper MAPPER = new ObjectMapper();

    /** nginx 가 앉는 자리. 기본 {@code trusted-proxies} 안이라 헤더가 해석된다. */
    private static final String BEHIND_PROXY = "127.0.0.1";

    /** 프록시 없이 직접 붙은 클라이언트. 신뢰 목록 밖이라 헤더가 무시된다. */
    private static final String DIRECT_PUBLIC = "203.0.113.9";

    /** 창을 넉넉히 잡는다 — 이 테스트가 재는 것은 시간 경과가 아니라 한도 초과다. */
    private static RateLimitProperties props(int authLimit) {
        RateLimitProperties p = new RateLimitProperties();
        p.setEnabled(true);
        p.setWindowSeconds(3600);
        p.setAuthMaxRequests(authLimit);
        return p;
    }

    private static ApiRateLimitFilter filter(int authLimit) {
        return new ApiRateLimitFilter(props(authLimit), MAPPER);
    }

    /** login 버킷(이메일 로그인·회원가입)의 한도를 지정한 필터. */
    private static ApiRateLimitFilter filterWithLoginLimit(int loginLimit) {
        RateLimitProperties p = props(100);
        p.setLoginMaxRequests(loginLimit);
        return new ApiRateLimitFilter(p, MAPPER);
    }

    /** 가족·채팅 쓰기 버킷({@code POST /api/groups}·초대 발급)의 한도를 지정한 필터. */
    private static ApiRateLimitFilter filterWithCommunityLimits(int read, int write) {
        RateLimitProperties p = props(100);
        p.setCommunityReadMaxRequests(read);
        p.setCommunityWriteMaxRequests(write);
        return new ApiRateLimitFilter(p, MAPPER);
    }

    private static ApiRateLimitFilter filterWithGroupWriteLimit(int groupWriteLimit) {
        RateLimitProperties p = props(100);
        p.setGroupWriteMaxRequests(groupWriteLimit);
        return new ApiRateLimitFilter(p, MAPPER);
    }

    /** 산책 쓰기 버킷({@code POST /api/walks} · 삭제 · 회고 글)의 한도를 지정한 필터. */
    private static ApiRateLimitFilter filterWithWalkWriteLimit(int walkWriteLimit) {
        RateLimitProperties p = props(100);
        p.setWalkWriteMaxRequests(walkWriteLimit);
        return new ApiRateLimitFilter(p, MAPPER);
    }

    /** 신뢰 프록시 뒤에서 {@code X-Real-IP} 하나만 실어 보내는, 운영과 같은 모양의 요청. */
    private static MockHttpServletResponse call(ApiRateLimitFilter filter,
                                                String method, String path, String realIp) throws Exception {
        return call(filter, method, path, BEHIND_PROXY, "X-Real-IP", realIp);
    }

    private static MockHttpServletResponse call(ApiRateLimitFilter filter,
                                                String method, String path,
                                                String remoteAddr,
                                                String headerName, String headerValue) throws Exception {
        MockHttpServletRequest request = new MockHttpServletRequest(method, path);
        request.setRequestURI(path);
        request.setRemoteAddr(remoteAddr);
        if (headerValue != null) {
            request.addHeader(headerName, headerValue);
        }
        MockHttpServletResponse response = new MockHttpServletResponse();
        filter.doFilter(request, response, new MockFilterChain());
        return response;
    }

    /** 한도까지 태우고, 한도+1 번째 응답을 돌려준다. */
    private static MockHttpServletResponse exhaust(ApiRateLimitFilter filter,
                                                   String method, String path, int limit) throws Exception {
        for (int i = 0; i < limit; i++) {
            MockHttpServletResponse ok = call(filter, method, path, "198.51.100.7");
            assertThat(ok.getStatus())
                    .as("한도 안(%d/%d)의 요청은 통과해야 한다", i + 1, limit)
                    .isEqualTo(200);
        }
        return call(filter, method, path, "198.51.100.7");
    }

    // ─────────────────── A. 인증 경로가 버킷에 매핑된다 (완료 조건 6·11) ───────────────────

    @Test
    @DisplayName("POST /auth/token/refresh 는 인증 버킷이다 — 한도+1 번째에서 429")
    void refreshEndpoint_isRateLimited() throws Exception {
        // #9 는 이 경로가 rate limit 없이 열려 있다는 사실을 #14 로 넘겼다. 여기서 닫는다.
        // 이 분기를 resolveRule 에서 지우면 이 테스트가 빨간불이다 (완료 조건 11).
        MockHttpServletResponse blocked = exhaust(filter(3), "POST", "/auth/token/refresh", 3);

        assertThat(blocked.getStatus()).isEqualTo(429);
    }

    @Test
    @DisplayName("POST /auth/oauth/{provider}/callback 은 인증 버킷이다 — 한도+1 번째에서 429")
    void oauthCallbackEndpoint_isRateLimited() throws Exception {
        // 1회용 코드 교환은 자격증명을 만들어 내는 경로다. 무제한이면 코드 추측이 공짜가 된다.
        MockHttpServletResponse blocked = exhaust(filter(2), "POST", "/auth/oauth/kakao/callback", 2);

        assertThat(blocked.getStatus()).isEqualTo(429);
    }

    @Test
    @DisplayName("GET /oauth2/authorization/kakao 진입도 인증 버킷이다 — 한도+1 번째에서 429")
    void socialEntryPoint_isRateLimited() throws Exception {
        MockHttpServletResponse blocked = exhaust(filter(2), "GET", "/oauth2/authorization/kakao", 2);

        assertThat(blocked.getStatus()).isEqualTo(429);
    }

    @Test
    @DisplayName("POST /auth/signup 도 login 버킷이다 — 한도+1 번째에서 429")
    void signupEndpoint_isRateLimited() throws Exception {
        // 이 분기가 없던 동안 회원가입은 **무제한**이었다. resolveRule 이 null 을 돌려주면
        // 필터가 그대로 통과시키기 때문이다 — 표에 없는 경로는 한도가 0 이 아니라 무한이다.
        // 계정 대량 생성은 이메일 열거와 스팸 계정의 입구다.
        // resolveRule 에서 이 분기를 지우면 여기가 빨간불이다.
        MockHttpServletResponse blocked = exhaust(filterWithLoginLimit(3), "POST", "/auth/signup", 3);

        assertThat(blocked.getStatus()).isEqualTo(429);
    }

    @Test
    @DisplayName("회원가입과 로그인은 같은 버킷을 나눠 쓴다 — 합쳐서 한도다")
    void signupAndLogin_shareTheSameBucket() throws Exception {
        // 버킷 이름이 같으므로 카운터도 같아야 한다. 따로 세면 한도가 사실상 두 배가 된다.
        ApiRateLimitFilter f = filterWithLoginLimit(2);

        assertThat(call(f, "POST", "/auth/login", "203.0.113.9").getStatus()).isNotEqualTo(429);
        assertThat(call(f, "POST", "/auth/signup", "203.0.113.9").getStatus()).isNotEqualTo(429);

        assertThat(call(f, "POST", "/auth/signup", "203.0.113.9").getStatus())
                .as("로그인 1 + 가입 1 로 한도 2 를 이미 썼으므로 세 번째는 막혀야 한다")
                .isEqualTo(429);
    }

    // ─────────────────── A''. 커뮤니티 (이슈 #170 · #211) ───────────────────
    //
    // 커뮤니티 읽기 셋은 **게스트에게 열려 있다**(ADR-0016 결정 3). 그 전까지 이 경로를
    // 막고 있던 것은 anyRequest().authenticated() 였는데 그 방어선이 사라졌다 — 그리고
    // resolveRule 의 표에 **없으면 한도가 0 이 아니라 무한**이다(null 을 주면 그대로 통과).
    //
    // 그래서 버킷 둘을 함께 넣었는데 **그것을 잠그는 필터 테스트가 없었다**(#211 에서 발견).
    // application-test.properties 가 두 한도를 100000 으로 올리므로, 여기가 없으면
    // 저장소 전체에서 커뮤니티 한도를 재는 곳이 0 이 된다.

    @Test
    @DisplayName("GET /api/community/posts 는 community-read 버킷이다 — 게스트가 부르는 경로다")
    void communityFeed_isRateLimited() throws Exception {
        MockHttpServletResponse blocked = exhaust(
                filterWithCommunityLimits(2, 100), "GET", "/api/community/posts", 2);

        assertThat(blocked.getStatus()).isEqualTo(429);
    }

    @Test
    @DisplayName("글 id 가 숫자가 아니어도 읽기 버킷이 덮는다 — permitAll 과 같은 집합이어야 한다")
    void communityDetail_withNonNumericId_isStillMetered() throws Exception {
        // SecurityConfig 의 permitAll 은 "/api/community/posts/*" 라 임의의 한 세그먼트를
        // 연다. 여기 패턴을 [0-9]+ 로 좁히면 GET /api/community/posts/abc 가
        // **인증 없음 + 한도 무한**이 된다.
        MockHttpServletResponse blocked = exhaust(
                filterWithCommunityLimits(2, 100), "GET", "/api/community/posts/abc", 2);

        assertThat(blocked.getStatus()).isEqualTo(429);
    }

    @Test
    @DisplayName("글 작성·삭제·반응은 community-write 버킷을 나눠 쓴다 — 합쳐서 한도다")
    void communityWrites_shareOneBucket() throws Exception {
        ApiRateLimitFilter f = filterWithCommunityLimits(100, 2);

        assertThat(call(f, "POST", "/api/community/posts", "198.51.100.7").getStatus())
                .isEqualTo(200);
        assertThat(call(f, "DELETE", "/api/community/posts/7", "198.51.100.7").getStatus())
                .as("삭제가 이 버킷 밖이면 지우기를 무한히 부를 수 있다 (#211)")
                .isEqualTo(200);

        assertThat(call(f, "POST", "/api/community/posts/7/reactions/help", "198.51.100.7")
                .getStatus())
                .as("셋이 한 버킷이라 세 번째가 막힌다")
                .isEqualTo(429);
    }

    @Test
    @DisplayName("PATCH 도 쓰기 버킷이다 — 이 표에 없으면 한도가 0 이 아니라 무한이다")
    void communityPatch_isMetered() throws Exception {
        // #211 이 저장소 최초의 PATCH 를 열 때 이 필터는 POST·DELETE 둘만 보고 있었다.
        // 고치지 않았으면 한도 없는 쓰기 경로가 하나 생겼을 것이다.
        MockHttpServletResponse blocked = exhaust(
                filterWithCommunityLimits(100, 2), "PATCH", "/api/community/posts/7", 2);

        assertThat(blocked.getStatus()).isEqualTo(429);
    }

    @Test
    @DisplayName("커뮤니티 예비 요청(OPTIONS)은 쓰기 버킷을 안 태운다 — 안 쓴 사람의 글쓰기가 막힌다")
    void communityPreflight_doesNotBurnTheWriteBucket() throws Exception {
        ApiRateLimitFilter f = filterWithCommunityLimits(100, 1);

        assertThat(call(f, "OPTIONS", "/api/community/posts", "198.51.100.9").getStatus())
                .isEqualTo(200);
        assertThat(call(f, "POST", "/api/community/posts", "198.51.100.9").getStatus())
                .as("예비 요청이 한 칸을 먹었으면 여기서 429 가 난다")
                .isEqualTo(200);
    }

    @Test
    @DisplayName("신고는 커뮤니티 쓰기와 다른 버킷이다 — 글을 쏟아부어 신고를 막을 수 있으면 안 된다")
    void communityReport_hasItsOwnBucket() throws Exception {
        RateLimitProperties p = props(100);
        p.setCommunityWriteMaxRequests(1);
        p.setCommunityReportMaxRequests(2);
        ApiRateLimitFilter f = new ApiRateLimitFilter(p, MAPPER);

        // 쓰기를 통째로 소진시킨다.
        assertThat(call(f, "POST", "/api/community/posts", "198.51.100.11").getStatus())
                .isEqualTo(200);
        assertThat(call(f, "POST", "/api/community/posts", "198.51.100.11").getStatus())
                .isEqualTo(429);

        assertThat(call(f, "POST", "/api/community/posts/7/reports", "198.51.100.11").getStatus())
                .as("""
                        쓰기가 바닥나도 신고는 살아 있어야 한다. 합쳐 두면 신고 수단을 없애는 \
                        가장 값싼 방법이 '글을 쏟아붓기' 가 된다 — chat-report 가 같은 이유로 \
                        채팅 쓰기와 갈라져 있다.""")
                .isEqualTo(200);
    }

    @Test
    @DisplayName("신고 경로가 쓰기 규칙보다 먼저 매칭된다 — 순서가 뒤집히면 그 줄이 영영 안 걸린다")
    void communityReport_isMatchedBeforeTheWriteRule() throws Exception {
        RateLimitProperties p = props(100);
        p.setCommunityWriteMaxRequests(100000);
        p.setCommunityReportMaxRequests(1);
        ApiRateLimitFilter f = new ApiRateLimitFilter(p, MAPPER);

        assertThat(call(f, "POST", "/api/community/posts/7/comments/9/reports", "198.51.100.12")
                .getStatus()).isEqualTo(200);
        assertThat(call(f, "POST", "/api/community/posts/7/comments/9/reports", "198.51.100.12")
                .getStatus())
                .as("쓰기 규칙이 먼저 걸리면 여기가 100000 한도가 되어 영원히 200 이다")
                .isEqualTo(429);
    }

    @Test
    @DisplayName("읽기와 쓰기는 다른 버킷이다 — 목록을 새로고침하다 글을 못 쓰게 되면 안 된다")
    void communityReadAndWrite_areSeparateBuckets() throws Exception {
        ApiRateLimitFilter f = filterWithCommunityLimits(1, 1);

        assertThat(call(f, "GET", "/api/community/posts", "198.51.100.7").getStatus())
                .isEqualTo(200);
        assertThat(call(f, "GET", "/api/community/posts", "198.51.100.7").getStatus())
                .isEqualTo(429);

        assertThat(call(f, "POST", "/api/community/posts", "198.51.100.7").getStatus())
                .as("읽기를 다 써도 쓰기는 남아 있어야 한다")
                .isEqualTo(200);
    }

    // ─────────────────── A'. 가족·채팅 쓰기 경로 (이슈 #75 · 📌 #86 원칙 4) ───────────────────

    @Test
    @DisplayName("POST /api/groups 는 group-write 버킷이다 — 한도+1 번째에서 429")
    void groupCreation_isRateLimited() throws Exception {
        // 이 분기가 없던 동안 그룹 생성은 **무제한**이었다 — 한 계정으로 200번 불러
        // 429 가 0건이었고, 요청 한 건마다 family_group·chat_room·chat_room_member
        // 세 행이 생겼다(OWASP API4). resolveRule 에서 이 분기를 지우면 여기가 빨간불이다.
        MockHttpServletResponse blocked =
                exhaust(filterWithGroupWriteLimit(3), "POST", "/api/groups", 3);

        assertThat(blocked.getStatus()).isEqualTo(429);
    }

    @Test
    @DisplayName("POST /api/chat/rooms/{roomId}/invites 도 group-write 버킷이다 — 한도+1 번째에서 429")
    void inviteIssuing_isRateLimited() throws Exception {
        // 초대 발급 하나가 "7일 동안 인증 없이 방에 들어올 수 있는 열쇠" 를 하나 더 만든다.
        // 무제한이던 동안 방 하나가 살아 있는 코드 200개를 든 상태가 됐다.
        MockHttpServletResponse blocked = exhaust(
                filterWithGroupWriteLimit(2), "POST", "/api/chat/rooms/7/invites", 2);

        assertThat(blocked.getStatus()).isEqualTo(429);
    }

    @Test
    @DisplayName("그룹 생성과 초대 발급은 같은 버킷을 나눠 쓴다 — 합쳐서 한도다")
    void groupCreationAndInviteIssuing_shareTheSameBucket() throws Exception {
        ApiRateLimitFilter f = filterWithGroupWriteLimit(2);

        assertThat(call(f, "POST", "/api/groups", "203.0.113.9").getStatus()).isNotEqualTo(429);
        assertThat(call(f, "POST", "/api/chat/rooms/7/invites", "203.0.113.9").getStatus())
                .isNotEqualTo(429);

        assertThat(call(f, "POST", "/api/groups", "203.0.113.9").getStatus())
                .as("생성 1 + 발급 1 로 한도 2 를 이미 썼으므로 세 번째는 막혀야 한다")
                .isEqualTo(429);
    }

    @Test
    @DisplayName("POST /api/groups/{id}/care-logs 도 group-write 버킷이다 — 한도+1 번째에서 429")
    void careLogWriting_isRateLimited() throws Exception {
        // 요청 한 건이 care_log 행을 하나 만들고, 그 행은 가족 전원의 홈 카드에 뜬다.
        // 표에 없으면 한도가 0 이 아니라 무한이다 — resolveRule 에서 이 분기를 지우면 여기가 빨간불이다.
        MockHttpServletResponse blocked = exhaust(
                filterWithGroupWriteLimit(3), "POST", "/api/groups/12/care-logs", 3);

        assertThat(blocked.getStatus()).isEqualTo(429);
    }

    @Test
    @DisplayName("DELETE /api/groups/{id}/care-logs/{careLogId} 도 group-write 버킷이다 — 한도+1 번째에서 429")
    void careLogDeletion_isRateLimited() throws Exception {
        // 산책 삭제가 walk-write 인 것과 같은 판단 — 지우는 일은 찍는 일과 같은 빈도로 일어난다(#209).
        MockHttpServletResponse blocked = exhaust(
                filterWithGroupWriteLimit(2), "DELETE", "/api/groups/12/care-logs/7", 2);

        assertThat(blocked.getStatus()).isEqualTo(429);
    }

    @Test
    @DisplayName("PUT /api/groups/{id}/walk-notes 도 group-write 버킷이다 — 한도+1 번째에서 429")
    void walkNoteRewriting_isRateLimited() throws Exception {
        // 주의사항은 그룹당 한 장이라 PUT 한 번이 **가족 모두가 보는 문서를 통째로** 바꾼다.
        MockHttpServletResponse blocked = exhaust(
                filterWithGroupWriteLimit(2), "PUT", "/api/groups/12/walk-notes", 2);

        assertThat(blocked.getStatus()).isEqualTo(429);
    }

    @Test
    @DisplayName("DELETE /api/dogs/{dogId} 는 group-write 버킷이다 — 소프트 삭제라 지운 행이 상한에 안 센다")
    void dogDeletion_isRateLimited() throws Exception {
        // 등록·삭제를 반복하면 행이 계속 쌓인다(#156). 등록과 같은 속도 한도가 그 자리를 막는다.
        MockHttpServletResponse blocked = exhaust(
                filterWithGroupWriteLimit(2), "DELETE", "/api/dogs/7", 2);

        assertThat(blocked.getStatus()).isEqualTo(429);
    }

    @Test
    @DisplayName("산책 쓰기 셋이 모두 walk-write 버킷이다 — 저장·삭제·회고 글")
    void walkWrites_shareTheSameBucket() throws Exception {
        // 표에 없으면 한도가 0 이 아니라 무한이다. resolveRule 에서 이 분기 중 하나를
        // 지우면 여기가 빨간불이다.
        assertThat(exhaust(filterWithWalkWriteLimit(2), "POST", "/api/walks", 2).getStatus())
                .isEqualTo(429);
        assertThat(exhaust(filterWithWalkWriteLimit(2), "DELETE", "/api/walks/7", 2).getStatus())
                .isEqualTo(429);
        // 회고 글 교체(#187). 삭제와 같은 버킷이다 — 글을 고치는 일이 산책을 저장하는
        // 일보다 잦을 이유가 없다.
        assertThat(exhaust(filterWithWalkWriteLimit(2), "PUT", "/api/walks/7/memo", 2).getStatus())
                .isEqualTo(429);
    }

    @Test
    @DisplayName("산책 읽기 셋은 walk-write 버킷이 아니다 — 화면 진입마다 부르는 경로다")
    void walkReads_areNotInTheWalkWriteBucket() throws Exception {
        ApiRateLimitFilter f = filterWithWalkWriteLimit(1);

        // 홈·기록·통계 세 화면이 진입할 때마다 부른다. 여기까지 묶으면 화면 전환마다 429 다.
        // **미룬 것이지 안전한 것이 아니다** — 이 단언이 그 사실을 눈에 보이게 남겨 둔다.
        for (String path : new String[]{"/api/walks", "/api/walks/7", "/api/walks/stats/weekly"}) {
            assertThat(call(f, "GET", path, "198.51.100.9").getStatus()).isEqualTo(200);
            assertThat(call(f, "GET", path, "198.51.100.9").getStatus()).isEqualTo(200);
        }

        // 상세 조회 경로가 회고 글 경로와 접두사를 공유한다. 정규식이 느슨하면
        // GET /api/walks/7 이 쓰기 버킷에 걸린다.
        assertThat(call(f, "GET", "/api/walks/7/memo", "198.51.100.9").getStatus())
                .as("GET 은 메서드가 달라 쓰기 버킷이 아니다")
                .isEqualTo(200);
    }

    @Test
    @DisplayName("가족 읽기와 회수·참여는 group-write 버킷이 아니다 — 시끄러운 게이트는 지워진다")
    void readsAndRevokeAndJoin_areNotInTheGroupWriteBucket() throws Exception {
        ApiRateLimitFilter f = filterWithGroupWriteLimit(1);

        // 읽기는 행을 만들지 않는다. 여기까지 묶으면 화면 전환마다 429 다.
        assertThat(call(f, "GET", "/api/groups/me", "198.51.100.7").getStatus()).isEqualTo(200);
        assertThat(call(f, "GET", "/api/groups/me", "198.51.100.7").getStatus()).isEqualTo(200);

        // 케어 읽기 둘도 같은 이유로 표 밖이다(이슈 #76). 홈 화면이 진입할 때마다 부르는
        // 경로라 숫자를 정하려면 앱의 폴링 주기부터 정해야 하고, 그건 M2.6 이다.
        // **미룬 것이지 안전한 것이 아니다** — 이 단언이 그 사실을 눈에 보이게 남겨 둔다.
        assertThat(call(f, "GET", "/api/groups/12/care-logs", "198.51.100.7").getStatus())
                .isEqualTo(200);
        assertThat(call(f, "GET", "/api/groups/12/care-logs", "198.51.100.7").getStatus())
                .isEqualTo(200);
        assertThat(call(f, "GET", "/api/groups/12/walk-notes", "198.51.100.7").getStatus())
                .isEqualTo(200);
        assertThat(call(f, "GET", "/api/groups/12/walk-notes", "198.51.100.7").getStatus())
                .isEqualTo(200);

        // 회수는 자기 방 코드를 죽이는 것뿐이다. 유출 대응을 한도로 막으면 그게 더 나쁘다.
        assertThat(call(f, "DELETE", "/api/chat/rooms/7/invites/AAAAA-AAAAA", "198.51.100.7")
                .getStatus()).isEqualTo(200);
        assertThat(call(f, "DELETE", "/api/chat/rooms/7/invites/AAAAA-AAAAA", "198.51.100.7")
                .getStatus()).isEqualTo(200);

        // 참여 경로는 아직 표 밖이다 — #75 의 NOTE 가 M2.6 으로 미뤘다. 미룬 것이지
        // 안전한 것이 아니고, 이 단언이 그 사실을 눈에 보이게 남겨 둔다.
        assertThat(call(f, "POST", "/api/chat/invites/AAAAA-AAAAA/join", "198.51.100.7")
                .getStatus()).isEqualTo(200);
        assertThat(call(f, "POST", "/api/chat/invites/AAAAA-AAAAA/join", "198.51.100.7")
                .getStatus()).isEqualTo(200);
    }

    @Test
    @DisplayName("인증 경로가 아닌 곳은 인증 버킷에 걸리지 않는다")
    void unrelatedPath_isNotInTheAuthBucket() throws Exception {
        ApiRateLimitFilter filter = filter(1);
        // /auth/me 는 인증된 조회지 자격증명 경로가 아니다. 여기까지 묶으면 앱이 화면 전환마다 429 다.
        assertThat(call(filter, "GET", "/auth/me", "198.51.100.7").getStatus()).isEqualTo(200);
        assertThat(call(filter, "GET", "/auth/me", "198.51.100.7").getStatus()).isEqualTo(200);
        assertThat(call(filter, "GET", "/auth/me", "198.51.100.7").getStatus()).isEqualTo(200);
    }

    // ─────────────────── B. 카운터의 열쇠는 **위조할 수 없는** IP 다 ───────────────────
    //
    // 여기 있던 `X-Forwarded-For 가 다르면 카운터가 분리된다` 는 결함을 사양으로 고정하고
    // 있었다. 그 성질은 정확히 "헤더 한 줄로 한도를 없앨 수 있다" 와 같은 말이다.
    // 실측: 한도 5 에 매 요청 다른 XFF 로 1000건 → 429 **0건**.

    @Test
    @DisplayName("신뢰 프록시 뒤에서 X-Forwarded-For 를 위조해도 카운터가 갈라지지 않는다")
    void spoofedForwardedForHeader_doesNotSplitTheCounter() throws Exception {
        // 운영 nginx 는 X-Real-IP 를 $remote_addr 로 **덮어쓰고**, XFF 는
        // $proxy_add_x_forwarded_for 로 **덧붙인다**. 즉 XFF 앞부분은 클라이언트가 정한다.
        // 기본 ip-header 가 X-Real-IP 이므로 그 앞부분은 카운터에 아무 영향이 없어야 한다.
        ApiRateLimitFilter filter = filter(2);

        for (int i = 0; i < 2; i++) {
            MockHttpServletResponse ok = call(filter, "POST", "/auth/token/refresh",
                    BEHIND_PROXY, "X-Forwarded-For", "10.9.9." + i + ", 198.51.100.7");
            assertThat(ok.getStatus()).isEqualTo(200);
        }

        MockHttpServletResponse blocked = call(filter, "POST", "/auth/token/refresh",
                BEHIND_PROXY, "X-Forwarded-For", "10.9.9.99, 198.51.100.7");

        assertThat(blocked.getStatus())
                .as("XFF 를 매 요청 바꿔도 한도가 서야 한다 — 갈라지면 헤더 한 줄로 rate limit 이 사라진다")
                .isEqualTo(429);
    }

    @Test
    @DisplayName("신뢰 프록시 밖에서 온 연결의 IP 헤더는 아예 읽지 않는다")
    void ipHeaderFromUntrustedPeer_isIgnored() throws Exception {
        // 프록시 없이 노출된 배포. 헤더를 믿으면 아무나 자기 카운터를 새로 만들 수 있다.
        ApiRateLimitFilter filter = filter(2);

        for (int i = 0; i < 2; i++) {
            MockHttpServletResponse ok = call(filter, "POST", "/auth/token/refresh",
                    DIRECT_PUBLIC, "X-Real-IP", "10.1.1." + i);
            assertThat(ok.getStatus()).isEqualTo(200);
        }

        MockHttpServletResponse blocked = call(filter, "POST", "/auth/token/refresh",
                DIRECT_PUBLIC, "X-Real-IP", "10.1.1.99");

        assertThat(blocked.getStatus())
                .as("연결 반대편이 신뢰 프록시가 아니면 헤더는 그냥 요청자가 적은 문자열이다")
                .isEqualTo(429);
    }

    @Test
    @DisplayName("ip-header 를 X-Forwarded-For 로 두면 첫 원소가 아니라 마지막 홉을 쓴다")
    void forwardedForHeader_usesTheLastHopNotTheFirst() throws Exception {
        RateLimitProperties p = props(2);
        p.setIpHeader("X-Forwarded-For");
        ApiRateLimitFilter filter = new ApiRateLimitFilter(p, MAPPER);

        // 신뢰 프록시가 1단일 때, 그 프록시가 실제로 본 주소는 **마지막** 원소다.
        for (int i = 0; i < 2; i++) {
            assertThat(call(filter, "POST", "/auth/token/refresh",
                    BEHIND_PROXY, "X-Forwarded-For", "1.2.3." + i + ", 198.51.100.7").getStatus())
                    .isEqualTo(200);
        }
        assertThat(call(filter, "POST", "/auth/token/refresh",
                BEHIND_PROXY, "X-Forwarded-For", "1.2.3.9, 198.51.100.7").getStatus())
                .as("앞 원소를 쓰면 여기서 200 이 나온다 — 그게 고치기 전의 동작이었다")
                .isEqualTo(429);

        // 마지막 홉이 다르면(= 실제로 다른 클라이언트) 여전히 카운터가 분리된다.
        assertThat(call(filter, "POST", "/auth/token/refresh",
                BEHIND_PROXY, "X-Forwarded-For", "1.2.3.9, 198.51.100.8").getStatus())
                .as("한 사람이 전체를 잠글 수 있으면 그것도 결함이다")
                .isEqualTo(200);
    }

    @Test
    @DisplayName("서로 다른 실제 클라이언트는 카운터가 분리된다")
    void realClients_stillHaveTheirOwnCounters() throws Exception {
        ApiRateLimitFilter filter = filter(1);

        assertThat(call(filter, "POST", "/auth/token/refresh", "198.51.100.1").getStatus()).isEqualTo(200);
        assertThat(call(filter, "POST", "/auth/token/refresh", "198.51.100.1").getStatus())
                .as("같은 IP 의 두 번째 요청은 한도(1)를 넘는다")
                .isEqualTo(429);

        assertThat(call(filter, "POST", "/auth/token/refresh", "198.51.100.2").getStatus())
                .as("다른 IP 의 첫 요청까지 막으면 한 사람이 전체를 잠글 수 있다")
                .isEqualTo(200);
    }

    @Test
    @DisplayName("신뢰 프록시 목록이 비면 헤더를 아무도 못 쓴다 — 열어 두는 쪽으로 실패하지 않는다")
    void emptyTrustedProxyList_meansNoHeaderIsTrusted() throws Exception {
        RateLimitProperties p = props(1);
        p.setTrustedProxies(List.of());
        ApiRateLimitFilter filter = new ApiRateLimitFilter(p, MAPPER);

        assertThat(call(filter, "POST", "/auth/token/refresh",
                BEHIND_PROXY, "X-Real-IP", "198.51.100.1").getStatus()).isEqualTo(200);
        assertThat(call(filter, "POST", "/auth/token/refresh",
                BEHIND_PROXY, "X-Real-IP", "198.51.100.2").getStatus())
                .as("목록이 비었으면 헤더가 무시되고 둘 다 127.0.0.1 로 센다")
                .isEqualTo(429);
    }

    // ─────────────────── C. 429 본문이 계약의 Error 다 (완료 조건 11) ───────────────────

    @Test
    @DisplayName("429 본문이 계약의 Error 스키마와 같은 모양이다 — 최상위 키는 error 하나뿐")
    void tooManyRequestsBody_matchesTheContractErrorEnvelope() throws Exception {
        // 예전 본문은 {status, error(문자열), message, windowSeconds, limit} 평면 구조였다.
        // 계약(openapi.yaml 의 Error)은 {error:{code,message,traceId}} 다. 평면으로 되돌리면
        // 이 테스트가 빨간불이다 (완료 조건 11).
        MockHttpServletResponse blocked = exhaust(filter(1), "POST", "/auth/token/refresh", 1);

        assertThat(blocked.getStatus()).isEqualTo(429);
        assertThat(blocked.getContentType()).contains("application/json");

        @SuppressWarnings("unchecked")
        Map<String, Object> body = MAPPER.readValue(blocked.getContentAsString(), Map.class);

        assertThat(body.keySet())
                .as("최상위에 필드를 펼치면 앱의 error.code 분기가 그 자리에서 깨진다")
                .containsExactly("error");

        Object errorNode = body.get("error");
        assertThat(errorNode)
                .as("error 가 문자열이면 그건 계약이 아니라 예전 평면 구조다")
                .isInstanceOf(Map.class);

        @SuppressWarnings("unchecked")
        Map<String, Object> error = (Map<String, Object>) errorNode;
        assertThat(error).containsKeys("code", "message", "traceId");
        assertThat(error.get("code"))
                .as("GlobalExceptionHandler.codeOf(TOO_MANY_REQUESTS) 와 같은 어휘여야 한다")
                .isEqualTo("RATE_LIMITED");
        assertThat(String.valueOf(error.get("message"))).isNotBlank();
    }

    @Test
    @DisplayName("429 본문이 버킷 이름이나 내부 한도 수치를 노출하지 않는다")
    void tooManyRequestsBody_doesNotLeakInternals() throws Exception {
        // 이 단언은 예전에 `doesNotContain("bucket")` 하나뿐이었다. 그래서 본문을 옛 평면
        // 구조({"limit":1,"windowSeconds":3600,...})로 되돌려도 초록이었다 — 이름이
        // 약속한 "내부 한도 수치" 를 아무도 지키지 않고 있었다. 키 집합을 동등 비교한다.
        MockHttpServletResponse blocked = exhaust(filter(1), "POST", "/auth/oauth/kakao/callback", 1);

        @SuppressWarnings("unchecked")
        Map<String, Object> body = MAPPER.readValue(blocked.getContentAsString(), Map.class);
        assertThat(body.keySet()).containsExactly("error");

        @SuppressWarnings("unchecked")
        Map<String, Object> error = (Map<String, Object>) body.get("error");
        assertThat(error.keySet())
                .as("여기에 키가 하나라도 더 붙으면 그것이 곧 내부 분류의 유출이다")
                .containsExactlyInAnyOrder("code", "message", "traceId");

        String raw = blocked.getContentAsString();
        assertThat(raw)
                .as("버킷 이름·한도 수치·창 길이는 서버 내부 구현이다 — 응답에 실으면 그대로 새어 나간다")
                .doesNotContain("bucket")
                .doesNotContain("limit")
                .doesNotContain("windowSeconds")
                .doesNotContain("\"auth\"");
    }

    @Test
    @DisplayName("429 는 Retry-After 를 창 길이(초)로 붙인다")
    void tooManyRequests_carriesRetryAfter() throws Exception {
        MockHttpServletResponse blocked = exhaust(filter(1), "POST", "/auth/token/refresh", 1);

        assertThat(blocked.getHeader("Retry-After"))
                .as("앱은 이 값을 보고 기다린다. 없으면 즉시 재시도해 카운터를 더 태운다")
                .isEqualTo("3600");
    }

    // ─────────────────── C-2. 관광공사 프록시 (이슈 #40) ───────────────────

    @Test
    @DisplayName("주변 장소 경로에 한도가 있다 — 인증 없는 공개 경로라 특히 중요하다")
    void placesNearby_isMetered() throws Exception {
        RateLimitProperties p = props(100);
        p.setPlacesMaxRequests(1);
        ApiRateLimitFilter filter = new ApiRateLimitFilter(p, MAPPER);

        assertThat(call(filter, "GET", "/api/places/nearby", "203.0.113.40").getStatus()).isEqualTo(200);
        assertThat(call(filter, "GET", "/api/places/nearby", "203.0.113.40").getStatus())
                .as("""
                        표에 없는 경로는 한도가 0 이 아니라 무한이다 (📌 #86 원칙 4).
                        이 경로는 security: [] 라 토큰조차 필요 없다.
                        """)
                .isEqualTo(429);
    }

    @Test
    @DisplayName("상세와 목록이 다른 버킷이다 — 상세를 쏟아부어 지도를 막을 수 없어야 한다")
    void placesDetail_hasItsOwnBucket() throws Exception {
        RateLimitProperties p = props(100);
        p.setPlacesMaxRequests(5);
        p.setPlacesDetailMaxRequests(1);
        ApiRateLimitFilter filter = new ApiRateLimitFilter(p, MAPPER);

        assertThat(call(filter, "GET", "/api/places/123", "203.0.113.41").getStatus()).isEqualTo(200);
        assertThat(call(filter, "GET", "/api/places/123", "203.0.113.41").getStatus()).isEqualTo(429);

        assertThat(call(filter, "GET", "/api/places/nearby", "203.0.113.41").getStatus())
                .as("상세 버킷이 찼다고 지도가 함께 막히면 안 된다")
                .isEqualTo(200);
    }

    @Test
    @DisplayName("카탈로그가 상세보다 먼저 걸린다 — /api/places/catalog 은 상세 패턴에도 맞는다")
    void placesCatalog_hasItsOwnBucket() throws Exception {
        RateLimitProperties p = props(100);
        p.setPlacesDetailMaxRequests(5);
        p.setPlacesCatalogMaxRequests(1);
        ApiRateLimitFilter filter = new ApiRateLimitFilter(p, MAPPER);

        assertThat(call(filter, "GET", "/api/places/catalog", "203.0.113.42").getStatus())
                .isEqualTo(200);
        assertThat(call(filter, "GET", "/api/places/catalog", "203.0.113.42").getStatus())
                .as("""
                        카탈로그 규칙이 상세 규칙보다 **뒤에** 오면 ^/api/places/[^/]+$ 가 먼저
                        잡아서, 응답 2.83MB 짜리가 상세와 같은 분당 30 을 받는다 — 한 IP 가
                        분당 85MB 를 뽑아 갈 수 있다.
                        """)
                .isEqualTo(429);

        assertThat(call(filter, "GET", "/api/places/123", "203.0.113.42").getStatus())
                .as("카탈로그 버킷이 찼다고 상세가 함께 막히면 안 된다")
                .isEqualTo(200);
    }

    @Test
    @DisplayName("약관 동의 쓰기(PUT /api/consents)는 group-write 버킷이다 — 요청 한 건이 행을 만든다")
    void consentsPut_isMetered() throws Exception {
        RateLimitProperties p = props(100);
        p.setGroupWriteMaxRequests(1);
        ApiRateLimitFilter filter = new ApiRateLimitFilter(p, MAPPER);

        assertThat(call(filter, "PUT", "/api/consents", "203.0.113.43").getStatus()).isEqualTo(200);
        assertThat(call(filter, "PUT", "/api/consents", "203.0.113.43").getStatus())
                .as("표에 없는 경로는 한도가 0 이 아니라 무한이다 (📌 #86 원칙 4)")
                .isEqualTo(429);
        assertThat(call(filter, "GET", "/api/consents", "203.0.113.43").getStatus())
                .as("읽기는 버킷이 없다 — 로그인 때 한 번이다")
                .isEqualTo(200);
    }

    // ─────────────────── D. 스위치가 실제로 끈다 ───────────────────

    @Test
    @DisplayName("rate-limit.enabled=false 면 한도를 넘겨도 통과한다")
    void disabledSwitch_turnsTheLimiterOff() throws Exception {
        RateLimitProperties p = props(1);
        p.setEnabled(false);
        ApiRateLimitFilter filter = new ApiRateLimitFilter(p, MAPPER);

        assertThat(call(filter, "POST", "/auth/token/refresh", "198.51.100.7").getStatus()).isEqualTo(200);
        assertThat(call(filter, "POST", "/auth/token/refresh", "198.51.100.7").getStatus()).isEqualTo(200);
    }
}
