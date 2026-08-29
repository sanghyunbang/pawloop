package com.heattrip.heat_trip_backend.user.controller;

import com.heattrip.heat_trip_backend.OAuth.principal.CurrentUser;
import com.heattrip.heat_trip_backend.user.dto.UpdateProfileRequest;
import com.heattrip.heat_trip_backend.user.dto.UserResponse;
import com.heattrip.heat_trip_backend.user.entity.User;
import org.springframework.web.bind.annotation.*;

import com.heattrip.heat_trip_backend.user.dto.AuthTokensResponse;
import com.heattrip.heat_trip_backend.user.dto.LoginRequest;
import com.heattrip.heat_trip_backend.user.dto.RefreshTokenRequest;
import com.heattrip.heat_trip_backend.user.dto.SignupRequest;
import com.heattrip.heat_trip_backend.user.service.RefreshTokenService;
import com.heattrip.heat_trip_backend.user.service.UserService;

import lombok.RequiredArgsConstructor;

import org.springframework.http.ResponseEntity;


@RestController
@RequestMapping("/auth")
@RequiredArgsConstructor
public class AuthController implements AuthApiDoc{
    
    private final UserService userService;
    private final RefreshTokenService refreshTokenService;

    @PostMapping("/signup")
    public ResponseEntity<String> signup(@RequestBody SignupRequest request) {
        userService.signup(request);
        return ResponseEntity.ok("회원가입 성공");
    }

    @PostMapping("/login")
    public ResponseEntity<String> login(@RequestBody LoginRequest request) throws IllegalAccessException {
        String token = userService.login(request); 
        return ResponseEntity.ok(token);
    }


    /**
     * 액세스 토큰 갱신 — refresh 토큰 회전. (이슈 #9)
     *
     * <p>인증이 필요 없다({@code SecurityConfig.publicMatchers} 에 이미 있다). 그래서 이 경로의
     * 401 은 Spring Security 가 만들지 않는다 — 서비스가 던진 {@code UnauthenticatedException}
     * 이 {@code GlobalExceptionHandler} 에 매핑되어 <b>본문 없는 401</b> 이 된다. 그 매핑이
     * 끊기면 같은 요청이 조용히 500 으로 새므로 통합 테스트가 그것을 못 박는다.
     *
     * <p>로그인 응답(현행 JWT 평문 문자열)과 모양이 다른 것은 의도다. 로그인 응답을 이 JSON 으로
     * 맞추는 것은 #10 의 범위다.
     */
    @PostMapping("/token/refresh")
    public ResponseEntity<AuthTokensResponse> refresh(@RequestBody RefreshTokenRequest request) {
        return ResponseEntity.ok(refreshTokenService.rotate(request.getRefreshToken()));
    }

    /**
     * 내 프로필 조회.
     *
     * <p>인증 주체는 {@code CurrentUserArgumentResolver} 가 채운다 — 여기서 Authorization 헤더를
     * 다시 읽지 않는다. 주입에 실패하는 모든 경우는 본문 없는 401 이다. (이슈 #5)
     */
    @GetMapping("/me")
    public ResponseEntity<UserResponse> me(@CurrentUser User me) {
        return ResponseEntity.ok(UserResponse.from(me));
    }

    /** 내 프로필 수정 (부분 수정) */
    @PutMapping("/me")
    public ResponseEntity<UserResponse> updateMe(
            @CurrentUser User me,
            @RequestBody UpdateProfileRequest req) {

        User updated = userService.updateProfile(me.getId(), req);
        return ResponseEntity.ok(UserResponse.from(updated));
    }

    /** 내 계정 삭제 */
    @DeleteMapping("/me")
    public ResponseEntity<Void> deleteMe(@CurrentUser User me) {
        userService.deleteMe(me.getId());
        return ResponseEntity.noContent().build(); // 204
    }

    /** 로그아웃 */
    @Override
    @PostMapping("/logout")
    public ResponseEntity<Void> logout(@CurrentUser User me) {
        userService.logout(me.getId());
        return ResponseEntity.noContent().build();
    }

    /** oauth2를 이용한 소셜 로그인 */
    @GetMapping("/oauth/{provider}")
    public ResponseEntity<Void> socialLogin() {

        return ResponseEntity.ok().build();
    }


}
