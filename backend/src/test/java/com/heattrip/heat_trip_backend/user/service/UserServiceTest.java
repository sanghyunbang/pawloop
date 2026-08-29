package com.heattrip.heat_trip_backend.user.service;

import com.heattrip.heat_trip_backend.OAuth.jwt.JWTProvider;
import com.heattrip.heat_trip_backend.OAuth.principal.UnauthenticatedException;
import com.heattrip.heat_trip_backend.user.dto.LoginRequest;
import com.heattrip.heat_trip_backend.user.dto.SignupRequest;
import com.heattrip.heat_trip_backend.user.dto.UpdateProfileRequest;
import com.heattrip.heat_trip_backend.user.entity.User;
import com.heattrip.heat_trip_backend.user.repository.UserRepository;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.security.crypto.password.PasswordEncoder;

import java.time.LocalDateTime;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class UserServiceTest {

    @Mock
    private UserRepository userRepository;

    @Mock
    private PasswordEncoder passwordEncoder;

    @Mock
    private JWTProvider jwtProvider;

    @InjectMocks
    private UserService userService;

    // ─────────────────────── 이메일 가입 (완료 조건 6) ───────────────────────

    @Test
    @DisplayName("이메일 가입 사용자는 provider='local' · social_id=null · role='ROLE_USER' 로 저장된다")
    void signup_storesLocalProviderAndDefaultRole() {
        // 이슈 #7 완료 조건 6: "이메일 가입 사용자가 로그인해도 기존과 동일하게 동작한다 (provider = 'local')".
        // provider 가 비면 계약(openapi.yaml)의 User.provider 가 null 로 나가고,
        // 마이그레이션 SQL 의 '백필 후 provider IS NULL 인 행은 없다' 검증도 깨진다.
        SignupRequest request = new SignupRequest();
        request.setEmail("bori@example.com");
        request.setPassword("test1234");
        request.setNickname("보리아빠");
        request.setName("보리아빠");
        request.setGender("male");
        request.setAgeGroup("over14");
        request.setAgreeTos(true);
        request.setAgreePrivacy(true);

        when(userRepository.findByEmail("bori@example.com")).thenReturn(Optional.empty());
        when(passwordEncoder.encode("test1234")).thenReturn("encoded-password");

        userService.signup(request);

        ArgumentCaptor<User> captor = ArgumentCaptor.forClass(User.class);
        verify(userRepository).save(captor.capture());
        User saved = captor.getValue();

        assertThat(saved.getProvider()).isEqualTo("local");
        assertThat(saved.getSocialId()).isNull();
        assertThat(saved.getRole()).isEqualTo("ROLE_USER");
        assertThat(saved.getEmail()).isEqualTo("bori@example.com");
        assertThat(saved.getPassword()).isEqualTo("encoded-password"); // 원문 저장 금지
    }

    @Test
    @DisplayName("이메일 가입자의 로그인 토큰 권한은 DB 의 role 값을 쓴다")
    void login_usesRoleFromDatabase() throws IllegalAccessException {
        LoginRequest request = new LoginRequest();
        request.setEmail("admin@example.com");
        request.setPassword("test1234");

        User user = User.builder()
                .id(7L)
                .email("admin@example.com")
                .password("encoded-password")
                .provider(User.PROVIDER_LOCAL)
                .role("ROLE_ADMIN")
                .build();

        when(userRepository.findByEmail("admin@example.com")).thenReturn(Optional.of(user));
        when(passwordEncoder.matches("test1234", "encoded-password")).thenReturn(true);
        when(jwtProvider.createAccessToken(7L, "ROLE_ADMIN")).thenReturn("jwt-token");

        assertThat(userService.login(request)).isEqualTo("jwt-token");
        verify(jwtProvider).createAccessToken(7L, "ROLE_ADMIN");
    }

    @Test
    @DisplayName("로그인 성공 시 JWT를 반환하며 토큰의 subject 로 이메일이 아니라 users.id 를 넘긴다")
    void login_returnsJwtWhenCredentialsMatch() throws IllegalAccessException {
        // createAccessToken 의 첫 인자가 Long 이라, login 을 user.getEmail() 로 되돌리면
        // 이 테스트가 실패하기 전에 **컴파일이 먼저 죽는다**. 그게 이 이슈의 진짜 방어선이다. (#5)
        LoginRequest request = new LoginRequest();
        request.setEmail("test1234@test.com");
        request.setPassword("test1234");

        User user = User.builder()
                .id(7L)
                .email("test1234@test.com")
                .password("encoded-password")
                .build();

        when(userRepository.findByEmail("test1234@test.com")).thenReturn(Optional.of(user));
        when(passwordEncoder.matches("test1234", "encoded-password")).thenReturn(true);
        when(jwtProvider.createAccessToken(7L, "ROLE_USER")).thenReturn("jwt-token");

        String token = userService.login(request);

        assertThat(token).isEqualTo("jwt-token");
        verify(jwtProvider).createAccessToken(7L, "ROLE_USER");
    }

    @Test
    @DisplayName("비밀번호가 틀리면 로그인에 실패한다")
    void login_throwsWhenPasswordDoesNotMatch() {
        LoginRequest request = new LoginRequest();
        request.setEmail("test1234@test.com");
        request.setPassword("wrong-password");

        User user = User.builder()
                .email("test1234@test.com")
                .password("encoded-password")
                .build();

        when(userRepository.findByEmail("test1234@test.com")).thenReturn(Optional.of(user));
        when(passwordEncoder.matches("wrong-password", "encoded-password")).thenReturn(false);

        assertThatThrownBy(() -> userService.login(request))
                .isInstanceOf(IllegalAccessException.class);
    }

    // ─────────────────────── users.id 로 받는 시그니처 (이슈 #5) ───────────────────────
    //
    // emailFromAuth_extractsEmailFromBearerToken 은 삭제됐다. 그 메서드가 없어졌기 때문이다 —
    // 인증 주체 해석은 CurrentUserArgumentResolver 한 곳이고, UserService 는 users.id 만 받는다.

    @Test
    @DisplayName("프로필 수정은 users.id 로 사용자를 찾아 요청된 필드만 반영한다")
    void updateProfile_updatesOnlyProvidedFields() {
        User existing = User.builder()
                .id(7L)
                .email("bori@example.com")
                .name("옛이름")
                .nickname("옛닉네임")
                .gender(User.Gender.MALE)
                .travelType("default")
                .build();
        when(userRepository.findById(7L)).thenReturn(Optional.of(existing));
        when(userRepository.save(existing)).thenReturn(existing);

        UpdateProfileRequest req = new UpdateProfileRequest();
        req.setNickname("  보리아빠  ");
        req.setGender("female");
        req.setAge(7);

        User updated = userService.updateProfile(7L, req);

        assertThat(updated.getNickname()).isEqualTo("보리아빠"); // 앞뒤 공백은 잘린다
        assertThat(updated.getGender()).isEqualTo(User.Gender.FEMALE);
        assertThat(updated.getAge()).isEqualTo(7);
        assertThat(updated.getName())
                .as("요청에 없는 필드는 건드리지 않는다")
                .isEqualTo("옛이름");
    }

    @Test
    @DisplayName("프로필 수정에서 마케팅 동의를 켜면 동의 버전과 동의 시각이 함께 채워진다")
    void updateProfile_turningOnMarketingConsentStampsVersionAndTime() {
        User existing = User.builder().id(7L).agreeMarketing(false).build();
        when(userRepository.findById(7L)).thenReturn(Optional.of(existing));
        when(userRepository.save(existing)).thenReturn(existing);

        UpdateProfileRequest req = new UpdateProfileRequest();
        req.setAgreeMarketing(true);

        User updated = userService.updateProfile(7L, req);

        assertThat(updated.getAgreeMarketing()).isTrue();
        assertThat(updated.getMarketingVersion()).isEqualTo("v1.0");
        assertThat(updated.getMarketingAgreedAt()).isNotNull();
    }

    @Test
    @DisplayName("프로필 수정에서 마케팅 동의를 끄면 동의 버전과 동의 시각이 지워진다")
    void updateProfile_turningOffMarketingConsentClearsVersionAndTime() {
        User existing = User.builder()
                .id(7L)
                .agreeMarketing(true)
                .marketingVersion("v1.0")
                .marketingAgreedAt(LocalDateTime.now())
                .build();
        when(userRepository.findById(7L)).thenReturn(Optional.of(existing));
        when(userRepository.save(existing)).thenReturn(existing);

        UpdateProfileRequest req = new UpdateProfileRequest();
        req.setAgreeMarketing(false);

        User updated = userService.updateProfile(7L, req);

        assertThat(updated.getAgreeMarketing()).isFalse();
        assertThat(updated.getMarketingVersion()).isNull();
        assertThat(updated.getMarketingAgreedAt()).isNull();
    }

    @Test
    @DisplayName("탈퇴는 users.id 로 사용자를 찾아 삭제한다")
    void deleteMe_deletesUserFoundById() {
        User existing = User.builder().id(7L).email("bori@example.com").build();
        when(userRepository.findById(7L)).thenReturn(Optional.of(existing));

        userService.deleteMe(7L);

        verify(userRepository).delete(existing);
    }

    @Test
    @DisplayName("그 users.id 의 사용자가 없으면 400 이 아니라 401 로 이어지는 예외를 던지며 식별자를 메시지에 담지 않는다")
    void deleteMe_throwsUnauthenticatedWithoutLeakingIdentifier() {
        when(userRepository.findById(7L)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> userService.deleteMe(7L))
                .as("이 시점의 '없음' 은 잘못된 요청이 아니라 '이 토큰의 주체가 더는 없다' 이다")
                .isInstanceOf(UnauthenticatedException.class)
                // GlobalExceptionHandler 가 ex.getMessage() 를 응답 본문에 그대로 싣는다 (이슈 #6).
                // 예전에는 여기 메시지가 "User not found: bori@example.com" 이었다.
                .hasMessageNotContaining("@")
                .hasMessageNotContaining("7");
    }

    // TODO(#9): RefreshToken 도입 시 아래 테스트를 되살린다.
    //
    // 이 테스트는 RefreshTokenRepository 가 생기기 전에 먼저 쓰였고(TDD),
    // 그 타입이 아직 없어 **테스트 소스가 컴파일되지 않는 상태**로 남아 있었다.
    // CI 가 붙으면서 드러났다. 의도를 잃지 않도록 명세만 남긴다.
    //
    // 현재 UserService.logout(email) 은 본문이 비어 있다(UserService.java:163).
    // #9 에서 RefreshToken 엔티티·저장소를 만들고 폐기를 구현할 때
    // 아래를 그대로 살리면 된다.
    //
    // @Test
    // @DisplayName("로그아웃: 해당 사용자의 refreshToken을 폐기한다.")
    // void logout_revokesRefreshToken() {
    //     userService.logout("bori@x.com");
    //     verify(refreshTokenRepository).deleteByEmail("bori@x.com");
    // }
}
