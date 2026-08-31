package com.heattrip.heat_trip_backend.chatweb;

import com.heattrip.heat_trip_backend.chat.ChatMessagePageView;

import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * 계약({@code openapi.yaml})의 {@code ChatMessagePage} 모양 — 이슈 #79.
 *
 * <p>공용 {@code Page}({@code nextCursor})를 쓰지 않는다. 커서가 {@code roomSeq} 라 다음
 * 커서는 클라이언트가 이미 들고 있고, 정작 스스로 알 수 없는 것은 <b>방의 현재
 * {@code lastSeq}</b> 다 — 미읽음을 맞추려면 그 값이 필요하고 델타가 비어 있을 때도 필요하다.
 *
 * @param items   {@code roomSeq} 오름차순. 삭제된 메시지도 톰스톤으로 들어 있다(ADR-0011)
 * @param lastSeq 방의 현재 마지막 {@code roomSeq}. 비어 있는 응답에도 실린다
 */
public record ChatMessagePageResponse(
        List<ChatMessageResponse> items,
        long lastSeq,
        boolean hasMore) {

    /**
     * @param blockedIds 읽는 사람이 가린 발신자들. <b>목록에서 빼지 않고 표시만 한다</b> —
     *                   빼면 그 {@code roomSeq} 가 도달하지 않아 미읽음 뱃지가 영원히 남는다
     *                   (#82 · ADR-0011)
     */
    static ChatMessagePageResponse of(ChatMessagePageView page, Map<Long, String> senderNames,
                                      Set<Long> blockedIds) {
        return new ChatMessagePageResponse(
                page.items().stream()
                        .map(message -> ChatMessageResponse.of(
                                message,
                                senderNames.get(message.senderUserId()),
                                blockedIds.contains(message.senderUserId())))
                        .toList(),
                page.lastSeq(),
                page.hasMore());
    }
}
