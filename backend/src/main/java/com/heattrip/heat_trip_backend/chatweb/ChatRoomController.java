package com.heattrip.heat_trip_backend.chatweb;

import com.heattrip.heat_trip_backend.user.CurrentUser;
import com.heattrip.heat_trip_backend.chat.ChatMessageSendResult;
import com.heattrip.heat_trip_backend.chat.ChatMessageSender;
import com.heattrip.heat_trip_backend.chat.ChatRoomService;
import com.heattrip.heat_trip_backend.chat.ChatRoomView;
import com.heattrip.heat_trip_backend.user.entity.User;

import lombok.RequiredArgsConstructor;

import org.springframework.http.HttpHeaders;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.DeleteMapping;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.List;

/**
 * 방 목록 · 메시지 조회 · 전송 · 읽음 — 이슈 #79. 계약은 {@code openapi.yaml} 의
 * {@code /api/chat/**} 다.
 *
 * <p>이 클래스가 {@code chat} 패키지 밖에 있는 이유는 {@code package-info} 에 있다.
 *
 * <h2>인가 (📌 #86 원칙 4)</h2>
 * <ul>
 *   <li><b>인증</b> — 네 경로 모두 {@code SecurityConfig} 의 {@code anyRequest().authenticated()}
 *       로 떨어진다. {@code publicMatchers} 에 {@code /api/chat} 은 없다.</li>
 *   <li><b>멤버십</b> — 방 id 를 받는 셋은 전부 {@code chat_room_member} 를 보고,
 *       <b>{@code removed_at} 이 찍힌 사람도 403</b> 이다. 판정은
 *       {@code ChatRoomService.requireLiveMembership} 한 곳이다.
 *       {@code @PreAuthorize} 를 쓰지 않은 이유는 {@code ChatRoomService.requireOwner} 의
 *       javadoc 과 같다 — 여기서 필요한 것은 토큰의 role 이 아니라 <b>이 방에서의 멤버십</b>
 *       이라 DB 를 봐야 한다.</li>
 *   <li><b>없는 방과 남의 방이 같은 답</b>이다(403). 404 로 답하면 방 id 를 훑어 "있는 방/
 *       없는 방" 을 가려낼 수 있다. 방 목록({@code GET /rooms})은 방 id 를 받지 않으므로
 *       403 을 낼 대상이 없고, 대신 답의 범위 자체가 내 멤버십이라 남의 방이 섞이지 않는다.</li>
 *   <li><b>rate limit</b> — <b>네 경로 다 표에 없다.</b> 📌 #86 원칙 4 가 요구하는 등재를
 *       여기서 하지 않은 것은 이슈 <b>#80</b> 이 채팅 버킷을 소유하기 때문이고, 폴링 주기와
 *       함께 정해야 숫자에 근거가 생긴다. <b>미룬 것이지 안전한 것이 아니다</b> —
 *       {@code ApiRateLimitFilter.resolveRule} 이 {@code null} 을 돌려주면 필터가 그대로
 *       통과시키므로, <b>표에 없는 경로는 한도가 0 이 아니라 무한이다.</b> 지금 이 넷은
 *       한 계정으로 몇 번을 불러도 429 가 나오지 않는다.</li>
 * </ul>
 *
 * <h2>ETag 를 직접 계산한다 — {@code ShallowEtagHeaderFilter} 를 쓰지 않는다</h2>
 * <p>그 필터는 <b>본문을 다 만들어 놓고</b> 해시한다. 절약되는 것은 네트워크뿐이고 조회·
 * 조립은 그대로 남아, 폴링처럼 대부분이 "바뀐 것 없음" 인 경로에서는 아무것도 줄지 않는다.
 * 여기서는 {@code chat_room} 한 행({@code lastSeq})만 읽고 끝낸다.
 *
 * <p><b>304 를 주기 전에 인가가 끝나 있어야 한다.</b> 순서가 뒤집히면 남의 방
 * {@code lastSeq} 를 304/200 차이로 알아낼 수 있다 — 타이밍이 아니라 응답 자체가 오라클이
 * 된다. 그래서 {@code roomForMember} 가 인가와 방 읽기를 <b>한 조회</b>로 한다.
 */
@RestController
@RequiredArgsConstructor
@RequestMapping("/api/chat")
public class ChatRoomController {

