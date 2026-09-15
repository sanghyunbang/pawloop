package com.heattrip.heat_trip_backend.chatweb;

import com.heattrip.heat_trip_backend.chat.ChatMessagePageView;
import com.heattrip.heat_trip_backend.chat.ChatMessageView;

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
 * @param replies     답장들의 원문 미리보기, <b>원문</b> 메시지 id 별(#452). 답장이 아닌 메시지는 {@code null}
 *
 * <h2>{@code changed} 는 "이미 받은 말이 바뀌었다" 다 (ADR-0023, #500)</h2>
 * <p>{@code items} 는 <b>새 말</b>이고 {@code changed} 는 <b>옛 말의 새 모양</b>이다. 둘을 한 목록에 섞으면
 * 앱이 바뀐 말을 대화 맨 아래에 다시 그린다 — 지워진 말이 새 말처럼 올라온다. 앱은 {@code changed} 의 항목을
 * <b>같은 id 의 자리에 덮어쓰고</b> 순서는 그대로 {@code roomSeq} 가 정한다.
 */
public record ChatMessagePageResponse(
        List<ChatMessageResponse> items,
        long lastSeq,
        boolean hasMore,
        List<ChatMessageResponse> changed,
        long lastChangeSeq) {

    static ChatMessagePageResponse of(ChatMessagePageView page, Map<Long, String> senderNames,
                                      Set<Long> blockedIds, Map<Long, ChatMessageResponse.Media> photos,
                                      Map<Long, ChatMessageResponse.ReplyTo> replies) {
        return new ChatMessagePageResponse(
                shape(page.items(), senderNames, blockedIds, photos, replies),
                page.lastSeq(),
                page.hasMore(),
                shape(page.changed(), senderNames, blockedIds, photos, replies),
                page.lastChangeSeq());
    }

    /** 같은 규칙으로 옮긴다 — 새 말이든 바뀐 말이든 계약의 모양은 하나다. */
    private static List<ChatMessageResponse> shape(List<ChatMessageView> messages, Map<Long, String> senderNames,
                                                   Set<Long> blockedIds, Map<Long, ChatMessageResponse.Media> photos,
                                                   Map<Long, ChatMessageResponse.ReplyTo> replies) {
        return messages.stream()
                .map(message -> ChatMessageResponse.of(
                        message,
                        senderNames.get(message.senderUserId()),
                        blockedIds.contains(message.senderUserId()),
                        photos.get(message.id()),
                        ChatMessages.replyOf(replies, message)))
                .toList();
    }
}
