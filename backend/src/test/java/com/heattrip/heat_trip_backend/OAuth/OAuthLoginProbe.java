package com.heattrip.heat_trip_backend.OAuth;

import com.heattrip.heat_trip_backend.OAuth.handler.OAuth2SuccessHandler;
import com.heattrip.heat_trip_backend.OAuth.jwt.JWTProvider;
import com.heattrip.heat_trip_backend.OAuth.service.CustomOAuth2UserService;
import com.heattrip.heat_trip_backend.user.entity.RefreshToken;
import com.heattrip.heat_trip_backend.user.entity.User;
import com.heattrip.heat_trip_backend.user.repository.RefreshTokenRepository;
import com.heattrip.heat_trip_backend.user.repository.UserRepository;
import com.heattrip.heat_trip_backend.user.service.RefreshTokenService;
import org.mockito.ArgumentMatchers;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.core.ParameterizedTypeReference;
import org.springframework.http.HttpStatus;
import org.springframework.http.RequestEntity;
import org.springframework.http.ResponseEntity;
import org.springframework.mock.web.MockHttpServletRequest;
import org.springframework.mock.web.MockHttpServletResponse;
import org.springframework.security.oauth2.client.registration.ClientRegistration;
import org.springframework.security.oauth2.client.userinfo.OAuth2UserRequest;
import org.springframework.security.oauth2.core.AuthorizationGrantType;
import org.springframework.security.oauth2.core.OAuth2AccessToken;
import org.springframework.security.oauth2.core.OAuth2AuthenticationException;
import org.springframework.security.oauth2.core.user.OAuth2User;
import org.springframework.security.oauth2.client.authentication.OAuth2AuthenticationToken;
import org.springframework.test.util.ReflectionTestUtils;
import org.springframework.web.client.RestOperations;

import java.time.Clock;
import java.time.Instant;
import java.util.HashMap;
import java.util.Map;
import java.util.Optional;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.when;

/**
 * 소셜 로그인 한 번(사용자 정보 조회 → 신규 가입 → JWT 발급 → 앱으로 리다이렉트)을
 * 네트워크·DB 없이 그대로 재현하는 테스트 지그.
 *
 * 로그 위생 테스트(#6)와 표준출력 회귀 테스트가 같은 경로를 공유해야 해서 여기에 모았다.
 * UserInfo 호출은 {@link RestOperations} 를 갈아끼워 막고, DB 는 리포지토리 목으로 막는다.
 */
final class OAuthLoginProbe {

    /** 소셜 ID. 로그 어디에도 나타나면 안 되는 값. */
    static final String PROVIDER_ID = "109876543210987654321";

    /** 이메일. 로그 어디에도 나타나면 안 되는 값. */
    static final String EMAIL = "probe-user@example.com";

    /** 정확히 32바이트 — HS256 최소 키 길이. */
    static final String SECRET = "test-only-secret-key-32bytes-min!!";

    private OAuthLoginProbe() {
    }

    static JWTProvider jwtProvider() {
        JWTProvider provider = new JWTProvider();
        ReflectionTestUtils.setField(provider, "secret", SECRET);
        ReflectionTestUtils.setField(provider, "expirationMillis", 3_600_000L);
        ReflectionTestUtils.invokeMethod(provider, "init");
        return provider;
    }

    /**
     * DB 없이 도는 refresh 토큰 서비스. 저장은 목이 삼키고, 발급된 원문만 밖으로 나온다. (이슈 #9)
     */
    static RefreshTokenService refreshTokenService() {
        RefreshTokenRepository refreshTokenRepository = mock(RefreshTokenRepository.class);
        when(refreshTokenRepository.save(any(RefreshToken.class)))
                .thenAnswer(invocation -> invocation.getArgument(0));
        return new RefreshTokenService(
                refreshTokenRepository, mock(UserRepository.class), jwtProvider(),
                Clock.systemDefaultZone(), 1_209_600_000L);
    }

    /**
     * 로그인 1회가 발급한 두 자격증명.
     *
     * <p>refresh 토큰이 여기 함께 있는 이유: RT 는 14일짜리라 로그에 새면 대가가 AT 보다 크다.
     * 로그 위생 테스트가 원문과 그 SHA-256 해시를 둘 다 대조할 수 있어야 한다. (이슈 #6·#9)
     */
    record IssuedTokens(String accessToken, String refreshToken) {
    }

