package com.heattrip.heat_trip_backend.walk.service;

import com.heattrip.heat_trip_backend.walk.entity.Walk;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import java.time.LocalDateTime;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * 목록 커서 — 이슈 #145.
 *
 * <p>여기서 지키는 것은 <b>정밀도</b> 하나다. 처음에는 {@code toEpochMilli()} 로 접었는데,
 * 컬럼이 {@code datetime(6)} 이라 실제 값에는 마이크로초가 있다. 잘린 커서로 다음 장을
 * 물으면 그 사이에 있는 행이 {@code < cursorAt} 도 {@code = cursorAt} 도 아니게 되어
 * <b>영원히 건너뛰어진다.</b>
 */
class WalkCursorTest {

    @Test
    @DisplayName("마이크로초가 왕복해도 살아 있다 — 잘리면 장 경계에서 행이 사라진다")
    void survivesMicrosecondPrecision() {
        LocalDateTime withMicros = LocalDateTime.of(2026, 9, 1, 12, 0, 0, 123_456_000);
        Walk walk = Walk.builder().createdAt(withMicros).build();
        setId(walk, 42L);

        WalkCursor parsed = WalkCursor.parse(WalkCursor.of(walk)).orElseThrow();

        assertThat(parsed.createdAt())
                .as("toEpochMilli() 로 접으면 .123000 이 되고 .123456 사이의 행이 건너뛰어진다")
                .isEqualTo(withMicros);
        assertThat(parsed.id()).isEqualTo(42L);
    }

    @Test
    @DisplayName("읽을 수 없는 커서는 비어 있다 — 부르는 쪽이 첫 장을 준다")
    void unreadableCursorsAreEmpty() {
        assertThat(WalkCursor.parse(null)).isEmpty();
        assertThat(WalkCursor.parse("")).isEmpty();
        assertThat(WalkCursor.parse("   ")).isEmpty();
        assertThat(WalkCursor.parse("!!!not-base64!!!")).isEmpty();
        assertThat(WalkCursor.parse(java.util.Base64.getUrlEncoder().withoutPadding()
                .encodeToString("없는:모양".getBytes()))).isEmpty();
        assertThat(WalkCursor.parse(java.util.Base64.getUrlEncoder().withoutPadding()
                .encodeToString("1:2".getBytes())))
                .as("세 조각이 아니면 우리 커서가 아니다")
                .isEmpty();
    }

    /** {@code id} 는 Lombok 빌더에 없다(DB 가 채운다). 테스트에서만 리플렉션으로 꽂는다. */
    private static void setId(Walk walk, long id) {
        try {
            var field = Walk.class.getDeclaredField("id");
            field.setAccessible(true);
            field.set(walk, id);
        } catch (ReflectiveOperationException e) {
            throw new IllegalStateException(e);
        }
    }
}
