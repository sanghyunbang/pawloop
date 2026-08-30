package com.heattrip.heat_trip_backend.observability.logging;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * {@link SensitiveDataMasker} 의 첫 테스트 — 이슈 #75.
 *
 * <h2>왜 지금 생기나</h2>
 * <p>이 클래스에는 테스트가 <b>0건</b>이었다. 그동안 무엇이 가려지고 무엇이 안 가려지는지는
 * 정규식을 읽는 사람의 기억에만 있었고, 그래서 <b>초대코드가 경로에 실려 로그로 나간다</b>는
 * 사실도 아무 신호를 내지 않았다. 프로브 실행 중 실제로 찍힌 줄:
 * <pre>
 *   [REQ] POST /api/chat/invites/Y9VAQ-VV852/join failed in 43ms: ...
 *   [ALERT] slack send skipped/failed for POST /api/chat/invites/Y9VAQ-VV852/join
 * </pre>
 *
 * <p><b>오탐도 함께 본다.</b> 경로를 통째로 가리면 조사할 때 어느 방·어느 오퍼레이션인지가
 * 사라진다. 그러면 이 게이트는 시끄러운 게이트가 되고, 시끄러운 게이트는 지워진다.
 *
 * <p>스프링 컨텍스트를 띄우지 않는다(#21).
 */
class SensitiveDataMaskerTest {

    private final SensitiveDataMasker masker = new SensitiveDataMasker();

    @Test
    @DisplayName("참여 경로의 초대코드가 가려진다 — 로그·알림에 남는 유일한 열쇠였다")
    void theInviteCodeInTheJoinPathIsMasked() {
        String logLine = "[REQ] POST /api/chat/invites/Y9VAQ-VV852/join failed in 43ms";

        assertThat(SensitiveDataMasker.maskUri(logLine))
                .as("""
                        초대코드는 인증 없이 방에 들어오는 열쇠다(InviteCodeGenerator javadoc). \
                        로그·알림 채널에 접근할 수 있는 사람이 계정 하나만 있으면 남의 가족방에 \
                        들어갈 수 있다. maskUri 를 지우면 여기가 빨간불이다.""")
                .isEqualTo("[REQ] POST /api/chat/invites/***/join failed in 43ms")
                .doesNotContain("Y9VAQ-VV852");
    }

    @Test
    @DisplayName("회수 경로의 초대코드도 가려진다 — 방 id 는 남는다")
    void theInviteCodeInTheRevokePathIsMaskedButTheRoomIdSurvives() {
        String masked = SensitiveDataMasker.maskUri(
                "uri=/api/chat/rooms/42/invites/KH24R-JZBXC");

        assertThat(masked).doesNotContain("KH24R-JZBXC");
        assertThat(masked)
                .as("방 id 까지 지우면 어느 방의 일인지 알 수 없어 조사가 불가능해진다")
                .isEqualTo("uri=/api/chat/rooms/42/invites/***");
    }

    @Test
    @DisplayName("코드를 싣지 않는 경로는 건드리지 않는다 — 시끄러운 게이트는 지워진다")
    void pathsThatCarryNoSecretAreLeftAlone() {
        // 발급은 코드를 받지 않고 만든다. 이 경로까지 가리면 "어느 방에 발급했나" 가 사라진다.
        assertThat(SensitiveDataMasker.maskUri("POST /api/chat/rooms/42/invites"))
                .isEqualTo("POST /api/chat/rooms/42/invites");
        assertThat(SensitiveDataMasker.maskUri("POST /api/groups"))
                .isEqualTo("POST /api/groups");
        assertThat(SensitiveDataMasker.maskUri("GET /api/groups/me"))
                .isEqualTo("GET /api/groups/me");
        assertThat(SensitiveDataMasker.maskUri("GET /api/explore/places/search?q=서울숲"))
                .isEqualTo("GET /api/explore/places/search?q=서울숲");
    }

    @Test
    @DisplayName("mask(...) 도 같은 규칙을 지나간다 — 스택트레이스에 섞인 경로가 새지 않는다")
    void theInstanceMaskAppliesTheSameUriRule() {
        assertThat(masker.mask("JDBC ... /api/chat/invites/Y9VAQ-VV852/join ..."))
                .doesNotContain("Y9VAQ-VV852");
    }

    @Test
    @DisplayName("예전 규칙 둘은 그대로다 — Bearer 토큰과 secret= 형태")
    void theExistingRulesStillApply() {
        assertThat(masker.mask("Authorization: Bearer eyJhbGciOi.JIUzI1NiJ9.abc"))
                .isEqualTo("Authorization: Bearer ***");
        assertThat(masker.mask("client_secret=abcdef"))
                .isEqualTo("client_secret=***");
    }

    @Test
    @DisplayName("null·빈 문자열에 부르는 것이 안전하다 — 마스킹이 로그 경로를 죽이면 안 된다")
    void nullAndBlankAreSafe() {
        assertThat(SensitiveDataMasker.maskUri(null)).isNull();
        assertThat(SensitiveDataMasker.maskUri("")).isEmpty();
        assertThat(masker.mask(null)).isNull();
    }
}
