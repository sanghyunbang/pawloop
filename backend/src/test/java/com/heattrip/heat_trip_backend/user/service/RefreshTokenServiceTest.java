package com.heattrip.heat_trip_backend.user.service;

import com.heattrip.heat_trip_backend.OAuth.jwt.JWTProvider;
import com.heattrip.heat_trip_backend.OAuth.principal.UnauthenticatedException;
import com.heattrip.heat_trip_backend.user.dto.AuthTokensResponse;
import com.heattrip.heat_trip_backend.user.entity.RefreshToken;
import com.heattrip.heat_trip_backend.user.entity.User;
import com.heattrip.heat_trip_backend.user.repository.RefreshTokenRepository;
import com.heattrip.heat_trip_backend.user.repository.UserRepository;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;

import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.time.Clock;
import java.time.Duration;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.util.HexFormat;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

/**
 * refresh 토큰의 발급·회전·재사용 감지·만료 정리를 목과 <b>고정 {@link Clock}</b> 으로 잠근다 — 이슈 #9.
 *
 * <p>고정 시계가 있어야 "만료 시각 = 발급 시각 + {@code jwt.refresh-expiration}" 을 벽시계 없이
 * 단언할 수 있다. 이슈가 "테스트하기 어려운 부분"으로 지목한 자리가 정확히 그것이다 —
 * {@code expiresAt} 을 과거로 직접 세팅하는 우회로는 설정값 자체가 검증되지 않는다.
 *
 * <p>해시 검증에서 프로덕션 함수를 재사용하지 않고 테스트가 {@link MessageDigest} 로 직접
 * 계산하는 것도 의도다. 같은 함수를 양쪽에서 쓰면 그 함수를 항등식으로 바꿔도 초록불이다.
 */
@ExtendWith(MockitoExtension.class)
class RefreshTokenServiceTest {

    /** 14일. application-*.properties 의 jwt.refresh-expiration 기본값과 같은 값이다. */
    private static final long REFRESH_EXPIRATION_MILLIS = 1_209_600_000L;

    private static final LocalDateTime NOW = LocalDateTime.of(2026, 8, 30, 12, 0, 0);
    private static final long USER_ID = 7L;

    @Mock
    private RefreshTokenRepository refreshTokenRepository;

    @Mock
    private UserRepository userRepository;

    @Mock
    private JWTProvider jwtProvider;

    private RefreshTokenService refreshTokenService;

    @BeforeEach
    void createService() {
        Clock fixed = Clock.fixed(NOW.atZone(ZoneId.systemDefault()).toInstant(), ZoneId.systemDefault());
        refreshTokenService = new RefreshTokenService(
                refreshTokenRepository, userRepository, jwtProvider, fixed, REFRESH_EXPIRATION_MILLIS);
    }

    // ─────────────────────── 발급 (완료 조건 8) ───────────────────────

    @Test
    @DisplayName("발급된 refresh 토큰은 원문이 아니라 그 SHA-256 hex 로만 저장된다")
    void issueFor_storesOnlyTheHash() {
        String raw = refreshTokenService.issueFor(USER_ID);

        RefreshToken saved = captureSaved();
        assertThat(saved.getTokenHash())
                .as("평문을 그대로 넣으면 DB 유출이 곧 전 계정 탈취다 (완료 조건 8)")
                .isNotEqualTo(raw)
                .isEqualTo(independentSha256Hex(raw))
                .hasSize(64);
        assertThat(saved.getUserId()).isEqualTo(USER_ID);
        assertThat(saved.getRevokedAt()).as("갓 발급한 토큰은 살아 있다").isNull();
    }

    @Test
    @DisplayName("발급된 refresh 토큰 원문은 패딩 없는 Base64URL 43자다 — 딥링크에 그대로 실을 수 있다")
    void issueFor_returnsPaddingFreeBase64Url() {
        String raw = refreshTokenService.issueFor(USER_ID);

        // '=' 가 있으면 딥링크 쿼리스트링에 URL 인코딩 규약을 앱과 합의해야 한다.
        // 43자는 256bit 를 Base64 로 적었을 때의 길이다 — 엔트로피가 줄지 않았다는 뜻이기도 하다.
        assertThat(raw).hasSize(43).matches("[A-Za-z0-9_-]{43}");
    }

