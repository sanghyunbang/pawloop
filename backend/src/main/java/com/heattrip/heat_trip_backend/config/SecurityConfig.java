package com.heattrip.heat_trip_backend.config;

import java.util.ArrayList;
import java.util.List;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.HttpMethod;
import org.springframework.http.HttpStatus;
import org.springframework.security.authentication.AuthenticationManager;
import org.springframework.security.config.annotation.authentication.configuration.AuthenticationConfiguration;
import org.springframework.security.config.annotation.web.builders.HttpSecurity;
import org.springframework.security.config.http.SessionCreationPolicy;
import org.springframework.security.crypto.bcrypt.BCryptPasswordEncoder;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.security.web.SecurityFilterChain;
import org.springframework.security.web.authentication.HttpStatusEntryPoint;
import org.springframework.security.web.authentication.UsernamePasswordAuthenticationFilter;
import org.springframework.security.oauth2.client.endpoint.OAuth2AccessTokenResponseClient;
import org.springframework.security.oauth2.client.endpoint.OAuth2AuthorizationCodeGrantRequest;
import org.springframework.web.cors.CorsConfiguration;
import org.springframework.web.cors.CorsConfigurationSource;
import org.springframework.web.cors.UrlBasedCorsConfigurationSource;

import org.springframework.security.oauth2.client.web.OAuth2AuthorizationRequestRedirectFilter;

import com.heattrip.heat_trip_backend.OAuth.AppleOidcUserService;
import com.heattrip.heat_trip_backend.OAuth.handler.OAuth2FailureHandler;
import com.heattrip.heat_trip_backend.OAuth.handler.OAuth2SuccessHandler;
import com.heattrip.heat_trip_backend.OAuth.jwt.JWTAuthenticationFilter;
import com.heattrip.heat_trip_backend.OAuth.jwt.JWTProvider;
import com.heattrip.heat_trip_backend.OAuth.service.CustomOAuth2UserService;
import com.heattrip.heat_trip_backend.OAuth.state.OAuthAppStateFilter;
import com.heattrip.heat_trip_backend.security.ApiRateLimitFilter;
import com.heattrip.heat_trip_backend.security.ChatBodySizeLimitFilter;
import com.heattrip.heat_trip_backend.security.ChatRateLimitFilter;

import lombok.RequiredArgsConstructor;

@Configuration
@RequiredArgsConstructor
public class SecurityConfig {

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
    static final List<String> PUBLIC_MATCHERS = List.of(
            "/",
            "/oauth2/**",
            "/login/**",
            "/auth/signup",
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
            "/api/places/trails/*/route"
    );

    /**
     * {@code app.security.docs-public} 이 켜졌을 때만 열리는 경로 — 이슈 #232.
     *
     * <p><b>따로 둔 이유가 있다.</b> 조건부라 {@link #PUBLIC_MATCHERS} 에 못 넣는데, 그렇다고
     * 메서드 안에 두면 "공개되는 경로" 를 세는 검사가 이 셋을 못 본다 —
     * {@code PublicPathsAreRateLimitedTest} 가 둘을 함께 읽는다.
     */
    static final List<String> DOCS_MATCHERS = List.of(
            "/v3/api-docs/**",
            "/swagger-ui.html",
            "/swagger-ui/**");



    private final JWTProvider jwtProvider;
    private final CustomOAuth2UserService customOAuth2UserService;

    /** OIDC(openid scope) 등록 — Apple — 의 사용자 서비스. 같은 upsert 를 지난다 (#301). */
    private final AppleOidcUserService appleOidcUserService;

    /** 토큰 교환. Apple 만 client_secret 을 서명한 JWT 로 바꿔 끼운다 — AppleSignInConfig (#301). */
    private final OAuth2AccessTokenResponseClient<OAuth2AuthorizationCodeGrantRequest> accessTokenResponseClient;
    private final OAuth2SuccessHandler oAuth2SuccessHandler;
    private final OAuth2FailureHandler oAuth2FailureHandler;
    private final PublicSecurityProperties publicSecurityProperties;
    private final ApiRateLimitFilter apiRateLimitFilter;