    /**
     * {@code limit} 을 안 보냈을 때의 한 장 크기 — 이슈 #79("afterSeq 없으면 최신 50건").
     *
     * <p><b>이 상수가 {@code ChatLimits} 가 아니라 여기 있는 것은 종류가 다른 수이기
     * 때문이다.</b> 정원·유효기간은 플랜에 따라 달라질 수 있는 <b>한도</b>지만, 페이지 크기는
     * 계약이 선언한 <b>질의 파라미터의 기본값</b>이다. 플랜이 생겨도 이 값은 안 움직인다.
     */
    private static final int DEFAULT_PAGE_SIZE = 50;

    /** 계약이 선언한 {@code maximum}. 한 장에 이보다 많이 주지 않는다. */
    private static final int MAX_PAGE_SIZE = 100;

    private final ChatRoomService chatRooms;
    private final ChatRooms roomList;
    private final ChatMessages chatMessages;
    private final ChatMessageSender sender;

    /**
     * 내 방 목록. 방마다 미읽음은 {@code lastSeq − lastReadSeq} <b>뺄셈</b>이다.
     *
     * <p>쿼리는 방 개수와 무관하게 넷이다({@link ChatRooms}). 방마다 미리보기를 따로 찾는
     * 판이면 방 20개에 쿼리가 21개다.
     */
    @GetMapping("/rooms")
    public List<ChatRoomResponse> myRooms(@CurrentUser User user) {
        return roomList.of(user.getId());
    }

    /**
     * 메시지 목록 — 폴링 델타({@code afterSeq})와 과거 스크롤({@code beforeSeq}) 겸용.
     *
     * <p>둘 다 없으면 최신 한 장이다. 둘을 함께 주면 400 이다.
     *
     * <h2>{@code If-None-Match} 를 언제 304 로 답하는가</h2>
     * <p>세 가지가 <b>전부</b> 참일 때만이다.
     * <ol>
     *   <li>인가를 통과했다 — 이 조건이 먼저다(위 javadoc).</li>
     *   <li>{@code afterSeq} 를 보냈다 — 즉 <b>폴링</b>이다. 첫 진입·과거 스크롤은 창이
     *       달라지므로 방의 {@code lastSeq} 가 그대로여도 응답이 같지 않다.</li>
     *   <li>{@code afterSeq >= lastSeq} 다 — 즉 실제로 줄 것이 없다.</li>
     * </ol>
     *
     * <h2>⚠️ 그 세 조건만으로는 부족하다 — 프레임워크가 뒤에서 한 번 더 판정한다</h2>
     * <p>위 판단을 통과해 <b>200 과 본문</b>을 돌려줘도, {@code HttpEntityMethodProcessor}
     * 가 응답의 {@code ETag} 헤더와 요청의 {@code If-None-Match} 를 <b>스스로</b> 대조해
     * 200 을 304 로 갈아치우고 본문을 버린다({@code isResourceNotModified}). 그래서 예전
     * 판은 이렇게 깨졌다(60줄 방에서 실측):
     * <pre>
     *   ① afterSeq=0            → 200, 50건, hasMore=true, ETag "1:60"
     *   ② afterSeq=50 + 그 ETag → <b>304, 본문 없음</b>   (51~60 열 줄이 사라진다)
     *   ③ ② 에서 ETag 만 빼면   → 200, 10건 [51..60]
     * </pre>
     * <p>①의 ETag 가 <b>거짓말</b>이었던 것이 원인이다. 그 응답은 60번까지 준 적이 없는데
     * "이 응답은 lastSeq=60 상태다" 라고 표시했다. 그래서 <b>부분 페이지에는 ETag 를 아예
     * 붙이지 않는다</b> — {@code afterSeq} 를 보냈고({@code = 폴링}) {@code hasMore} 가
     * 거짓일 때만 붙인다. 그 응답만이 "{@code lastSeq} 까지 전부 손에 넣었다" 를 뜻한다.
     *
     * <p>이 규칙 하나로 성질이 둘 따라온다.
     * <ul>
     *   <li><b>ETag 의 뜻이 하나가 된다</b> — {@code "{roomId}:{lastSeq}"} 를 들고 있는
     *       클라이언트는 그 {@code lastSeq} 까지 실제로 다 받은 클라이언트다. 그러니 그
     *       ETag 로 되물었을 때의 304 는 언제나 옳다.</li>
     *   <li><b>첫 진입·과거 스크롤이 304 로 막히지 않는다</b> — 그 응답에는 ETag 가 없어
     *       프레임워크가 대조할 것이 없다. 예전 판은 옛 ETag 만 있으면 두 경우 다 빈 304 를
     *       돌려줬다(실측). 계약이 "304 는 {@code afterSeq} 를 보낸 폴링에만 나갑니다" 라고
     *       적은 문장이 그때는 거짓이었다.</li>
     * </ul>
     *
     * <p>이슈 #79 가 정한 ETag 모양({@code "{roomId}:{lastSeq}"})은 그대로 지킨다. 창을
     * ETag 에 담는 길({@code "{roomId}:{afterSeq}:{lastSeq}"})도 같은 증상을 없애지만 그건
     * 계약이 정한 모양을 바꾸는 것이라 고르지 않았다.
     *
     * <p>200 응답의 ETag 는 <b>본문과 함께 읽은</b> {@code lastSeq} 로 만든다. 인가 때 읽은
     * 값으로 만들면 그 사이에 들어온 메시지가 다음 폴링에서 304 로 가려질 수 있다.
     */
    @GetMapping("/rooms/{roomId}/messages")
    public ResponseEntity<ChatMessagePageResponse> messages(
            @CurrentUser User user,
            @PathVariable long roomId,
            @RequestParam(required = false) Long afterSeq,
            @RequestParam(required = false) Long beforeSeq,
            @RequestParam(required = false) Integer limit,
            @RequestHeader(value = HttpHeaders.IF_NONE_MATCH, required = false) String ifNoneMatch) {

        ChatRoomView room = chatRooms.roomForMember(roomId, user.getId());
        if (afterSeq != null
                && etagOf(roomId, room.lastSeq()).equals(ifNoneMatch)
                && afterSeq >= room.lastSeq()) {
            return ResponseEntity.status(HttpStatus.NOT_MODIFIED)
                    .eTag(etagOf(roomId, room.lastSeq()))
                    .build();
        }

        ChatMessagePageResponse page =
                chatMessages.page(roomId, user.getId(), afterSeq, beforeSeq, pageSize(limit));
        return respondWithPage(roomId, afterSeq, page);
    }

