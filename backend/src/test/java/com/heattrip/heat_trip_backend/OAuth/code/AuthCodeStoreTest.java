package com.heattrip.heat_trip_backend.OAuth.code;

import com.heattrip.heat_trip_backend.config.OAuthSecurityProperties;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.time.Clock;
import java.time.Duration;
import java.time.Instant;
import java.time.ZoneId;
import java.time.ZoneOffset;
import java.util.Optional;

import static org.assertj.core.api.Assertions.assertThat;
import static org.assertj.core.api.Assertions.assertThatThrownBy;

/**
 * 1회용 코드의 두 벽 — <b>재사용 차단</b>과 <b>만료</b>. (이슈 #14 완료 조건 2·3·10)
 *
 * <p>두 벽은 <b>서로 다른 테스트 메서드</b>다. 한 메서드에 몰아넣으면 구현에서 하나를 지워도
 * 같은 테스트 하나만 빨간불이라, "어느 쪽이 무너졌는지" 를 종료 코드로 알 수 없다.
 * 완료 조건 10 이 요구하는 것이 정확히 그 분리다.
 *
 * <p><b>{@code Thread.sleep} 을 쓰지 않는다.</b> 만료를 벽시계로 재면 61초짜리 테스트가 되고,
 * CI 에서 가장 먼저 버려지는 종류의 테스트가 된다. {@link Clock} 을 주입해
 * {@link Clock#offset(Clock, Duration)} 으로 시간을 민다.
 */
class AuthCodeStoreTest {

    private static final Instant BASE = Instant.parse("2026-08-30T12:00:00Z");

    /**
     * 시간을 밀 수 있는 시계. {@code Clock.fixed} 는 불변이라 발급과 소비 사이에 시간을
     * 옮길 수 없고, 저장소는 발급·소비에 <b>같은 인스턴스</b>를 써야 한다.
     */
    private static final class ShiftableClock extends Clock {
        private Clock delegate;

        ShiftableClock(Clock delegate) {
            this.delegate = delegate;
        }

        void shift(Duration amount) {
            this.delegate = Clock.offset(this.delegate, amount);
        }

        @Override public ZoneId getZone() { return delegate.getZone(); }
        @Override public Clock withZone(ZoneId zone) { return new ShiftableClock(delegate.withZone(zone)); }
        @Override public Instant instant() { return delegate.instant(); }
    }

    private static OAuthSecurityProperties props(long ttlSeconds) {
        OAuthSecurityProperties p = new OAuthSecurityProperties();
        p.setCodeTtlSeconds(ttlSeconds);
        return p;
    }

    private static String issue(AuthCodeStore store) {
        return store.issue(42L, "kakao", "state-abc", false);
    }

    // ─────────────────────── ① 재사용 차단 (완료 조건 2) ───────────────────────

    @Test
    @DisplayName("같은 코드로 두 번 교환하면 두 번째는 실패한다")
    void 같은코드로_두번교환하면_두번째는_실패한다() {
        // consume 의 `codes.remove` 를 `codes.get` 으로 바꾸면 이 테스트만 빨간불이다.
        // 만료 검사를 지워도 이 테스트는 초록 그대로다 (완료 조건 10).
        AuthCodeStore store = new AuthCodeStore(new ShiftableClock(Clock.fixed(BASE, ZoneOffset.UTC)), props(60));
        String code = issue(store);

        Optional<AuthCode> first = store.consume(code);
        Optional<AuthCode> second = store.consume(code);

        assertThat(first).as("첫 교환은 성공해야 한다 — 아니면 이 테스트는 아무것도 증명하지 못한다").isPresent();
        assertThat(second)
                .as("가로챈 코드가 두 번 통하면 1회용이라는 말이 거짓이 된다")
                .isEmpty();
    }

    @Test
    @DisplayName("소비된 코드는 저장소에서 사라진다 — '쓴 표시' 를 남긴 채 붙들고 있지 않는다")
    void 소비된코드는_저장소에서_사라진다() {
        AuthCodeStore store = new AuthCodeStore(new ShiftableClock(Clock.fixed(BASE, ZoneOffset.UTC)), props(60));
        String code = issue(store);
        assertThat(store.size()).isEqualTo(1);

        store.consume(code);

        assertThat(store.size()).isZero();
    }

    // ─────────────────────── ② 만료 (완료 조건 3) ───────────────────────

    @Test
    @DisplayName("발급 후 61초가 지나면 교환이 실패한다")
    void 발급후_61초가_지나면_교환이_실패한다() {
        // Thread.sleep 금지 — Clock.offset 으로 시간을 민다.
        // consume 의 만료 검사를 지우면 이 테스트만 빨간불이다.
        ShiftableClock clock = new ShiftableClock(Clock.fixed(BASE, ZoneOffset.UTC));
        AuthCodeStore store = new AuthCodeStore(clock, props(60));
        String code = issue(store);

        clock.shift(Duration.ofSeconds(61));

        assertThat(store.consume(code))
                .as("60초를 넘긴 코드는 없는 것과 같다")
                .isEmpty();
    }

    @Test
    @DisplayName("발급 후 59초까지는 교환이 성립한다 — 만료가 너무 이르면 정상 로그인이 죽는다")
    void 발급후_59초까지는_교환이_성립한다() {
        // 이 테스트가 없으면 "항상 만료" 라는 구현도 위 테스트를 통과한다.
        ShiftableClock clock = new ShiftableClock(Clock.fixed(BASE, ZoneOffset.UTC));
        AuthCodeStore store = new AuthCodeStore(clock, props(60));
        String code = issue(store);

        clock.shift(Duration.ofSeconds(59));

        assertThat(store.consume(code)).isPresent();
    }

