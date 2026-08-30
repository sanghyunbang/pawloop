package com.heattrip.heat_trip_backend.user.controller;

import com.heattrip.heat_trip_backend.OAuth.principal.CurrentUser;
import com.heattrip.heat_trip_backend.user.dto.UpdateProfileRequest;
import com.heattrip.heat_trip_backend.user.dto.UserResponse;
import com.heattrip.heat_trip_backend.user.entity.User;
import org.springframework.web.bind.annotation.*;

import com.heattrip.heat_trip_backend.OAuth.code.OAuthCodeExchangeService;
import com.heattrip.heat_trip_backend.OAuth.state.OAuthAppStateFilter;
import com.heattrip.heat_trip_backend.user.dto.AuthTokensResponse;
import com.heattrip.heat_trip_backend.user.dto.LoginRequest;
import com.heattrip.heat_trip_backend.user.dto.OAuthCodeExchangeRequest;
import com.heattrip.heat_trip_backend.user.dto.RefreshTokenRequest;
import com.heattrip.heat_trip_backend.user.dto.SignupRequest;
import com.heattrip.heat_trip_backend.user.service.RefreshTokenService;
import com.heattrip.heat_trip_backend.user.service.UserService;

import lombok.RequiredArgsConstructor;

import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;

import java.net.URI;
import java.util.List;
import java.util.Locale;


@RestController
@RequestMapping("/auth")
@RequiredArgsConstructor
public class AuthController implements AuthApiDoc{

    private final UserService userService;
    private final RefreshTokenService refreshTokenService;

    /** 1회용 코드 → 토큰. 소셜 경로에서 토큰이 나가는 유일한 자리다. (이슈 #14) */
    private final OAuthCodeExchangeService oauthCodeExchangeService;

    /**
     * 소셜 로그인의 <b>실제</b> 진입점. Spring Security 의 {@code oauth2Login()} 이 만든다.
     *
     * <p>{@code GET /auth/oauth/{provider}} 는 이 경로로 넘겨주는 얇은 래퍼일 뿐이다 —
     * 인증 로직을 다시 구현하지 않는다.
     */
    private static final String SPRING_OAUTH2_ENTRY_POINT = "/oauth2/authorization/";

    /**
     * 계약({@code docs/04-api/openapi.yaml} 의 {@code components/parameters/Provider})의
     * enum 과 <b>같은 목록</b>이어야 한다. 여기서만 넓히면 계약에 없는 값이 302 로 통과한다.
     *
     * <p>{@code naver} 가 있는 이유: 제품 결정상 보류(#15)일 뿐 백엔드 설정과 매핑 코드가
     * 살아 있고, 계약도 enum 에 유지한다.
     */
    private static final List<String> SUPPORTED_PROVIDERS = List.of("kakao", "naver", "google");

    /**
     * 호환 래퍼가 302 대상에 실어 보내도 되는 {@code state} 의 형태.
     * <b>패턴을 여기 다시 적지 않는다</b> — {@link OAuthAppStateFilter#SAFE_STATE} 가 정본이고,
     * 사본을 만들면 한쪽만 넓어져 래퍼는 통과시키는데 필터는 버리는 값이 생긴다.
     */
    private static final java.util.regex.Pattern SAFE_OAUTH_STATE = OAuthAppStateFilter.SAFE_STATE;

