package com.heattrip.heat_trip_backend.chatweb;

import com.heattrip.heat_trip_backend.chat.ChatReactionView;

import java.util.List;

/**
 * 반응을 켜고 끈 뒤의 <b>최신 집계</b> — 계약의 {@code ChatReactions}(#452).
 *
 * <h2>집계를 실어 왕복을 하나로 줄인다</h2>
 * <p>커뮤니티 반응과 같은 모양이다. 앱이 자기 화면에서 숫자를 1 올리고 마는 판은 <b>남이 동시에 누른
 * 것을 못 본다</b> — 다음 폴링까지 내 화면만 틀린 숫자를 들고 있게 된다.
 *
 * <h2>{@code messageId} 를 함께 싣는다</h2>
 * <p>앱은 이 응답을 <b>어느 말풍선에</b> 얹을지 알아야 한다. 요청 경로에 이미 있는 값이지만, 응답만
 * 들고 처리하는 자리(재시도 · 큐)에서 그 경로를 다시 꿰어 보게 만들 이유가 없다.
 *
 * <p>여기 실린 것과 같은 집계가 <b>다음 폴링에도</b> 온다 — 반응은 방의 변경 번호를 올리므로
 * 그 말이 {@code changed} 에 실려 방의 모두에게 흐른다(ADR-0023). 이 응답은 누른 사람이 기다리지
 * 않게 하는 지름길이지 유일한 경로가 아니다.
 */
public record ChatReactionsResponse(long messageId, List<ChatMessageResponse.Reaction> reactions) {

    static ChatReactionsResponse of(long messageId, List<ChatReactionView> reactions) {
        return new ChatReactionsResponse(messageId, ChatMessageResponse.Reaction.allOf(reactions));
    }
}
