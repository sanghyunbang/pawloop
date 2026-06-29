package com.heattrip.heat_trip_backend.OAuth.service;

import org.springframework.security.oauth2.client.userinfo.DefaultOAuth2UserService;
import org.springframework.security.oauth2.client.userinfo.OAuth2UserRequest;
import org.springframework.security.oauth2.core.OAuth2AuthenticationException;
import org.springframework.security.oauth2.core.user.OAuth2User;
import org.springframework.stereotype.Service;

import jakarta.validation.OverridesAttribute;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;

import java.time.LocalDateTime;
import java.util.Map;
import java.util.Optional;

import com.heattrip.heat_trip_backend.OAuth.user.CustomOAuth2User;
import com.heattrip.heat_trip_backend.OAuth.user.GoogleOAuth2User;
import com.heattrip.heat_trip_backend.OAuth.user.KakaoOAuth2User;
import com.heattrip.heat_trip_backend.OAuth.user.NaverOAuth2User;
import com.heattrip.heat_trip_backend.OAuth.user.OAuth2UserInfo;
import com.heattrip.heat_trip_backend.user.entity.User;
import com.heattrip.heat_trip_backend.user.repository.UserRepository;

// 이 클래스는 로그인 성공시 호출될 예정 : SuccessHandler랑 관련
// 1. 어떤 소셜 로그인인지 식별 
// 2. 해당 응답 데이터를 OAuth2UserInfo 인터페이스를 구현한 객체로 변환
// 3. 사용자 DB 조회 및 저장/갱신 로직 수행
// 4. 최종적으로 인증객체(OAuth2User)를 생성하여 반환
// + 사용자 정보를 SecurityContext에 저장하여 인증 상태 유지 (?) => Spring Seucurity가 자동으로 해줌

// cf) Spring Seucurity OAuth2 의 동작 흐름 요약
//
// 1. 사용자가 Google/Kakao/Naver 소셜 로그인 버튼을 클릭하면,
//    Spring Security는 해당 소셜 제공자의 인증 서버로 리다이렉트합니다.
//
// 2. 사용자가 인증에 성공하면 소셜 서버는 '인가 코드 (authorization code)'를 콜백 URI로 보냅니다.
//     이건 application.yml 또는 application.properties 파일에 입력
//      spring.security.oauth2.client.registration.google.redirect-uri={baseUrl}/login/oauth2/code/{registrationId}
//     - 예: http://localhost:8080/login/oauth2/code/google
//     - 이 URI는 Spring Security가 미리 설정해둔 콜백 URI입니다.
//
// 3. Spring Security는 이 인가 코드를 이용해 Access Token을 받아옵니다.
//     → 따로 "인가 코드 → 토큰" 요청을 직접 구현하지 않아도 됨.
//
// 4. 그런 다음 Access Token을 사용해 소셜 제공자에게 사용자 정보를 요청하고,
//    응답 데이터를 바탕으로 OAuth2User 객체를 생성합니다.
//
// 5. 이때 호출되는 것이 CustomOAuth2UserService.loadUser(OAuth2UserRequest)입니다.
//    - 내부에서 registrationId(google/kakao/naver)에 따라 응답을 파싱하여
//      OAuth2UserInfo(GoogleOAuth2User, KakaoOAuth2User 등) 객체로 래핑합니다.
//
// 6. 생성된 OAuth2User 객체는 Spring Security가 내부적으로
//    Authentication 객체로 감싸고 SecurityContextHolder에 저장합니다.
//     - OAuth2User 객체를 Spring Security가 내부적으로 감싸서 Authentication 객체로 자동 생성합니다.
//     - 이건 OAuth2LoginAuthenticationFilter 내부에서 자동 처리됩니다.
//
// 7. 이후 애플리케이션은 이 Authentication 객체를 통해 사용자의 인증 상태를 확인할 수 있습니다.
//  - SecurityContextHolder는 현재 로그인한 사용자 정보를 담는 곳이에요. 정확히는 스레드마다 SecurityContext를 저장하는 유틸리티 클래스(객체를 저장하는 정적(Static) 유틸리티 클래스입니다.)
//  - 내부적으로 ThreadLocal을 이용함
//  - SecurityContextHolder.getContext().getAuthentication();
//  - 이 코드를 쓰면 지금 로그인한 사용자의 인증 정보(Authentication 객체)를 가져올 수 있습니다.

// 이후 사용자는 인증된 상태가 되어 protected 리소스에 접근할 수 있게 됩니다.

@Slf4j // 로그를 출력할 수 있는 어노테이션 (@slf4j -> log.info("메시지"), log.error() 형태로 사용 가능)
@Service // 이 클래스는 서비스 레이어에서 사용되는 컴포넌트로, 스프링이 자동으로 빈으로 등록합니다.
// @Service 어노테이션은 이 클래스가 서비스 역할을 한다는 것을 스프링에게 알려줍니다.
// - 서비스 레이어는 비즈니스 로직을 처리하는 곳으로, 컨트롤러와 데이터 액세스 레이어(Repository) 사이에서 중간 역할을 합니다.

