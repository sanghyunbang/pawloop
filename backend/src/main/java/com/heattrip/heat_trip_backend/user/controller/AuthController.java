package com.heattrip.heat_trip_backend.user.controller;

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
public class AuthController {
    
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


    /** 내 프로필 조회 */
    @GetMapping("/me")
    public ResponseEntity<UserResponse> me(@RequestHeader("Authorization") String authHeader) {

        String email = userService.emailFromAuth(authHeader);
        User me = userService.findByEmail(email);
        return ResponseEntity.ok(UserResponse.from(me));
    }

    /** 내 프로필 수정 (부분 수정) */
    @PutMapping("/me")
    public ResponseEntity<UserResponse> updateMe(
            @RequestHeader("Authorization") String authHeader,
            @RequestBody UpdateProfileRequest req) {

        String email = userService.emailFromAuth(authHeader);
        User updated = userService.updateProfile(email, req);
        return ResponseEntity.ok(UserResponse.from(updated));
    }

    /** 내 계정 삭제 */
    @DeleteMapping("/me")
    public ResponseEntity<Void> deleteMe(@RequestHeader("Authorization") String authHeader) {
        String email = userService.emailFromAuth(authHeader); // 토큰 → 이메일
        userService.deleteMe(email);
        return ResponseEntity.noContent().build(); // 204
    }

}
