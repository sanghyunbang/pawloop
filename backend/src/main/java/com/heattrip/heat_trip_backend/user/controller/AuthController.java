package com.heattrip.heat_trip_backend.user.controller;

import com.heattrip.heat_trip_backend.user.dto.UpdateProfileRequest;
import com.heattrip.heat_trip_backend.user.dto.UserResponse;
import com.heattrip.heat_trip_backend.user.entity.User;
import jakarta.servlet.http.HttpServletRequest;
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
     * <p><b>알려진 결함 — 소셜 계정에서는 동작하지 않는다. 고치는 곳은 이슈 #5 다.</b>
     * 소셜 로그인이 발급하는 JWT 의 {@code sub} 는 {@code CustomOAuth2User.getName()} =
     * {@code "kakao_1234567890"} 인데, 아래 코드는 그 값을 이메일로 보고 {@code findByEmail} 한다.
     * 그래서 모든 소셜 계정에서 이 엔드포인트가 400 이다 — {@code PUT /me}·{@code DELETE /me}·
     * {@code POST /logout} 도 같은 이유로 같은 상태다.
     *
     * <p>이슈 #7(소셜 계정 모델)은 저장 구조만 고쳤고 이 조회 경로는 일부러 건드리지 않았다.
     * subject 를 {@code users.id} 로 통일하는 것이 #5 의 범위이고, 여기서 우회하면 #5 가
     * 지워야 할 코드가 늘어난다. <b>#7 의 완료 조건 2(이메일 없는 카카오 계정으로
     * {@code GET /auth/me} 가 200)는 #5 가 들어와야 참이 된다.</b>
     */
    @GetMapping("/me")
    public ResponseEntity<UserResponse> me(@RequestHeader("Authorization") String authHeader) {

        // TODO(#5): subject 를 users.id 로 통일하고 findById 로 바꾼다.
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

    /** 로그아웃 */
    @Override
    @PostMapping("/logout")
    public ResponseEntity<?> logout(HttpServletRequest request) {


        String authHeader = request.getHeader("Authorization"); // 헤더 직접 꺼내기
        String email = userService.emailFromAuth(authHeader); // /me와 마찬가지로 토믄에서 이메일 꺼내고
        userService.logout(email);
        return ResponseEntity.noContent().build();
    }

    /** oauth2를 이용한 소셜 로그인 */
    @GetMapping("/oauth/{provider}")
    public ResponseEntity<Void> socialLogin() {

        return ResponseEntity.ok().build();
    }


}
