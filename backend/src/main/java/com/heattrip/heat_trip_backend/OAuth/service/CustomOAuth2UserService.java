package com.heattrip.heat_trip_backend.OAuth.service;

import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.security.oauth2.client.userinfo.DefaultOAuth2UserService;
import org.springframework.security.oauth2.client.userinfo.OAuth2UserRequest;
import org.springframework.security.oauth2.core.OAuth2AuthenticationException;
import org.springframework.security.oauth2.core.OAuth2Error;
import org.springframework.security.oauth2.core.user.OAuth2User;
import org.springframework.stereotype.Service;
import org.springframework.util.StringUtils;

import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;

import java.time.LocalDateTime;
import java.util.Locale;
import java.util.Map;
import java.util.Objects;
import java.util.Optional;

import com.heattrip.heat_trip_backend.OAuth.user.CustomOAuth2User;
import com.heattrip.heat_trip_backend.OAuth.user.GoogleOAuth2User;
import com.heattrip.heat_trip_backend.OAuth.user.KakaoOAuth2User;
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
@RequiredArgsConstructor // final 필드에 대한 생성자를 자동으로 생성해줍니다 -> repository 주입
public class CustomOAuth2UserService extends DefaultOAuth2UserService {

    /** 공급자가 표시 이름을 하나도 주지 않았을 때 쓰는 닉네임 접두사. */
    static final String DEFAULT_NICKNAME_PREFIX = "반려인";

    private final UserRepository userRepository; // 사용자 정보를 저장할 JPA Repository

    /**
     * 소셜 로그인 후 사용자 정보 요쳥이 완료되면 자동으로 이 메서드가 호출
     * 내부적으로 AccessToken을 이용해 소셜 제공자에게 사용자 정보를 요청하고,
     * 미리 정의한 DTO로 변환하는 역할을 함
     *
     * <p><b>이 메서드는 단위 테스트 대상이 아니다.</b> {@code super.loadUser(userRequest)} 가
     * 공급자 userinfo 엔드포인트로 실제 HTTP 를 친다. DB 조회·생성·갱신은 전부
     * {@link #upsertUser(OAuth2UserInfo, Map)} 로 떼어 놨고, 테스트는 그쪽을 겨눈다. (이슈 #7)
     */
    @Override
    public OAuth2User loadUser(OAuth2UserRequest userRequest) throws OAuth2AuthenticationException {

        // 기본 메서드를 사용하여 OAuth2 서버에서 사용자 정보를 가져옴
        OAuth2User oAuth2User = super.loadUser(userRequest);

        // 소셜 로그인 제공자 식별자 (google, kakao, naver 등)
        String registrationId = userRequest.getClientRegistration().getRegistrationId();

        // 사용자 정보 (Map<String, Object>)를 가져옴
        Map<String, Object> attributes = oAuth2User.getAttributes();

        OAuth2UserInfo userInfo = toUserInfo(registrationId, attributes);

        // 사용자 정보 로그 출력 — 소셜 ID(providerId)와 이메일은 남기지 않는다. 제공자 이름만. (이슈 #6)
        log.info("[OAuth2 로그인] provider: {}", userInfo.getProvider());

        return upsertUser(userInfo, attributes);
    }

    /**
     * registrationId → 공급자별 파서.
     *
     * <p>대소문자를 정규화한다. 카카오 설정은 {@code client-name=Kakao} 라서 예전 코드에는
     * {@code case "kakao"} 와 {@code case "Kakao"} 가 나란히 있었다. registrationId 는 설정 파일이
     * 정하는 값이라 언제든 대소문자가 흔들릴 수 있고, case 를 하나씩 늘리는 것은 해결이 아니다.
     */
    static OAuth2UserInfo toUserInfo(String registrationId, Map<String, Object> attributes) {
        String provider = (registrationId == null) ? "" : registrationId.trim().toLowerCase(Locale.ROOT);
        return switch (provider) {
            case "google" -> new GoogleOAuth2User(attributes);
            case "kakao" -> new KakaoOAuth2User(attributes);
            // naver 는 여기 없다. ADR-0010 이 보류로 확정했고, 클라이언트 등록도
            // application-dev/prod.properties 에서 걷어냈다(#15). 분기만 남겨 두면
            // "지원한다" 는 인상을 주는 죽은 코드가 되고, 등록을 되살리는 사람이
            // 그 분기를 근거로 삼는다. 되살리려면 ADR-0010 을 먼저 고쳐야 한다.
            default -> throw new OAuth2AuthenticationException(
                    new OAuth2Error("unsupported_provider"),
                    "지원하지 않는 소셜 공급자입니다: " + provider);
        };
    }

