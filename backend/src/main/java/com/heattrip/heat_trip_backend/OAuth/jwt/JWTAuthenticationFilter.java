package com.heattrip.heat_trip_backend.OAuth.jwt;

import java.io.IOException;
import java.util.Collections;

import org.springframework.security.authentication.UsernamePasswordAuthenticationToken;
import org.springframework.security.core.authority.SimpleGrantedAuthority;
import org.springframework.security.core.context.SecurityContextHolder;
import org.springframework.security.web.authentication.WebAuthenticationDetails;
import org.springframework.security.web.authentication.WebAuthenticationDetailsSource;
import org.springframework.util.StringUtils;
import org.springframework.web.filter.OncePerRequestFilter;

import jakarta.servlet.FilterChain;
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

/**
 * JWT 인증을 위한 커스텀 필터 클래스
 * - Spring Security의 OncePerRequestFilter를 상속받아 요청당 한 번만 실행됨
 * - 요청 헤더에서 JWT 토큰을 추출하고, 검증 후 인증 정보를 SecurityContext에 설정함
 */
public class JWTAuthenticationFilter extends OncePerRequestFilter {
    
   private final JWTProvider jwtProvider; // JWT 토큰 생성 및 검증 등을 담당

    // 생성자를 통한 의존성 주입 (SecurityConfig에서 new로 생성하며 주입해 사용)
    public JWTAuthenticationFilter(JWTProvider jwtProvider) {
        this.jwtProvider = jwtProvider;
    }

    @Override
    protected void doFilterInternal(HttpServletRequest request, HttpServletResponse response, FilterChain filterChain) throws ServletException, IOException {
        // 1. HTTP 요청 Authorization 헤더에서 JWT 토큰 추출
        String token = extractToken(request);

        // 2. 토큰이 존재하고 유효한 경우
        if (token != null && jwtProvider.validateToken(token)) {
            // JWTProvider를 통해 토큰에서 사용자 ID 추출
            String userId = jwtProvider.getUserIdFromToken(token);
                        
            // JWTProvider를 통해 토큰에서 사용자 Role 추출
            String role = jwtProvider.getRoleFromToken(token);

            // 3. 인증 객체 생성 (여기서는 간단히 userId와 role을 사용, 패스워드는 null 처리)
            UsernamePasswordAuthenticationToken authentication = new UsernamePasswordAuthenticationToken(
                    userId, // 사용자 ID
                    null, // 패스워드는 사용하지 않음
                    Collections.singletonList(new SimpleGrantedAuthority(role)) // 권한 부여 , singltonList를 써서 immutable 리스트로 생성
            );

            // 4. 인증 객체에 요청 정보 설정 (IP, 세션 등)
            // 모바일 앱의 경우 세션은 보통 null
            authentication.setDetails(new WebAuthenticationDetailsSource().buildDetails(request));

            // 5. SecurityContext에 인증 정보 저장
            // 이 인증 정보는 이후 요청 처리 과정에서 사용됨
            SecurityContextHolder.getContext().setAuthentication(authentication);
        }

        // 6. 다음 필터로 요청 전달
        /**
         * [클라이언트]
            ↓
            [JWTAuthenticationFilter]
            → request 헤더에서 JWT 추출
            → SecurityContext 설정
            → filterChain.doFilter(request, response)
            ↓
            [다음 필터들...] : Spring Seurity의 다른 필터들
            → 예: OAuth2LoginAuthenticationFilter, UsernamePasswordAuthenticationFilter 등
            ↓
            [컨트롤러 (@RestController)]
            ↓
            [HttpServletResponse에 응답 작성]

         */
        filterChain.doFilter(request, response);
    }

   // 요청 헤더에서 JWT 토큰을 추출하는 메서드
   private String extractToken(HttpServletRequest request) {
        String header = request.getHeader("Authorization"); // 일반적으로 "Authorization: Bearer <token>" 형식임
        if(StringUtils.hasText(header) && header.startsWith("Bearer ")) {
            return header.substring(7); // "Bearer " 이후의 토큰 부분만 반환
        }
        return null; // 토큰이 없거나 형식이 잘못된 경우 null 반환
    }
    
}
