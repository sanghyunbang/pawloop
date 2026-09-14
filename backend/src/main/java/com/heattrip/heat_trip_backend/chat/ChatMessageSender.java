package com.heattrip.heat_trip_backend.chat;

import org.springframework.dao.DataIntegrityViolationException;
import org.springframework.stereotype.Component;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.TransactionDefinition;
import org.springframework.transaction.support.TransactionTemplate;

import java.util.function.Consumer;

/**
 * 재전송을 <b>200 으로 번역</b>하는 자리 — 이슈 #79 완료 조건 3·8.
 *
 * <h2>왜 {@link ChatRoomService} 안이 아니라 별도 빈인가 — 트랜잭션 경계 하나 때문이다</h2>
 * <p>{@code UNIQUE (room_id, sender_user_id, client_msg_id)} 를 어긴 INSERT 는
 * {@link DataIntegrityViolationException} 을 내고, 그 순간 <b>그 트랜잭션은 롤백 표식이
 * 찍힌다.</b> 그래서 "잡아서 기존 메시지를 다시 읽어 돌려준다" 는 일은 반드시 그 트랜잭션
 * <b>밖</b>에서 해야 한다 — 같은 트랜잭션 안에서 읽으려 하면 Hibernate 세션이 이미 깨진
 * 상태이고, 커밋도 거부된다.
 *
 * <p>그런데 {@code ChatRoomService} 안에 그 바깥 메서드를 두면 성립하지 않는다. 스프링의
 * {@code @Transactional} 은 <b>프록시</b>로 걸리므로 같은 빈 안에서 부르는
 * {@code this.postMessage(...)} 는 프록시를 지나가지 않는다. 트랜잭션이 아예 안 열려
 * 발급과 INSERT 가 각자의 트랜잭션으로 갈라지고, 그러면 #78 이 막아 둔 구멍
 * ("번호는 받았는데 메시지가 없다")이 그대로 돌아온다.
 *
 * <p>그래서 방향이 한쪽인 빈을 하나 더 둔다: 이 클래스는 {@code ChatRoomService} 를 알고,
 * {@code ChatRoomService} 는 이 클래스를 모른다. 순환도 없고, chat 의 공개 표면에 더해지는
 * 것은 <b>전송 하나</b>다. {@code ChatRoomService} 의 javadoc 이 그 예외를 적어 두었다.
 *
 * <h2>왜 미리 조회해서 막지 않는가 — 그러면 제약이 죽는다</h2>
 * <p>INSERT 전에 {@code findMessageByClientMsgId} 로 확인하고 있으면 돌려주는 판이
 * 더 자연스러워 보인다. 고르지 않았다.
 * <ul>
 *   <li><b>확인-후-쓰기는 동시 요청 둘을 함께 통과시킨다</b>(📌 #86 원칙 5). 그것을 막으려면
 *       방 행을 미리 잠가야 하는데, 그러면 잠금이 판정이 되고 {@code UNIQUE} 는 장식이 된다.</li>
 *   <li>그 상태에서는 <b>완료 조건 8 이 성립하지 않는다</b> — 제약을 지워도 미리 조회가
 *       중복을 걸러 테스트가 초록이다. 이슈가 요구하는 것은 "제약을 지우면 3번이 실패한다"
 *       이고, 그 문장이 참이려면 중복을 실제로 막는 것이 제약이어야 한다.</li>
 * </ul>
 *
 * <p>진 쪽이 롤백되면 {@code assignNextSeq} 가 올린 {@code last_seq} 도 함께 되돌아간다 —
 * 그래서 재전송은 번호를 태우지 않는다({@code ChatRoomService#postMessage} javadoc ·
 * {@code ChatMessageIntegrationTest.aRejectedSendBurnsNoNumber}).
 *
 * <h2>"같은 트랜잭션에서 할 일" 을 받는다 (#452)</h2>
 * <p>사진 메시지는 INSERT 된 메시지의 id 에 사진을 붙여야 하는데, 붙이는 쪽(미디어)은 chat 이
 * 모르는 모듈이다({@code ChatBoundaryArchitectureTest}). 그래서 chat 은 <b>무엇을 붙이는지 모른 채</b>
 * 부르는 쪽이 준 일을 INSERT 와 <b>같은 트랜잭션</b>에서 해 준다 — 그 일이 던지면(남의 사진 등)
 * 메시지도 없던 일이 되고 번호도 안 태운다. 두 트랜잭션으로 갈라 두면 "사진 없는 사진 메시지" 가
 * 남는다. 트랜잭션은 {@link TransactionTemplate} 으로 연다 — {@code postMessage} 가 요구하는
 * {@code READ_COMMITTED} 를 같이 준다(잠금 뒤 인가를 <b>다시 읽는</b> 단계가 스냅숏이 아니라
 * 지금 값을 봐야 한다). 재전송(이미 있는 메시지)에는 그 일을 부르지 않는다.
 */
