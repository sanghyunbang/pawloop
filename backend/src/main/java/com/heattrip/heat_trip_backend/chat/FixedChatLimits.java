package com.heattrip.heat_trip_backend.chat;

import org.springframework.stereotype.Component;

import java.time.Duration;

/**
 * 지금의 유일한 {@link ChatLimits} 구현체. <b>인자를 무시하고 상수를 돌려준다.</b>
 *
 * <p>플랜이 하나뿐이라 사용자를 볼 것이 없다. 그래도 인자를 받는 이유는 {@link ChatLimits}
 * javadoc 에 있다 — 나중에 이 파일 하나만 DB 를 읽게 바꾸면 호출부는 그대로다.
 *
 * <p><b>이 파일이 세 값의 유일한 자리다.</b> chat 패키지의 다른 어디에도 같은 숫자를
 * 적지 않는다. {@code ChatLimitsTest} 가 그것을 검사하고, 그 테스트는 이 파일에 실제로
 * 숫자가 있는지도 함께 본다(장치가 스스로 살아 있는지 확인하려고).
 *
 * <h3>값의 근거</h3>
 * <ul>
 *   <li><b>정원 50명</b> — 카카오 단체방 3,000 · 라인 500 · 왓츠앱 1,024 는 우리 용도와
 *       무관하다(카카오 관계자도 정원 선정에 "특별한 이유는 없다" 고 했다). 이미
 *       만들어진 화면이 '우리 가족' 3명, '서울숲 산책 크루' 6명이다.</li>
 *   <li><b>유효기간 7일</b> — 디스코드 클라이언트 기본이 7일이다. 슬랙은 30일이지만
 *       가족 초대는 한 번 보내고 곧 쓰므로 짧은 쪽을 택했다.</li>
 *   <li><b>사용 횟수 무제한</b> — 디스코드 API 의 {@code max_uses} 기본값도 0(무제한)이다.
 *       회수·재발급이 있으므로 유출 대응 수단은 따로 있다.</li>
 * </ul>
 *
 * <p><b>상태가 없다.</b> 인스턴스가 몇 대든 같은 값을 돌려주므로 📌 #86 §2 의 표에
 * 줄을 추가하지 않는다.
 */
@Component
public class FixedChatLimits implements ChatLimits {

    private static final int MAX_MEMBERS_PER_ROOM = 50;
    private static final Duration INVITE_TTL = Duration.ofDays(7);

    /** {@code null} = 무제한. 상수로 이름을 붙여 두면 "0 이 무제한인가" 를 매번 안 물어도 된다. */
    private static final Integer MAX_INVITE_USES_UNLIMITED = null;

    @Override
    public int maxMembersPerRoom(long userId) {
        return MAX_MEMBERS_PER_ROOM;
    }

    @Override
    public Duration inviteTtl(long userId) {
        return INVITE_TTL;
    }

    @Override
    public Integer maxInviteUses(long userId) {
        return MAX_INVITE_USES_UNLIMITED;
    }
}