    /**
     * 200 + 본문. <b>ETag 는 이 응답이 "{@code lastSeq} 까지 전부" 일 때만 붙인다.</b>
     *
     * <p>붙이지 않는 편이 안전한 쪽이다 — ETag 가 없으면 다음 폴링이 조건 없는 200 을 받아
     * 한 번 더 조회할 뿐이지만, 틀린 ETag 를 붙이면 프레임워크가 그 다음 응답을 빈 304 로
     * 바꿔 <b>메시지를 잃는다</b>(위 javadoc). 첫 장·첫 진입·과거 스크롤이 그 자리다.
     */
    private static ResponseEntity<ChatMessagePageResponse> respondWithPage(
            long roomId, Long afterSeq, ChatMessagePageResponse page) {

        boolean coversEverythingUpToLastSeq = afterSeq != null && !page.hasMore();
        if (!coversEverythingUpToLastSeq) {
            return ResponseEntity.ok(page);
        }
        return ResponseEntity.ok().eTag(etagOf(roomId, page.lastSeq())).body(page);
    }

    /**
     * 메시지 전송. 처음이면 201, 같은 {@code clientMsgId} 의 재전송이면 <b>200</b> 이다.
     *
     * <p>409 가 아닌 이유는 {@link ChatMessageSendResult} javadoc 에 있다 — 재시도한
     * 클라이언트 입장에서 그 요청은 성공했다.
     *
     * <p>보낸 사람 이름은 토큰이 가리키는 사용자에서 온다. 저장되는 것은 <b>그때의
     * 스냅샷</b>이고 응답에 실리는 것은 <b>지금</b>의 이름인데, 보낸 사람 자신에 대해서는
     * 두 값이 같다 — 그래서 여기서는 {@code users} 를 한 번 더 읽지 않는다
     * ({@code ChatSenderNames} 가 필요한 곳은 남의 이름을 붙이는 목록 경로다).
     *
     * <p><b>그 말이 성립하려면 돌아온 메시지가 반드시 부르는 사람의 것이어야 한다.</b>
     * 멱등키의 범위가 {@code (room_id, client_msg_id)} 였을 때는 아니었다 — 같은 방의 다른
     * 멤버가 같은 키를 쓰면 남의 메시지가 200 으로 돌아왔고, 여기서 거기에 <b>부르는 사람의
     * 이름</b>을 찍어 {@code senderUserId} 와 {@code senderName} 이 다른 사람을 가리키는
     * 응답이 나갔다(실측). 지금은 제약과 조회의 범위에 {@code sender_user_id} 가 들어 있어
     * 그 경우가 없다({@link ChatMessageSender#send}).
     */
    @PostMapping("/rooms/{roomId}/messages")
    public ResponseEntity<ChatMessageResponse> send(@CurrentUser User user,
                                                    @PathVariable long roomId,
                                                    @RequestBody ChatSendRequest request) {
        ChatMessageSendResult result = sender.send(roomId, user.getId(), user.displayName(),
                request.body(), request.contentType(), request.clientMsgId());

        return ResponseEntity
                .status(result.created() ? HttpStatus.CREATED : HttpStatus.OK)
                .body(ChatMessageResponse.of(result.message(), user.displayName()));
    }

