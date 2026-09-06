package com.heattrip.heat_trip_backend.chatweb;

import com.heattrip.heat_trip_backend.chat.ChatMemberView;
import com.heattrip.heat_trip_backend.chat.ChatRoomSummaryView;
import com.heattrip.heat_trip_backend.chat.ChatRoomView;
import com.heattrip.heat_trip_backend.chat.ChatTime;

import java.time.Instant;
import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * 계약({@code openapi.yaml})의 {@code ChatRoom} 모양 — 이슈 #75·#79.
 *
 * <p><b>{@code ChatRoomView} 를 그대로 내보내지 않는 이유는 이름 하나다.</b> 계약은 방 이름을
 * {@code title} 이라 부르고 chat 은 {@code name} 이라 부른다. 여기서 옮기지 않으면 계약과
 * 실제 응답이 갈리고, 앱은 계약을 보고 만든다.
 *
 * <h2>#75 가 일부러 비워 뒀던 넷을 #79 가 채운다</h2>
 * <p>{@code lastReadSeq}·{@code unread}·{@code myRole}·{@code lastMessage} 는 #75 시점에
 * "지금 0 이나 {@code null} 을 실어 보내면 앱은 '값이 있다' 고 읽는다" 는 이유로 없었다.
 * 이제 넷 다 실제 값이 있다 — 미읽음은 {@code lastSeq − lastReadSeq} 뺄셈이다.
 *
 * <p><b>{@code lastMessage} 만 여전히 {@code null} 일 수 있다</b>: 아직 아무 말도 없는 방과,
 * 입장 응답({@code POST /api/chat/invites/&#123;code&#125;/join})이다. 뒤의 것은 그 값을
 * 얻으려고 방금 들어온 사람에게 조회를 하나 더 붙일 이유가 없어서다 — 앱은 입장 직후 방
 * 화면으로 가고, 그 화면이 메시지를 직접 부른다.
 *
 * <p>계약의 {@code isDefault}·{@code members} 는 여기 없다. {@code members} 는 방 상세
 * 조회(M2.6 의 다른 이슈)에만 실리고, {@code isDefault} 는 "가족방이 기본" 이라는 판단이라
 * chat 이 답할 수 없다({@code originKind} 를 해석하는 것은 chat 밖의 일이다 — ADR-0011).
 * 없는 필드를 0 이나 {@code false} 로 채우지 않는 것이 #75 가 정한 규칙이다.
 *
 * <h2>시각은 {@link java.time.Instant} 다 — 오프셋이 붙어야 계약이 성립한다</h2>
 * <p>계약이 {@code format: date-time} 이라고 선언했고 그건 RFC3339 <b>오프셋</b>이 있어야
 * 성립한다. {@code LocalDateTime} 을 그대로 실으면 잭슨이 {@code "2026-09-03T00:25:33.92"}
 * 로 낸다 — 앱의 {@code DateTime.tryParse} 는 그것을 <b>기기 지역 시각</b>으로 읽으므로
 * 해외에 있는 가족이 보면 그만큼 어긋난 시각이 그려진다(#248).
 *
 * <p>컬럼에 담긴 값은 UTC 다 — 이유는 {@link ChatTime}. 세우는 것도 그 클래스다.
 */
public record ChatRoomResponse(
        long id,
        String title,
        String tag,
        String originKind,
        String originRef,
        long lastSeq,
        long lastReadSeq,
        long unread,
        int memberCount,
        String myRole,
        ChatMessageResponse lastMessage,
        Instant createdAt,
        boolean muted) {

    /**
     * 방 목록 한 줄 — {@code GET /api/chat/rooms}.
     *
     * @param senderNames 미리보기 발신자의 <b>지금</b> 이름. {@link ChatSenderNames} 가
     *                    한 번의 조회로 모아 온 것이다
     * @param blockedIds  읽는 사람이 가린 발신자들. <b>미리보기도 가려야 한다</b> — 방 안에서
     *                    접어 놓고 목록에서 그대로 보여 주면 가린 사람의 말이 거기로 샌다(#82)
     */
    static ChatRoomResponse of(ChatRoomSummaryView summary, Map<Long, String> senderNames,
                               Set<Long> blockedIds) {
        ChatRoomView room = summary.room();
        ChatMessageResponse preview = summary.lastMessage() == null ? null
                : ChatMessageResponse.of(summary.lastMessage(),
                        senderNames.get(summary.lastMessage().senderUserId()),
                        blockedIds.contains(summary.lastMessage().senderUserId()));
        return new ChatRoomResponse(room.id(), room.name(), room.tag(),
                room.originKind(), room.originRef(), room.lastSeq(),
                summary.lastReadSeq(), summary.unread(), summary.memberCount(),
                summary.myRole(), preview, ChatTime.toInstant(room.createdAt()), summary.muted());
    }

    /**
     * 입장 응답 — {@code POST /api/chat/invites/&#123;code&#125;/join}.
     *
     * <p>멤버 목록을 <b>이미 읽어 온 것</b>에서 내 역할과 워터마크를 꺼낸다. 그 목록은
     * {@code memberCount} 때문에 어차피 부르는 조회라 추가 쿼리가 0이다.
     *
     * <p>내 행이 없을 수는 없다 — 방금 들어왔거나 이미 멤버였던 경우에만 여기 온다.
     * 그래도 방어적으로 기본값을 두는 이유는, 이 응답이 <b>입장 성공</b>을 알리는 자리라
     * 여기서 예외를 던지면 실제로는 들어온 사람에게 실패 화면이 뜨기 때문이다.
     */
    static ChatRoomResponse of(ChatRoomView room, List<ChatMemberView> liveMembers, long meUserId) {
        ChatMemberView me = liveMembers.stream()
                .filter(member -> member.userId() == meUserId)
                .findFirst()
                .orElse(null);
        long lastReadSeq = me == null ? 0L : me.lastReadSeq();
        return new ChatRoomResponse(room.id(), room.name(), room.tag(),
                room.originKind(), room.originRef(), room.lastSeq(),
                lastReadSeq, room.lastSeq() - lastReadSeq, liveMembers.size(),
                me == null ? null : me.role(), null, ChatTime.toInstant(room.createdAt()),
                me != null && me.muted());
    }
}
