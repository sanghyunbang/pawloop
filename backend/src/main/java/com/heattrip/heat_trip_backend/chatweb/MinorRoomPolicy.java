package com.heattrip.heat_trip_backend.chatweb;

import com.heattrip.heat_trip_backend.user.entity.User;

import java.util.Set;

/**
 * 만 14세 미만이 들어갈 수 있는 방 — 이슈 #82 완료 조건 5.
 *
 * <h2>왜 여기에 있는가</h2>
 * <p>이 판정에는 두 가지가 필요하다 — <b>그 사람의 나이대</b>({@code users.age_group}) 와
 * <b>방의 종류</b>({@code chat_room.origin_kind}). 그런데
 * <ul>
 *   <li>{@code chat} 은 {@code users} 를 못 본다(ADR-0011 결정 4).</li>
 *   <li>{@code chat} 은 {@code origin_kind} 를 <b>해석하지 않는다</b> —
 *       {@code originKind.equals("FAMILY")} 로 갈라지는 코드가 거기 생기는 순간 그 결정이
 *       사라진다({@code FamilyGroupService.ORIGIN_KIND} javadoc).</li>
 * </ul>
 *
 * <p>둘 다 보는 자리가 {@code chatweb} 이다. 이 패키지는 원래 "사용자를 id 로 바꾸고
 * {@code ChatRoomService} 를 부르는" 일을 한다({@code package-info}) — 나이대를 문자열
 * 목록으로 바꾸는 것이 정확히 그 모양이다.
 *
 * <h2>{@code FamilyGroupService.ORIGIN_KIND} 를 직접 못 쓴다</h2>
 * <p>{@code chatweb} 의 {@code allowedDependencies} 는 {@code chat} 과 {@code user} 뿐이라
 * {@code group} 을 볼 수 없다. 그래서 문자열을 여기 한 번 더 적는다.
 *
 * <p><b>두 벌이 되는 것을 테스트가 막는다</b> — {@code MinorRoomPolicyTest} 가 이 상수와
 * {@code FamilyGroupService.ORIGIN_KIND} 가 같은지 본다(테스트는 모듈 경계 밖이라 둘 다 볼
 * 수 있다). 한쪽만 바뀌면 빨간불이다.
 *
 * <h2>신청 창구는 만들지 않는다</h2>
 * <p>이슈가 그렇게 정했다. "만 14세 미만은 가족 방에만 참여할 수 있습니다" 하나이고,
 * 예외를 받는 경로는 없다.
 *
 * <h2>가입 시 입력값을 믿는다</h2>
 * <p>만 14세 확인이 실제 나이와 일치하는지는 우리가 검증할 수 없다(#82 의 "테스트하기 어려운
 * 부분"). 여기가 보증하는 것은 <b>선언된 나이대에 대해 규칙이 동작한다</b>까지다.
 */
final class MinorRoomPolicy {

    /**
     * {@code FamilyGroupService.ORIGIN_KIND} 와 <b>같아야 하는</b> 값.
     * 다르면 {@code MinorRoomPolicyTest} 가 빨간불이다.
     */
    static final String FAMILY_ORIGIN_KIND = "FAMILY";

    private MinorRoomPolicy() {
    }

    /**
     * 이 사람이 들어갈 수 있는 방의 {@code origin_kind} 들.
     *
     * <p>{@code null} 은 <b>제한 없음</b>이다 — {@code ChatRoomService#joinByInviteCode} 가
     * 그렇게 읽는다.
     *
     * <p>판정은 {@link User#isUnder14()} 가 한다. {@code getAgeGroup() == UNDER14} 를 여기
     * 적지 않는 이유는 <b>{@code AgeGroup} 이 중첩 타입</b>이라 {@code User} 가 공개 표면이어도
     * 그 표면을 물려받지 않기 때문이다 — 밖에서 부르면 모듈 경계 위반이 하나 는다.
     * 처음에 그렇게 적었다가 {@code ModularityBaselineTest} 가 232 → 233 으로 잡았다.
     *
     * <p><b>나이대를 모르는 계정은 막지 않는다</b>({@code isUnder14} javadoc).
     */
    static Set<String> allowedOriginKindsFor(User user) {
        return user.isUnder14() ? Set.of(FAMILY_ORIGIN_KIND) : null;
    }
}
