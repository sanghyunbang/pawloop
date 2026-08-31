package com.heattrip.heat_trip_backend.chatweb;

import com.heattrip.heat_trip_backend.chat.ChatReadView;

/**
 * 읽음 워터마크를 올린 결과 — 계약({@code openapi.yaml})의
 * {@code POST /api/chat/rooms/&#123;roomId&#125;/read} 200 본문. 이슈 #79.
 *
 * <p>보낸 값이 아니라 <b>서버가 실제로 쓴 값</b>이다. 뒤늦게 도착한 작은 값은 무시되고
 * ({@code GREATEST}), 방의 끝을 넘는 값은 잘린다({@code LEAST}). 앱이 낙관적으로 그린
 * 뱃지를 되맞추려면 그 값이 필요하다.
 */
public record ChatReadResponse(long lastReadSeq, long unread) {

    static ChatReadResponse of(ChatReadView view) {
        return new ChatReadResponse(view.lastReadSeq(), view.unread());
    }
}