@Component
public class ChatMessageSender {

    private final ChatRoomService chatRooms;

    /** INSERT 와 "같은 트랜잭션에서 할 일" 을 한 경계에 묶는다. 격리는 {@code postMessage} 와 같다. */
    private final TransactionTemplate sameTransaction;

    public ChatMessageSender(ChatRoomService chatRooms, PlatformTransactionManager transactions) {
        this.chatRooms = chatRooms;
        this.sameTransaction = new TransactionTemplate(transactions);
        this.sameTransaction.setIsolationLevel(TransactionDefinition.ISOLATION_READ_COMMITTED);
    }

    /**
     * 글자 메시지 한 줄 — 같은 트랜잭션에서 더 할 일이 없는 전송.
     *
     * @see #send(long, long, String, String, String, String, Consumer)
     */
    public ChatMessageSendResult send(long roomId, long senderUserId, String senderName,
                                      String body, String contentType, String clientMsgId) {
        return send(roomId, senderUserId, senderName, body, contentType, clientMsgId, null, posted -> { });
    }

    /** 답장이 아닌 전송 — {@code replyToId} 없이. */
    public ChatMessageSendResult send(long roomId, long senderUserId, String senderName,
                                      String body, String contentType, String clientMsgId,
                                      Consumer<ChatMessageView> alongside) {
        return send(roomId, senderUserId, senderName, body, contentType, clientMsgId, null, alongside);
    }

    /**
     * 메시지 한 줄. <b>이 사람이</b> 같은 {@code clientMsgId} 로 다시 보내면 이미 있는
     * 그 메시지를 돌려준다.
     *
     * <h2>모든 제약 위반을 멱등으로 번역하지 않는다</h2>
     * <p>{@link DataIntegrityViolationException} 은 멱등키 말고 다른 이유로도 난다
     * ({@code UNIQUE (room_id, room_seq)} · 컬럼 폭 · FK). 그것들까지 200 으로 바꾸면
     * 서버 고장이 성공으로 보고된다. 그래서 <b>그 키의 메시지가 실제로 있을 때만</b>
     * 번역하고, 없으면 원래 예외를 그대로 다시 던진다 — 그때는 500 이 맞는 답이다.
     *
     * <p>{@code clientMsgId} 가 없는 전송은 애초에 멱등을 요구하지 않는다({@code UNIQUE} 는
     * {@code NULL} 을 겹침으로 보지 않는다). 그 경우도 그대로 던진다.
     *
     * <h2>찾는 범위가 제약의 범위와 같아야 한다 (#79)</h2>
     * <p>{@code senderUserId} 를 빼고 찾으면 <b>남의 메시지</b>를 "당신이 아까 보낸 그것"
     * 이라며 200 으로 돌려주게 된다. 그 판을 실제로 돌려 봤다 — 같은 방의 A·B 가 같은
     * 키를 쓰면 B 는 200 과 함께 A 의 본문을 받고, B 가 하려던 말은 어디에도 남지 않는다.
     * B 의 앱은 200 을 성공으로 읽으므로 재시도조차 하지 않는다. 그래서 제약도 이 조회도
     * 범위가 {@code (room_id, sender_user_id, client_msg_id)} 다.
     *
     * <p>그래서 돌아오는 메시지는 <b>언제나 부르는 사람 자신의 것</b>이다 —
     * {@code ChatRoomController.send} 가 응답의 이름을 자기 이름으로 채우는 근거가 그것이다.
     *
     * @param replyToId 답장(#452)이면 원문 메시지의 id — 같은 방이어야 한다. 검증은
     *                  {@link ChatRoomService#postMessage(long, long, String, String, String, String, Long)}
     * @param alongside INSERT 된 메시지를 받아 <b>같은 트랜잭션</b>에서 할 일(사진 붙이기, #452).
     *                  던지면 메시지도 없던 일이 된다. 재전송(이미 있는 메시지)에는 부르지 않는다
     */
    public ChatMessageSendResult send(long roomId, long senderUserId, String senderName,
                                      String body, String contentType, String clientMsgId,
                                      Long replyToId, Consumer<ChatMessageView> alongside) {
        try {
            ChatMessageView posted = sameTransaction.execute(status -> {
                ChatMessageView view = chatRooms.postMessage(
                        roomId, senderUserId, senderName, body, contentType, clientMsgId, replyToId);
                alongside.accept(view);
                return view;
            });
            return new ChatMessageSendResult(posted, true);
        } catch (DataIntegrityViolationException collision) {
            if (clientMsgId == null || clientMsgId.isBlank()) {
                throw collision;
            }
            return chatRooms.findMessageByClientMsgId(roomId, senderUserId, clientMsgId)
                    .map(existing -> new ChatMessageSendResult(existing, false))
                    .orElseThrow(() -> collision);
        }
    }
}