    @Test
    @DisplayName("만료 시각은 고정 시계의 현재 시각 + jwt.refresh-expiration(14일) 과 정확히 같다")
    void issueFor_usesConfiguredExpiration() {
        // 이 단언이 설정값을 실제로 잠근다. 만료 계산을 상수로 하드코딩하면 여기서 걸린다.
        refreshTokenService.issueFor(USER_ID);

        RefreshToken saved = captureSaved();
        assertThat(saved.getCreatedAt()).isEqualTo(NOW);
        assertThat(saved.getExpiresAt())
                .isEqualTo(NOW.plus(Duration.ofMillis(REFRESH_EXPIRATION_MILLIS)))
                .isEqualTo(NOW.plusDays(14));
    }

    @Test
    @DisplayName("두 번 발급하면 서로 다른 원문이 나온다 — 난수원이 살아 있다")
    void issueFor_returnsDistinctTokens() {
        assertThat(refreshTokenService.issueFor(USER_ID))
                .isNotEqualTo(refreshTokenService.issueFor(USER_ID));
    }

    // ─────────────────────── 정상 회전 (완료 조건 2·3) ───────────────────────

    @Test
    @DisplayName("유효한 refresh 토큰으로 회전하면 옛 행이 폐기되고 새 액세스·refresh 토큰이 나온다")
    void rotate_revokesOldRowAndIssuesNewPair() {
        String oldRaw = "old-refresh-token";
        RefreshToken live = live(oldRaw);
        when(refreshTokenRepository.findByTokenHash(independentSha256Hex(oldRaw)))
                .thenReturn(Optional.of(live));
        when(refreshTokenRepository.revokeIfLive(live.getId(), NOW)).thenReturn(1);
        when(userRepository.findById(USER_ID)).thenReturn(Optional.of(user("ROLE_USER")));
        when(jwtProvider.createAccessToken(USER_ID, "ROLE_USER")).thenReturn("new-access-token");
        when(jwtProvider.getExpiresInSeconds()).thenReturn(3600L);

        AuthTokensResponse response = refreshTokenService.rotate(oldRaw);

        // 옛 행에 revokedAt 을 찍지 않으면 완료 조건 3("옛 RT 로 다시 refresh → 401")이 성립하지 않는다.
        verify(refreshTokenRepository).revokeIfLive(live.getId(), NOW);
        assertThat(response.accessToken()).isEqualTo("new-access-token");
        assertThat(response.expiresIn()).isEqualTo(3600L);
        assertThat(response.refreshToken())
                .as("회전은 '같은 토큰을 다시 주는 것' 이 아니다 (완료 조건 2)")
                .isNotEqualTo(oldRaw)
                .isNotBlank();
        assertThat(captureSaved().getTokenHash())
                .isEqualTo(independentSha256Hex(response.refreshToken()));
    }

    @Test
    @DisplayName("회전이 만드는 액세스 토큰의 권한은 DB 의 role 값을 쓴다")
    void rotate_usesRoleFromDatabase() {
        String raw = "admin-refresh-token";
        RefreshToken live = live(raw);
        when(refreshTokenRepository.findByTokenHash(independentSha256Hex(raw)))
                .thenReturn(Optional.of(live));
        when(refreshTokenRepository.revokeIfLive(live.getId(), NOW)).thenReturn(1);
        when(userRepository.findById(USER_ID)).thenReturn(Optional.of(user("ROLE_ADMIN")));
        when(jwtProvider.createAccessToken(USER_ID, "ROLE_ADMIN")).thenReturn("admin-access-token");

        assertThat(refreshTokenService.rotate(raw).accessToken()).isEqualTo("admin-access-token");
        verify(jwtProvider).createAccessToken(USER_ID, "ROLE_ADMIN");
    }

    // ─────────────────────── 재사용 감지 (완료 조건 4) ───────────────────────