    /**
     * 로그인 1회를 끝까지 수행한다.
     *
     * @return 발급된 액세스 토큰·refresh 토큰 원문 (로그에 남지 않았는지 대조할 때 쓴다)
     */
    static IssuedTokens runLogin() throws Exception {
        OAuth2User user = loadUser();

        // CustomOAuth2User.getName() → provider_providerId. 성공 핸들러가 이 값을 subject 로 쓴다.
        user.getName();

        JWTProvider jwtProvider = jwtProvider();
        MockHttpServletRequest request = new MockHttpServletRequest();
        MockHttpServletResponse response = new MockHttpServletResponse();
        OAuth2AuthenticationToken authentication =
                new OAuth2AuthenticationToken(user, user.getAuthorities(), "google");

        new OAuth2SuccessHandler(jwtProvider, refreshTokenService())
                .onAuthenticationSuccess(request, response, authentication);

        String redirect = response.getRedirectedUrl();
        if (redirect == null || !redirect.contains("token=")) {
            throw new IllegalStateException("리다이렉트 URL 에 토큰이 없다: " + redirect);
        }
        // substring 으로 자르지 않는다 — &refresh= 가 붙은 뒤로는 'token=' 뒤가 AT 의 끝이 아니다.
        return new IssuedTokens(queryParam(redirect, "token"), queryParam(redirect, "refresh"));
    }

    /** 딥링크 쿼리스트링에서 파라미터 하나를 꺼낸다. 값에는 URL 예약문자가 없다(Base64URL·JWT). */
    static String queryParam(String url, String name) {
        String query = url.substring(url.indexOf('?') + 1);
        for (String pair : query.split("&")) {
            int eq = pair.indexOf('=');
            if (eq > 0 && pair.substring(0, eq).equals(name)) {
                return pair.substring(eq + 1);
            }
        }
        throw new IllegalStateException("딥링크에 " + name + " 파라미터가 없다: " + url);
    }

    /** 신규 가입 분기에서 DB 가 채워 주는 PK. 실제 저장소는 IDENTITY 로 값을 넣어 준다. */
    static final long ASSIGNED_USER_ID = 42L;

    /** CustomOAuth2UserService.loadUser 를 네트워크 없이 실행한다(신규 가입 분기). */
    static OAuth2User loadUser() {
        UserRepository userRepository = mock(UserRepository.class);
        // 식별 키는 (provider, social_id) 다 — username 이 아니다. (이슈 #7)
        when(userRepository.findByProviderAndSocialId("google", PROVIDER_ID)).thenReturn(Optional.empty());
        when(userRepository.findByUsername("google_" + PROVIDER_ID)).thenReturn(Optional.empty());
        when(userRepository.findByEmail(EMAIL)).thenReturn(Optional.empty());
        // 지그 보수: save 를 스텁하지 않으면 목이 null 을 돌려주고, CustomOAuth2UserService.createUser 는
        // 반환값을 쓰지 않으므로 user.getId() 가 null 로 남는다. 실제 저장소라면 절대 일어나지 않는 상태다.
        // 그대로 두면 #5 이후의 OAuth2SuccessHandler 가 users.id 를 못 찾아 토큰 대신 실패 딥링크를
        // 돌려주고, 이 지그를 쓰는 로그 위생·표준출력 테스트 9건이 #5 와 무관한 이유로 무너진다.
        when(userRepository.save(any(User.class))).thenAnswer(invocation -> {
            User saved = invocation.getArgument(0);
            if (saved.getId() == null) {
                saved.setId(ASSIGNED_USER_ID);
            }
            return saved;
        });

        return service(userRepository).loadUser(userRequest());
    }

    // ───────────────────── 실패·충돌 분기 (이슈 #7 / #6) ─────────────────────
    //
    // 아래 세 프로브는 이 PR 이 새로 만든 '이메일이 오가는 경로'를 로그 위생 테스트가
    // 실제로 태울 수 있게 하려고 있다. 성공 경로 하나만 돌리면 이 분기들은 한 줄도
    // 실행되지 않아서, 누가 이메일을 로그로 흘려도 스위트가 초록불이었다.

    /**
     * 같은 이메일을 쓰는 계정이 이미 있어 신규 가입이 거절되는 경로.
     *
     * @return {@code CustomOAuth2UserService.emailAlreadyRegistered} 가 던진 예외
     */
    static OAuth2AuthenticationException runEmailCollisionLogin() {
        UserRepository userRepository = mock(UserRepository.class);
        when(userRepository.findByProviderAndSocialId("google", PROVIDER_ID)).thenReturn(Optional.empty());
        when(userRepository.findByUsername("google_" + PROVIDER_ID)).thenReturn(Optional.empty());
        // 구글로 처음 들어온 이 이메일을 카카오 계정이 이미 쓰고 있다.
        when(userRepository.findByEmail(EMAIL)).thenReturn(Optional.of(
                User.builder().id(99L).provider("kakao").socialId("k-1").email(EMAIL).build()));

        return expectFailure(userRepository);
    }

