package com.heattrip.heat_trip_backend.user.repository;

import com.heattrip.heat_trip_backend.support.AbstractMySqlIntegrationTest;
import com.heattrip.heat_trip_backend.user.entity.RefreshToken;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.jdbc.AutoConfigureTestDatabase;
import org.springframework.boot.test.autoconfigure.orm.jpa.DataJpaTest;
import org.springframework.dao.DataIntegrityViolationException;

import java.time.LocalDateTime;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * refresh_token 테이블의 <b>제약과 원자성</b>을 실제 MySQL 8 로 확인한다 — 이슈 #9.
 *
 * <p>여기서만 확인되는 것들이다. {@code UNIQUE(token_hash)} 도, 조건부 UPDATE 의
 * "처음 1 · 두 번째 0" 도 자바 코드가 아니라 DB 의 성질이다. 목으로는 정의상 잡히지 않는다.
 *
 * <p>{@code replace = NONE} 인 이유: 이 저장소에서 스프링 컨텍스트를 띄우는 테스트는 전부
 * 실제 MySQL 8 컨테이너 위에서 돈다({@link AbstractMySqlIntegrationTest}). H2 는 #49 에서
 * 걷혔다 — 이슈 본문의 "H2 가 자동 대체된다"는 서술은 그보다 앞선 시점의 것이다.
 * {@code replace = NONE} 이 없으면 {@code @DataJpaTest} 가 임베디드 DB 로 갈아치운다.
 */
@DataJpaTest
@AutoConfigureTestDatabase(replace = AutoConfigureTestDatabase.Replace.NONE)
class RefreshTokenRepositoryTest extends AbstractMySqlIntegrationTest {

    private static final long USER = 7L;
    private static final long OTHER_USER = 8L;

    @Autowired
    private RefreshTokenRepository refreshTokenRepository;

    // ─────────────────────── UNIQUE(token_hash) ───────────────────────

    @Test
    @DisplayName("같은 token_hash 로 두 번 저장하면 DB 가 거부한다")
    void duplicateTokenHash_isRejectedByDatabase() {
        refreshTokenRepository.saveAndFlush(live(USER, "a".repeat(64)));

        assertThatThrownBy(() -> refreshTokenRepository.saveAndFlush(live(OTHER_USER, "a".repeat(64))))
                .as("'해시 1개 = 행 1개' 가 무너지면 findByTokenHash 가 어느 행을 줄지 미정이 되고 "
                        + "재사용 감지의 전제가 사라진다")
                .isInstanceOf(DataIntegrityViolationException.class);
    }

    @Test
    @DisplayName("findByTokenHash 는 그 해시의 행을 찾고, 없는 해시는 empty 다")
    void findByTokenHash_findsTheRow() {
        RefreshToken saved = refreshTokenRepository.saveAndFlush(live(USER, "b".repeat(64)));

        Optional<RefreshToken> found = refreshTokenRepository.findByTokenHash("b".repeat(64));

        assertThat(found).isPresent();
        assertThat(found.get().getId()).isEqualTo(saved.getId());
        assertThat(found.get().getUserId()).isEqualTo(USER);
        assertThat(refreshTokenRepository.findByTokenHash("c".repeat(64))).isEmpty();
    }

    // ─────────────────────── 조건부 UPDATE 의 원자성 ───────────────────────

    @Test
    @DisplayName("revokeIfLive 는 처음에 1을 돌려주고 같은 행에 두 번째 호출은 0을 돌려준다")
    void revokeIfLive_returnsOneThenZero() {
        RefreshToken saved = refreshTokenRepository.saveAndFlush(live(USER, "d".repeat(64)));
        LocalDateTime now = LocalDateTime.of(2026, 8, 30, 0, 0);

        assertThat(refreshTokenRepository.revokeIfLive(saved.getId(), now))
                .as("첫 회전은 폐기 권한을 얻는다")
                .isEqualTo(1);
        assertThat(refreshTokenRepository.revokeIfLive(saved.getId(), now.plusMinutes(1)))
                .as("이 계약이 깨지면 같은 RT 로 두 세션이 동시에 발급된다")
                .isEqualTo(0);

        RefreshToken reloaded = refreshTokenRepository.findById(saved.getId()).orElseThrow();
        assertThat(reloaded.getRevokedAt())
                .as("최초 폐기 시각이 사건 기록이다 — 두 번째 호출이 덮어쓰면 안 된다")
                .isEqualTo(now);
    }

