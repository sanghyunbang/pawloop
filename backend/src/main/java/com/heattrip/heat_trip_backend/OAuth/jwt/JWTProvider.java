package com.heattrip.heat_trip_backend.OAuth.jwt;

import io.jsonwebtoken.*; // JWT 토큰 생성을 위한 JJWT 라이브러리의 핵심 클래스들
import io.jsonwebtoken.security.Keys; // 안전한 서명 키 생성을 위한 도구

import jakarta.annotation.PostConstruct;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.security.access.method.P;
import org.springframework.stereotype.Component;

import java.security.Key;
import java.util.Date;

@Component
public class JWTProvider {
    
    // application.properties 파일에서 jwt.secret 값을 읽기
    @Value("${jwt.secret}")
    private String secret;

    // JWT 서명을 위한 키 객체
    // 이 키는 비밀 키로, JWT 토큰의 서명을 생성하고 검증하는 데 사용됩니다.    
    private Key key;

    private final long TOKEN_VALID_TIME = 1000L * 60 * 60 * 10000; // 1시간

    // @PostConstruct 어노테이션은 이 메서드가 빈 초기화 후에 호출됨을 나타냅니다.
    // 이 메서드는 JWTProvider가 생성된 후, 즉 의존성 주입이 완료된 후에 실행됩니다.
    // 이 시점에서 비밀 키를 기반으로 실제 서명용 키 객체를 생성합니다.
    @PostConstruct
    protected void init() {
        // 주입된 비밀 키를 기반으로 실제 서명용 key 객체 생성
        this.key = Keys.hmacShaKeyFor(secret.getBytes());
    }

    /**
     * JWT Access Token 생성
     * @param userId 사용자 ID (예: "abc123")
     * @param role 사용자 권한 정보 (예: "ROLE_USER")
     * @return 생성된 JWT 문자열
     */


    public String createAccessToken(String userId, String role) {
        Date now = new Date();
        Date expiry = new Date(now.getTime() + TOKEN_VALID_TIME);

        System.out.println("[JWTProvider] token 생성 진입");
        System.out.println("[JWTProvider] secret length = " + secret.length());
        System.out.println("[JWTProvider] userId: " + userId + ", role: " + role);


        return Jwts.builder()
                .setSubject(userId)
                .claim("role", role)
                .setIssuedAt(now)
                .setExpiration(expiry)
                .signWith(key, SignatureAlgorithm.HS256)
                .compact();
    }

    public String getUserIdFromToken(String token) {
        return parseClaims(token).getSubject();
    }

    public String getRoleFromToken(String token) {
        return parseClaims(token).get("role", String.class); // JWT 내의 role 클레임 읽기
    }


    /**
     * JWT 토큰을 파싱해서 내부 클레임(내용)을 추출
     * @param token JWT 토큰 문자열
     * @return Claims 객체 (토큰의 내용)
     * @throws JwtException JWT 파싱 중 오류 발생 시 예외
     * @throws IllegalArgumentException 토큰이 null이거나 비어있을 때 예외
     */
    private Claims parseClaims(String token) {
        try {
            return Jwts.parserBuilder() // 파서를 설정할 빌더 객체를 가져옴 
                    .setSigningKey(key) // 서명 검증에 쓸 키를 설정
                    .build() // 파서 빌드 완료(객체가 생성된 걸 의미)
                    .parseClaimsJws(token) // JWT 문자열을 실제로 파싱하고 서명 확인
                    .getBody(); // 성공적으로 파싱되면 내부 payload(클레임) 반환
        } catch (JwtException | IllegalArgumentException e) {
            // 유효하지 않은 토큰(만료, 위조, 형식 오류 등)이 들어오면 발생
            throw new RuntimeException("Invalid JWT token"); // 사용자 정의 예외로 던짐
        }   
    }

    public boolean validateToken(String token) {
        try {
            parseClaims(token); // 내부에서 예외 없으면 유효한 토큰
            return true;
        } catch (JwtException | IllegalArgumentException e) {
            return false; // 파싱 실패하면 유효하지 않은 토큰 
        }
    }
 
}
