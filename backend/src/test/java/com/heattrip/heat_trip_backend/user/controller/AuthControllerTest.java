package com.heattrip.heat_trip_backend.user.controller;

import com.heattrip.heat_trip_backend.user.dto.AuthTokensResponse;
import com.heattrip.heat_trip_backend.user.dto.LoginRequest;
import com.heattrip.heat_trip_backend.user.dto.RefreshTokenRequest;
import com.heattrip.heat_trip_backend.user.dto.SignupRequest;
import com.heattrip.heat_trip_backend.user.signup.EmailVerificationService;
import com.heattrip.heat_trip_backend.user.dto.UpdateProfileRequest;
import com.heattrip.heat_trip_backend.user.dto.UserResponse;
import com.heattrip.heat_trip_backend.user.NeighborhoodCatalog;
import com.heattrip.heat_trip_backend.user.entity.User;
import com.heattrip.heat_trip_backend.user.service.RefreshTokenService;
import com.heattrip.heat_trip_backend.user.service.UserService;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.verifyNoInteractions;
import static org.mockito.Mockito.verifyNoMoreInteractions;
import static org.mockito.Mockito.when;

/**
 * AuthController 가 <b>주입된 인증 주체만</b> 쓰는지 확인한다. (이슈 #5)
 *
 * <p>예전 이 테스트는 {@code userService.emailFromAuth("Bearer jwt-token")} 을 스텁했다.
 * 그 메서드가 사라졌으므로 옛 테스트는 실패하기 전에 <b>컴파일부터 죽는다</b> — 이 이슈에서
 * 되돌림에 대한 가장 강한 반응이다.
 */
@ExtendWith(MockitoExtension.class)
class AuthControllerTest {

    @Mock
    private UserService userService;

    @Mock
    private RefreshTokenService refreshTokenService;

    /** 이메일 가입의 인증 (#635). 가입 요청은 이제 여기로만 간다. */
    @Mock
    private EmailVerificationService emailVerification;

    /**
     * 동네 이름을 붙이는 표 (#342). 여기서는 빈 응답이면 충분하다 — 이 테스트가 보는 것은
     * "컨트롤러가 주입된 사용자를 그대로 넘기는가" 이고 동네는 그 답을 안 바꾼다.
     * Mockito 가 {@code Optional} 반환에 기본으로 {@code empty} 를 준다.
     */
    @Mock
    private NeighborhoodCatalog neighborhoods;

    @InjectMocks
    private AuthController authController;

    private static final User ME = User.builder()
            .id(7L)
            .email("test1234@test.com")
            .name("Tester")
            .nickname("tripper")
            .gender(User.Gender.MALE)
            .build();

