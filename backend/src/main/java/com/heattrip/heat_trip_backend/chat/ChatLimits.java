package com.heattrip.heat_trip_backend.chat;

import java.time.Duration;

/**
 * 방·초대에 걸리는 한도의 <b>유일한 출처</b> — 이슈 #74, 근거 ADR-0011 결정 10.
 *
 * <h2>왜 상수 셋이 아니라 인터페이스인가</h2>
 * <p>지금 필요한 것은 정말 상수 셋뿐이다(50명 · 7일 · 무제한). 그런데 <b>시그니처가
 * 처음부터 사용자 기준</b>이라는 것이 요점이다 — 호출부가 플랜을 모른다. 나중에 유료
 * 플랜이 생기면 고치는 것은 구현체 하나이고 호출부는 한 줄도 안 바뀐다.
 *
 * <p>텔레그램이 {@code channels_limit_default}/{@code channels_limit_premium} 을 서버에서
 * 내려주는 것(한도가 코드가 아니라 데이터), 스트라이프 Entitlements 가 플랜 이름 대신
 * {@code lookup_key} 로 검사하라는 것이 같은 이유다.
 *
 * <p><b>지금 만들지 않는 것.</b> {@code users.plan} 컬럼 · 플랜 표 · 결제 SDK ·
 * 기능 플래그 시스템. 넷 다 없다. 플래그는 <b>지워야 할 것</b>이고 entitlement 는
 * <b>지우면 안 되는 것</b>인데, 둘 다 없는 상태에서 플래그부터 넣으면 같은 통에 섞인다.
 *
 * <h2>이 인터페이스를 우회하면 테스트가 빨간불이다</h2>
 * <p>정원·유효기간을 서비스 코드에 직접 적는 것을 {@code ChatLimitsTest} 가 막는다.
 * 무엇을 금지하는지는 그 테스트의 javadoc 에 정확히 적혀 있다.
 *
 * @see FixedChatLimits 지금의 유일한 구현체 — 인자를 무시하고 상수를 돌려준다
 */
public interface ChatLimits {

    /** 방 정원. 강퇴된 멤버는 정원을 차지하지 않는다. 넘으면 {@code ROOM_MEMBER_LIMIT}(409). */
    int maxMembersPerRoom(long userId);

    /** 새로 발급하는 초대코드의 유효기간. */
    Duration inviteTtl(long userId);

    /**
     * 초대코드 하나를 쓸 수 있는 횟수.
     *
     * @return {@code null} 이면 무제한. 넘으면 {@code INVITE_USES_EXHAUSTED}(409)
     */
    Integer maxInviteUses(long userId);
}