    /** 채팅 버킷. 사용자 단위로 세야 해서 인증 <b>뒤</b>에 붙는다 (#80). */
    private final ChatRateLimitFilter chatRateLimitFilter;

    /** 채팅 본문 크기. 읽기 전에 막아야 해서 체인 <b>맨 앞</b>이다 (#129). */
    private final ChatBodySizeLimitFilter chatBodySizeLimitFilter;

    /** 앱이 만든 state 를 소셜 왕복 동안 세션에 붙들어 둔다. (이슈 #14) */
    private final OAuthAppStateFilter oAuthAppStateFilter;

    @Bean
    public PasswordEncoder passwordEncoder() {
        return new BCryptPasswordEncoder();
    }

    @Bean
    public AuthenticationManager authenticationManager(AuthenticationConfiguration configuration) throws Exception {
        return configuration.getAuthenticationManager();
    }

    @Bean
    public SecurityFilterChain filterChain(HttpSecurity http) throws Exception {
        // 인가 경계의 정본은 계약(docs/04-api/openapi.yaml)의 Auth 태그 설명이다.
        //
        // 예전에는 "/auth/**" 를 통째로 permitAll 했다. 그러면 회원 탈퇴(DELETE /auth/me)와
        // 프로필 수정(PUT /auth/me), 로그아웃(POST /auth/logout)이 Spring Security 인가
        // 계층을 아예 거치지 않는다. 컨트롤러가 @RequestHeader("Authorization") 를 직접 읽는
        // 것 말고는 방어가 없어서, 계약이 선언한 401 보장이 실제로는 성립하지 않았다. (이슈 #23-D)
        //
        // 그래서 비인증이어야 하는 경로만 열거한다. 나머지 /auth/* 는
        // anyRequest().authenticated() 로 떨어져 토큰 없이는 401 이 된다.
        var publicMatchers = new ArrayList<>(PUBLIC_MATCHERS);

        if (publicSecurityProperties.isDocsPublic()) {
            publicMatchers.add("/v3/api-docs/**");
            publicMatchers.add("/swagger-ui.html");
            publicMatchers.add("/swagger-ui/**");
        }

        http
            .cors(cors -> cors.configurationSource(corsConfigurationSource()))
            .csrf(csrf -> csrf.disable())
            .formLogin(login -> login.disable())
            .sessionManagement(session -> session.sessionCreationPolicy(SessionCreationPolicy.STATELESS))
            .authorizeHttpRequests(auth -> auth
                .requestMatchers(publicMatchers.toArray(String[]::new)).permitAll()
                // ── 커뮤니티 읽기는 인증이 선택이다 (ADR-0016 결정 3 · #170) ────────
                //
                // publicMatchers 에 못 넣는다. 그 목록은 **경로만** 받는데 커뮤니티는
                // 같은 경로에 GET(선택)과 POST(필수)가 겹친다 — 경로로 열면 글쓰기까지
                // 비인증이 된다. 감정 여행 시절의 /api/explore/** 가 그 반례였다 — 그 아래
                // POST .../feedback 이 실제로 토큰 없이 행을 만들었다(#94 로 지웠다).
                //
                // 와일드카드(/api/community/**)도 쓰지 않는다. 여는 것은 실제로 있는
                // GET 셋뿐이다 — /api/places/** 를 거부한 것과 같은 이유다(위 :94-96).
                //
                // 체인은 하나로 둔다. 나누면 필터 순서(chatBodySizeLimit → apiRateLimit →
                // JWTAuthentication → chatRateLimit)를 어느 체인에 복제할지 매번 정해야
                // 하고, 빠뜨리면 **게스트 경로만 한도 없이 열린다.**
                //
                // JWTAuthenticationFilter 는 여기에도 걸린다 — 토큰이 있으면 principal 을
                // 채우고 없으면 조용히 통과시킨다. 그래서 같은 경로가 게스트에게도, 로그인한
                // 사람에게도 열리고 CommunityController.viewerId() 가 둘을 가른다.
                .requestMatchers(HttpMethod.GET,
                        "/api/community/posts",
                        "/api/community/posts/*",
                        "/api/community/posts/*/comments").permitAll()
                .requestMatchers("/public/**").authenticated()
                .anyRequest().authenticated()
            )
            // oauth2Login() 을 켜면 기본 진입점이 LoginUrlAuthenticationEntryPoint 라서
            // 인증이 없는 요청에 401 이 아니라 로그인 페이지로 302 를 준다. 모바일 JSON API 에는
            // 쓸모가 없고, 계약(openapi.yaml)이 선언한 401 과도 어긋난다. 상태 코드로 답한다.
            // 소셜 로그인 진입점(/oauth2/**)은 permitAll 이라 이 변경의 영향을 받지 않는다.
            .exceptionHandling(ex -> ex.authenticationEntryPoint(
                    new HttpStatusEntryPoint(HttpStatus.UNAUTHORIZED)))
            // failureHandler 가 없으면 Spring Security 기본값이 /login?error 로 302 를 주고,
            // 그 경로에 핸들러가 없어 결국 500 이 된다. CustomOAuth2UserService 가 만든
            // email_already_registered 같은 원인 코드가 앱에 전혀 닿지 않는다. (이슈 #7)
            // 성공과 같은 딥링크로, 토큰 대신 에러 코드만 실어 돌려보낸다.
            .oauth2Login(oauth2 -> oauth2
                .tokenEndpoint(token -> token.accessTokenResponseClient(accessTokenResponseClient))
                .userInfoEndpoint(userInfo -> userInfo
                    .userService(customOAuth2UserService)
                    // scope 에 openid 가 있는 등록(Apple)은 이쪽이다 — id_token 클레임으로 같은 upsert (#301)
                    .oidcUserService(appleOidcUserService))
                .successHandler(oAuth2SuccessHandler)
                .failureHandler(oAuth2FailureHandler)
            );

        http.addFilterBefore(new JWTAuthenticationFilter(jwtProvider), UsernamePasswordAuthenticationFilter.class);
        // state 캡처는 진입점의 302 보다 **먼저** 일어나야 한다. 이 필터를 시큐리티 체인 밖에
        // 두면(빈으로만 등록하면) 자동 등록 순서상 시큐리티 체인 뒤라, 진입 요청은 이미 302 로
        // 끝난 뒤라서 앱이 붙인 state 를 영영 못 본다. (이슈 #14)
        http.addFilterBefore(oAuthAppStateFilter, OAuth2AuthorizationRequestRedirectFilter.class);

        // ⚠️ rate limit 은 **소셜 진입점 리다이렉트 필터보다 앞**이어야 한다. (이슈 #14)
        //
        // 예전에는 `addFilterBefore(apiRateLimitFilter, JWTAuthenticationFilter.class)` 였고,
        // 그 자리는 체인에서 OAuth2AuthorizationRequestRedirectFilter **뒤**다. 진입점 요청은
        // 그 리다이렉트 필터가 302 를 쓰고 chain.doFilter 를 부르지 않은 채 끝내므로,
        // 뒤에 있는 rate limit 필터까지 요청이 오지 않는다. 실제 체인 덤프로 확인한 순서:
        //   [6]OAuthAppStateFilter [7]OAuth2AuthorizationRequestRedirectFilter
        //   [8]OAuth2LoginAuthenticationFilter [9]ApiRateLimitFilter
        // 그 상태에서 한도 2 로 GET /oauth2/authorization/kakao 를 6번 치면 전부 302 였고,
        // 곧이어 같은 버킷의 POST /auth/token/refresh 가 401,401,429 를 냈다 — 앞선 6건이
        // 카운터에 **한 건도** 들어가지 않았다는 뜻이다. `resolveRule` 의 분기와
        // ApiRateLimitFilterTest.socialEntryPoint_isRateLimited 는 초록인데도 그랬다.
        // 단위 테스트는 필터를 직접 태우므로 체인 위치를 정의상 볼 수 없다.
        //
        // OAuthAppStateFilter 보다도 앞에 두는 이유: 한도를 넘긴 요청이 세션조차 만들지
        // 않는다(그 필터는 state 를 담으려고 request.getSession(true) 를 부른다).
        // 이 순서를 되돌리면 ApiRateLimitFilterChainOrderIntegrationTest 가 빨간불이다.
        http.addFilterBefore(apiRateLimitFilter, OAuthAppStateFilter.class);
        // ⚠️ 본문 크기 검사는 **rate limit 보다도 앞**이어야 한다. (이슈 #129)
        //
        // 20MB 본문을 읽어 String 으로 올린 뒤 400 을 내던 것이 이 필터가 고치는 것이다
        // (실측 317ms -> 15ms). 뒤에 두면 그 비용을 이미 치른 뒤에 막는 것이라 의미가 없다.
        // 인증보다도 앞인 것도 의도다 — 누가 보냈든 20MB 를 힙으로 올릴 이유가 없다.
        //
        // **이 줄이 apiRateLimitFilter 등록 아래에 있는 것은 필수다.** addFilterBefore 의 기준
        // 필터는 체인에 **이미 등록된** 것이어야 한다 — 위로 올리면 HttpSecurity 가
        // IllegalArgumentException 을 던지고 스프링 컨텍스트가 아예 안 뜬다(실측: 통합 테스트
        // 162건이 한꺼번에 죽었다). 체인에서의 위치는 여전히 rate limit 앞이다.
        http.addFilterBefore(chatBodySizeLimitFilter, ApiRateLimitFilter.class);

        // ⚠️ 채팅 rate limit 은 **JWT 필터 뒤**여야 한다. (이슈 #80)
        //
        // 위의 apiRateLimitFilter 는 체인 맨 앞이라 세는 시점에 사용자가 누구인지 모른다.
        // 그래서 열쇠가 IP 이고, 가족 넷이 한 공유기에서 동시에 폴링하면 넷이 한 카운터로
        // 합쳐진다 — 가족 단위 서비스에서 실제로 일어난다.
        //
        // 앞 필터를 뒤로 옮기는 것은 답이 아니다. 그 자리는 #14 가 정한 것이고 되돌리면
        // 소셜 진입점이 다시 무제한이 된다(리다이렉트 필터가 302 를 쓰고 체인을 끊는다).
        // 그래서 채팅 버킷만 별도 필터로 인증 뒤에 둔다.
        //
        // 이 순서를 되돌리면 SecurityContext 가 비어 있어 사용자 열쇠 대신 IP 로 떨어진다 —
        // 조용히 잘못 세는 것이라 ChatRateLimitFilterChainOrderIntegrationTest 가 지킨다.
        http.addFilterAfter(chatRateLimitFilter, JWTAuthenticationFilter.class);
        return http.build();
    }

    @Bean
    public CorsConfigurationSource corsConfigurationSource() {
        CorsConfiguration config = new CorsConfiguration();
        config.setAllowedOrigins(
                List.of(publicSecurityProperties.getAllowedOrigins().split(",")).stream()
                        .map(String::trim)
                        .filter(origin -> !origin.isEmpty())
                        .toList()
        );
        config.setAllowedMethods(List.of("GET", "POST", "PUT", "DELETE", "OPTIONS"));
        config.setAllowedHeaders(List.of("*"));
        config.setAllowCredentials(true);

        UrlBasedCorsConfigurationSource source = new UrlBasedCorsConfigurationSource();
        source.registerCorsConfiguration("/**", config);
        return source;
    }
}