    @Test
    @DisplayName("로그인 API는 서비스가 만든 AuthTokens 를 그대로 200 으로 응답한다")
    void login_returnsAuthTokensFromService() {
        // 예전에는 반환 타입이 ResponseEntity<String> 이었고 본문이 JWT 평문이었다.
        // 그 시절 단언("jwt-token" 문자열 비교)은 이 타입 변경으로 **컴파일부터 죽는다** —
        // 되돌림에 대한 가장 강한 반응이다. (이슈 #10 완료 조건 9)
        LoginRequest request = new LoginRequest();
        request.setEmail("test1234@test.com");
        request.setPassword("test1234");
        AuthTokensResponse tokens = new AuthTokensResponse(
                "jwt-token", "opaque-refresh-token", 3600L, false, UserResponse.from(ME));
        when(userService.login(request)).thenReturn(tokens);

        var response = authController.login(request);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody())
                .as("컨트롤러는 얇다 — 응답 조립은 서비스가 끝냈다")
                .isEqualTo(tokens);
    }

    @Test
    @DisplayName("회원가입 API는 계정을 안 만들고 202 로 응답한다 — 코드를 보냈다는 뜻이다")
    void signup_returns202AndOnlyStartsVerification() {
        // 2026-09 이전에는 여기서 바로 계정을 만들고 201 을 줬다. 지금은 인증 코드를 보내고
        // 계정은 /auth/signup/verify 에서 생긴다 — **만들어진 것이 없으므로 201 은 거짓말이다**
        // (#635, ADR-0022 를 뒤집는다).
        SignupRequest request = new SignupRequest();
        request.setEmail("test1234@test.com");
        when(emailVerification.start(request)).thenReturn(true);

        var response = authController.signup(request);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.ACCEPTED);
        assertThat(response.getBody()).isNotNull();
        assertThat(response.getBody().mailSent()).isTrue();
        // 계정을 만드는 쪽은 아예 안 부른다.
        verifyNoInteractions(userService);
    }

    @Test
    @DisplayName("메일이 안 나갔으면 그 사실을 응답에 싣는다 — 조용히 성공한 척하지 않는다")
    void signup_saysWhenTheMailDidNotGoOut() {
        SignupRequest request = new SignupRequest();
        request.setEmail("test1234@test.com");
        when(emailVerification.start(request)).thenReturn(false);

        // 대기 행은 이미 있고 메일만 못 나간 상태다 — 앱은 "다시 보내기" 를 권하면 된다.
        assertThat(authController.signup(request).getBody().mailSent()).isFalse();
    }

    @Test
    @DisplayName("내 정보 조회 API는 주입된 사용자를 그대로 응답으로 바꿀 뿐 토큰을 다시 읽지 않는다")
    void me_returnsInjectedUserWithoutTouchingTheService() {
        var response = authController.me(ME);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        UserResponse body = response.getBody();
        assertThat(body).isNotNull();
        assertThat(body.getId()).isEqualTo(7L);
        assertThat(body.getEmail()).isEqualTo("test1234@test.com");
        assertThat(body.getName()).isEqualTo("Tester");
        assertThat(body.getGender()).isEqualTo("MALE");

        // 조회는 리졸버가 이미 끝냈다. 컨트롤러가 여기서 서비스를 한 번 더 부르면
        // 주체 해석 지점이 다시 둘로 갈라진다.
        verifyNoMoreInteractions(userService);
    }

    @Test
    @DisplayName("프로필 수정 API는 주입된 사용자의 users.id 로 수정 서비스를 호출한다")
    void updateMe_passesUserIdToService() {
        UpdateProfileRequest request = new UpdateProfileRequest();
        request.setNickname("new-nick");

        User updated = User.builder()
                .id(7L)
                .email("test1234@test.com")
                .nickname("new-nick")
                .gender(User.Gender.FEMALE)
                .build();
        when(userService.updateProfile(7L, request)).thenReturn(updated);

        var response = authController.updateMe(ME, request);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).isNotNull();
        assertThat(response.getBody().getNickname()).isEqualTo("new-nick");
        // 시그니처가 Long 이라 이메일을 넘기는 옛 코드는 컴파일되지 않는다.
        verify(userService).updateProfile(7L, request);
    }

    @Test
    @DisplayName("회원 탈퇴 API는 주입된 사용자의 users.id 로 삭제 서비스를 호출하고 204를 반환한다")
    void deleteMe_passesUserIdAndReturns204() {
        ResponseEntity<Void> response = authController.deleteMe(ME);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.NO_CONTENT);
        verify(userService).deleteMe(7L);
    }

    @Test
    @DisplayName("로그아웃 API는 주입된 사용자의 users.id 로 로그아웃 처리하고 204를 반환한다")
    void logout_passesUserIdAndReturns204() {
        ResponseEntity<Void> response = authController.logout(ME);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.NO_CONTENT);
        verify(userService).logout(7L);
    }

    @Test
    @DisplayName("토큰 갱신 API는 본문의 refreshToken 을 그대로 회전 서비스에 넘기고 결과를 200 으로 돌려준다")
    void refresh_returnsRotatedTokensFromService() {
        // 컨트롤러는 얇다 — 검증도 회전도 서비스가 한다. 여기서 null·공백을 400 으로 거르면
        // 계약이 선언한 '본문 없는 401' 과 어긋난다. (이슈 #9)
        RefreshTokenRequest request = new RefreshTokenRequest();
        request.setRefreshToken("opaque-refresh-token");
        AuthTokensResponse rotated = new AuthTokensResponse("new-jwt", "new-refresh", 3600L);
        when(refreshTokenService.rotate("opaque-refresh-token")).thenReturn(rotated);

        var response = authController.refresh(request);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).isEqualTo(rotated);
        verify(refreshTokenService).rotate("opaque-refresh-token");
    }
}