    // ─────────────────────── 사용자 경계 ───────────────────────

    @Test
    @DisplayName("revokeAllByUserId 는 그 사용자의 살아 있는 행만 폐기하고 다른 사용자 행은 건드리지 않는다")
    void revokeAllByUserId_touchesOnlyThatUser() {
        RefreshToken mine1 = refreshTokenRepository.saveAndFlush(live(USER, "e".repeat(64)));
        RefreshToken mine2 = refreshTokenRepository.saveAndFlush(live(USER, "f".repeat(64)));
        RefreshToken theirs = refreshTokenRepository.saveAndFlush(live(OTHER_USER, "0".repeat(64)));
        LocalDateTime now = LocalDateTime.of(2026, 8, 30, 1, 0);

        assertThat(refreshTokenRepository.revokeAllByUserId(USER, now)).isEqualTo(2);

        assertThat(refreshTokenRepository.findById(mine1.getId()).orElseThrow().getRevokedAt()).isEqualTo(now);
        assertThat(refreshTokenRepository.findById(mine2.getId()).orElseThrow().getRevokedAt()).isEqualTo(now);
        assertThat(refreshTokenRepository.findById(theirs.getId()).orElseThrow().getRevokedAt())
                .as("한 사람의 재사용 감지가 다른 사람의 세션을 끊으면 안 된다")
                .isNull();
    }

    @Test
    @DisplayName("deleteByUserId 는 그 사용자의 행만 지운다 — 폐기된 행까지 함께")
    void deleteByUserId_removesOnlyThatUsersRows() {
        refreshTokenRepository.saveAndFlush(live(USER, "1".repeat(64)));
        refreshTokenRepository.saveAndFlush(revoked(USER, "2".repeat(64)));
        RefreshToken theirs = refreshTokenRepository.saveAndFlush(live(OTHER_USER, "3".repeat(64)));

        assertThat(refreshTokenRepository.deleteByUserId(USER))
                .as("탈퇴 정리는 살아 있는 행만이 아니라 그 사용자의 모든 행이다 (완료 조건 7)")
                .isEqualTo(2);

        assertThat(refreshTokenRepository.findByTokenHash("1".repeat(64))).isEmpty();
        assertThat(refreshTokenRepository.findByTokenHash("2".repeat(64))).isEmpty();
        assertThat(refreshTokenRepository.findById(theirs.getId())).isPresent();
    }

    // ─────────────────────── 만료 정리 경계 ───────────────────────

    @Test
    @DisplayName("deleteByExpiresAtBefore 는 기준 시각보다 이른 행만 지우고 같은 시각의 행은 남긴다")
    void deleteByExpiresAtBefore_removesOnlyEarlierRows() {
        LocalDateTime cutoff = LocalDateTime.of(2026, 8, 30, 4, 30);
        refreshTokenRepository.saveAndFlush(expiringAt(USER, "4".repeat(64), cutoff.minusSeconds(1)));
        refreshTokenRepository.saveAndFlush(expiringAt(USER, "5".repeat(64), cutoff));
        refreshTokenRepository.saveAndFlush(expiringAt(USER, "6".repeat(64), cutoff.plusSeconds(1)));

        assertThat(refreshTokenRepository.deleteByExpiresAtBefore(cutoff)).isEqualTo(1);

        assertThat(refreshTokenRepository.findByTokenHash("4".repeat(64))).isEmpty();
        assertThat(refreshTokenRepository.findByTokenHash("5".repeat(64)))
                .as("만료 시각이 정확히 기준과 같은 행은 아직 살아 있다")
                .isPresent();
        assertThat(refreshTokenRepository.findByTokenHash("6".repeat(64))).isPresent();
    }

    // ─────────────────────── 지그 ───────────────────────

    private static RefreshToken live(long userId, String tokenHash) {
        return expiringAt(userId, tokenHash, LocalDateTime.now().plusDays(14));
    }

    private static RefreshToken revoked(long userId, String tokenHash) {
        RefreshToken token = live(userId, tokenHash);
        token.setRevokedAt(LocalDateTime.now());
        return token;
    }

    private static RefreshToken expiringAt(long userId, String tokenHash, LocalDateTime expiresAt) {
        return RefreshToken.builder()
                .userId(userId)
                .tokenHash(tokenHash)
                .expiresAt(expiresAt)
                .createdAt(LocalDateTime.now())
                .build();
    }
}
