전체 아키텍처 요약
OAuth2.0 소셜 로그인 -> 사용자 인증 -> JWT 생성 -> 프론트 전달 및 인증 처리

주요 구성 요소 (파일명 : 설명)

1. SecurityConfig : Spring Security 설정(configure(HttpSecurity))
2. OAuth2UserService : 각 소셜에서 받아온 사용자 정보를 가공하는 클래스
3. OAuth2SuccessHandler : 로그인 성공 시 JWT 발급 및 리다이렉트 처리
4. OAuth2FialureHandler : 로그인 실패시 처리
5. JWTProvider : JWT 생성/검증 유틸 (SUCCESSHANDLER랑 관련한 유틸들?)
6. JWTAuthenticationFilter : JWT가 있는 요청을 인증 처리해주는 필터
7. UserRepository : 소셜 로그인 사용자를 DB에 저장하거나 업데이트
8. CustomOAuth2User : 소셜 프로필을 감싸는 커스텀 유저 객체


코드 작업 순서

### (1) OAuth2User 인터페이스 만들기

- 소셜 제공자(GOOGLE, KAKAO, NAVER)별 응답 정보를 추상화
- 모든 사용자 정보 클래스가 구현해야할 공통 메서드 정의 

```
public interface OAuth2UserInfo {
    String getProvider();     // ex. "google", "kakao"
    String getProviderId();   // ex. Google의 sub, Kakao의 id
    String getEmail();        // 이메일
    String getName();         // 사용자 이름
}
```

### (2) 소셜별 사용자 정보 DTO 생성하기

2-1. GoogleOAuth2User.java

```
public class GoogleOAuth2User implements OAuth2UserInfo {
    private Map<String, Object> attributes;
    // 생성자, getter, 위 인터페이스 메서드 구현
}

```

2-2. NaverOAuth2User.java

```
public class NaverOAuth2User implements OAuth2UserInfo {
    private Map<String, Object> attributes;
    // "response" 내부 JSON 처리 주의
}
```

2-3. KakaoOauth2User.java

```
public class KakaoOAuth2User implements OAuth2UserInfo {
    private Map<String, Object> attributes;
    // profile, account 구조 파악 필요
}
```

### (3) CustomOAuth2UserService.java

- 소셜 응답을 위의 DTO로 변환하고 사용자 DB 등록 OR 조회 처리
- DefaultOAuth2UserService를 확장

```
@Service
public class CustomOAuth2UserService extends DefaultOAuth2UserService {
    @Override
    public OAuth2User loadUser(OAuth2UserRequest userRequest) throws OAuth2AuthenticationException {
        // registrationId (google, kakao, naver) 구분
        // 사용자 정보 DTO 생성
        // 사용자 DB 저장/조회
        // CustomUserDetails 리턴
    }
}
```

### (4) OAuth2SuccessHandler.java

- 로그인 성공 시 JWT 생성 및 응답 처리

```
@Component
public class OAuth2SuccessHandler extends SimpleUrlAuthenticationSuccessHandler {
    @Override
    public void onAuthenticationSuccess(HttpServletRequest request, HttpServletResponse response, Authentication authentication) {
        // 사용자 정보 가져오기
        // JWT 생성
        // 쿠키나 리다이렉트 응답으로 JWT 전달
    }
}

```

### (5) OAuth2FailureHandler.java

- 로그인 실패 처리

```
@Component
public class OAuth2FailureHandler extends SimpleUrlAuthenticationFailureHandler {
    @Override
    public void onAuthenticationFailure(HttpServletRequest request, HttpServletResponse response, AuthenticationException exception) {
        // 실패 로그 출력
        // 실패 응답 보내기 or 리다이렉트
    }
}
```

### (6) JWTProvider.java

- JWT 생성, 검증, 만료 여부 체크 유틸 클래스

```
@Component
public class JWTProvider {
    public String createAccessToken(String userId, String role) {...}
    public boolean validateToken(String token) {...}
    public String getUserIdFromToken(String token) {...}
}
```

### (7) JWTAuthenticationFilter.java

- 요청 헤더의 JWT를 파싱하여 사용자 인증 설정
- Spring Security의 인증 필터 앞에 추가

```
public class JWTAuthenticationFilter extends OncePerRequestFilter {
    @Override
    protected void doFilterInternal(...) {
        // Authorization 헤더에서 Bearer 토큰 추출
        // JWT 검증
        // SecurityContext에 사용자 정보 등록
    }
}
```

### (8) SecurityConfig.java

- 위의 모든 설정을 통합하고 filter, successhandler, userService 설정

```
@Configuration
@EnableWebSecurity
public class SecurityConfig extends WebSecurityConfigurerAdapter {
    @Override
    protected void configure(HttpSecurity http) throws Exception {
        http
            .oauth2Login()
                .userInfoEndpoint().userService(customOAuth2UserService)
                .and()
                .successHandler(oAuth2SuccessHandler)
                .failureHandler(oAuth2FailureHandler)
            .and()
            .addFilterBefore(jwtAuthenticationFilter(), UsernamePasswordAuthenticationFilter.class);
    }
}
```

com.example.security.oauth2
│
├── user
│   ├── OAuth2UserInfo.java
│   ├── GoogleOAuth2User.java
│   ├── KakaoOAuth2User.java
│   └── NaverOAuth2User.java
│
├── service
│   └── CustomOAuth2UserService.java
│
├── handler
│   ├── OAuth2SuccessHandler.java
│   └── OAuth2FailureHandler.java
│
├── jwt
│   ├── JWTProvider.java
│   └── JWTAuthenticationFilter.java
│
└── config
    └── SecurityConfig.java


### 전체 흐름 간단 요약 : OAuth2 로그인 → JWT 발급 → 이후 요청에서 JWT 인증

```
사용자 (Flutter 앱)
   │
   ├── ① [GET] /oauth2/authorization/google (또는 kakao/naver)
   │        └─ 사용자가 로그인 버튼을 눌러 요청
   ↓
[Spring Security 필터 체인 시작]
   ↓
② OAuth2LoginAuthenticationFilter (내부 제공)
   │
   ├── access token 요청 (소셜 인증 서버)
   ├── 사용자 정보 요청
   ↓
③ CustomOAuth2UserService.loadUser(userRequest)
   └─ GoogleOAuth2User, NaverOAuth2User 등 생성 (CustomOAuth2User로 래핑)
   └─ 반환된 OAuth2User는 SecurityContext에 저장됨
   ↓
④ SuccessHandler.onAuthenticationSuccess(request, response, authentication)
   └─ 사용자 정보 확인
   └─ JWT 생성
   └─ JWT를 **응답 본문 or 쿠키 or 헤더**로 Flutter에 전달
   ↓
✔️ 로그인 완료 (Flutter 앱은 JWT를 저장, ex: secure storage)

======================== 이후 요청부터는 ========================

Flutter 앱
   │
⑤ [GET or POST] /api/protected-resource
   └─ HTTP 요청 헤더에 JWT 포함 (Authorization: Bearer {token})
   ↓
⑥ JwtAuthenticationFilter (우리가 직접 구현)
   └─ JWT 파싱 및 검증
   └─ 유효하다면 UsernamePasswordAuthenticationToken 생성
   └─ SecurityContext에 저장
   ↓
⑦ Controller / Service
   └─ 인증된 사용자로 API 실행

```