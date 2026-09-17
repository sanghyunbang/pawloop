package com.heattrip.heat_trip_backend.security;

import java.util.List;

/**
 * <b>토큰 없이 열리는 경로의 정본.</b> 이 저장소에서 "누구나 부를 수 있는 주소" 는 여기에만 적는다.
 *
 * <h2>왜 SecurityConfig 가 아니라 여기인가</h2>
 *
 * <p>2026-09-17 까지는 {@code config.SecurityConfig} 의 상수였다. 그런데 이 목록을 읽어야 하는 쪽이
 * 둘로 늘었다 — 인가를 거는 {@code SecurityConfig} 와, 동의를 강제하면서 <b>그 예외를 같은 목록으로
 * 정해야 하는</b> {@link ConsentRequiredFilter}(#660). 필터가 {@code config} 를 부르면
 * {@code config -> security -> config} 순환이 생긴다 — {@code ModuleCycleTest} 가 그것을 잡았다.
 *
 * <p>그래서 목록을 아래쪽인 {@code security} 로 내렸다. 이제 {@code config} 만 여기를 부르고,
 * 화살표는 한 방향이다. 사본을 만들지 않은 것이 요점이다 — 목록이 둘이 되면 한쪽에서 경로를 지워도
 * 다른 쪽은 모른 채 계속 열어 둔다.
 */
public final class PublicPaths {

    private PublicPaths() {
    }

    /**
     * 인증 없이 열리는 경로 — 이슈 #23-D. <b>정본은 계약의 Auth 태그 설명</b>이다.
     *
     * <h2>왜 상수로 꺼냈나</h2>
     * <p>여기 있는 경로는 <b>인증이라는 방어선이 없는</b> 것들이라, 남은 방어선이 레이트리밋
     * 하나뿐이다. 그런데 {@code ApiRateLimitFilter} 의 표에 <b>없으면 한도가 0 이 아니라
     * 무한</b>이다 — 즉 여기 한 줄을 더하면서 그쪽을 안 고치면 <b>인증도 한도도 없는
     * 경로</b>가 조용히 생긴다. 실제로 {@code /api/explore/**} 가 그 상태였다(#232).
     *
     * <p>메서드 지역 변수였을 때는 그것을 세는 검사를 쓸 수 없었다. 꺼내 두면
     * {@code PublicPathsAreRateLimitedTest} 가 전체를 돈다.
     */
    public static final List<String> PUBLIC_MATCHERS = List.of(
            "/",
            "/oauth2/**",
            "/login/**",
            "/auth/signup",
            // 가입 인증 (#635). 코드를 받은 사람은 아직 토큰이 없으므로 비인증이어야 한다.
            // 와일드카드(`/auth/signup/**`)로 안 여는 것은 의도다 — 나중에 그 아래 경로를
            // 하나 더 만들면 그것까지 **인증 없음 + 한도 무한**으로 딸려 들어간다(#232 의 자리).
            "/auth/signup/verify",
            "/auth/signup/resend",
            // 비밀번호 재설정 (#635 조각 ③). 비밀번호를 잊은 사람은 토큰이 없다 —
            // 인증 뒤에 두면 아무도 못 쓴다. 여기도 와일드카드가 아니라 낱개다.
            "/auth/password/reset-request",
            "/auth/password/reset",
            "/auth/login",
            "/auth/oauth/**",
            "/auth/token/refresh",
            "/error",
            "/actuator/health/**",
            "/actuator/info",
            "/actuator/prometheus",
            // 관광공사 프록시(#40). 계약이 security: [] 로 선언했다 — 지도는 로그인
            // 전에도 보여야 한다.
            //
            // "/api/places/**" 로 안 쓴 것은 의도다. 와일드카드로 열면 rate limit 의
            // 경로 분기가 못 덮는 자리(/api/places/a/b 같은)가 **인증 없음 + 한도 무한**
            // 이 된다. 여는 것은 실제로 있는 두 경로뿐이다.
            "/api/places/nearby",
            "/api/places/*",
            // 산책로의 선(#291). 셋째 경로다 — 지도는 로그인 전에도 보여야 한다.
            "/api/places/trails/*/route",
            // 산책 안전 지수(#336). 5km 격자 번호만 받는 GET 하나. **인증을 안 받는 것이 의도다** —
            // 누구의 격자인지 서버가 모르게 둔다(A안 #235). 한도는 rate limit 의 walk-safety 버킷(IP).
            "/api/walk-safety/now"
    );

    /**
     * {@code app.security.docs-public} 이 켜졌을 때만 열리는 경로 — 이슈 #232.
     *
     * <p><b>따로 둔 이유가 있다.</b> 조건부라 {@link #PUBLIC_MATCHERS} 에 못 넣는데, 그렇다고
     * 메서드 안에 두면 "공개되는 경로" 를 세는 검사가 이 셋을 못 본다 —
     * {@code PublicPathsAreRateLimitedTest} 가 둘을 함께 읽는다.
     */
    public static final List<String> DOCS_MATCHERS = List.of(
            "/v3/api-docs/**",
            "/swagger-ui.html",
            "/swagger-ui/**");

    /**
     * 게스트도 읽을 수 있는 커뮤니티 경로 — ADR-0016 결정 3 · #170. <b>GET 일 때만</b>이다.
     *
     * <p>{@link #PUBLIC_MATCHERS} 에 못 넣는 이유는 {@code SecurityConfig.filterChain} 의 주석에
     * 길게 적혀 있다 — 요지는 그 목록이 <b>경로만</b> 받는데 여기는 같은 경로에 GET(선택)과
     * POST(필수)가 겹친다는 것이다. 경로로 열면 글쓰기까지 비인증이 된다.
     *
     * <p>메서드 안의 문자열이 아니라 상수인 것은 <b>읽는 쪽이 둘이기 때문</b>이다(#660).
     * {@link ConsentRequiredFilter} 가 "동의 전에도 게스트와 같은 처지인 곳" 을 이 목록으로
     * 정한다 — 손으로 옮겨 적으면 사본이 둘이 되고, 여기 한 줄을 지웠을 때 그쪽은 모른 채
     * 계속 열어 둔다.
     */
    public static final List<String> COMMUNITY_GUEST_GETS = List.of(
            "/api/community/posts",
            "/api/community/posts/*",
            "/api/community/posts/*/comments");
}
