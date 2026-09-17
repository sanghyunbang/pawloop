package com.heattrip.heat_trip_backend.chatweb;

import com.heattrip.heat_trip_backend.S3.MediaAttachment;
import com.heattrip.heat_trip_backend.S3.MediaAttachment.AttachedMedia;
import com.heattrip.heat_trip_backend.moderation.Blocks;
import com.heattrip.heat_trip_backend.moderation.ContentFilter;
import com.heattrip.heat_trip_backend.chat.ChatMessagePageView;
import com.heattrip.heat_trip_backend.chat.ChatMessageSendResult;
import com.heattrip.heat_trip_backend.chat.ChatMessageSender;
import com.heattrip.heat_trip_backend.chat.ChatMessageView;
import com.heattrip.heat_trip_backend.chat.ChatReactionView;
import com.heattrip.heat_trip_backend.chat.ChatRoomService;
import com.heattrip.heat_trip_backend.user.entity.User;

import org.springframework.stereotype.Component;
import org.springframework.transaction.PlatformTransactionManager;
import org.springframework.transaction.support.TransactionTemplate;

import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;
import java.util.stream.Stream;

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
 * <h2>사진도 여기서 붙고 여기서 읽힌다 (#452)</h2>
 * <p>{@code chat} 은 경계 밖의 우리 패키지를 하나도 못 본다({@code ChatBoundaryArchitectureTest}).
 * 그래서 사진 메시지의 사진({@link MediaAttachment}, {@code ref_type=CHAT} · {@code ref_id=message.id})은
 * 이름·가리기와 같은 자리, 즉 여기서 조립한다. 붙이는 것은 {@link ChatMessageSender} 가 INSERT 와
 * <b>같은 트랜잭션</b>에서 불러 주는 일이라 남의 사진이면 메시지도 없던 일이 된다. 읽을 때는 한 장에
 * 한 번 — 사진 메시지가 없는 장은 묻지도 않는다. 지울 때는 메시지와 사진을 한 트랜잭션에서 함께.
 *
 * <h2>답장의 원문 미리보기도 여기서 만든다 (#452)</h2>
 * <p>{@code chat} 은 답장을 원문의 id 하나로만 안다({@code ChatMessageView#replyToId}). 원문의 내용을
 * 답장 행에 복사해 두지 않는 이유는 원문이 나중에 지워지거나(톰스톤) 보낸 사람의 이름이 바뀌기 때문이다 —
 * 미리보기는 <b>응답 때마다</b> 원문을 읽어 만든다. 한 장의 답장들이 가리키는 원문은 <b>한 번의 조회</b>로
 * 모은다(이름·사진과 같은 규칙) — 답장이 없는 장은 묻지 않는다.
 *
 * <h2>반응도 한 번의 조회다 (#452)</h2>
 * <p>말풍선 아래 반응 줄은 {@code chat} 이 집계해 주고({@code ChatRoomService#reactionsOf}) 여기서 계약의
 * 모양으로 옮긴다. 이름·사진·답장 원문과 같은 규칙이다 — <b>한 장에 한 번</b> 묻고, 반응이 하나도 없는
 * 장이면 조회 자체를 안 한다.
 *
 * <p>전송 응답에는 반응이 없다(빈 배열). 방금 만든 말에 누가 반응했을 리 없다 — 그 자리에서 한 번 더
 * 묻는 것은 언제나 0을 확인하는 왕복이다.
 *
 * <p>이 패키지가 하는 일은 여전히 셋뿐이다(package-info) — 사용자를 id 로 바꾸고,
 * {@code ChatRoomService} 를 부르고, 돌아온 값 레코드를 계약의 모양으로 옮긴다.
 * <b>판정은 여기 없다</b> — 트랜잭션은 사진을 메시지와 한 몸으로 묶는 데에만 쓴다.
 */
@Component
public class ChatMessages {

    private final ChatRoomService chatRooms;
    private final ChatMessageSender sender;
    private final ChatSenderNames senderNames;
    private final Blocks blocks;
    private final MediaAttachment media;

    /**
     * 말풍선을 보내기 전에 거른다 — 이슈 #681. {@code moderation} 모듈의 공개 표면이다.
     *
     * <p><b>왜 {@code chat} 이 아니라 여기인가.</b> {@code chat} 은 경계 밖의 우리 패키지를
     * 하나도 못 본다({@code allowedDependencies = {}} · {@code ChatBoundaryArchitectureTest}).
     * 이름·가리기·사진이 이미 이 자리에서 붙는 것과 같은 이유로, 거르기도 여기다.
     */
    private final ContentFilter contentFilter;

    /** 삭제 — 메시지의 톰스톤과 사진 제거를 한 경계에 묶는다. */
    private final TransactionTemplate sameTransaction;

    public ChatMessages(ChatRoomService chatRooms, ChatMessageSender sender, ChatSenderNames senderNames,
                        Blocks blocks, MediaAttachment media, ContentFilter contentFilter,
                        PlatformTransactionManager transactions) {
        this.chatRooms = chatRooms;
        this.sender = sender;
        this.senderNames = senderNames;
        this.blocks = blocks;
        this.media = media;
        this.contentFilter = contentFilter;
        this.sameTransaction = new TransactionTemplate(transactions);
    }

    /** 전송의 결과 — 계약의 모양으로 옮긴 메시지와, 처음(201)인지 재전송(200)인지. */
    public record Sent(ChatMessageResponse message, boolean created) {
    }

    /**
     * 전송 — 글자든 사진이든. 처음이면 {@code created}, 같은 {@code clientMsgId} 의 재전송이면 아니다
     * ({@link ChatMessageSender#send}).
     *
     * <h2>사진 메시지의 규칙 (#452)</h2>
     * <ul>
     *   <li>{@code mediaId} 가 있으면 종류는 {@code image} 다 — 생략해도 되고, 다른 종류를 적으면 400.</li>
     *   <li>{@code image} 라고 적고 {@code mediaId} 가 없으면 400 — "사진 없는 사진 메시지" 는 만들지 않는다.</li>
     *   <li>본문은 캡션이라 비어도 된다 — 그 판단은 {@code ChatRoomService#postMessage} 가 종류를 보고 한다.</li>
     *   <li>사진은 <b>내가 올렸고, {@code ready} 이고, 아직 어디에도 안 붙은 것</b>만 — 아니면 400 이고
     *       메시지도 없던 일이 된다(같은 트랜잭션). 사진 하나에 메시지 하나다.</li>
     * </ul>
     *
     * <p>보낸 사람 이름은 토큰의 사용자에서 온다 — 저장되는 것은 그때의 스냅샷, 응답은 지금 이름인데
     * 자기 자신에 대해서는 둘이 같으므로 {@code users} 를 다시 읽지 않는다. 가리기도 자기 말에는 없다.
     */
    public Sent send(long roomId, User user, ChatSendRequest request) {
        // 거르기가 전송 앞에 선다 (#681, 애플 App Review Guideline 1.2). 번호도 안 태우고
        // 사진도 안 붙는다 — INSERT 자체가 일어나지 않기 때문이다. 캡션이 없는 사진
        // 메시지는 검사할 글이 없는 자리라 그대로 지나간다.
        contentFilter.requireClean(request.body());
        String type = contentTypeOf(request);
        Long mediaId = request.mediaId();
        List<AttachedMedia> attached = new ArrayList<>(1);
        ChatMessageSendResult result = sender.send(roomId, user.getId(), user.displayName(),
                request.body(), type, request.clientMsgId(), request.replyToId(),
                posted -> {
                    if (mediaId != null) {
                        attached.addAll(media.attach(MediaAttachment.REF_CHAT,
                                String.valueOf(posted.id()), List.of(mediaId), user.getId()));
                    }
                });
        ChatMessageResponse.Media photo = result.created()
                ? firstOf(attached)
                : photosOf(List.of(result.message())).get(result.message().id());
        ChatMessageResponse.ReplyTo replyTo = replyOf(repliesOf(roomId, List.of(result.message())), result.message());
        return new Sent(ChatMessageResponse.of(result.message(), user.displayName(), false, photo, replyTo),
                result.created());
    }

    /**
     * 내 메시지 삭제(#197)와 그 사진 제거(#452)를 한 트랜잭션에서. 인가(보낸 사람만 · 404/403)는
     * {@link ChatRoomService#deleteMessage} 안에 있고, 사진은 그것이 통과한 뒤에만 지운다 —
     * 남의 사진 메시지에 삭제를 대면 403 이고 사진은 그대로다. 글자 메시지면 지울 사진이 없을 뿐이다.
     */
    public void delete(long messageId, long userId) {
        sameTransaction.executeWithoutResult(status -> {
            chatRooms.deleteMessage(messageId, userId);
            media.detachAll(MediaAttachment.REF_CHAT, String.valueOf(messageId));
        });
    }

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
        Map<Long, ChatMessageResponse.Media> photos = photosOf(messages);
        Map<Long, ChatMessageResponse.ReplyTo> replies = repliesOf(roomId, messages);
        return messages.stream()
                .map(message -> ChatMessageResponse.of(message, names.get(message.senderUserId()),
                        false, photos.get(message.id()), replyOf(replies, message)))
                .toList();
    }

    /**
     * 메시지 한 장 — 계약의 {@code ChatMessagePage} 모양. 이슈 #79.
     *
     * <p><b>인가는 {@link ChatRoomService#messagePage} 안에 있다.</b> 여기서 한 번 더 묻지
     * 않는 것이 의도다 — 판정이 두 곳에 있으면 한쪽이 낡는다.
     *
     * <p>{@code limit} 은 이미 정규화된 값이다({@link ChatRoomController} 가 계약의 기본값·
     * 최댓값으로 자른다).
     */
    public ChatMessagePageResponse page(long roomId, long userId,
                                        Long afterSeq, Long beforeSeq, Long afterChangeSeq, int limit) {
        ChatMessagePageView page = chatRooms.messagePage(roomId, userId, afterSeq, beforeSeq, afterChangeSeq, limit);
        // 새 말과 바뀐 말을 함께 놓고 한 번에 묻는다(ADR-0023, #500) — 이름도 사진도 답장 원문도 조회는 한 번이다.
        List<ChatMessageView> all = Stream.concat(page.items().stream(), page.changed().stream()).toList();
        Map<Long, String> names = senderNames.of(
                all.stream().map(ChatMessageView::senderUserId).toList());
        // 한 장에 한 번 묻는다. 메시지마다 "가렸나" 를 물으면 100건 조회에 쿼리가 101개다 —
        // 바로 위 이름 해석이 이미 피해 둔 함정이다. 사진도 같은 규칙이다.
        return ChatMessagePageResponse.of(page, names, blocks.blockedBy(userId), photosOf(all),
                repliesOf(roomId, all), reactionsOf(all, userId));
    }

    /**
     * 이 장의 반응 집계(#452) — 메시지 id → 종류별 {@code (count, mine)}, <b>한 번의 조회</b>.
     *
     * <p>{@code chat} 이 세고 여기서는 옮기기만 한다. {@code mine} 이 있어서 읽는 사람을 함께 넘긴다 —
     * 같은 말이 누구에게는 "내가 누른 것" 이고 누구에게는 아니다({@code hiddenByBlock} 과 같은 종류의 값).
     */
    private Map<Long, List<ChatReactionView>> reactionsOf(List<ChatMessageView> messages, long viewerId) {
        return chatRooms.reactionsOf(messages.stream().map(ChatMessageView::id).toList(), viewerId);
    }

    /**
     * 답장들의 원문 미리보기(#452) — <b>원문</b> 메시지 id → 미리보기, <b>한 번의 조회</b>. 답장이 하나도
     * 없으면 묻지 않는다. 원문을 보낸 사람의 이름은 지금 이름이다(메시지와 같은 규칙, #78).
     */
    private Map<Long, ChatMessageResponse.ReplyTo> repliesOf(long roomId, List<ChatMessageView> messages) {
        List<Long> ids = messages.stream().map(ChatMessageView::replyToId).filter(Objects::nonNull).distinct().toList();
        if (ids.isEmpty()) {
            return Map.of();
        }
        List<ChatMessageView> originals = chatRooms.messagesByIds(roomId, ids);
        Map<Long, String> names = senderNames.of(originals.stream().map(ChatMessageView::senderUserId).toList());
        Map<Long, ChatMessageResponse.ReplyTo> replies = new HashMap<>();
        for (ChatMessageView original : originals) {
            replies.put(original.id(), ChatMessageResponse.ReplyTo.of(original, names.get(original.senderUserId())));
        }
        return replies;
    }

    /** 이 메시지의 답장 미리보기 — 답장이 아니거나 원문이 하드 삭제돼 없으면 {@code null}. */
    static ChatMessageResponse.ReplyTo replyOf(Map<Long, ChatMessageResponse.ReplyTo> replies, ChatMessageView message) {
        return message.replyToId() == null ? null : replies.get(message.replyToId());
    }

    /**
     * 사진 메시지들의 사진 — 메시지 id → 사진, <b>한 번의 조회</b>. 사진 메시지가 하나도 없으면
     * 묻지 않는다(대부분의 장이 그렇다). 지워진 사진 메시지는 행이 없어 빠진다 — 응답은 {@code null}.
     */
    private Map<Long, ChatMessageResponse.Media> photosOf(List<ChatMessageView> messages) {
        List<String> refs = messages.stream()
                .filter(m -> ChatRoomService.IMAGE_CONTENT_TYPE.equals(m.contentType()))
                .map(m -> String.valueOf(m.id()))
                .toList();
        if (refs.isEmpty()) {
            return Map.of();
        }
        Map<Long, ChatMessageResponse.Media> photos = new HashMap<>();
        media.attachedTo(MediaAttachment.REF_CHAT, refs).forEach((ref, list) -> {
            ChatMessageResponse.Media first = firstOf(list);
            if (first != null) {
                photos.put(Long.parseLong(ref), first);
            }
        });
        return photos;
    }

    private static ChatMessageResponse.Media firstOf(List<AttachedMedia> attached) {
        return attached == null || attached.isEmpty() ? null : ChatMessageResponse.Media.of(attached.get(0));
    }

    /**
     * 종류 판정 — 사진이 있으면 {@code image}, 없으면 요청이 적은 그대로(생략이면 chat 이 {@code text} 로).
     * 둘이 어긋난 요청은 400 이다({@link IllegalArgumentException} → {@code GlobalExceptionHandler}).
     */
    private static String contentTypeOf(ChatSendRequest request) {
        String requested = request.contentType() == null ? "" : request.contentType().strip();
        boolean hasPhoto = request.mediaId() != null;
        boolean saysImage = ChatRoomService.IMAGE_CONTENT_TYPE.equals(requested);
        if (hasPhoto && !requested.isEmpty() && !saysImage) {
            throw new IllegalArgumentException("사진이 있는 메시지의 종류는 image 입니다.");
        }
        if (saysImage && !hasPhoto) {
            throw new IllegalArgumentException("사진 메시지에 mediaId 가 없습니다.");
        }
        return hasPhoto ? ChatRoomService.IMAGE_CONTENT_TYPE : request.contentType();
    }
}