    /**
     * 소셜 계정을 찾거나 만든다 — 이 클래스에서 DB 를 만지는 유일한 지점.
     *
     * <p>식별 키는 {@code (provider, social_id)} 다. <b>이메일로 찾지 않는다.</b>
     * 카카오는 이메일을 주지 않을 수 있고, 사용자가 나중에 동의를 켜면 값이 생긴다.
     * 시간에 따라 나타났다 사라지는 값은 식별 키가 될 수 없다.
     *
     * @return 신규 생성 여부({@code isNew})까지 실은 인증 주체
     */
    public CustomOAuth2User upsertUser(OAuth2UserInfo userInfo, Map<String, Object> attributes) {
        String provider = userInfo.getProvider();
        String socialId = trimToNull(userInfo.getProviderId());

        if (socialId == null) {
            // social_id 가 없으면 이 사람을 다시 알아볼 방법이 없다. 익명 행을 만드느니 실패한다.
            throw new OAuth2AuthenticationException(
                    new OAuth2Error("missing_social_id"),
                    "소셜 공급자가 사용자 고유 ID 를 주지 않았습니다. provider=" + provider);
        }

        Optional<User> existing = findExisting(provider, socialId);

        if (existing.isPresent()) {
            User user = existing.get();
            if (applyProviderProfile(user, userInfo)) {
                // 예전에는 여기서 아무것도 하지 않고 곧장 return 했다. 그래서 카카오에서 닉네임을
                // 바꿔도 우리 DB 는 영원히 옛날 값이었다. (이슈 #7)
                userRepository.save(user);
                log.debug("[OAuth2 로그인] 기존 사용자 프로필 갱신 (provider={})", provider);
            }
            return principal(userInfo, attributes, user, false);
        }

        User created = createUser(userInfo, provider, socialId);
        log.debug("신규 사용자 생성 후 CustomOAuth2User 반환 (provider={})", provider); // 제공자 이름만 남긴다 (이슈 #6)
        return principal(userInfo, attributes, created, true);
    }

    // ─────────────────────────── 조회 ───────────────────────────

    private Optional<User> findExisting(String provider, String socialId) {
        Optional<User> byKey = userRepository.findByProviderAndSocialId(provider, socialId);
        if (byKey.isPresent()) {
            return byKey;
        }

        // 백필 SQL(backend/mysql/post-start/04_users_social_account_model.sql)이
        // 아직 돌지 않은 레거시 행은 식별자가
        // username = "{provider}_{socialId}" 한 문자열에 뭉쳐 있다. 여기서 새 컬럼으로 옮겨 심지 않으면
        // 그 사용자는 로그인할 때마다 계정이 하나씩 새로 생긴다.
        return userRepository.findByUsername(legacyUsername(provider, socialId))
                .map(legacy -> {
                    legacy.setProvider(provider);
                    legacy.setSocialId(socialId);
                    userRepository.save(legacy);
                    log.info("[OAuth2 로그인] 레거시 계정을 (provider, social_id) 로 이관했다. provider={}", provider);
                    return legacy;
                });
    }

    // ─────────────────────────── 생성 ───────────────────────────

    private User createUser(OAuth2UserInfo userInfo, String provider, String socialId) {
        String email = trimToNull(userInfo.getEmail());
        if (email != null && userRepository.findByEmail(email).isPresent()) {
            throw emailAlreadyRegistered(provider);
        }

        // 공급자가 준 표시 이름. 카카오는 nickname(필수 동의라 보통 온다), 구글은 name.
        // 둘 다 없을 수 있고, 그래도 가입은 성공해야 한다.
        String displayName = trimToNull(userInfo.getName());
        LocalDateTime now = LocalDateTime.now();

        User user = User.builder()
                .username(legacyUsername(provider, socialId)) // 레거시 독자를 위해 계속 채운다
                .provider(provider)
                .socialId(socialId)
                .role(User.ROLE_USER)
                .email(email)          // null 일 수 있다 — 그게 정상이다
                .name(displayName)
                .nickname(displayName) // 공급자 이름을 초기 닉네임으로 쓴다
                .gender(User.Gender.OTHER) // 기본값 설정 (필요시 수정 가능)
                .travelType("default") // 기본 여행 타입 설정 (필요시 수정 가능)
                .createdAt(now)
                .updatedAt(now)
                .build();

        saveNew(user, provider);

        if (!StringUtils.hasText(user.getNickname())) {
            // 기본 닉네임은 id 가 있어야 만들 수 있어서 저장 이후다. 신규 가입 1회뿐인 추가 UPDATE 다.
            user.setNickname(defaultNickname(user));
            saveNew(user, provider);
        }
        return user;
    }

    private void saveNew(User user, String provider) {
        try {
            userRepository.save(user);
        } catch (DataIntegrityViolationException e) {
            // 사전 조회와 INSERT 사이에 같은 이메일/같은 소셜 계정이 끼어든 경합.
            // 예외 원인(e)을 그대로 싣지 않는다 — DB 메시지에 이메일 값이 들어 있고,
            // 그게 인증 실패 로그로 흘러가면 이슈 #6 의 로그 위생이 깨진다.
            log.warn("[OAuth2 로그인] 계정 저장이 무결성 제약에 걸렸다. provider={}", provider);
            throw new OAuth2AuthenticationException(
                    new OAuth2Error("account_conflict"),
                    "계정 생성에 실패했습니다. 잠시 후 다시 시도해 주세요. provider=" + provider);
        }
    }

