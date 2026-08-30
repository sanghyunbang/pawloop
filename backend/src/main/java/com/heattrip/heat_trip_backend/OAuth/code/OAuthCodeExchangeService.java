package com.heattrip.heat_trip_backend.OAuth.code;

import com.heattrip.heat_trip_backend.OAuth.jwt.JWTProvider;
import com.heattrip.heat_trip_backend.OAuth.principal.UnauthenticatedException;
import com.heattrip.heat_trip_backend.user.dto.AuthTokensResponse;
import com.heattrip.heat_trip_backend.user.dto.UserResponse;
import com.heattrip.heat_trip_backend.user.entity.User;
import com.heattrip.heat_trip_backend.user.repository.UserRepository;
import com.heattrip.heat_trip_backend.user.service.RefreshTokenService;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.Locale;
import java.util.Optional;

/**
 * 1회용 코드 → {@code AuthTokens}. 계약의 {@code POST /auth/oauth/{provider}/callback} 의 속. (이슈 #14)
 *
 * <p>토큰이 소셜 경로로 나가는 <b>유일한</b> 자리다. {@code OAuth2SuccessHandler} 는 이제
 * 코드만 만들고, 토큰은 여기서 응답 본문으로만 나간다 — URL 로는 나가지 않는다.
 *
 * <h2>실패는 전부 본문 없는 401 이다</h2>
 * 없는 코드·이미 쓴 코드·만료된 코드·공급자 불일치·{@code state} 부재·{@code state} 불일치·
 * 주체 소실이 전부 같은 모양이다. 구분해 주면 그 응답 차이 자체가 "그 코드가 존재하긴 했는가" 를 알려 주는
 * 오라클이 된다. {@code UnauthenticatedException} 은 {@code GlobalExceptionHandler} 가
 * 본문 없는 401 로 매핑한다(#44 가 정한 자리 — 새 advice 를 만들면 catch-all 이 먼저 잡아 500 이 샌다).
 */
@Service
public class OAuthCodeExchangeService {

    private static final Logger log = LoggerFactory.getLogger(OAuthCodeExchangeService.class);

    private final AuthCodeStore authCodeStore;
    private final JWTProvider jwtProvider;
    private final RefreshTokenService refreshTokenService;
    private final UserRepository userRepository;

    public OAuthCodeExchangeService(AuthCodeStore authCodeStore,
                                    JWTProvider jwtProvider,
                                    RefreshTokenService refreshTokenService,
                                    UserRepository userRepository) {
        this.authCodeStore = authCodeStore;
        this.jwtProvider = jwtProvider;
        this.refreshTokenService = refreshTokenService;
        this.userRepository = userRepository;
    }

    /**
     * 코드를 토큰으로 바꾼다.
     *
     * @param provider 경로 변수. 코드를 만든 공급자와 같아야 한다
     * @param code     딥링크로 받은 1회용 코드
     * @param state    앱이 인증 시작 때 만들어 저장해 둔 난수
     * @throws UnauthenticatedException 위 실패 전부 — <b>본문 없는 401</b>
     */
    public AuthTokensResponse exchange(String provider, String code, String state) {
        // consume 은 성공하든 실패하든 그 코드를 죽인다. 여기서 아래 검사에 걸려 401 이 나도
        // 같은 코드로 다시 시도할 수 없다 — 그게 옳다. 코드 하나에 시도 한 번이다.
        AuthCode authCode = authCodeStore.consume(code).orElseThrow(() -> {
            log.warn("[소셜 코드 교환] 살아 있지 않은 코드가 제시되었다 — 없음·재사용·만료 중 하나.");
            return new UnauthenticatedException();
        });

        // 코드는 그것을 만든 공급자의 경로로만 교환된다. 아니면 카카오로 얻은 코드를
        // /auth/oauth/google/callback 으로 밀어 넣어도 통과한다 — 계약이 경로 변수를 두고
        // 있는데 아무 의미가 없는 상태가 된다.
        if (!normalize(provider).equals(normalize(authCode.provider()))) {
            log.warn("[소셜 코드 교환] 코드를 만든 공급자와 교환 경로가 다르다.");
            throw new UnauthenticatedException();
        }

        // ── 서버쪽 state 대조 ────────────────────────────────────────────────
        //
        // 앱쪽 대조(응답 바꿔치기 방어)를 대신하지 않는다 — 코드를 그것이 시작된 인증
        // 왕복에 묶어 두는 두 번째 줄이다.
        //
        // ⚠️ 빈 state 로 발급된 코드는 **교환하지 않는다.** 예전에는 "옛 앱은 state 를
        // 보내지 않으니 양쪽 다 빈 문자열이면 통과" 였는데, 그러면 이 검사의 존재 여부를
        // 왕복을 시작한 쪽이 정하게 된다 — state 를 생략하기만 하면 두 번째 줄이 사라진다.
        // 검사를 켜고 끄는 스위치를 클라이언트에게 주는 것과 같다.
        //
        // 하위 호환을 잃지 않는가: 잃을 것이 없다. `?token=` 딥링크를 기다리던 옛 앱은
        // 이 브랜치가 딥링크 모양을 바꾼 시점에 이미 로그인이 성립하지 않는다. 지금
        // 출시되는 앱은 `newOAuthState()` 로 항상 state 를 만들어 보낸다.
        if (nullToEmpty(authCode.state()).isBlank()) {
            log.warn("[소셜 코드 교환] state 없이 시작된 인증의 코드는 교환하지 않는다.");
            throw new UnauthenticatedException();
        }
        if (!constantTimeEquals(authCode.state(), nullToEmpty(state))) {
            log.warn("[소셜 코드 교환] state 가 코드 발급 시점의 값과 다르다.");
            throw new UnauthenticatedException();
        }

        // 권한은 코드가 아니라 사용자 행에서 읽는다 — 발급과 교환 사이(≤60초)에
        // 탈퇴하거나 권한이 내려갔으면 그 변화가 토큰에 반영돼야 한다.
        User user = Optional.ofNullable(authCode.userId())
                .flatMap(userRepository::findById)
                .orElseThrow(UnauthenticatedException::new);

        String accessToken = jwtProvider.createAccessToken(user.getId(), roleOf(user));
        // RT 발급·저장의 유일한 통로. 원문은 이 응답 본문 말고 아무 데도 남지 않는다. (이슈 #9)
        String refreshToken = refreshTokenService.issueFor(user.getId());

        log.debug("소셜 1회용 코드를 토큰으로 교환했다.");
        return new AuthTokensResponse(
                accessToken,
                refreshToken,
                jwtProvider.getExpiresInSeconds(),
                authCode.isNew(),
                UserResponse.from(user));
    }

    /** role 컬럼이 없던 시절에 만들어진 행은 값이 비어 있을 수 있다. */
    private static String roleOf(User user) {
        String role = user.getRole();
        return (role == null || role.isBlank()) ? User.ROLE_USER : role;
    }

    private static String normalize(String value) {
        return value == null ? "" : value.trim().toLowerCase(Locale.ROOT);
    }

    private static String nullToEmpty(String value) {
        return value == null ? "" : value;
    }

    /**
     * 길이와 내용 비교에 조기 반환이 없다. {@code state} 는 짧게 사는 값이라 타이밍 공격의
     * 현실적 가치는 낮지만, 비교 한 줄을 안전하게 쓰는 데 드는 비용도 0 이다.
     */
    private static boolean constantTimeEquals(String a, String b) {
        return MessageDigest.isEqual(
                a.getBytes(StandardCharsets.UTF_8),
                b.getBytes(StandardCharsets.UTF_8));
    }
}