    @Test
    @DisplayName("이미 폐기된 refresh 토큰이 다시 오면 그 사용자의 refresh 토큰을 전량 폐기하고 401 로 이어지는 예외를 던진다")
    void rotate_reusedToken_revokesEverySessionOfThatUser() {
        // 폐기된 RT 가 다시 왔다 = 두 주체가 같은 RT 를 갖고 있었다. 어느 쪽이 정당한지 서버는
        // 가릴 수 없으므로 닫는 쪽으로 실패한다. 체인 단위로만 끊으면 탈취자가 먼저 회전한 경우
        // 탈취자의 새 RT 가 살아남는다 — 막으려던 것을 정확히 못 막는다.
        String raw = "leaked-refresh-token";
        RefreshToken revoked = live(raw);
        revoked.setRevokedAt(NOW.minusMinutes(5));
        when(refreshTokenRepository.findByTokenHash(independentSha256Hex(raw)))
                .thenReturn(Optional.of(revoked));
        // 조건부 UPDATE 가 0 을 돌려주는 것이 곧 '이미 폐기됨' 이다.
        when(refreshTokenRepository.revokeIfLive(revoked.getId(), NOW)).thenReturn(0);

        assertThatThrownBy(() -> refreshTokenService.rotate(raw))
                .isInstanceOf(UnauthenticatedException.class);

        verify(refreshTokenRepository).revokeAllByUserId(USER_ID, NOW);
        verify(refreshTokenRepository, never()).save(any(RefreshToken.class));
    }

    // ─────────────────────── 만료·미존재 (완료 조건 5) ───────────────────────

    @Test
    @DisplayName("만료된 refresh 토큰은 401 로 이어지는 예외이되 전량 폐기를 유발하지 않는다")
    void rotate_expiredToken_doesNotRevokeEverything() {
        // 만료는 유출의 증거가 아니라 시간의 경과다. 이걸 유출로 오해하면 아무 일도 없었는데
        // 시계만 지나도 그 사용자의 모든 기기가 끊긴다.
        String raw = "expired-refresh-token";
        RefreshToken expired = live(raw);
        expired.setExpiresAt(NOW.minusSeconds(1));
        when(refreshTokenRepository.findByTokenHash(independentSha256Hex(raw)))
                .thenReturn(Optional.of(expired));

        assertThatThrownBy(() -> refreshTokenService.rotate(raw))
                .isInstanceOf(UnauthenticatedException.class);

        verify(refreshTokenRepository, never()).revokeAllByUserId(anyLong(), any());
        verify(refreshTokenRepository, never()).revokeIfLive(anyLong(), any());
    }

    @Test
    @DisplayName("만료 시각이 정확히 현재와 같은 refresh 토큰도 만료로 본다 — 경계는 닫는 쪽이다")
    void rotate_tokenExpiringExactlyNow_isRejected() {
        String raw = "boundary-refresh-token";
        RefreshToken boundary = live(raw);
        boundary.setExpiresAt(NOW);
        when(refreshTokenRepository.findByTokenHash(independentSha256Hex(raw)))
                .thenReturn(Optional.of(boundary));

        assertThatThrownBy(() -> refreshTokenService.rotate(raw))
                .isInstanceOf(UnauthenticatedException.class);
    }

    @Test
    @DisplayName("만료된 데다 폐기까지 된 refresh 토큰도 전량 폐기를 유발하지 않는다 — 만료를 먼저 검사한다")
    void rotate_expiredAndRevokedToken_doesNotTriggerReuseDetection() {
        // 검사 순서(①없음 ②만료 ③재사용)가 계약인 이유가 이것이다. 순서를 바꾸면 그냥 오래
        // 방치된 토큰 하나가 살아 있는 다른 기기들을 전부 끊는다.
        String raw = "old-and-revoked-token";
        RefreshToken token = live(raw);
        token.setExpiresAt(NOW.minusDays(1));
        token.setRevokedAt(NOW.minusDays(2));
        when(refreshTokenRepository.findByTokenHash(independentSha256Hex(raw)))
                .thenReturn(Optional.of(token));

        assertThatThrownBy(() -> refreshTokenService.rotate(raw))
                .isInstanceOf(UnauthenticatedException.class);

        verify(refreshTokenRepository, never()).revokeAllByUserId(anyLong(), any());
    }

    @Test
    @DisplayName("존재하지 않는 refresh 토큰도 401 로 이어지는 예외이되 전량 폐기를 유발하지 않는다")
    void rotate_unknownToken_isRejectedWithoutRevokingAnything() {
        when(refreshTokenRepository.findByTokenHash(independentSha256Hex("ghost")))
                .thenReturn(Optional.empty());

        assertThatThrownBy(() -> refreshTokenService.rotate("ghost"))
                .isInstanceOf(UnauthenticatedException.class);

        verify(refreshTokenRepository, never()).revokeAllByUserId(anyLong(), any());
    }

