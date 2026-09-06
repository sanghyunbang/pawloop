package com.heattrip.heat_trip_backend.user.service;

import com.heattrip.heat_trip_backend.OAuth.jwt.JWTProvider;
import com.heattrip.heat_trip_backend.user.UnauthenticatedException;
import com.heattrip.heat_trip_backend.user.dto.AuthTokensResponse;
import com.heattrip.heat_trip_backend.user.dto.LoginRequest;
import com.heattrip.heat_trip_backend.user.dto.SignupRequest;
import com.heattrip.heat_trip_backend.user.dto.UpdateProfileRequest;
import com.heattrip.heat_trip_backend.user.entity.User;
import com.heattrip.heat_trip_backend.user.repository.UserRepository;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.InOrder;
import org.springframework.context.ApplicationEventPublisher;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.security.crypto.password.PasswordEncoder;
import org.springframework.web.server.ResponseStatusException;

import java.time.LocalDateTime;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatCode;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.inOrder;
import static org.mockito.Mockito.never;
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

    /** RT 를 만지는 유일한 통로. UserService 는 RefreshTokenRepository 를 직접 보지 않는다. (이슈 #9) */
    @Mock
    private RefreshTokenService refreshTokenService;

    /** 로그아웃·탈퇴의 사건(#83). 이 테스트는 발행 자체를 재지 않는다 — 듣는 쪽의 통합 테스트가 잰다. */
    @Mock
    private ApplicationEventPublisher events;

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

    // ─────────────────────── gender · ageGroup 해석 (이슈 #42) ───────────────────────

    /** 필수 항목만 채운 가입 요청. gender·ageGroup 은 호출부가 정한다. */
    private SignupRequest signupRequest(String gender, String ageGroup) {
        SignupRequest request = new SignupRequest();
        request.setEmail("bori@example.com");
        request.setPassword("test1234");
        request.setNickname("보리아빠");
        request.setName("보리아빠");
        request.setGender(gender);
        request.setAgeGroup(ageGroup);
        return request;
    }

    private User signupAndCapture(SignupRequest request) {
        when(userRepository.findByEmail("bori@example.com")).thenReturn(Optional.empty());
        when(passwordEncoder.encode("test1234")).thenReturn("encoded-password");

        userService.signup(request);

        ArgumentCaptor<User> captor = ArgumentCaptor.forClass(User.class);
        verify(userRepository).save(captor.capture());
        return captor.getValue();
    }

    @Test
    @DisplayName("gender 를 안 보내면 500 이 아니라 정상 가입되고, 성별은 null(미지정)로 저장된다")
    void signup_withoutGender_succeedsAndStoresNull() {
        // 예전에는 safeLower(null) 이 null 을 그대로 switch 에 넘겨 NPE 였다 — 500.
        // 계약(openapi.yaml 의 User.gender)이 null 을 허용하므로 null 이 사실에 맞는 저장이다.
        User saved = signupAndCapture(signupRequest(null, null));

        assertThat(saved.getGender())
                .as("미지정을 OTHER 로 바꿔 저장하면 '기타'라고 답한 사람과 구분되지 않는다")
                .isNull();
        assertThat(saved.getAgeGroup())
                .as("ageGroup 은 안 보내면 OVER14 — 계약이 그렇게 선언한다")
                .isEqualTo(User.AgeGroup.OVER14);
    }

    @Test
    @DisplayName("gender 는 대소문자를 가리지 않는다 — 'male' 도 'MALE' 도 MALE 이다")
    void signup_genderIsCaseInsensitive() {
        assertThat(signupAndCapture(signupRequest("male", "over14")).getGender())
                .isEqualTo(User.Gender.MALE);
    }

    @Test
    @DisplayName("gender 에 모르는 값이 오면 조용히 OTHER 로 바꾸지 않고 400 으로 거절한다")
    void signup_unknownGender_isRejected() {
        // 조용히 OTHER 로 떨어뜨리면 클라이언트의 오타가 데이터로 굳는다.
        assertThatThrownBy(() -> userService.signup(signupRequest("mail", "over14")))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("gender");

        verify(userRepository, never()).save(any(User.class));
    }

    @Test
    @DisplayName("ageGroup 에 모르는 값이 오면 OVER14 로 떨어뜨리지 않고 400 으로 거절한다")
    void signup_unknownAgeGroup_isRejected() {
        // UNDER14 는 마케팅 동의 처리가 달라지는 값이다. 모르는 문자열을 OVER14 로 보는 것은
        // 미성년자를 성인으로 취급하는 것과 같다.
        assertThatThrownBy(() -> userService.signup(signupRequest("MALE", "over-14")))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("ageGroup");

        verify(userRepository, never()).save(any(User.class));
    }

    @Test
    @DisplayName("프로필 수정도 같은 규칙을 쓴다 — 모르는 gender 는 OTHER 가 아니라 400 이다")
    void updateProfile_unknownGender_isRejected() {
        User existing = User.builder().id(7L).email("bori@example.com").build();
        when(userRepository.findById(7L)).thenReturn(Optional.of(existing));

        UpdateProfileRequest req = new UpdateProfileRequest();
        req.setGender("여자");

        assertThatThrownBy(() -> userService.updateProfile(7L, req))
                .isInstanceOf(IllegalArgumentException.class)
                .hasMessageContaining("gender");
    }

    @Test
    @DisplayName("이메일 가입자의 로그인 토큰 권한은 DB 의 role 값을 쓴다")
    void login_usesRoleFromDatabase() {
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

        assertThat(userService.login(request).accessToken()).isEqualTo("jwt-token");
        verify(jwtProvider).createAccessToken(7L, "ROLE_ADMIN");
    }

    @Test
    @DisplayName("로그인 성공 시 JWT를 반환하며 토큰의 subject 로 이메일이 아니라 users.id 를 넘긴다")
    void login_returnsJwtWhenCredentialsMatch() {
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

        assertThat(userService.login(request).accessToken()).isEqualTo("jwt-token");
        verify(jwtProvider).createAccessToken(7L, "ROLE_USER");
    }

    @Test
    @DisplayName("로그인 응답에는 발급된 refresh 토큰 원문과 만료 초와 계약의 User 가 함께 실린다")
    void login_carriesRefreshTokenAndExpiryAndUser() {
        // #9 는 refresh 토큰을 발급·저장까지만 했고 반환값에 실을 자리가 없었다 — 그 행은
        // 아무에게도 전달되지 않은 채 만료 정리에 걷혔다. 여기가 그 전달을 잠그는 자리다. (#10)
        LoginRequest request = new LoginRequest();
        request.setEmail("bori@example.com");
        request.setPassword("test1234");

        User user = User.builder()
                .id(7L)
                .email("bori@example.com")
                .password("encoded-password")
                .nickname("보리아빠")
                .provider(User.PROVIDER_LOCAL)
                .build();

        when(userRepository.findByEmail("bori@example.com")).thenReturn(Optional.of(user));
        when(passwordEncoder.matches("test1234", "encoded-password")).thenReturn(true);
        when(jwtProvider.createAccessToken(7L, "ROLE_USER")).thenReturn("jwt-token");
        when(jwtProvider.getExpiresInSeconds()).thenReturn(3600L);
        when(refreshTokenService.issueFor(7L)).thenReturn("opaque-refresh-token");

        AuthTokensResponse tokens = userService.login(request);

        assertThat(tokens.refreshToken())
                .as("발급해 놓고 응답에 싣지 않으면 앱은 1시간마다 재로그인해야 한다")
                .isEqualTo("opaque-refresh-token");
        assertThat(tokens.expiresIn())
                .as("만료 초는 JWTProvider 가 실제 수명에서 계산한 값이어야 한다 (완료 조건 2)")
                .isEqualTo(3600L);
        assertThat(tokens.isNew())
                .as("이미 있는 계정으로 들어오는 경로다 — '이번에 생성됐는가' 의 답은 정해져 있다")
                .isFalse();
        assertThat(tokens.user()).isNotNull();
        assertThat(tokens.user().getId()).isEqualTo(7L);
        assertThat(tokens.user().getNickname()).isEqualTo("보리아빠");
        assertThat(tokens.user().getProvider()).isEqualTo("local");
    }

    @Test
    @DisplayName("비밀번호가 틀리면 400·500 이 아니라 본문 없는 401 로 이어지는 예외를 던진다")
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

        // 예전에는 IllegalAccessException(checked)이었다. 그건 어떤 핸들러에도 걸리지 않아
        // catch-all 이 잡아 500 으로 나갔다 — 계약은 이 경로에 401 만 선언한다. (#10)
        assertThatThrownBy(() -> userService.login(request))
                .isInstanceOf(UnauthenticatedException.class);
    }

    @Test
    @DisplayName("가입되지 않은 이메일도 비밀번호 오류와 똑같이 본문 없는 401 이다")
    void login_unknownEmail_isIndistinguishableFromWrongPassword() {
        // 구분해 주면 그 자체가 '이 이메일이 가입돼 있는가' 를 묻는 조회 수단이 된다 (#6).
        LoginRequest request = new LoginRequest();
        request.setEmail("nobody@example.com");
        request.setPassword("test1234");

        when(userRepository.findByEmail("nobody@example.com")).thenReturn(Optional.empty());

        assertThatThrownBy(() -> userService.login(request))
                .isInstanceOf(UnauthenticatedException.class)
                .hasMessageNotContaining("@");
    }

    @Test
    @DisplayName("이미 가입된 이메일로 다시 가입하면 400 이 아니라 409 로 거절하고 이메일을 사유에 담지 않는다")
    void signup_duplicateEmail_isConflictWithoutEchoingTheEmail() {
        SignupRequest request = signupRequest("MALE", "over14");
        when(userRepository.findByEmail("bori@example.com"))
                .thenReturn(Optional.of(User.builder().id(1L).email("bori@example.com").build()));

        assertThatThrownBy(() -> userService.signup(request))
                .isInstanceOf(ResponseStatusException.class)
                .satisfies(thrown -> assertThat(((ResponseStatusException) thrown).getStatusCode().value())
                        .as("계약은 이 경로에 409 Conflict 를 선언한다 — 400 은 '입력이 틀렸다' 는 다른 말이다")
                        .isEqualTo(409))
                // 사유 문구는 그대로 응답 본문이 된다 (#6).
                .hasMessageNotContaining("@");

        verify(userRepository, never()).save(any(User.class));
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

    // ─────────────────── refresh 토큰 (이슈 #9) ───────────────────
    //
    // 이 자리에는 오래도록 주석 블록이 있었다 — RefreshTokenRepository 가 생기기 전에 TDD 로
    // 먼저 쓰였고, 타입이 없어 컴파일이 죽는 바람에 주석으로 봉인된 명세였다.
    // 되살리되 그대로는 아니다: 그 초안은 `deleteByEmail("bori@x.com")` 이었는데, 이메일 기반
    // 조회 규약은 #5 가 죽였다. 폐기는 users.id 로 한다.

    @Test
    @DisplayName("로그아웃은 그 사용자의 refresh 토큰을 users.id 기준으로 전량 폐기한다")
    void logout_revokesAllRefreshTokensOfThatUser() {
        // 기기 하나만 끊지 않는 이유는 계약이 '전 기기'로 선언했기 때문이다
        // (openapi.yaml 의 POST /auth/logout: "특정 기기 하나만 끊는 요청 본문은 정의하지 않습니다").
        userService.logout(7L);

        verify(refreshTokenService).revokeAllByUserId(7L);
    }

    @Test
    @DisplayName("탈퇴는 사용자를 지우기 전에 그 사용자의 refresh 토큰을 먼저 삭제한다")
    void deleteMe_removesRefreshTokensBeforeDeletingTheUser() {
        // 순서가 계약이다. users 로의 FK 를 걸지 않기로 했으므로 DB 가 원장을 대신 정리해 주지
        // 않는다 — 여기서 빠뜨리면 탈퇴한 사용자의 RT 행이 남는다 (완료 조건 7).
        User existing = User.builder().id(7L).email("bori@example.com").build();
        when(userRepository.findById(7L)).thenReturn(Optional.of(existing));

        userService.deleteMe(7L);

        InOrder order = inOrder(refreshTokenService, userRepository);
        order.verify(refreshTokenService).deleteAllByUserId(7L);
        order.verify(userRepository).delete(existing);
    }

    @Test
    @DisplayName("이메일 로그인도 액세스 토큰과 함께 refresh 토큰을 발급·저장한다")
    void login_issuesRefreshTokenForThatUser() {
        // 발급 자체를 잠근다. 그 값이 응답까지 실려 나가는지는
        // login_carriesRefreshTokenAndExpiryAndUser 가 본다 (#10).
        LoginRequest request = new LoginRequest();
        request.setEmail("bori@example.com");
        request.setPassword("test1234");

        User user = User.builder()
                .id(7L)
                .email("bori@example.com")
                .password("encoded-password")
                .build();

        when(userRepository.findByEmail("bori@example.com")).thenReturn(Optional.of(user));
        when(passwordEncoder.matches("test1234", "encoded-password")).thenReturn(true);
        when(jwtProvider.createAccessToken(7L, "ROLE_USER")).thenReturn("jwt-token");

        assertThatCode(() -> userService.login(request)).doesNotThrowAnyException();

        verify(refreshTokenService).issueFor(7L);
    }
}