    /**
     * 사전 조회와 INSERT 사이에 같은 값이 끼어들어 저장이 무결성 제약에 걸리는 경로.
     *
     * <p>목이 던지는 메시지는 MySQL 이 실제로 주는 문구 그대로다 — 그 안에 이메일 원문이
     * 들어 있으므로, 예외를 cause 로 싣거나 메시지를 이어 붙이면 로그로 새어 나간다.
     *
     * @return {@code CustomOAuth2UserService.saveNew} 가 던진 예외
     */
    static OAuth2AuthenticationException runIntegrityViolationLogin() {
        UserRepository userRepository = mock(UserRepository.class);
        when(userRepository.findByProviderAndSocialId("google", PROVIDER_ID)).thenReturn(Optional.empty());
        when(userRepository.findByUsername("google_" + PROVIDER_ID)).thenReturn(Optional.empty());
        when(userRepository.findByEmail(EMAIL)).thenReturn(Optional.empty());
        when(userRepository.save(any(User.class))).thenThrow(new DataIntegrityViolationException(
                "could not execute statement [Duplicate entry '" + EMAIL + "' for key 'users.UK_email']"));

        return expectFailure(userRepository);
    }

    /**
     * 기존 행에 공급자 이메일을 반영하려는데 그 이메일을 다른 계정이 이미 쓰고 있는 경로.
     * 로그인은 통과하고 email 갱신만 건너뛴다.
     */
    static OAuth2User runEmailUpdateSkippedLogin() {
        User existing = User.builder()
                .id(42L).provider("google").socialId(PROVIDER_ID)
                .name("프로브 사용자").nickname("프로브 사용자").role("ROLE_USER")
                .build();
        UserRepository userRepository = mock(UserRepository.class);
        when(userRepository.findByProviderAndSocialId("google", PROVIDER_ID))
                .thenReturn(Optional.of(existing));
        when(userRepository.findByEmail(EMAIL)).thenReturn(Optional.of(
                User.builder().id(99L).provider("kakao").socialId("k-1").email(EMAIL).build()));

        return service(userRepository).loadUser(userRequest());
    }

    private static OAuth2AuthenticationException expectFailure(UserRepository userRepository) {
        try {
            service(userRepository).loadUser(userRequest());
        } catch (OAuth2AuthenticationException e) {
            return e;
        }
        throw new IllegalStateException("실패 분기를 태우지 못했다 — 프로브 스텁이 어긋났다.");
    }

    /** userinfo HTTP 를 목으로 막은 서비스. 공급자 응답에는 늘 {@link #EMAIL} 이 들어 있다. */
    @SuppressWarnings("unchecked")
    private static CustomOAuth2UserService service(UserRepository userRepository) {
        Map<String, Object> attributes = new HashMap<>();
        attributes.put("sub", PROVIDER_ID);
        attributes.put("email", EMAIL);
        attributes.put("name", "프로브 사용자");

        RestOperations restOperations = mock(RestOperations.class);
        when(restOperations.exchange(any(RequestEntity.class),
                ArgumentMatchers.<ParameterizedTypeReference<Map<String, Object>>>any()))
                .thenReturn(new ResponseEntity<>(attributes, HttpStatus.OK));

        CustomOAuth2UserService service = new CustomOAuth2UserService(userRepository);
        service.setRestOperations(restOperations);
        return service;
    }

    private static OAuth2UserRequest userRequest() {
        ClientRegistration registration = ClientRegistration.withRegistrationId("google")
                .clientId("test-client-id")
                .clientSecret("test-client-secret")
                .authorizationGrantType(AuthorizationGrantType.AUTHORIZATION_CODE)
                .redirectUri("http://localhost:8080/login/oauth2/code/google")
                .authorizationUri("http://localhost:0/authorize")
                .tokenUri("http://localhost:0/token")
                .userInfoUri("http://localhost:0/userinfo")
                .userNameAttributeName("sub")
                .build();

        OAuth2AccessToken accessToken = new OAuth2AccessToken(
                OAuth2AccessToken.TokenType.BEARER,
                "probe-access-token",
                Instant.now(),
                Instant.now().plusSeconds(60));

        return new OAuth2UserRequest(registration, accessToken);
    }
}
