package com.heattrip.heat_trip_backend.OAuth.handler;

import org.springframework.security.core.Authentication;
import org.springframework.security.web.authentication.AuthenticationSuccessHandler;
import org.springframework.stereotype.Component;

import com.heattrip.heat_trip_backend.OAuth.jwt.JWTProvider;

import java.io.IOException; 
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

@Component // 자동으로 빈에 등록해줌. 이후에 SecurityConfig에서 @EnableWebSecurity로 활성화된 Spring Security 설정에 의해 사용됨
// AuthenticationSuccessHandler 인터페이스를 구현하여 로그인 성공 시 동작을 정의할 예정
// 이 클래스는 OAuth2 로그인 성공 후 추가 작업을 처리하는 데 사용.
public class OAuth2SuccessHandler implements AuthenticationSuccessHandler{

    // JWT 생성 및 서명 등을 처리하는 클래스 (JWTProvider) 미리 만들어 둠
    private final JWTProvider jwtProvider;

    // 생성자를 통한 의존성 주입 (? gradle말고 여기서 말하는 의존성 주입은 또 뭐지)
    // JWTProvider를 주입받아 사용( JWTProvider가 빈에 주입 되어 있어야 함)

    public OAuth2SuccessHandler(JWTProvider jwtProvider) {
        this.jwtProvider = jwtProvider;
    }

    /**
     * 인증 성공 시 실행되는 메서드
     * @param request 사용자의 요청 객체
     * @param response 서버의 응답 객체
     * @param authentication 인증 성공 후의 사용자 정보 객체 (Principal, 권한 등 포함)
     */

     @Override
     public void onAuthenticationSuccess(HttpServletRequest request, 
                                         HttpServletResponse response, 
                                         Authentication authentication) throws IOException, ServletException {
        
        System.out.println("[V] OAuth2SuccessHandler triggered"); // 진입여부 확인

         // 인증 성공 후 JWT 토큰 생성 및 응답에 추가하는 로직을 구현할 예정
         // 예: String token = jwtProvider.createAccessToken(authentication.getName(), authentication.getAuthorities());
         // response.addHeader("Authorization", "Bearer " + token);
         
         // getName() 메서드는 CustomOAuth2User에서 provider + "_" + providerId 형식으로 사용자 식별자를 반환하도록 구현되어 있음
         String userId = authentication.getName();

         // 사용자 권한 정보 가져오기
         String role = authentication.getAuthorities().iterator().next().getAuthority(); // 권한 정보 가져오기 (예: ROLE_USER)

         // JWT 토큰 생성
         String token = jwtProvider.createAccessToken(userId, role);

         // flutter + web_oauth_2 에 맞춰서 redirec URI 만들기
         // 예: heattrip://login-callback?token=<access-token>

         String redirect = "heattrip://login-callback?token=" + token;

         response.sendRedirect(redirect);
         
         System.out.println("[!] onAuthenticationSuccess() called!");
         System.out.println("[V] userId = " + userId);


        
    }  
    
}




         // Flutter 앱으로 리디랙션
         // 아래 URI는 flutter_web_auth_2에서 설정한 redirect URI와 일치해야 함


         // 클라이언트(Flutter)에게 JSON 형태로 응답 : FLUTTER + FLUTTER_wEB_AUTH_2는 JSON 못받아옴
        //  response.setContentType("application/json");
        //  response.setCharacterEncoding("UTF-8");
         
        //  Map<String, String> tokenMap = new HashMap<>();
        //  tokenMap.put("accessToken", token);
        //  tokenMap.put("userId", userId);
        //  tokenMap.put("role", role);

         // JSON을 만들어서 HTTP 응답으로 보내는 행위
         // Spring Security가 내부적으로 호출해서 처리 결과를 응답으로 보내주는 방식
         // 리턴을 하지 않아도 response 객체에 직접 쓰기(write) 

         // ObjectMapper는 Jackson 라이브러리에서 제공하는 JSON 처리 클래스
         // writeValue() : Java 객체를 JSON으로 변환해서 출력 (파일, 문자열, HTTP 응답 등)

         // response.getWriter() : HttpServletResponse 객체에서 본문에 글을 쓸 수 있는 출력 스트림을 가져옴

         /**
         *  Java Map 객체 (tokenMap)
                ↓
            ObjectMapper.writeValue(출력대상, java 객체)
                ↓
            JSON 변환 후
                ↓
            response.getWriter()로 응답 본문에 출력
                ↓
            클라이언트에서 JSON 응답 수신

         */
        //  new ObjectMapper().writeValue(response.getWriter(), tokenMap); 
