package com.heattrip.heat_trip_backend.chatweb;

import com.heattrip.heat_trip_backend.chat.ChatMessageView;
import com.heattrip.heat_trip_backend.chat.ChatRoomService;

import lombok.RequiredArgsConstructor;

import org.springframework.stereotype.Component;

import java.util.List;
import java.util.Map;

/**
 * 메시지 목록을 <b>계약의 모양</b>으로 만든다 — 조회와 이름 해석을 한 자리에서 묶는다.
 * 이슈 #78 완료 조건 3·4.
 *
 * <h2>왜 이 클래스가 있는가 — 해석기가 응답 경로 위에 서야 한다</h2>
 * <p>{@link ChatSenderNames} 만 만들어 두고 아무도 안 부르면, 완료 조건 3·4 를 초록으로
 * 만드는 것은 <b>테스트가 그 클래스를 직접 부르는 것</b>뿐이다. 그건 #74 의
 * {@code AuthCode.role} 과 같은 모양이다 — 매 INSERT 마다 채우지만 아무도 읽지 않는 값.
 * 그 상태로 넘기면 #79 를 짜는 사람이 이 조립을 처음부터 다시 판단하게 되고, 그때
 * {@code sender_name} 스냅샷을 그대로 응답에 실으면 완료 조건 4 가 조용히 깨진다.
 *
 * <p>그래서 조립을 지금 <b>이름이 붙은 한 자리</b>에 둔다. #79 는 여기에 HTTP 만 붙인다
 * (경로·인가·{@code ChatMessagePage} 포장). 그때 붙일 인가는 {@code ChatRoomService}
 * 에게 묻는다 — {@link ChatRoomService#messagesAfter} 가 인가를 안 하는 것이 그 뜻이다.
 *
 * <h2>이름은 한 번의 조회로 모은다</h2>
 * <p>메시지마다 {@code findById} 를 부르면 50건 조회에 쿼리가 51개다. 폴링이라 그 곱셈이
 * 그대로 초당 부하가 된다 — {@link ChatSenderNames#of(java.util.Collection)} 이 그 자리다.
 *
 * <p>이 패키지가 하는 일은 여전히 셋뿐이다(package-info) — 사용자를 id 로 바꾸고,
 * {@code ChatRoomService} 를 부르고, 돌아온 값 레코드를 계약의 모양으로 옮긴다.
 * <b>판정도 트랜잭션도 여기 없다.</b>
 */
@Component
@RequiredArgsConstructor
public class ChatMessages {

    private final ChatRoomService chatRooms;
    private final ChatSenderNames senderNames;

    /**
     * {@code afterSeq} 다음 메시지들 — {@code room_seq} 오름차순, 이름은 <b>지금</b> 값이다.
     *
     * <p>삭제된 메시지도 톰스톤으로 그대로 들어 있다. 거르면 그 {@code roomSeq} 가
     * 클라이언트에 도달하지 않아 미읽음 뱃지가 영원히 남는다(ADR-0011).
     */
    public List<ChatMessageResponse> after(long roomId, long afterSeq, int limit) {
        List<ChatMessageView> messages = chatRooms.messagesAfter(roomId, afterSeq, limit);
        Map<Long, String> names = senderNames.of(
                messages.stream().map(ChatMessageView::senderUserId).toList());
        return messages.stream()
                .map(message -> ChatMessageResponse.of(message, names.get(message.senderUserId())))
                .toList();
    }
}