// @RequiredArgsConstructor // final로 선언된 필드에 대해 생성자를 자동으로 생성해줍니다.
// - 이 어노테이션은 Lombok 라이브러리에서 제공하며, final 필드에 대한 생성자를 자동으로 생성합니다.
// - 이 클래스의 생성자는 final로 선언된 필드들에 대한 생성자를 자동으로 만들어줍니다.
// - 예를 들어, @Autowired를 사용하지 않고도 의존성 주입을 할 수 있습니다.

@RequiredArgsConstructor // final 필드에 대한 생성자를 자동으로 생성해줍니다 -> repository 주입

public class CustomOAuth2UserService extends DefaultOAuth2UserService {

    private final UserRepository userRepository; // 사용자 정보를 저장할 JPA Repository

    /**
     * 소셜 로그인 후 사용자 정보 요쳥이 완료되면 자동으로 이 메서드가 호출
     * 내부적으로 AccessToken을 이용해 소셜 제공자에게 사용자 정보를 요청하고,
     * 미리 정의한 DTO로 변환하는 역할을 함
     */

     @Override
     public OAuth2User loadUser(OAuth2UserRequest userRequest) throws OAuth2AuthenticationException {
        
        try {
            System.out.println("[V] CustomOAuth2UserService.loadUser 진입");
            // 기존 처리
        } catch (Exception e) {
            System.out.println("[!] CustomOAuth2UserService.loadUser에서 예외 발생: " + e.getMessage());
            e.printStackTrace();
            throw e;
        }


        // 기본 메서드를 사용하여 OAuth2 서버에서 사용자 정보를 가져옴
        OAuth2User oAuth2User = super.loadUser(userRequest);

        // 소셜 로그인 제공자 식별자 (google, kakao, naver 등)
        String registrationId = userRequest.getClientRegistration().getRegistrationId();

        // 사용자 정보 (Map<String, Object>)를 가져옴
        Map<String, Object> attributes = oAuth2User.getAttributes();

        // 공통 사용자 정보 인터페이스를 구현한 객체 생성
        OAuth2UserInfo userInfo;  

        // 제공자에 따라 적절한 OAuth2UserInfo 객체 생성
        switch (registrationId) {
            case "google":
                userInfo = new GoogleOAuth2User(attributes);
                break;      
            case "kakao":
                userInfo = new KakaoOAuth2User(attributes);
                break;
            case "Kakao":
                userInfo = new KakaoOAuth2User(attributes);
                break;
            case "naver":
                userInfo = new NaverOAuth2User(attributes);
                break;  
            default:
                throw new OAuth2AuthenticationException("Unsupported provider: " + registrationId);

        }

        // 사용자 정보 로그 출력
        log.info("[OAuth2 로그인] provider: {}, userId: {}, email: {}", 
            userInfo.getProvider(), userInfo.getProviderId(), userInfo.getEmail());
        
        // 여기서 DB 조회 및 회원 가입 로직 등을 추가할 수 있음
        //    - 사용자 정보 저장
        //    - JWT 발급은 SuccessHandler에서 진행 예정

        String username = userInfo.getProvider() + "_" + userInfo.getProviderId();


        Optional<User> existingUser = userRepository.findByUsername(username);
        User user;
        if (existingUser.isPresent()) {
            user = existingUser.get(); // 로그인 유저
            // 기존 유저에 대해 필요한 업데이트 로직 추가 가능
            return new CustomOAuth2User(userInfo, attributes);

            // 기존 사용자 정보 업데이트 (예: 이메일, 프로필 사진 등) 로직 추가 가능
        
        } else {

            user = User.builder()
                .username(username) // provider + providerId 형식으로 username 설정
                .email(userInfo.getEmail())  // email은 OAuth2UserInfo에서 가져옴
                .name(userInfo.getName()) // 사용자 이름
                .gender(User.Gender.OTHER) // 기본값 설정 (필요시 수정 가능)
                .travelType("default") // 기본 여행 타입 설정 (필요시 수정 가능)
                .createdAt(LocalDateTime.now()) // 생성일
                .updatedAt(LocalDateTime.now()) // 수정일
                .build();

        // 새 사용자 저장
        userRepository.save(user); // ← 신규 유저는 저장도 필요

        System.out.println("[DEBUG] Returning CustomOAuth2User for provider: " + registrationId); // [0802 디버깅 추가]


        // 사용자 정보를 우리 CustomOAuth2User 객체에 담아서 반환 ( getName() 메서드로 사용자 식별 가능하게 해놓음 ( SucessHanlder와 관련 ) )
        return new CustomOAuth2User(userInfo, attributes);
        }
    }
}