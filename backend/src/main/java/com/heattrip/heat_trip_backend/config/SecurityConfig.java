package com.heattrip.heat_trip_backend.config;

import java.util.ArrayList;
import java.util.List;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
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
import org.springframework.web.cors.CorsConfiguration;
import org.springframework.web.cors.CorsConfigurationSource;
import org.springframework.web.cors.UrlBasedCorsConfigurationSource;

import org.springframework.security.oauth2.client.web.OAuth2AuthorizationRequestRedirectFilter;

import com.heattrip.heat_trip_backend.OAuth.handler.OAuth2FailureHandler;
import com.heattrip.heat_trip_backend.OAuth.handler.OAuth2SuccessHandler;
import com.heattrip.heat_trip_backend.OAuth.jwt.JWTAuthenticationFilter;
import com.heattrip.heat_trip_backend.OAuth.jwt.JWTProvider;
import com.heattrip.heat_trip_backend.OAuth.service.CustomOAuth2UserService;
import com.heattrip.heat_trip_backend.OAuth.state.OAuthAppStateFilter;
import com.heattrip.heat_trip_backend.security.ApiRateLimitFilter;
import com.heattrip.heat_trip_backend.security.ChatRateLimitFilter;

import lombok.RequiredArgsConstructor;

@Configuration
@RequiredArgsConstructor
public class SecurityConfig {

    private final JWTProvider jwtProvider;
    private final CustomOAuth2UserService customOAuth2UserService;
    private final OAuth2SuccessHandler oAuth2SuccessHandler;
    private final OAuth2FailureHandler oAuth2FailureHandler;
    private final PublicSecurityProperties publicSecurityProperties;
    private final ApiRateLimitFilter apiRateLimitFilter;

    /** 채팅 버킷. 사용자 단위로 세야 해서 인증 <b>뒤</b>에 붙는다 (#80). */
    private final ChatRateLimitFilter chatRateLimitFilter;

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
        var publicMatchers = new ArrayList<>(List.of(
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
                "/api/explore/**"
        ));

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
                // ── 관리자 배치는 로그인한 아무나 부를 수 있으면 안 된다 ──────────────
                // `/api/curation/**` 보다 **먼저** 와야 한다. Spring Security 는 먼저
                // 일치하는 규칙을 쓰므로, 순서를 뒤집으면 이 줄이 영영 실행되지 않는다
                // (#14 에서 필터 등록 순서 때문에 rate limit 이 도달조차 못 한 것과 같은 종류다).
                //
                // 이 아래 `SeedEmotionAdminController` 는 전 장소를 돌며 외부 LLM 을
                // 호출하는 배치다(`SeedEmotionBatchService`). `.authenticated()` 만 걸려
                // 있던 동안에는 **로그인한 아무나 청구서를 늘릴 수 있었다.**
                //
                // 지금 `ROLE_ADMIN` 을 가진 계정은 없다 — `User.role` 기본값이 `ROLE_USER`
                // 하나뿐이라(`User.java:37,99`) 사실상 아무도 못 지나간다. 그게 의도다.
                // 운영자가 쓰려면 그 계정 행의 `users.role` 을 `ROLE_ADMIN` 으로 바꾸고
                // 다시 로그인하면 된다 — 토큰의 role 클레임이 그대로 권한이 되므로
                // (`JWTAuthenticationFilter.java:56`) 별도 배선이 필요 없다.
                .requestMatchers("/api/curation/admin/**").hasRole("ADMIN")
                .requestMatchers("/api/curation/**").authenticated()
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
                .userInfoEndpoint(userInfo -> userInfo.userService(customOAuth2UserService))
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
