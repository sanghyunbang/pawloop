package com.heattrip.heat_trip_backend.OAuth.controller;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import com.heattrip.heat_trip_backend.OAuth.code.OAuthCodeExchangeService;

import org.mockito.InjectMocks;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.http.HttpStatus;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.Mockito.verifyNoMoreInteractions;

/**
 * {@code /auth/oauth/*} 두 경로. #107 에서 {@code AuthControllerTest} 에서 옮겨 왔다 —
 * 대상 코드가 {@code OAuthLoginController} 로 옮겨졌기 때문이다.
 *
 * <p><b>테스트를 같이 옮기는 것이 중요하다.</b> 커버리지 게이트가 {@code OAuth/**} 와
 * {@code user/**} 를 한 묶음(BUNDLE)으로 보고 하한이 0.80 이라, 코드만 옮기고 테스트를
 * 안 옮기면 덮이지 않은 줄이 그대로 남는다.
 */
@ExtendWith(MockitoExtension.class)
class OAuthLoginControllerTest {

    @Mock
    private OAuthCodeExchangeService oauthCodeExchangeService;

    @InjectMocks
    private OAuthLoginController controller;

    @Test
    @DisplayName("소셜 로그인 시작 API는 Spring 진입점으로 302 리다이렉트만 하고 인증 로직을 재구현하지 않는다")
    void startOAuth_redirectsToTheSpringEntryPoint() {
        // naver 는 ADR-0010 이 보류로 확정하면서 계약 enum 과 SUPPORTED_PROVIDERS 에서
        // 함께 빠졌다(#15). 이제 이 래퍼에서 400 이다 — AuthContractIntegrationTest 가 확인한다.
        for (String provider : new String[] {"kakao", "google"}) {
            var response = controller.startOAuth(provider, null);

            assertThat(response.getStatusCode())
                    .as("계약은 이 경로를 302 로 선언한다. 예전 구현은 빈 200 이었다")
                    .isEqualTo(HttpStatus.FOUND);
            assertThat(response.getHeaders().getLocation())
                    .hasToString("/oauth2/authorization/" + provider);
        }

        // 이 경로는 협력자를 전혀 부르지 않는다 — 부르는 순간 인증 로직의 두 번째 사본이 생긴다.
        // 옮기기 전에는 verifyNoMoreInteractions(userService) 였다. 이 컨트롤러에는 userService 가
        // 없으므로 같은 뜻을 이 컨트롤러의 유일한 협력자에 대해 단언한다. (#107)
        verifyNoMoreInteractions(oauthCodeExchangeService);
    }

    @Test
    @DisplayName("호환 래퍼가 state 를 302 대상까지 옮긴다 — 옮기지 않으면 그 경로로 시작한 로그인은 100% 실패한다")
    void startOAuth_forwardsTheAppState() {
        // #14 가 "돌아온 state 가 다르면 로그인 실패로 처리하라" 를 계약에 못 박았다.
        // 이 래퍼가 state 를 버리면 OAuthAppStateFilter 는 state 없는 요청만 보고, 딥링크는
        // ?code=X&state=(빈 값)으로 나가며, 앱의 대조는 반드시 실패한다. 계약이 이 경로를
        // "막다른 길에 빠지지 않게 하는 호환 표면" 이라고 광고하는데 그 반대였다.
        var response = controller.startOAuth("kakao", "AbC_123-xyz");

        assertThat(response.getHeaders().getLocation())
                .hasToString("/oauth2/authorization/kakao?state=AbC_123-xyz");
    }

    @Test
    @DisplayName("래퍼가 옮기는 state 는 화이트리스트를 통과한 값뿐이다 — 통과 못 하면 아예 붙이지 않는다")
    void startOAuth_dropsUnsafeState() {
        // 이 값은 Location 헤더에 그대로 들어간다. 검증 없이 이어 붙이면 & 나 개행 한 글자로
        // 파라미터·헤더를 주입할 수 있다. 잘라 쓰거나 인코딩하지 않고 **버린다** —
        // OAuthAppStateFilter 가 어차피 같은 이유로 버리는 값이다(패턴은 그쪽이 정본).
        for (String unsafe : new String[] {"a&b=c", "with space", "%0d%0aX-Injected: 1", "", "x".repeat(129)}) {
            assertThat(controller.startOAuth("kakao", unsafe).getHeaders().getLocation())
                    .as("불안전한 state(%s)는 붙지 않아야 한다", unsafe)
                    .hasToString("/oauth2/authorization/kakao");
        }
    }

    @Test
    @DisplayName("화이트리스트에 없는 공급자는 302 가 아니라 400 이고 사유에 입력값을 되싣지 않는다")
    void startOAuth_rejectsUnsupportedProvider() {
        // 화이트리스트를 지우면 facebook 이 302 를 받아 이 테스트가 빨간불이 된다.
        // (이슈 #10 완료 조건 11)
        assertThatThrownBy(() -> controller.startOAuth("facebook", null))
                .isInstanceOf(IllegalArgumentException.class)
                // 메시지는 그대로 400 응답 본문이 된다. 입력을 되싣으면 반사형 XSS 재료다.
                .hasMessageNotContaining("facebook");
    }

    @Test
    @DisplayName("공급자 이름은 대소문자와 앞뒤 공백을 가리지 않는다")
    void startOAuth_normalizesTheProviderName() {
        var response = controller.startOAuth("  Kakao ", null);

        assertThat(response.getStatusCode()).isEqualTo(HttpStatus.FOUND);
        assertThat(response.getHeaders().getLocation())
                .as("정규화하지 않으면 /oauth2/authorization/Kakao 로 넘어가 그쪽에서 등록을 못 찾는다")
                .hasToString("/oauth2/authorization/kakao");
    }

}
