package com.heattrip.heat_trip_backend.OAuth.service;

import com.heattrip.heat_trip_backend.OAuth.user.CustomOAuth2User;
import com.heattrip.heat_trip_backend.OAuth.user.GoogleOAuth2User;
import com.heattrip.heat_trip_backend.OAuth.user.KakaoOAuth2User;
import com.heattrip.heat_trip_backend.OAuth.user.OAuth2UserInfo;
import com.heattrip.heat_trip_backend.user.entity.User;
import com.heattrip.heat_trip_backend.user.repository.UserRepository;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.security.oauth2.core.OAuth2AuthenticationException;

import java.util.HashMap;
import java.util.Map;
import java.util.Optional;
import java.util.concurrent.atomic.AtomicLong;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.assertj.core.api.Assertions.catchThrowableOfType;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * 소셜 계정 upsert — 이슈 #7.
 *
 * <p>{@code loadUser} 는 {@code super.loadUser(userRequest)} 로 공급자에 실제 HTTP 를 쳐서
 * 단위 테스트할 수 없다. DB 조회·생성·갱신은 {@link CustomOAuth2UserService#upsertUser} 로
 * 떼어 놨고, 이 테스트는 그쪽만 겨눈다. (정책 #21 — 서비스 계층은 Mockito)
 */
@ExtendWith(MockitoExtension.class)
class CustomOAuth2UserServiceTest {

    private static final String SOCIAL_ID = "1234567890";

    @Mock
    private UserRepository userRepository;

    private CustomOAuth2UserService service;

    /** JPA IDENTITY 를 흉내 낸다 — save 가 새 행에 PK 를 채워 준다. */
    private final AtomicLong sequence = new AtomicLong(0);

    @BeforeEach
    void setUp() {
        service = new CustomOAuth2UserService(userRepository);
    }

    private void givenSaveAssignsId() {
        when(userRepository.save(any(User.class))).thenAnswer(invocation -> {
            User saved = invocation.getArgument(0);
            if (saved.getId() == null) {
                saved.setId(sequence.incrementAndGet());
            }
            return saved;
        });
    }

    // ─────────────────────── 신규 생성 ───────────────────────

    @Test
    @DisplayName("이메일이 null 인 카카오 응답으로도 사용자 생성이 성공한다")
    void upsert_createsUserEvenWhenKakaoGivesNoEmail() {
        // 이메일 동의를 거부한 사용자의 응답 — kakao_account 에 email 키가 없다.
        OAuth2UserInfo kakao = kakao(SOCIAL_ID, "보리아빠", null);
        when(userRepository.findByProviderAndSocialId("kakao", SOCIAL_ID)).thenReturn(Optional.empty());
        when(userRepository.findByUsername("kakao_" + SOCIAL_ID)).thenReturn(Optional.empty());
        givenSaveAssignsId();

        CustomOAuth2User principal = service.upsertUser(kakao, Map.of("id", SOCIAL_ID));

        ArgumentCaptor<User> captor = ArgumentCaptor.forClass(User.class);
        verify(userRepository).save(captor.capture());
        User saved = captor.getValue();

        assertThat(saved.getProvider()).isEqualTo("kakao");
        assertThat(saved.getSocialId()).isEqualTo(SOCIAL_ID);
        assertThat(saved.getEmail()).isNull();          // 여기서 죽지 않는 것이 이 이슈의 핵심이다
        assertThat(saved.getNickname()).isNotNull();
        assertThat(saved.getRole()).isEqualTo("ROLE_USER");
        assertThat(saved.getUsername()).isEqualTo("kakao_" + SOCIAL_ID); // 레거시 독자용으로 계속 채운다
        assertThat(principal.isNew()).isTrue();
    }

    @Test
    @DisplayName("공급자가 이름도 주지 않으면 반려인{id} 기본 닉네임을 만든다")
    void upsert_generatesDefaultNicknameWhenProviderGivesNoName() {
        OAuth2UserInfo kakao = kakao(SOCIAL_ID, null, null);
        when(userRepository.findByProviderAndSocialId("kakao", SOCIAL_ID)).thenReturn(Optional.empty());
        when(userRepository.findByUsername("kakao_" + SOCIAL_ID)).thenReturn(Optional.empty());
        givenSaveAssignsId();

        service.upsertUser(kakao, Map.of());

        ArgumentCaptor<User> captor = ArgumentCaptor.forClass(User.class);
        verify(userRepository, times(2)).save(captor.capture());
        assertThat(captor.getValue().getNickname()).isEqualTo("반려인1");
    }

    @Test
    @DisplayName("신규 생성 시 이메일이 이미 다른 계정에 있으면 명시적으로 실패한다")
    void upsert_failsWhenEmailBelongsToAnotherAccount() {
        // 카카오 A(x@y.com)와 구글 B(같은 이메일)가 둘 다 가입하려는 상황.
        // 계정 연동은 #2 Epic 범위 밖이라 자동 병합하지 않는다. DB 제약에 부딪혀
        // 500 으로 죽는 대신, 원인을 말하는 인증 예외로 실패한다.
        OAuth2UserInfo google = google("g-1", "보리아빠", "bori@example.com");
        when(userRepository.findByProviderAndSocialId("google", "g-1")).thenReturn(Optional.empty());
        when(userRepository.findByUsername("google_g-1")).thenReturn(Optional.empty());
        when(userRepository.findByEmail("bori@example.com"))
                .thenReturn(Optional.of(User.builder().id(7L).provider("kakao").socialId("k-1")
                        .email("bori@example.com").build()));

        assertThatThrownBy(() -> service.upsertUser(google, Map.of()))
                .isInstanceOf(OAuth2AuthenticationException.class)
                .hasMessageContaining("이미 있습니다");

        verify(userRepository, never()).save(any(User.class));
    }

    @Test
    @DisplayName("INSERT 가 무결성 제약에 걸리면 500 이 아니라 account_conflict 인증 실패로 끝난다")
    void upsert_failsWithAuthErrorWhenSaveHitsIntegrityConstraint() {
        // 사전 조회(findByEmail)와 INSERT 사이에 같은 값이 끼어드는 경합. 이 catch 가 없으면
        // DataIntegrityViolationException 이 필터체인 밖으로 나가 500 이 된다.
        // 이 PR 의 핵심 주장("원인을 말하는 인증 실패")이 실제로 성립하는지 여기서 잠근다.
        OAuth2UserInfo google = google("g-1", "보리아빠", "bori@example.com");
        when(userRepository.findByProviderAndSocialId("google", "g-1")).thenReturn(Optional.empty());
        when(userRepository.findByUsername("google_g-1")).thenReturn(Optional.empty());
        when(userRepository.findByEmail("bori@example.com")).thenReturn(Optional.empty());
        // MySQL 이 실제로 주는 문구 — 안에 이메일 원문이 들어 있다.
        when(userRepository.save(any(User.class))).thenThrow(new DataIntegrityViolationException(
                "could not execute statement [Duplicate entry 'bori@example.com' for key 'users.UK_email']"));

        OAuth2AuthenticationException thrown = catchThrowableOfType(
                OAuth2AuthenticationException.class, () -> service.upsertUser(google, Map.of()));

        assertThat(thrown).isNotNull();
        assertThat(thrown.getError().getErrorCode()).isEqualTo("account_conflict");
        // DB 예외를 cause 로 싣거나 메시지에 이어 붙이면 이메일이 인증 실패 로그로 흘러간다. (이슈 #6)
        assertThat(thrown.getCause()).isNull();
        assertThat(thrown.getMessage()).doesNotContain("bori@example.com");
        assertThat(thrown.getMessage()).doesNotContain("Duplicate entry");
    }

    @Test
    @DisplayName("공급자가 소셜 ID 를 주지 않으면 익명 행을 만들지 않고 실패한다")
    void upsert_failsWhenProviderIdMissing() {
        OAuth2UserInfo kakao = kakao(null, "보리아빠", null);

        assertThatThrownBy(() -> service.upsertUser(kakao, Map.of()))
                .isInstanceOf(OAuth2AuthenticationException.class);

        verify(userRepository, never()).save(any(User.class));
    }

    // ─────────────────────── 기존 사용자 ───────────────────────

    @Test
    @DisplayName("기존 사용자의 닉네임이 카카오에서 바뀌면 갱신하고 저장한다")
    void upsert_updatesNicknameOfExistingUser() {
        User existing = User.builder()
                .id(42L).provider("kakao").socialId(SOCIAL_ID)
                .name("옛닉").nickname("옛닉").role("ROLE_USER")
                .build();
        when(userRepository.findByProviderAndSocialId("kakao", SOCIAL_ID)).thenReturn(Optional.of(existing));

        CustomOAuth2User principal = service.upsertUser(kakao(SOCIAL_ID, "새닉", null), Map.of());

        ArgumentCaptor<User> captor = ArgumentCaptor.forClass(User.class);
        verify(userRepository).save(captor.capture());
        assertThat(captor.getValue().getNickname()).isEqualTo("새닉");
        assertThat(principal.isNew()).isFalse();
    }

    @Test
    @DisplayName("같은 소셜 계정으로 다시 로그인해도 행이 늘지 않는다 — 바뀐 게 없으면 저장조차 하지 않는다")
    void upsert_doesNotInsertOnRepeatedLogin() {
        User existing = User.builder()
                .id(42L).provider("kakao").socialId(SOCIAL_ID)
                .name("보리아빠").nickname("보리아빠").role("ROLE_USER")
                .build();
        when(userRepository.findByProviderAndSocialId("kakao", SOCIAL_ID)).thenReturn(Optional.of(existing));

        CustomOAuth2User principal = service.upsertUser(kakao(SOCIAL_ID, "보리아빠", null), Map.of());

        verify(userRepository, never()).save(any(User.class));
        assertThat(principal.isNew()).isFalse();
        assertThat(principal.getUserId()).isEqualTo(42L);
    }

    @Test
    @DisplayName("나중에 이메일 동의를 켜면 비어 있던 기존 행의 email 이 채워진다")
    void upsert_fillsEmailWhenUserLaterConsents() {
        User existing = User.builder()
                .id(42L).provider("kakao").socialId(SOCIAL_ID)
                .name("보리아빠").nickname("보리아빠").role("ROLE_USER")
                .email(null)
                .build();
        when(userRepository.findByProviderAndSocialId("kakao", SOCIAL_ID)).thenReturn(Optional.of(existing));
        when(userRepository.findByEmail("bori@example.com")).thenReturn(Optional.empty());

        service.upsertUser(kakao(SOCIAL_ID, "보리아빠", "bori@example.com"), Map.of());

        ArgumentCaptor<User> captor = ArgumentCaptor.forClass(User.class);
        verify(userRepository).save(captor.capture());
        assertThat(captor.getValue().getEmail()).isEqualTo("bori@example.com");
    }

    @Test
    @DisplayName("공급자 이메일이 다른 계정에 이미 있으면 로그인은 통과시키고 email 만 갱신하지 않는다")
    void upsert_skipsEmailUpdateWhenTakenByAnotherAccount() {
        User existing = User.builder()
                .id(42L).provider("kakao").socialId(SOCIAL_ID)
                .name("보리아빠").nickname("보리아빠").role("ROLE_USER")
                .build();
        when(userRepository.findByProviderAndSocialId("kakao", SOCIAL_ID)).thenReturn(Optional.of(existing));
        when(userRepository.findByEmail("bori@example.com"))
                .thenReturn(Optional.of(User.builder().id(99L).provider("google").build()));

        CustomOAuth2User principal = service.upsertUser(kakao(SOCIAL_ID, "보리아빠", "bori@example.com"), Map.of());

        // 이미 쓰고 있던 계정을 잠그는 것이 더 나쁘다 — 로그인은 되고, 선택 필드만 포기한다.
        assertThat(principal.isNew()).isFalse();
        assertThat(existing.getEmail()).isNull();
        verify(userRepository, never()).save(any(User.class));
    }

    @Test
    @DisplayName("사용자가 앱에서 직접 고친 닉네임은 소셜 로그인이 덮어쓰지 않는다")
    void upsert_doesNotOverwriteUserEditedNickname() {
        User existing = User.builder()
                .id(42L).provider("kakao").socialId(SOCIAL_ID)
                .name("카카오이름")        // 지난 로그인에서 공급자가 준 값
                .nickname("내가고친닉")     // 사용자가 PUT /auth/me 로 직접 바꾼 값
                .role("ROLE_USER")
                .build();
        when(userRepository.findByProviderAndSocialId("kakao", SOCIAL_ID)).thenReturn(Optional.of(existing));

        service.upsertUser(kakao(SOCIAL_ID, "카카오새이름", null), Map.of());

        assertThat(existing.getNickname()).isEqualTo("내가고친닉");
        assertThat(existing.getName()).isEqualTo("카카오새이름"); // 공급자 원본은 최신으로 유지
    }

    @Test
    @DisplayName("프로필 이미지가 바뀌면 반영한다")
    void upsert_updatesImageUrl() {
        User existing = User.builder()
                .id(42L).provider("google").socialId("g-1")
                .name("보리아빠").nickname("보리아빠").role("ROLE_USER")
                .imageUrl("https://old.example.com/a.jpg")
                .build();
        when(userRepository.findByProviderAndSocialId("google", "g-1")).thenReturn(Optional.of(existing));

        Map<String, Object> attributes = new HashMap<>();
        attributes.put("sub", "g-1");
        attributes.put("name", "보리아빠");
        attributes.put("picture", "https://new.example.com/b.jpg");

        service.upsertUser(new GoogleOAuth2User(attributes), attributes);

        assertThat(existing.getImageUrl()).isEqualTo("https://new.example.com/b.jpg");
        verify(userRepository).save(existing);
    }

    @Test
    @DisplayName("role 컬럼이 비어 있던 옛 행은 로그인할 때 ROLE_USER 로 채워진다")
    void upsert_backfillsMissingRole() {
        User legacy = User.builder()
                .id(42L).provider("kakao").socialId(SOCIAL_ID)
                .name("보리아빠").nickname("보리아빠")
                .build();
        legacy.setRole(null); // @Builder.Default 를 우회해 '옛 행' 상태를 만든다
        when(userRepository.findByProviderAndSocialId("kakao", SOCIAL_ID)).thenReturn(Optional.of(legacy));

        CustomOAuth2User principal = service.upsertUser(kakao(SOCIAL_ID, "보리아빠", null), Map.of());

        assertThat(legacy.getRole()).isEqualTo("ROLE_USER");
        assertThat(principal.getAuthorities())
                .extracting(a -> a.getAuthority())
                .containsExactly("ROLE_USER");
        verify(userRepository).save(legacy);
    }

    // ─────────────────────── 레거시 행 이관 ───────────────────────

    @Test
    @DisplayName("백필 전 레거시 행(username=kakao_1234)을 찾아 새 컬럼으로 옮기고 새 계정을 만들지 않는다")
    void upsert_adoptsLegacyRowInsteadOfCreatingDuplicate() {
        User legacy = User.builder()
                .id(42L).username("kakao_" + SOCIAL_ID)
                .name("보리아빠").nickname("보리아빠").role("ROLE_USER")
                .build();
        when(userRepository.findByProviderAndSocialId("kakao", SOCIAL_ID)).thenReturn(Optional.empty());
        when(userRepository.findByUsername("kakao_" + SOCIAL_ID)).thenReturn(Optional.of(legacy));

        CustomOAuth2User principal = service.upsertUser(kakao(SOCIAL_ID, "보리아빠", null), Map.of());

        assertThat(legacy.getProvider()).isEqualTo("kakao");
        assertThat(legacy.getSocialId()).isEqualTo(SOCIAL_ID);
        assertThat(principal.isNew())
                .as("이미 있던 사용자다 — 온보딩으로 보내면 안 된다")
                .isFalse();
        verify(userRepository).save(legacy);
    }

    // ─────────────────────── registrationId 정규화 ───────────────────────

    @Test
    @DisplayName("registrationId 는 대소문자를 가리지 않는다 — \"Kakao\" 도 \"kakao\" 와 같다")
    void toUserInfo_normalizesRegistrationIdCase() {
        Map<String, Object> attributes = Map.of("id", SOCIAL_ID);

        // 카카오 설정은 client-name=Kakao 라서 예전 코드에는 case "Kakao" 가 따로 있었다.
        for (String registrationId : new String[]{"kakao", "Kakao", "KAKAO", " Kakao "}) {
            OAuth2UserInfo info = CustomOAuth2UserService.toUserInfo(registrationId, attributes);
            assertThat(info)
                    .as("registrationId=%s", registrationId)
                    .isInstanceOf(KakaoOAuth2User.class);
            assertThat(info.getProvider()).isEqualTo("kakao");
        }
    }

    @Test
    @DisplayName("google 은 매핑되고, naver 는 지원 공급자가 아니라 거절된다")
    void toUserInfo_mapsGoogleAndRefusesNaver() {
        OAuth2UserInfo googleInfo = CustomOAuth2UserService.toUserInfo(
                "Google", Map.of("sub", "g-1", "name", "보리아빠", "email", "bori@example.com"));
        assertThat(googleInfo).isInstanceOf(GoogleOAuth2User.class);
        assertThat(googleInfo.getProviderId()).isEqualTo("g-1");

        // ADR-0010 이 네이버를 보류로 확정했다. 그 결정을 산문이 아니라 여기서 잠근다 —
        // 파서(NaverOAuth2User)와 클라이언트 등록을 함께 걷어냈으므로, 되살리려면
        // 이 테스트가 먼저 빨간불이 되고 그때 ADR 을 고칠지 결정하게 된다. (#15, #13)
        assertThatThrownBy(() -> CustomOAuth2UserService.toUserInfo("NAVER", Map.of(
                        "response", Map.of("id", "n-1", "name", "보리아빠"))))
                .isInstanceOf(OAuth2AuthenticationException.class)
                .hasMessageContaining("naver");
    }

    @Test
    @DisplayName("모르는 공급자는 예외로 거절한다")
    void toUserInfo_rejectsUnknownProvider() {
        assertThatThrownBy(() -> CustomOAuth2UserService.toUserInfo("apple", Map.of()))
                .isInstanceOf(OAuth2AuthenticationException.class);
        assertThatThrownBy(() -> CustomOAuth2UserService.toUserInfo(null, Map.of()))
                .isInstanceOf(OAuth2AuthenticationException.class);
    }

    // ─────────────────────── fixtures ───────────────────────

    /** 카카오 실제 응답 모양 그대로 만든다 — 값이 없으면 키 자체를 넣지 않는다. */
    private static OAuth2UserInfo kakao(String socialId, String nickname, String email) {
        Map<String, Object> attributes = new HashMap<>();
        if (socialId != null) {
            attributes.put("id", socialId);
        }
        Map<String, Object> account = new HashMap<>();
        if (email != null) {
            account.put("email", email);
        }
        if (nickname != null) {
            account.put("profile", Map.of("nickname", nickname));
        }
        attributes.put("kakao_account", account);
        return new KakaoOAuth2User(attributes);
    }

    private static OAuth2UserInfo google(String sub, String name, String email) {
        Map<String, Object> attributes = new HashMap<>();
        attributes.put("sub", sub);
        attributes.put("name", name);
        attributes.put("email", email);
        return new GoogleOAuth2User(attributes);
    }
}
