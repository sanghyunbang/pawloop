package com.heattrip.heat_trip_backend.user.controller;

import com.heattrip.heat_trip_backend.user.CurrentUser;
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

import jakarta.validation.Valid;

import lombok.RequiredArgsConstructor;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;



@RestController
@RequestMapping("/auth")
@RequiredArgsConstructor
public class AuthController implements AuthApiDoc{

    private final UserService userService;
    private final RefreshTokenService refreshTokenService;

    /** 1회용 코드 → 토큰. 소셜 경로에서 토큰이 나가는 유일한 자리다. (이슈 #14) */

    /**
     * 소셜 로그인의 <b>실제</b> 진입점. Spring Security 의 {@code oauth2Login()} 이 만든다.
     *
     * <p>{@code GET /auth/oauth/{provider}} 는 이 경로로 넘겨주는 얇은 래퍼일 뿐이다 —
     * 인증 로직을 다시 구현하지 않는다.
     */



    /**
     * 이메일/비밀번호 회원가입.
     *
     * <p>계약이 선언한 <b>201 + {@code User}</b> 다. 예전에는 200 + 평문 {@code "회원가입 성공"}
     * 이었다 — 계약 어디에도 없는 모양이고, 클라이언트가 방금 만든 계정의 {@code id} 조차
     * 알 수 없었다. (이슈 #10)
     */
    @PostMapping("/signup")
    public ResponseEntity<UserResponse> signup(@Valid @RequestBody SignupRequest request) {
        return ResponseEntity.status(HttpStatus.CREATED)
                .body(UserResponse.from(userService.signup(request)));
    }

    /**
     * 이메일/비밀번호 로그인 — 계약의 {@code AuthTokens} JSON.
     *
     * <p><b>반환 타입을 {@code ResponseEntity<String>} 으로 되돌리지 마라.</b> 그러면 #9 가
     * 발급·저장하는 refresh 토큰이 다시 아무에게도 전달되지 않고, 앱은 액세스 토큰이 만료될
     * 때마다 재로그인해야 한다. 되돌리면 {@code AuthContractIntegrationTest} 의 JSON 경로
     * 단언이 컴파일 또는 실행에서 죽는다. (이슈 #10 완료 조건 9)
     *
     * <p>자격증명 실패는 <b>본문 없는 401</b> 이다 — 서비스가 던지는
     * {@code UnauthenticatedException} 을 {@code GlobalExceptionHandler} 가 매핑한다.
     */
    @PostMapping("/login")
    public ResponseEntity<AuthTokensResponse> login(@RequestBody LoginRequest request) {
        return ResponseEntity.ok(userService.login(request));
    }


    /**
     * 액세스 토큰 갱신 — refresh 토큰 회전. (이슈 #9)
     *
     * <p>인증이 필요 없다({@code SecurityConfig.publicMatchers} 에 이미 있다). 그래서 이 경로의
     * 401 은 Spring Security 가 만들지 않는다 — 서비스가 던진 {@code UnauthenticatedException}
     * 이 {@code GlobalExceptionHandler} 에 매핑되어 <b>본문 없는 401</b> 이 된다. 그 매핑이
     * 끊기면 같은 요청이 조용히 500 으로 새므로 통합 테스트가 그것을 못 박는다.
     *
     * <p>응답은 로그인과 같은 {@code AuthTokensResponse} 지만 {@code isNew}·{@code user} 가
     * 없다 — 갱신에는 의미가 없는 질문이라 JSON 에서 아예 빠진다(#10 에서도 그대로 둔다).
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
     *
     * <p>응답 스키마는 계약의 {@code User} 다. {@code isNew} 는 여기 없다 — 그건 로그인 응답
     * ({@code AuthTokens})의 1회성 이벤트 속성이지 프로필의 영속 속성이 아니다(#23).
     */
    @GetMapping("/me")
    public ResponseEntity<UserResponse> me(@CurrentUser User me) {
        return ResponseEntity.ok(UserResponse.from(me));
    }

    /** 내 프로필 수정 (부분 수정) */
    @PutMapping("/me")
    public ResponseEntity<UserResponse> updateMe(
            @CurrentUser User me,
            // @Valid 가 없으면 DTO 의 @Size 가 **붙어 있어도 안 걸린다** (#229).
            @Valid @RequestBody UpdateProfileRequest req) {

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



}
