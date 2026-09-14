package com.heattrip.heat_trip_backend.chatweb;

import com.heattrip.heat_trip_backend.chat.ChatMessagePageView;

import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * 계약({@code openapi.yaml})의 {@code ChatMessagePage} — 이슈 #79.
 *
 * <p>공용 {@code Page}({@code nextCursor})를 쓰지 않는다. 커서가 {@code roomSeq} 라 다음 커서는
 * 클라이언트가 이미 들고 있고, 정작 스스로 알 수 없는 것은 방의 {@code lastSeq} 다 — 그것이
 * 있어야 미읽음을 맞춘다.
 *
 * @param senderNames 발신자들의 <b>지금</b> 이름. {@link ChatSenderNames} 가 한 번의 조회로 모아 온 것
 * @param blockedIds  읽는 사람이 가린 발신자들 — {@code hiddenByBlock} 의 근거(#82)
 * @param photos      사진 메시지의 사진, 메시지 id 별(#452). 없는 메시지는 {@code null} 로 실린다
 */
public record ChatMessagePageResponse(
        List<ChatMessageResponse> items,
        long lastSeq,
        boolean hasMore) {

    static ChatMessagePageResponse of(ChatMessagePageView page, Map<Long, String> senderNames,
                                      Set<Long> blockedIds, Map<Long, ChatMessageResponse.Media> photos) {
        return new ChatMessagePageResponse(
                page.items().stream()
                        .map(message -> ChatMessageResponse.of(
                                message,
                                senderNames.get(message.senderUserId()),
                                blockedIds.contains(message.senderUserId()),
                                photos.get(message.id())))
                        .toList(),
                page.lastSeq(),
                page.hasMore());
    }
}
