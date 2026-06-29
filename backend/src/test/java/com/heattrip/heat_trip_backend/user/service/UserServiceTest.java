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
}