    /**
     * 이메일/비밀번호 회원가입.
     *
     * <p>계약이 선언한 <b>201 + {@code User}</b> 다. 예전에는 200 + 평문 {@code "회원가입 성공"}
     * 이었다 — 계약 어디에도 없는 모양이고, 클라이언트가 방금 만든 계정의 {@code id} 조차
     * 알 수 없었다. (이슈 #10)
     */
    @PostMapping("/signup")
    public ResponseEntity<UserResponse> signup(@RequestBody SignupRequest request) {
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

    /**
     * 계약 경로의 소셜 로그인 시작 — {@code /oauth2/authorization/{provider}} 로의 <b>302 래퍼</b>.
     *
     * <p>예전에는 {@code ResponseEntity.ok().build()} 였다. 계약은 이 경로를 302 로 선언하면서
     * 동시에 "미구현 — 핸들러가 없다"고 적었는데, 실제로는 핸들러가 있었고 <b>빈 200</b> 을
     * 줬다. 계약도 코드도 사실이 아니었고, {@code AuthContractSpecTest} 가 그 거짓을 잠그고
     * 있었다. 셋을 함께 고친다. (이슈 #10 · #5 코멘트)
     *
     * <p><b>인증 로직을 여기서 다시 구현하지 않는다.</b> 실제 진입점은 Spring Security 의
     * {@code oauth2Login()} 이 만드는 {@code /oauth2/authorization/{provider}} 이고, 성공 시
     * 딥링크 복귀는 {@code OAuth2SuccessHandler} 가 그대로 처리한다.
     *
     * <p>화이트리스트에 없는 {@code provider} 는 <b>400</b> 이다 — 302 로 넘겨 봐야
     * {@code /oauth2/authorization/facebook} 에는 등록이 없어 그쪽에서 오류가 나고, 그 오류는
     * 원인을 알려 주지 않는다. 여기서 막으면 계약이 선언한 {@code Error} 본문으로 이유가 간다.
     * 사유 문구에 {@code provider} 원문을 되싣지 않는다 — 그건 곧 반사형 XSS 재료다.
     */
    @GetMapping("/oauth/{provider}")
    public ResponseEntity<Void> startOAuth(@PathVariable("provider") String provider,
                                           @RequestParam(value = "state", required = false) String state) {
        String normalized = provider == null ? "" : provider.trim().toLowerCase(Locale.ROOT);

        if (!SUPPORTED_PROVIDERS.contains(normalized)) {
            throw new IllegalArgumentException(
                    "지원하지 않는 소셜 로그인 공급자입니다. " + SUPPORTED_PROVIDERS + " 중 하나여야 합니다.");
        }

        return ResponseEntity.status(HttpStatus.FOUND)
                .location(URI.create(SPRING_OAUTH2_ENTRY_POINT + normalized + stateQuery(state)))
                .build();
    }

    /**
     * 302 대상에 이어 붙일 {@code ?state=...}. 통과하지 못한 값은 <b>붙이지 않는다</b>. (이슈 #14)
     *
     * <h2>왜 필요한가</h2>
     * #14 는 "돌아온 {@code state} 가 보낸 값과 다르면 로그인 실패로 처리하라" 를 계약 본문에
     * 못 박았다. 그런데 이 래퍼는 쿼리스트링을 옮기지 않아서, {@code GET /auth/oauth/kakao?state=S}
     * 로 시작한 클라이언트의 {@code S} 가 302 에서 사라졌다. 그러면 {@code OAuthAppStateFilter}
     * 는 {@code state} 없는 요청만 보게 되어 세션에 아무것도 담지 않고, 성공 딥링크는
     * {@code ?code=X&state=}(빈 값)으로 나가며, 앱의 대조는 <b>반드시</b> 실패한다.
     * 계약이 이 경로를 "막다른 길에 빠지지 않게 하는 호환 표면" 이라고 광고하는데, 그것을
     * 따르는 클라이언트는 100% 로그인에 실패하는 상태였다.
     *
     * <h2>왜 화이트리스트인가</h2>
     * 이 값은 {@code Location} 헤더에 그대로 들어간다. 검증 없이 이어 붙이면 개행이나
     * {@code &}·{@code #} 한 글자로 헤더·파라미터를 주입할 수 있다. {@code OAuthAppStateFilter}
     * 와 <b>같은</b> 문자 집합만 통과시킨다 — 어차피 그 필터를 통과하지 못하는 값을 실어 보내
     * 봐야 앱은 빈 {@code state} 를 받게 되고, 그때 실패의 이유를 알 수 없다.
     */
    private static String stateQuery(String state) {
        return (state != null && SAFE_OAUTH_STATE.matcher(state).matches())
                ? "?state=" + state
                : "";
    }

    /**
     * 1회용 코드 → {@code AuthTokens} 교환. (이슈 #14)
     *
     * <p>계약이 오래 자리만 잡아 두고 "미구현" 이라 적어 두었던 경로다. 이제 <b>소셜 로그인에서
     * 토큰이 클라이언트에 도달하는 유일한 통로</b>다 — 딥링크에는 코드와 {@code state} 만 실린다.
     *
     * <p>덕분에 {@code AuthTokens} 의 {@code expiresIn}·{@code isNew}·{@code user} 가 소셜
     * 경로에서도 도달한다. 예전에는 그 셋이 URL 쿼리로 표현할 방법이 없어 앱이 소셜 신규
     * 가입자를 온보딩으로 보내지 못했다.
     *
     * <p>인증이 필요 없다({@code SecurityConfig.publicMatchers} 의 {@code /auth/oauth/**}).
     * 주체는 코드 자체가 증명한다. 실패는 원인과 무관하게 <b>본문 없는 401</b> 이다 —
     * 구분해 주면 그 차이가 코드의 존재 여부를 알려 주는 오라클이 된다.
     *
     * <p>{@code provider} 화이트리스트 검사를 여기서 다시 하지 않는 이유: 코드에는 그것을 만든
     * 공급자가 실려 있고, 서비스가 경로 변수와 그 값을 대조한다. 목록에 없는 공급자로 만든
     * 코드는 애초에 존재할 수 없으므로 401 이 정확한 답이다.
     */
    @PostMapping("/oauth/{provider}/callback")
    public ResponseEntity<AuthTokensResponse> exchangeOAuthCode(
            @PathVariable("provider") String provider,
            @RequestBody OAuthCodeExchangeRequest request) {
        return ResponseEntity.ok(
                oauthCodeExchangeService.exchange(provider, request.getCode(), request.getState()));
    }
}
