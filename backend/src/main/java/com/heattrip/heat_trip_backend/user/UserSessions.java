package com.heattrip.heat_trip_backend.user;

/**
 * 이 사람의 로그인을 전부 끝낸다 — 이슈 #718(운영자 정지).
 *
 * <p>전 기기 로그아웃과 <b>같은 일</b>이다. 살아 있는 refresh 토큰을 전부 폐기하고 {@link UserSessionsRevoked} 를
 * 낸다 — 푸시가 그것을 듣고 기기 토큰을 폐기하므로 정지된 사람에게 알림이 가지 않는다.
 *
 * <p>이것만으로는 사람을 막지 못한다. 이미 나간 액세스 토큰은 만료 때까지 살아 있다. 정지된 사람을 실제로 막는 것은
 * 요청마다 정지를 보는 {@code security.AccountSuspensionFilter} 이고, 이것은 다음 토큰 연장을 끊는 일이다.
 */
public interface UserSessions {

    /** 이 사람의 refresh 토큰을 전부 폐기한다. 없으면 아무 일도 없다. */
    void endAll(long userId);
}
