package com.heattrip.heat_trip_backend.user.controller;

import com.heattrip.heat_trip_backend.OAuth.principal.CurrentUser;
import com.heattrip.heat_trip_backend.user.dto.UpdateProfileRequest;
import com.heattrip.heat_trip_backend.user.dto.UserResponse;
import com.heattrip.heat_trip_backend.user.entity.User;
import org.springframework.web.bind.annotation.*;

import com.heattrip.heat_trip_backend.user.dto.LoginRequest;
import com.heattrip.heat_trip_backend.user.dto.SignupRequest;
import com.heattrip.heat_trip_backend.user.service.UserService;

import lombok.RequiredArgsConstructor;

import org.springframework.http.ResponseEntity;


@RestController
@RequestMapping("/auth")
@RequiredArgsConstructor
public class AuthController implements AuthApiDoc{
    
    private final UserService userService;

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
