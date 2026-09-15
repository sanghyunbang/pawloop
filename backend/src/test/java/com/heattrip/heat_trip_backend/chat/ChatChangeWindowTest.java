package com.heattrip.heat_trip_backend.chat;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * 변경 피드가 훑는 창 — ADR-0023(#500) 결정 5. 스프링도 도커도 안 쓴다(#21).
 *
 * <p>창이 없으면 방을 오래 열어 둔 사람에게 1년 치 변경이 한 번에 간다. 반대로 창이 너무 좁으면 화면에
 * 들고 있는 말의 변화를 놓친다 — 그래서 <b>앱이 한 화면에 들고 있을 만한 범위</b>가 기준이다.
 */
class ChatChangeWindowTest {

    @Test
    @DisplayName("방이 창보다 짧으면 바닥은 0 이다 — 음수로 내려가지 않는다")
    void shortRoomsStartAtZero() {
        assertThat(ChatRoomService.changedWindowFloor(0)).isZero();
        assertThat(ChatRoomService.changedWindowFloor(1)).isZero();
        assertThat(ChatRoomService.changedWindowFloor(ChatRoomService.CHANGED_WINDOW)).isZero();
    }

    @Test
    @DisplayName("긴 방은 마지막 번호에서 창만큼 뒤가 바닥이다")
    void longRoomsLookBackOneWindow() {
        assertThat(ChatRoomService.changedWindowFloor(ChatRoomService.CHANGED_WINDOW + 50)).isEqualTo(50);
        assertThat(ChatRoomService.changedWindowFloor(10_000))
                .isEqualTo(10_000 - ChatRoomService.CHANGED_WINDOW);
    }

    @Test
    @DisplayName("창은 한 장(50)보다 넉넉하다 — 화면에 들고 있는 말이 창 밖으로 나가면 안 된다")
    void theWindowIsWiderThanAPage() {
        assertThat(ChatRoomService.CHANGED_WINDOW).isGreaterThanOrEqualTo(200);
    }
}
