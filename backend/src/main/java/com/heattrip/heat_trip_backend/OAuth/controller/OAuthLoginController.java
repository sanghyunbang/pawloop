package com.heattrip.heat_trip_backend.OAuth.controller;

import com.heattrip.heat_trip_backend.OAuth.code.OAuthCodeExchangeService;
import com.heattrip.heat_trip_backend.OAuth.state.OAuthAppStateFilter;
import com.heattrip.heat_trip_backend.user.dto.AuthTokensResponse;
import com.heattrip.heat_trip_backend.user.dto.OAuthCodeExchangeRequest;

import io.swagger.v3.oas.annotations.tags.Tag;
import lombok.RequiredArgsConstructor;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.net.URI;
import java.util.List;
import java.util.Locale;

/**
 * 소셜 로그인 진입과 1회용 코드 교환. (#107 에서 {@code user.controller.AuthController} 에서 분리)
 *
 * <h2>왜 분리했나</h2>
 * <p>이 두 경로는 {@code OAuth.code.OAuthCodeExchangeService} 와
 * {@code OAuth.state.OAuthAppStateFilter} 를 부른다. 그것들이 {@code user} 안의 컨트롤러에서
 * 불리면 {@code user -> OAuth} 화살표가 생기고, {@code OAuth} 는 이미 {@code user} 를 부르므로
 * <b>순환</b>이었다. 저장소에 마지막으로 남아 있던 순환이 이것이다.
 *
 * <p>{@code AuthController} 를 통째로 옮기는 길도 있었지만 고르지 않았다. 그러면
 * {@code /auth/signup} 과 {@code /auth/login} — 이메일·비밀번호 경로 — 이 소셜 로그인 모듈
 * 밑에 놓인다. 이름과 내용이 어긋난다. <b>OAuth 인 것만</b> 옮겼다.
 *
 * <h2>계약은 안 바뀐다</h2>
 * <p>경로({@code /auth/oauth/{provider}} · {@code /auth/oauth/{provider}/callback})도, 응답
 * 형태도, {@code @Tag(name = "Auth")} 그룹도 그대로다. 그룹을 여기 다시 적는 이유는
 * springdoc 이 태그를 <b>컨트롤러 단위</b>로 붙이기 때문이다 — 안 적으면 이 두 오퍼레이션만
 * 다른 그룹으로 떨어져 나가고, 그건 {@code openapi.yaml} 과 갈리는 것이다.
 */
@RestController
@RequestMapping("/auth")
@RequiredArgsConstructor
@Tag(name = "Auth", description = "소셜 로그인 · 토큰 · 내 정보")
public class OAuthLoginController {

    private final OAuthCodeExchangeService oauthCodeExchangeService;

    /**
     * 스프링 시큐리티 {@code oauth2Login()} 이 만드는 진짜 진입점. 이 컨트롤러의
     * {@code GET /auth/oauth/{provider}} 는 그리로 보내는 호환 래퍼일 뿐이다.
     */
    private static final String SPRING_OAUTH2_ENTRY_POINT = "/oauth2/authorization/";

    /**
     * 계약({@code docs/04-api/openapi.yaml} 의 {@code components/parameters/Provider})의
     * enum 과 <b>같은 목록</b>이어야 한다. 여기서만 넓히면 계약에 없는 값이 302 로 통과한다.
     *
     * <p>{@code naver} 는 <b>없다</b> — ADR-0010 이 보류로 확정했고 계약 enum 에서도 뺐다.
     * 예전에는 여기 있었고 계약에도 있었다. 두 곳을 같이 좁힌 것이지 한쪽만 좁힌 것이 아니다.
     *
     * <p><b>이것만으로 네이버 로그인이 막히지는 않는다.</b> 앱이 실제로 여는 것은 이 래퍼가
     * 아니라 스프링 시큐리티 자체 진입점 {@code /oauth2/authorization/{provider}} 이고
     * ({@code social_login_service.dart}), 네이버 클라이언트 등록은
     * {@code application-dev/prod.properties} 에 아직 살아 있다. 그 구멍을 닫는 것은 #13 이
     * 소유한다. 여기서 좁히는 것은 "계약이 광고하는 집합과 코드가 통과시키는 집합을 같게
     * 유지한다" 는 불변식이다 — {@code OpenApiAuthContractTest} 가 두 집합을 대조한다.
     */
    private static final List<String> SUPPORTED_PROVIDERS = List.of("kakao", "google", "apple");

    /**
     * 호환 래퍼가 302 대상에 실어 보내도 되는 {@code state} 의 형태.
     * <b>패턴을 여기 다시 적지 않는다</b> — {@link OAuthAppStateFilter#SAFE_STATE} 가 정본이고,
     * 사본을 만들면 한쪽만 넓어져 래퍼는 통과시키는데 필터는 버리는 값이 생긴다.
     */
    private static final java.util.regex.Pattern SAFE_OAUTH_STATE = OAuthAppStateFilter.SAFE_STATE;

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
