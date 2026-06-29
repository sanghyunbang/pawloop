package com.heattrip.heat_trip_backend.user.controller;

import com.heattrip.heat_trip_backend.user.dto.LoginRequest;
import com.heattrip.heat_trip_backend.user.dto.UpdateProfileRequest;
import com.heattrip.heat_trip_backend.user.dto.UserResponse;
import com.heattrip.heat_trip_backend.user.entity.User;
import com.heattrip.heat_trip_backend.user.service.UserService;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.HttpStatus;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class AuthControllerTest {

    @Mock
    private UserService userService;

    @InjectMocks
    private AuthController authController;

    @Test
    @DisplayName("로그인 API는 서비스가 반환한 JWT를 그대로 응답한다")
    void login_returnsTokenFromService() throws IllegalAccessException {
        LoginRequest request = new LoginRequest();
        request.setEmail("test1234@test.com");
        request.setPassword("test1234");
        when(userService.login(request)).thenReturn("jwt-token");

        var response = authController.login(request);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).isEqualTo("jwt-token");
    }

    @Test
    @DisplayName("내 정보 조회 API는 토큰에서 이메일을 뽑아 사용자 정보를 반환한다")
    void me_returnsMappedUserResponse() {
        User user = User.builder()
                .id(1L)
                .email("test1234@test.com")
                .name("Tester")
                .nickname("tripper")
                .gender(User.Gender.MALE)
                .build();

        when(userService.emailFromAuth("Bearer jwt-token")).thenReturn("test1234@test.com");
        when(userService.findByEmail("test1234@test.com")).thenReturn(user);

        var response = authController.me("Bearer jwt-token");

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        UserResponse body = response.getBody();
        assertThat(body).isNotNull();
        assertThat(body.getEmail()).isEqualTo("test1234@test.com");
        assertThat(body.getName()).isEqualTo("Tester");
        assertThat(body.getGender()).isEqualTo("MALE");
    }

    @Test
    @DisplayName("프로필 수정 API는 토큰에서 이메일을 뽑아 수정 서비스를 호출한다")
    void updateMe_usesEmailFromTokenAndReturnsUpdatedUser() {
        UpdateProfileRequest request = new UpdateProfileRequest();
        request.setNickname("new-nick");

        User updated = User.builder()
                .id(1L)
                .email("test1234@test.com")
                .nickname("new-nick")
                .gender(User.Gender.FEMALE)
                .build();

        when(userService.emailFromAuth("Bearer jwt-token")).thenReturn("test1234@test.com");
        when(userService.updateProfile("test1234@test.com", request)).thenReturn(updated);

        var response = authController.updateMe("Bearer jwt-token", request);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.OK);
        assertThat(response.getBody()).isNotNull();
        assertThat(response.getBody().getNickname()).isEqualTo("new-nick");
        verify(userService).updateProfile("test1234@test.com", request);
    }
}
