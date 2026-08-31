package com.heattrip.heat_trip_backend.chatweb;

import com.heattrip.heat_trip_backend.chat.ChatBlocks;
import com.heattrip.heat_trip_backend.chat.ChatMessageView;
import com.heattrip.heat_trip_backend.chat.ChatRoomService;
import com.heattrip.heat_trip_backend.chat.ChatRoomSummaryView;

import lombok.RequiredArgsConstructor;

import org.springframework.stereotype.Component;

import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.Set;

/**
 * 방 목록을 <b>계약의 모양</b>으로 만든다 — 이슈 #79. {@link ChatMessages} 와 같은 자리다.
 *
 * <h2>이름은 한 번의 조회로 모은다</h2>
 * <p>방마다 미리보기 발신자의 이름을 따로 찾으면 방 20개에 쿼리가 20개다. chat 이
 * 돌려주는 것은 {@code senderUserId} 뿐이고(chat 은 {@code users} 를 모른다 — ADR-0011
 * 결정 4), 그 id 들을 한 번에 모아 {@link ChatSenderNames} 에게 묻는다.
 *
 * <p>그래서 이 경로 전체의 쿼리 수는 <b>방 개수와 무관하게 넷</b>이다 —
 * 멤버십+방 · 방별 멤버 수 · 방별 마지막 메시지 · 이름.
 *
 * <p>이 패키지가 하는 일은 여전히 셋뿐이다(package-info) — 사용자를 id 로 바꾸고,
 * {@code ChatRoomService} 를 부르고, 돌아온 값 레코드를 계약의 모양으로 옮긴다.
 * <b>판정도 트랜잭션도 여기 없다</b>: 미읽음 뺄셈도 멤버십 필터도 전부
 * {@link ChatRoomService#myRooms} 안이다.
 */
@Component
@RequiredArgsConstructor
public class ChatRooms {

    private final ChatRoomService chatRooms;
    private final ChatSenderNames senderNames;
    private final ChatBlocks blocks;

    /** 내가 살아 있는 멤버로 있는 방들 — 참여 순서대로. 남의 방은 애초에 들어오지 않는다. */
    public List<ChatRoomResponse> of(long userId) {
        List<ChatRoomSummaryView> rooms = chatRooms.myRooms(userId);
        Map<Long, String> names = senderNames.of(rooms.stream()
                .map(ChatRoomSummaryView::lastMessage)
                .filter(Objects::nonNull)
                .map(ChatMessageView::senderUserId)
                .toList());
        // 미리보기도 가린다. 방 안에서 접어 놓고 목록에서 그대로 보여 주면 거기로 샌다.
        Set<Long> blockedIds = blocks.blockedBy(userId);
        return rooms.stream().map(room -> ChatRoomResponse.of(room, names, blockedIds)).toList();
    }
}
