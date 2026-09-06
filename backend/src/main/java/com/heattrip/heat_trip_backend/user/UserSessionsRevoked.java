package com.heattrip.heat_trip_backend.user;

/**
 * 이 사용자의 세션이 전부 끝났다 — 로그아웃(전 기기) 또는 탈퇴. {@code UserService} 가 그 트랜잭션 안에서
 * 발행한다.
 *
 * <p>{@code user} 는 누가 듣는지 모른다({@code allowedDependencies = {}}). 듣는 쪽은
 * {@code @TransactionalEventListener(AFTER_COMMIT)} 로 받는다 — 탈퇴가 롤백됐는데 부속 데이터만 지워지면
 * 안 된다. 지금 듣는 곳은 푸시(기기 토큰 폐기·삭제, #83)다.
 *
 * @param accountDeleted 탈퇴면 true — 듣는 쪽은 폐기가 아니라 삭제로 답한다(개인정보)
 */
public record UserSessionsRevoked(long userId, boolean accountDeleted) {
}