    /**
     * 내 메시지 삭제 — 이슈 #197. 소프트 삭제라 자리는 남는다({@code ChatRoomService#deleteMessage}).
     *
     * <p>경로가 방이 아니라 메시지 id 인 이유: 계약이 처음부터 그렇게 적어 두었고(2026-08-31,
     * {@code x-status: planned}), 메시지 id 는 전역 유일이라 방을 따로 받을 필요가 없다.
     * 한도 표에는 넣지 않는다 — 초대 회수와 같은 판단이다. 반복해도 새로 생기는 것이 없다.
     */
    @DeleteMapping("/messages/{messageId}")
    public ResponseEntity<Void> deleteMessage(@CurrentUser User user, @PathVariable long messageId) {
        chatRooms.deleteMessage(messageId, user.getId());
        return ResponseEntity.noContent().build();
    }

    /**
     * 읽음 워터마크 올리기. <b>단조 증가만</b> 하고 방의 끝을 넘지 않는다.
     *
     * <p>돌려주는 것은 보낸 값이 아니라 서버가 실제로 쓴 값이다({@link ChatReadResponse}).
     */
    @PostMapping("/rooms/{roomId}/read")
    public ChatReadResponse read(@CurrentUser User user,
                                 @PathVariable long roomId,
                                 @RequestBody ChatReadRequest request) {
        return ChatReadResponse.of(
                chatRooms.markRead(roomId, user.getId(), request.requireLastReadSeq()));
    }

    /**
     * {@code "{roomId}:{lastSeq}"} — 이슈 #79 가 정한 모양 그대로다.
     *
     * <p>따옴표를 여기서 붙인다. {@code ResponseEntity.eTag} 가 없으면 붙여 주지만, 비교하는
     * 쪽({@code If-None-Match} 헤더 값)은 따옴표가 있는 문자열이라 같은 모양으로 만들어야
     * 대조가 성립한다.
     */
    private static String etagOf(long roomId, long lastSeq) {
        return "\"%d:%d\"".formatted(roomId, lastSeq);
    }

    /**
     * 한 장의 크기. <b>거절하지 않고 자른다.</b>
     *
     * <p>{@code validBody} 는 긴 본문을 자르지 않고 400 으로 거절한다 — 사용자가 적은 것과
     * 화면에 뜨는 것이 갈리면 안 되기 때문이다. 여기서는 그 논리가 반대로 작동한다:
     * {@code limit} 은 사람이 적은 값이 아니라 앱이 정한 페이지 크기라 잘라도 사용자가 보는
     * 것이 달라지지 않고, 반대로 400 으로 거절하면 앱의 한 줄 실수가 <b>채팅 전체를</b>
     * 멈춘다. 완료 조건 2("끊겼다 붙어도 안 놓친다")를 지키는 쪽이 잘라 주는 쪽이다.
     */
    private static int pageSize(Integer requested) {
        if (requested == null) {
            return DEFAULT_PAGE_SIZE;
        }
        return Math.clamp(requested.longValue(), 1, MAX_PAGE_SIZE);
    }
}
