package com.heattrip.heat_trip_backend.user.service;

import com.heattrip.heat_trip_backend.OAuth.jwt.JWTProvider;
import com.heattrip.heat_trip_backend.user.dto.LoginRequest;
import com.heattrip.heat_trip_backend.user.entity.User;
import com.heattrip.heat_trip_backend.user.repository.UserRepository;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.security.crypto.password.PasswordEncoder;

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

    @Test
    @DisplayName("로그인 성공 시 JWT를 반환한다")
    void login_returnsJwtWhenCredentialsMatch() throws IllegalAccessException {
        LoginRequest request = new LoginRequest();
        request.setEmail("test1234@test.com");
        request.setPassword("test1234");

        User user = User.builder()
                .email("test1234@test.com")
                .password("encoded-password")
                .build();

        when(userRepository.findByEmail("test1234@test.com")).thenReturn(Optional.of(user));
        when(passwordEncoder.matches("test1234", "encoded-password")).thenReturn(true);
        when(jwtProvider.createAccessToken("test1234@test.com", "ROLE_USER")).thenReturn("jwt-token");

        String token = userService.login(request);

        assertThat(token).isEqualTo("jwt-token");
        verify(jwtProvider).createAccessToken("test1234@test.com", "ROLE_USER");
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

    @Test
    @DisplayName("Authorization 헤더에서 Bearer 토큰의 subject 이메일을 읽는다")
    void emailFromAuth_extractsEmailFromBearerToken() {
        when(jwtProvider.getUserIdFromToken("jwt-token")).thenReturn("test1234@test.com");

        String email = userService.emailFromAuth("Bearer jwt-token");

        assertThat(email).isEqualTo("test1234@test.com");
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
