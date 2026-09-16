package com.heattrip.heat_trip_backend.group;

/**
 * 가족이 하나 생겼다 — 이슈 #560.
 *
 * <p>듣는 쪽은 {@code @TransactionalEventListener(AFTER_COMMIT)} 로 받는다. 커밋 전에 받으면
 * 롤백된 가족에 딸린 것들만 남는다 — {@code ChatMessagePosted}·{@code UserSessionsRevoked} 가
 * 같은 이유로 같은 규약을 쓴다.
 *
 * <p><b>AFTER_COMMIT 은 비동기가 아니다.</b> 같은 스레드에서 커밋 직후에 돌고, 그게 끝나야
 * {@code POST /api/groups} 가 응답한다. 그래서 가족을 막 만든 사람이 여는 첫 화면에 기본
 * 항목 일곱이 <b>이미 있다</b> — 비동기로 두면 그 순간 카드가 비어 보인다.
 *
 * <h2>왜 이벤트인가</h2>
 *
 * <p>{@code group} 이 {@code care} 를 직접 부르면 <b>거꾸로 된 의존</b>이 생긴다. 가족은
 * 케어를 몰라도 되는 것이고, 앞으로 가족이 생길 때 할 일이 늘 때마다 {@code FamilyGroupService}
 * 가 그 모듈들을 하나씩 들게 된다. 알림({@code push})이 {@code chat} 을 이 방식으로 듣는다.
 *
 * @param groupId 새로 생긴 가족 그룹의 id
 */
public record FamilyGroupCreated(long groupId) {
}
