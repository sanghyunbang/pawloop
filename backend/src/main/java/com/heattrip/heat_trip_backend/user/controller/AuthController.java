package com.heattrip.heat_trip_backend.user.controller;

import com.heattrip.heat_trip_backend.user.CurrentUser;
import com.heattrip.heat_trip_backend.user.NeighborhoodCatalog;
import com.heattrip.heat_trip_backend.user.dto.UpdateProfileRequest;
import com.heattrip.heat_trip_backend.user.dto.UserResponse;
import com.heattrip.heat_trip_backend.user.entity.User;
import org.springframework.web.bind.annotation.*;

import com.heattrip.heat_trip_backend.user.dto.AuthTokensResponse;
import com.heattrip.heat_trip_backend.user.dto.LoginRequest;
import com.heattrip.heat_trip_backend.user.dto.RefreshTokenRequest;
import com.heattrip.heat_trip_backend.user.dto.PasswordResetInput;
import com.heattrip.heat_trip_backend.user.dto.PasswordResetRequestInput;
import com.heattrip.heat_trip_backend.user.dto.ResendSignupCodeRequest;
import com.heattrip.heat_trip_backend.user.dto.SignupRequest;
import com.heattrip.heat_trip_backend.user.dto.SignupStartedResponse;
import com.heattrip.heat_trip_backend.user.dto.VerifySignupRequest;
import com.heattrip.heat_trip_backend.user.password.PasswordResetService;
import com.heattrip.heat_trip_backend.user.signup.EmailVerificationService;
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

    /** 이메일 가입의 인증 — 코드 발급·확인 (#635). */
    private final EmailVerificationService emailVerification;

    /** 비밀번호 재설정 — 같은 메일 기반 (#635 조각 ③). */
    private final PasswordResetService passwordReset;

    /** 동네 코드에 이름을 붙이는 표 (#342). */
    private final NeighborhoodCatalog neighborhoods;

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
    /**
     * 이메일 가입을 <b>시작</b>한다 — 이슈 #635. 계정은 아직 안 생긴다.
     *
     * <h3>왜 201 이 아니라 202 인가</h3>
     * <p>2026-09 이전에는 이 경로가 바로 계정을 만들고 201 을 줬다. 지금은 인증 코드를
     * 메일로 보내고, 계정은 {@code /auth/signup/verify} 에서 생긴다 — <b>만들어진 것이
     * 없으므로 201 은 거짓말이다.</b>
     *
     * <h3>이미 가입된 주소도 같은 202 다</h3>
     * <p>409 를 주면 이 경로가 "이 사람이 가입했나" 를 묻는 조회 수단이 된다. 대신 그
     * 주소로 "이미 계정이 있다" 는 안내 메일이 간다 — 진짜 주인만 알게 된다
     * ({@code EmailVerificationService} 의 javadoc).
     */
    @PostMapping("/signup")
    public ResponseEntity<SignupStartedResponse> signup(@Valid @RequestBody SignupRequest request) {
        return ResponseEntity.accepted()
                .body(new SignupStartedResponse(emailVerification.start(request)));
    }

    /**
     * 코드를 확인하고 <b>계정을 만든다</b>. 성공하면 바로 로그인된 상태로 토큰을 준다.
     *
     * <p>가입만 시키고 로그인 화면으로 되돌리면 방금 정한 비밀번호를 다시 치게 된다.
     *
     * <p>410 은 "다시 받아야 한다"(만료·시도 초과·대기 없음), 401 은 "코드가 틀렸다" 다.
     * 둘을 뭉개면 앱이 "다시 보내기" 를 언제 권할지 모른다.
     */
    @PostMapping("/signup/verify")
    public ResponseEntity<AuthTokensResponse> verifySignup(
            @Valid @RequestBody VerifySignupRequest request) {
        return ResponseEntity.ok(emailVerification.verify(request.getEmail(), request.getCode()));
    }

    /**
     * 코드를 다시 보낸다.
     *
     * <p>대기 행이 없어도 <b>같은 202</b> 다 — "그런 대기 없음" 을 말하면 이 경로도 가입 여부
     * 조회 수단이 된다.
     */
    @PostMapping("/signup/resend")
    public ResponseEntity<SignupStartedResponse> resendSignupCode(
            @Valid @RequestBody ResendSignupCodeRequest request) {
        return ResponseEntity.accepted()
                .body(new SignupStartedResponse(emailVerification.resend(request.getEmail())));
    }

    /**
     * 비밀번호를 잊었을 때 코드를 보낸다 — 이슈 #635 조각 ③.
     *
     * <p><b>응답에 본문이 없다.</b> 그 주소로 계정이 있는지를 말하지 않는 것이 이 경로의
     * 요점이라, 돌려줄 것이 하나도 없어야 한다. 가입({@code /auth/signup})이
     * {@code mailSent} 를 주는 것과 다른데, 거기는 두 갈래가 모두 메일을 보내므로 그 값이
     * 아무것도 가리지 않는다. 여기서는 없는 주소에 메일을 안 보내므로 <b>그 값 자체가
     * 답이 된다.</b>
     *
     * <p>앱은 "가입된 주소라면 메일을 보냈어요" 라고 말하면 된다.
     */
    @PostMapping("/password/reset-request")
    public ResponseEntity<Void> requestPasswordReset(
            @Valid @RequestBody PasswordResetRequestInput request) {
        passwordReset.request(request.getEmail());
        return ResponseEntity.accepted().build();
    }

    /**
     * 코드를 확인하고 비밀번호를 바꾼다 — 이슈 #635 조각 ③.
     *
     * <p>성공하면 바로 로그인된 상태로 토큰을 준다. 그리고 <b>다른 기기의 세션을 전부
     * 끊는다</b> — 재설정을 하는 흔한 이유가 "누가 내 계정에 들어온 것 같다" 인데,
     * 살아 있는 refresh 토큰을 두면 그 사람은 그대로 들어와 있다.
     *
     * <p>410 은 "다시 받아야 한다"(만료·시도 초과·진행 중인 재설정 없음), 401 은
     * "코드가 틀렸다" 다. <b>없는 주소도 410</b> 이다 — 404 를 주면 이 경로가 가입 여부를
     * 묻는 조회 수단이 된다.
     */
    @PostMapping("/password/reset")
    public ResponseEntity<AuthTokensResponse> resetPassword(
            @Valid @RequestBody PasswordResetInput request) {
        return ResponseEntity.ok(passwordReset.reset(
                request.getEmail(), request.getCode(), request.getNewPassword()));
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
        return ResponseEntity.ok(withNeighborhood(me));
    }

    /** 내 프로필 수정 (부분 수정) */
    @PutMapping("/me")
    public ResponseEntity<UserResponse> updateMe(
            @CurrentUser User me,
            // @Valid 가 없으면 DTO 의 @Size 가 **붙어 있어도 안 걸린다** (#229).
            @Valid @RequestBody UpdateProfileRequest req) {

        User updated = userService.updateProfile(me.getId(), req);
        return ResponseEntity.ok(withNeighborhood(updated));
    }

    /**
     * 동네 이름을 붙여 응답한다 (#342).
     *
     * <p>이름은 서버의 표에서만 나온다 — 본문으로 받으면 아무나 자기 동네를 "청와대" 라고
     * 적어 글 카드에 띄울 수 있다.
     */
    private UserResponse withNeighborhood(User user) {
        return UserResponse.from(user,
                neighborhoods.find(user.getNeighborhoodCode()).orElse(null));
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
