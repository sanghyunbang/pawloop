package com.heattrip.heat_trip_backend.crew.service;

import com.heattrip.heat_trip_backend.schedule.entity.ScheduleOwnerKind;

import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;

import static org.assertj.core.api.Assertions.assertThat;

/**
 * 두 모듈이 <b>같은 문자열</b>로 크루 방을 가리키는가 — 이슈 #417.
 *
 * <h2>왜 이 검사가 따로 있어야 하는가</h2>
 * <p>{@code schedule} 은 크루 일정의 권한을 잴 때 "그 크루 방의 살아 있는 멤버인가" 를 묻고,
 * 그러려면 {@code chat_room.origin_kind} 를 알아야 한다. 그런데 그 상수를 {@code crew} 에서
 * 가져오면 <b>고리가 생긴다</b> — {@code crew} 는 품앗이를 맡을 때 일정 한 줄을 남기려고
 * {@code schedule} 을 부르기 때문이다({@code ModuleCycleTest} 가 잡는다).
 *
 * <p>그래서 문자열이 <b>두 곳</b>에 산다. 두 곳에 사는 값은 언젠가 한쪽만 바뀐다 — 그날
 * 크루 일정은 <b>조용히 404</b> 가 된다. 오류도 안 나고 로그도 안 남는다: 방을 못 찾으니
 * "없는 크루" 로 보이고, 그건 계약이 정한 정상 응답이다.
 *
 * <p>테스트는 두 모듈을 다 볼 수 있으므로 여기서 잰다. 이것이 그 값이 갈라지는 것을 잡는
 * 유일한 자리다.
 *
 * <p>스프링을 안 띄운다(#21).
 */
class CrewOriginKindMatchesScheduleTest {

    @Test
    @DisplayName("schedule 이 든 크루 출처 이름이 crew 가 방에 적는 이름과 같다")
    void theOriginKindIsTheSameOnBothSides() {
        assertThat(ScheduleOwnerKind.CREW_ORIGIN_KIND)
                .as("""
                        갈리면 크루 일정이 조용히 404 가 된다 — 오류도 로그도 안 남는다. \
                        한쪽을 고쳤으면 다른 쪽도 함께 고친다.""")
                .isEqualTo(CrewService.ORIGIN_KIND);
    }

    @Test
    @DisplayName("크루 일정의 주인 종류는 room 이다 — 계약이 그 글자로 나간다")
    void theOwnerKindWireIsRoom() {
        assertThat(ScheduleOwnerKind.ROOM.wire())
                .as("DB 의 ck_schedule_owner_kind 도 이 글자로 적혀 있다")
                .isEqualTo("room");
    }
}