    @Test
    @DisplayName("refreshToken 이 null 이거나 공백이면 400 이 아니라 401 로 이어지는 예외이고 DB 조회조차 하지 않는다")
    void rotate_blankToken_isRejectedBeforeTouchingTheDatabase() {
        // 여기서 IllegalArgumentException 을 던지면 GlobalExceptionHandler 가 400 으로 바꾸고,
        // 계약이 선언한 '본문 없는 401' 이 거짓이 된다.
        assertThatThrownBy(() -> refreshTokenService.rotate(null))
                .isInstanceOf(UnauthenticatedException.class);
        assertThatThrownBy(() -> refreshTokenService.rotate("   "))
                .isInstanceOf(UnauthenticatedException.class);

        verify(refreshTokenRepository, never()).findByTokenHash(any());
    }

    @Test
    @DisplayName("회전 도중 그 users.id 의 사용자가 사라졌으면 500 이 아니라 401 로 이어지는 예외다")
    void rotate_missingUser_isRejected() {
        String raw = "orphan-refresh-token";
        RefreshToken live = live(raw);
        when(refreshTokenRepository.findByTokenHash(independentSha256Hex(raw)))
                .thenReturn(Optional.of(live));
        when(refreshTokenRepository.revokeIfLive(live.getId(), NOW)).thenReturn(1);
        when(userRepository.findById(USER_ID)).thenReturn(Optional.empty());

        assertThatThrownBy(() -> refreshTokenService.rotate(raw))
                .isInstanceOf(UnauthenticatedException.class);
    }

    // ─────────────────────── 폐기·정리 ───────────────────────

    @Test
    @DisplayName("전 기기 로그아웃은 고정 시계의 현재 시각으로 그 사용자의 살아 있는 토큰을 폐기한다")
    void revokeAllByUserId_stampsNow() {
        when(refreshTokenRepository.revokeAllByUserId(USER_ID, NOW)).thenReturn(3);

        assertThat(refreshTokenService.revokeAllByUserId(USER_ID)).isEqualTo(3);
        verify(refreshTokenRepository).revokeAllByUserId(USER_ID, NOW);
    }

    @Test
    @DisplayName("탈퇴 정리는 폐기가 아니라 삭제다")
    void deleteAllByUserId_deletesRows() {
        when(refreshTokenRepository.deleteByUserId(USER_ID)).thenReturn(2);

        assertThat(refreshTokenService.deleteAllByUserId(USER_ID)).isEqualTo(2);
        verify(refreshTokenRepository).deleteByUserId(USER_ID);
        verify(refreshTokenRepository, never()).revokeAllByUserId(anyLong(), any());
    }

    @Test
    @DisplayName("만료 정리는 기준 시각을 고정 시계의 현재로 잡아 그보다 이른 행만 지운다")
    void purgeExpired_usesNowAsCutoff() {
        // 부등호를 뒤집거나 기준을 미래로 잡으면 살아 있는 토큰을 지운다 — 전 사용자 강제 로그아웃이다.
        when(refreshTokenRepository.deleteByExpiresAtBefore(NOW)).thenReturn(5);

        assertThat(refreshTokenService.purgeExpired()).isEqualTo(5);
        verify(refreshTokenRepository).deleteByExpiresAtBefore(eq(NOW));
    }

    // ─────────────────────── 지그 ───────────────────────

    private RefreshToken live(String raw) {
        return RefreshToken.builder()
                .id(100L)
                .userId(USER_ID)
                .tokenHash(independentSha256Hex(raw))
                .expiresAt(NOW.plusDays(7))
                .createdAt(NOW.minusDays(7))
                .build();
    }

    private static User user(String role) {
        return User.builder().id(USER_ID).email("bori@example.com").role(role).build();
    }

    private RefreshToken captureSaved() {
        ArgumentCaptor<RefreshToken> captor = ArgumentCaptor.forClass(RefreshToken.class);
        verify(refreshTokenRepository, org.mockito.Mockito.atLeastOnce()).save(captor.capture());
        return captor.getValue();
    }

    /** 프로덕션 해싱 함수를 부르지 않고 테스트가 직접 계산한다 — 순환 검증을 피한다. */
    private static String independentSha256Hex(String raw) {
        try {
            return HexFormat.of().formatHex(MessageDigest.getInstance("SHA-256")
                    .digest(raw.getBytes(StandardCharsets.UTF_8)));
        } catch (Exception e) {
            throw new IllegalStateException(e);
        }
    }
}
