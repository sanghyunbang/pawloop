package com.heattrip.heat_trip_backend.chat;

import java.util.List;

/**
 * 메시지 한 장 — 이슈 #79.
 *
 * <h2>왜 {@code nextCursor} 가 아니라 {@link #lastSeq} 인가</h2>
 * <p>커서가 {@code room_seq} 라 다음 요청의 커서는 클라이언트가 이미 손에 든 값
 * (마지막 항목의 {@code roomSeq})이다. 정작 클라이언트가 스스로 알 수 없는 것은 <b>방의
 * 현재 마지막 번호</b>다 — 미읽음을 맞추려면 그 값이 필요하고, 델타가 비어 있을 때도
 * 필요하다. 그래서 공용 {@code Page} 대신 이 모양이다(계약의 {@code ChatMessagePage}).
 *
 * <h2>{@link #hasMore} 는 한 줄 더 읽어서 정한다</h2>
 * <p>"{@code items.size() == limit} 이면 더 있다" 는 <b>틀린다</b> — 딱 맞아떨어지는 마지막
 * 장에서 참이 되어 앱이 빈 요청을 한 번 더 보낸다. 대신 {@code limit + 1} 개를 읽어 넘치면
 * 잘라 낸다. {@code room_seq} 에 빈틈이 없다는 성질에 기대지 않는 것도 그래서다 —
 * 그 성질은 발급과 롤백이 함께 맞아야 성립하는 것이고, 페이지 계산이 그것에 의존하면
 * 발급이 바뀌는 날 페이지가 조용히 틀린다.
 *
 * <p>삭제된 메시지도 {@link #items} 에 톰스톤으로 들어 있다. 거르면 그 {@code roomSeq} 가
 * 클라이언트에 도달하지 않아 읽음 커서가 넘지 못하고 미읽음 뱃지가 영원히 남는다(ADR-0011).
 *
 * @param items   {@code room_seq} <b>오름차순</b>. 어느 방향으로 페이지를 넘겼든 같은 순서다
 * @param lastSeq 방의 현재 마지막 {@code room_seq}. 응답이 비어 있어도 실린다
 */
public record ChatMessagePageView(
        List<ChatMessageView> items,
        long lastSeq,
        boolean hasMore) {
}
