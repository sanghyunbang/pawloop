package com.heattrip.heat_trip_backend.OAuth.handler;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.security.core.Authentication;
import org.springframework.security.web.authentication.AuthenticationSuccessHandler;
import org.springframework.stereotype.Component;

import com.heattrip.heat_trip_backend.OAuth.jwt.JWTProvider;
import com.heattrip.heat_trip_backend.OAuth.user.CustomOAuth2User;
import com.heattrip.heat_trip_backend.user.service.RefreshTokenService;

import java.io.IOException; 
import jakarta.servlet.ServletException;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.servlet.http.HttpServletResponse;

@Component // 자동으로 빈에 등록해줌. 이후에 SecurityConfig에서 @EnableWebSecurity로 활성화된 Spring Security 설정에 의해 사용됨
// AuthenticationSuccessHandler 인터페이스를 구현하여 로그인 성공 시 동작을 정의할 예정
// 이 클래스는 OAuth2 로그인 성공 후 추가 작업을 처리하는 데 사용.
public class OAuth2SuccessHandler implements AuthenticationSuccessHandler{

    private static final Logger log = LoggerFactory.getLogger(OAuth2SuccessHandler.class);

    // JWT 생성 및 서명 등을 처리하는 클래스 (JWTProvider) 미리 만들어 둠
    private final JWTProvider jwtProvider;

    // 생성자를 통한 의존성 주입 (? gradle말고 여기서 말하는 의존성 주입은 또 뭐지)
    // JWTProvider를 주입받아 사용( JWTProvider가 빈에 주입 되어 있어야 함)

    /** refresh 토큰 발급·저장의 유일한 통로. (이슈 #9) */
    private final RefreshTokenService refreshTokenService;

    public OAuth2SuccessHandler(JWTProvider jwtProvider, RefreshTokenService refreshTokenService) {
        this.jwtProvider = jwtProvider;
        this.refreshTokenService = refreshTokenService;
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
        
        // 진입 여부만 남긴다. 소셜 ID 도 users.id 도 로그에 남기지 않는다. (이슈 #6)
        log.debug("OAuth2 로그인 성공 처리 진입");

         // subject 는 users.id 다. 예전에는 authentication.getName()(= CustomOAuth2User.getName()
         // = "kakao_1234567890")을 그대로 썼고, 그 값이 소비처에서 이메일로 해석되는 바람에
         // 모든 소셜 계정에서 /auth/me 계열이 400 이었다. (이슈 #5)
         //
         // CustomOAuth2User.getName() 자체는 그대로 둔다 — Spring Security 가 principal 이름으로 쓰고,
         // 로그 위생 테스트(OAuthLoggingHygieneTest)가 그 값이 로그에 없음을 보장하는 기준이기도 하다.
         CustomOAuth2User principal = (CustomOAuth2User) authentication.getPrincipal();
         Long userId = principal.getUserId();

         if (userId == null) {
             // users.id 를 모르는 principal 로는 토큰을 만들 수 없다. 여기서 sub="null" 토큰을 발급하면
             // 앱 secure storage 에 저장되어 그 계정은 재로그인 전까지 영구 401 이 된다.
             // 실패 딥링크는 OAuth2FailureHandler 와 같은 모양이다 — 앱은 이미 그 형태를 기다린다.
             log.warn("[OAuth2 로그인] 인증 주체에 users.id 가 없어 토큰을 발급하지 않는다.");
             response.sendRedirect("heattrip://login-callback?error=account_state_invalid");
             return;
         }

         // 사용자 권한 정보 가져오기
         String role = authentication.getAuthorities().iterator().next().getAuthority(); // 권한 정보 가져오기 (예: ROLE_USER)

         // JWT 토큰 생성
         String token = jwtProvider.createAccessToken(userId, role);

         // refresh 토큰 발급·저장. 원문은 여기서 딥링크로 나가는 것 말고는 아무 데도 남지 않는다. (이슈 #9)
         String refreshToken = refreshTokenService.issueFor(userId);

         // flutter + web_oauth_2 에 맞춰서 redirect URI 만들기
         // 예: heattrip://login-callback?token=<access-token>&refresh=<refresh-token>
         //
         // ⚠️ token= 를 **앞**에 유지한다. 계약(openapi.yaml)에 적힌 현행 URL 접두사가
         //    `?token=` 이라, 순서를 뒤집으면 그 접두사로 매칭하는 기존 파싱이 즉사한다.
         //
         // ⚠️ 그래도 앱은 파싱을 고쳐야 한다: AT 는 더 이상 URL 의 꼬리가 아니다.
         //    'token=' 뒤를 전부 잘라 쓰면 &refresh=... 까지 삼켜 손상된 토큰을 저장한다.
         //    Uri.parse(url).queryParameters['token'] 로 읽어야 한다. (인수인계 대상: #11)
         //
         // ⚠️ 위험을 정확히 적어 둔다: RT 는 14일짜리 자격증명이고 이 딥링크는 302 의 Location
         //    헤더(액세스 로그·프록시 로그)와 브라우저 히스토리에 남는다. AT 가 이미 나가고 있는
         //    같은 채널이라 노출 '채널'이 새로 생기지는 않지만 창의 길이가 1시간 → 14일로 커진다.
         //    그 창은 회전 + 재사용 감지가 실질적으로 좁힌다(탈취된 RT 를 쓰는 순간, 정당한
         //    사용자의 다음 회전이 전량 폐기를 유발한다). 토큰을 URL 로 넘기는 방식 자체를
         //    1회용 코드 교환으로 바꾸는 것은 #14 의 범위다.
         String redirect = "heattrip://login-callback?token=" + token + "&refresh=" + refreshToken;

         // 캐시 경로 한 줄을 닫는다. 이 응답에는 두 개의 자격증명이 실려 있다.
         response.setHeader("Cache-Control", "no-store");

         response.sendRedirect(redirect);

         // 리다이렉트 URL 에는 토큰이 실려 있으므로 절대 로그로 남기지 않는다.
         // (액세스 로그·리버스 프록시 로그에 남는 문제는 운영 로그 설정 점검 대상이다 — 이슈 #6 참고)
         log.debug("OAuth2 로그인 성공 — 앱으로 리다이렉트 완료");
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