    @Test
    @DisplayName("만료 경계는 정확히 TTL 이다 — 60초 정각은 이미 만료다")
    void 만료경계는_정확히_TTL이다() {
        ShiftableClock clock = new ShiftableClock(Clock.fixed(BASE, ZoneOffset.UTC));
        AuthCodeStore store = new AuthCodeStore(clock, props(60));
        String code = issue(store);

        clock.shift(Duration.ofSeconds(60));

        assertThat(store.consume(code))
                .as("경계를 열어 두면 '60초 이내' 라는 계약이 '60초 이하' 로 슬며시 바뀐다")
                .isEmpty();
    }

    @Test
    @DisplayName("설정한 TTL 이 실제로 쓰인다 — 값을 바꾸면 만료 시점이 따라 움직인다")
    void 설정한_TTL이_실제로_쓰인다() {
        // TTL 을 상수로 박아 두면 이 테스트가 잡는다.
        ShiftableClock clock = new ShiftableClock(Clock.fixed(BASE, ZoneOffset.UTC));
        AuthCodeStore store = new AuthCodeStore(clock, props(10));
        String code = issue(store);

        clock.shift(Duration.ofSeconds(11));

        assertThat(store.consume(code)).isEmpty();
    }

    // ─────────────────────── ③ 그 밖 ───────────────────────

    @Test
    @DisplayName("코드에 실린 사실이 그대로 돌아온다 — 토큰 재료는 URL 이 아니라 여기 있다")
    void 코드에_실린_사실이_그대로_돌아온다() {
        AuthCodeStore store = new AuthCodeStore(new ShiftableClock(Clock.fixed(BASE, ZoneOffset.UTC)), props(60));
        String code = store.issue(7L, "google", "state-xyz", true);

        AuthCode consumed = store.consume(code).orElseThrow();

        assertThat(consumed.userId()).isEqualTo(7L);
        // role 은 여기 없다. 예전에는 실려 있었지만 프로덕션이 읽지 않았고
        // (교환 시점에 users 행에서 다시 읽는다), 그 단언만 "코드를 타고 전달된다" 는
        // 인상을 주고 있었다. 값이 틀려도 아무 일이 없는 필드는 초록불을 거짓말시킨다.
        assertThat(consumed.provider()).isEqualTo("google");
        assertThat(consumed.state()).isEqualTo("state-xyz");
        assertThat(consumed.isNew()).isTrue();
    }

    @Test
    @DisplayName("발급된 코드는 URL 인코딩이 필요 없는 문자만 쓴다")
    void 발급된코드는_URL안전문자만_쓴다() {
        // 딥링크 쿼리에 그대로 실린다. `+`·`/`·`=` 가 섞이면 앱쪽 파서마다 다르게 다뤄진다.
        AuthCodeStore store = new AuthCodeStore(new ShiftableClock(Clock.fixed(BASE, ZoneOffset.UTC)), props(60));

        assertThat(issue(store)).matches("[A-Za-z0-9_-]{43}");
    }

    @Test
    @DisplayName("두 번 발급하면 서로 다른 코드다")
    void 두번_발급하면_서로_다른코드다() {
        AuthCodeStore store = new AuthCodeStore(new ShiftableClock(Clock.fixed(BASE, ZoneOffset.UTC)), props(60));

        assertThat(issue(store)).isNotEqualTo(issue(store));
    }

    @Test
    @DisplayName("없는 코드·빈 코드는 조용히 빈 값이다 — 예외로 존재 여부를 알려 주지 않는다")
    void 없는코드는_조용히_빈값이다() {
        AuthCodeStore store = new AuthCodeStore(new ShiftableClock(Clock.fixed(BASE, ZoneOffset.UTC)), props(60));

        assertThat(store.consume("does-not-exist")).isEmpty();
        assertThat(store.consume("")).isEmpty();
        assertThat(store.consume(null)).isEmpty();
    }

    @Test
    @DisplayName("만료된 코드는 다음 발급 때 치워진다 — 맵이 무한정 자라지 않는다")
    void 만료된코드는_다음발급때_치워진다() {
        ShiftableClock clock = new ShiftableClock(Clock.fixed(BASE, ZoneOffset.UTC));
        AuthCodeStore store = new AuthCodeStore(clock, props(60));
        issue(store);
        issue(store);
        assertThat(store.size()).isEqualTo(2);

        clock.shift(Duration.ofSeconds(61));
        issue(store);

        assertThat(store.size())
                .as("죽은 코드 2개는 치워지고 방금 발급한 1개만 남는다")
                .isEqualTo(1);
    }

    @Test
    @DisplayName("users.id 없이 발급하려 하면 거부한다 — sub=null 토큰의 재료를 만들지 않는다")
    void userId없이_발급하지_않는다() {
        AuthCodeStore store = new AuthCodeStore(new ShiftableClock(Clock.fixed(BASE, ZoneOffset.UTC)), props(60));

        assertThatThrownBy(() -> store.issue(null, "kakao", "s", false))
                .isInstanceOf(IllegalArgumentException.class);
    }

    @Test
    @DisplayName("TTL 설정이 0 이하면 발급 자체를 거부한다 — 조용히 '항상 만료' 가 되지 않게")
    void TTL이_0이하면_발급을_거부한다() {
        AuthCodeStore store = new AuthCodeStore(new ShiftableClock(Clock.fixed(BASE, ZoneOffset.UTC)), props(0));

        assertThatThrownBy(() -> issue(store))
                .isInstanceOf(IllegalStateException.class)
                .hasMessageContaining("code-ttl-seconds");
    }
}
