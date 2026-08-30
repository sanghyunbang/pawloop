package com.heattrip.heat_trip_backend.chat;

/**
 * 초대코드 참여의 결과 — 이슈 #75 완료 조건 5.
 *
 * <p>{@code alreadyMember} 가 참이면 <b>아무것도 바뀌지 않았다</b>: 멤버십 행도, 초대코드의
 * {@code used_count} 도 그대로다. 응답은 성공(200)이다 — 사용자가 링크를 두 번 누른 것을
 * 실패로 돌려주면 앱이 보여줄 화면이 없다.
 *
 * <p>이 구분을 값으로 내보내는 이유는 <b>테스트가 그것을 단언할 수 있어야</b> 하기 때문이다.
 * 응답 상태만 보면 "새로 들어왔다" 와 "이미 있었다" 가 둘 다 200 이라 구별되지 않는다.
 */
public record ChatJoinResult(ChatRoomView room, boolean alreadyMember) {
}
