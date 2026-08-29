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
import org.springframework.http.ResponseEntity;

import static org.assertj.core.api.Assertions.assertThat;
import static org.mockito.Mockito.verify;
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
}