    /**
     * 공급자가 이름을 하나도 주지 않았을 때의 기본 닉네임.
     *
     * <p>소셜 ID 를 넣지 않는다 — 닉네임은 다른 사용자에게 보이는 값이다(이슈 #6).
     */
    static String defaultNickname(User user) {
        Long id = user.getId();
        return (id != null) ? DEFAULT_NICKNAME_PREFIX + id : DEFAULT_NICKNAME_PREFIX;
    }

    // ─────────────────────────── 갱신 ───────────────────────────

    /**
     * 공급자가 준 최신 프로필을 기존 행에 반영한다.
     *
     * @return 실제로 바뀐 값이 있으면 true (있을 때만 저장한다)
     */
    private boolean applyProviderProfile(User user, OAuth2UserInfo userInfo) {
        boolean changed = false;

        String displayName = trimToNull(userInfo.getName());
        if (displayName != null && !displayName.equals(user.getName())) {
            // 사용자가 우리 앱에서 직접 고친 닉네임은 덮지 않는다.
            // user.getName() 은 '지난 로그인에서 공급자가 준 이름'이므로,
            // 닉네임이 아직 그 값 그대로면 사용자가 손대지 않았다는 뜻이다.
            if (!StringUtils.hasText(user.getNickname()) || user.getNickname().equals(user.getName())) {
                user.setNickname(displayName);
            }
            user.setName(displayName);
            changed = true;
        }

        String imageUrl = trimToNull(userInfo.getImageUrl());
        if (imageUrl != null && !imageUrl.equals(user.getImageUrl())) {
            user.setImageUrl(imageUrl);
            changed = true;
        }

        // 이메일은 처음엔 null 이었다가, 사용자가 나중에 카카오에서 이메일 동의를 켜면 값이 생긴다.
        String email = trimToNull(userInfo.getEmail());
        if (email != null && !email.equalsIgnoreCase(user.getEmail())) {
            if (isTakenByAnother(email, user.getId())) {
                // 같은 이메일이 다른 계정에 이미 붙어 있다(예: 구글로 먼저 가입한 뒤 카카오로 로그인).
                // 계정 연동은 #2 Epic 범위 밖이다. 여기서 로그인을 막으면 '이미 잘 쓰던 계정'의
                // 사용자가 갑자기 못 들어오게 되므로, 로그인은 통과시키고 이메일만 갱신하지 않는다.
                // (신규 생성 때는 그럴 여지가 없어 실패시킨다 — createUser 참고.)
                log.warn("[OAuth2 로그인] 공급자 이메일이 다른 계정에 이미 등록돼 있어 갱신을 건너뛴다. provider={}",
                        user.getProvider());
            } else {
                user.setEmail(email);
                changed = true;
            }
        }

        if (!StringUtils.hasText(user.getRole())) {
            user.setRole(User.ROLE_USER); // role 컬럼이 없던 시절에 만들어진 행
            changed = true;
        }
        return changed;
    }

    private boolean isTakenByAnother(String email, Long selfId) {
        return userRepository.findByEmail(email)
                .filter(other -> !Objects.equals(other.getId(), selfId))
                .isPresent();
    }

    // ─────────────────────────── helpers ───────────────────────────

    private static CustomOAuth2User principal(OAuth2UserInfo userInfo,
                                              Map<String, Object> attributes,
                                              User user,
                                              boolean isNew) {
        return new CustomOAuth2User(userInfo, attributes, user.getId(), user.getRole(), isNew);
    }

    private OAuth2AuthenticationException emailAlreadyRegistered(String provider) {
        // 이메일 값 자체는 예외 메시지에 넣지 않는다 — 인증 실패 로그로 흘러간다(이슈 #6).
        log.warn("[OAuth2 로그인] 이미 다른 계정이 쓰는 이메일이라 가입을 거절했다. provider={}", provider);
        return new OAuth2AuthenticationException(
                new OAuth2Error("email_already_registered"),
                "이 이메일로 만들어진 계정이 이미 있습니다. 처음 가입한 방식으로 로그인해 주세요. provider=" + provider);
    }

    /** 레거시 username 규칙. 이제 식별 키가 아니라 '옛 행을 찾는 열쇠'일 뿐이다. */
    static String legacyUsername(String provider, String socialId) {
        return provider + "_" + socialId;
    }

    private static String trimToNull(String value) {
        if (value == null) {
            return null;
        }
        String trimmed = value.trim();
        return trimmed.isEmpty() ? null : trimmed;
    }
}
