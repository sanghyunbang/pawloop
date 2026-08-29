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

import com.heattrip.heat_trip_backend.OAuth.handler.OAuth2SuccessHandler;
import com.heattrip.heat_trip_backend.OAuth.jwt.JWTAuthenticationFilter;
import com.heattrip.heat_trip_backend.OAuth.jwt.JWTProvider;
import com.heattrip.heat_trip_backend.OAuth.service.CustomOAuth2UserService;
import com.heattrip.heat_trip_backend.security.ApiRateLimitFilter;

import lombok.RequiredArgsConstructor;

@Configuration
@RequiredArgsConstructor
public class SecurityConfig {

    private final JWTProvider jwtProvider;
    private final CustomOAuth2UserService customOAuth2UserService;
    private final OAuth2SuccessHandler oAuth2SuccessHandler;
    private final PublicSecurityProperties publicSecurityProperties;
    private final ApiRateLimitFilter apiRateLimitFilter;

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
            .oauth2Login(oauth2 -> oauth2
                .userInfoEndpoint(userInfo -> userInfo.userService(customOAuth2UserService))
                .successHandler(oAuth2SuccessHandler)
            );

        http.addFilterBefore(new JWTAuthenticationFilter(jwtProvider), UsernamePasswordAuthenticationFilter.class);
        http.addFilterBefore(apiRateLimitFilter, JWTAuthenticationFilter.class);
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
